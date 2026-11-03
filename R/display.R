# HTML pieces and the county map.

library(htmltools)
library(scales)
library(sf)
library(mapgl)

# The state's own colors for the two major parties. Green and Libertarian are
# darkened from the state's colors so their bars show up on a white page.
# Everything else (write-ins, smaller parties) is gray.
party_colors <- c(
  DEM = "#1171B9",
  REP = "#EB2326",
  GRE = "#3D9A0B",
  LIB = "#B98A00"
)
other_color <- "#8A8F98"

party_color <- function(party) {
  unname(coalesce(party_colors[party], other_color))
}

party_label <- function(party) {
  labels <- c(
    DEM = "Democratic", REP = "Republican", GRE = "Green",
    LIB = "Libertarian", CST = "Constitution", JFA = "Justice For All"
  )
  unname(coalesce(labels[party], party, ""))
}

fmt_votes <- label_comma()
fmt_share <- label_percent(accuracy = 0.1)

# Banner shown on any render that isn't the 2026 election
test_data_banner <- function(date = election_date()) {
  if (!is_test_data(date)) {
    return(NULL)
  }
  div(
    class = "test-data-banner",
    strong(paste(substr(date, 1, 4), "test data.")),
    " These are not 2026 results. The live site only ever shows 2026."
  )
}

waiting_message <- function(results) {
  if (sum(results$votes) > 0) {
    return(NULL)
  }
  div(
    class = "waiting-message",
    "Polls close at 7:30 p.m. ET. Results will appear here as counties report."
  )
}

# The status bar at the top of each page
status_bar <- function(counties) {
  state <- counties |> filter(county_id == 0)
  built <- format(Sys.time(), "%I:%M %p ET", tz = "America/New_York") |>
    str_remove("^0")

  stat <- function(label, value) {
    div(class = "status-item", span(class = "status-label", label), span(class = "status-value", value))
  }

  div(
    class = "status-bar",
    stat(
      "Precincts reporting",
      paste0(
        fmt_votes(state$precincts_reporting), " of ",
        fmt_votes(state$precincts_total)
      )
    ),
    stat("Ballots cast", fmt_votes(state$ballots_cast)),
    stat("Turnout", label_percent(accuracy = 0.1)(state$turnout)),
    stat("State data updated", state$state_updated),
    stat("Page built", built)
  )
}

# One row per candidate: name and party, a bar, then share and votes.
# Before any votes are counted, it lists candidates without bars.
candidate_bars <- function(results) {
  results <- results |> arrange(desc(votes), candidate)
  counting <- sum(results$votes) > 0
  top_votes <- max(results$votes)

  rows <- pmap(results, \(candidate, party, votes, share, ...) {
    leading <- counting && votes == top_votes
    color <- party_color(party)

    div(
      class = "candidate",
      div(
        class = "candidate-name",
        span(class = "party-swatch", style = paste0("background:", color)),
        span(candidate),
        if (!is.na(party)) span(class = "candidate-party", party_label(party)),
        if (leading) span(class = "leading-badge", "Leading")
      ),
      if (counting) {
        tagList(
          div(
            class = "bar-track",
            div(
              class = "bar-fill",
              style = paste0("width:", round(share * 100, 2), "%;background:", color)
            )
          ),
          div(
            class = "candidate-numbers",
            span(class = "candidate-share", fmt_share(share)),
            span(class = "candidate-votes", paste(fmt_votes(votes), "votes"))
          )
        )
      }
    )
  })

  div(class = "candidates", rows)
}

precincts_line <- function(results) {
  first <- results |> slice(1)
  p(
    class = "precincts-line",
    paste0(
      fmt_votes(first$precincts_reporting), " of ",
      fmt_votes(first$precincts_total), " precincts reporting"
    )
  )
}

# One card per US House district
house_cards <- function(house) {
  cards <- house |>
    split(house$district) |>
    map(\(district) {
      div(
        class = "house-card",
        h3(paste("District", first(district$district))),
        candidate_bars(district),
        precincts_line(district)
      )
    })

  div(class = "house-grid", cards)
}

# Margins of 60 points or more get the full party color
margin_limit <- 0.6
margin_mid_color <- "#E4E4E4"
no_votes_color <- "#FFFFFF"

margin_label <- function(x) {
  points <- round(x * 100)
  case_when(
    is.na(x) ~ "No votes counted yet",
    points > 0 ~ paste0("D+", points),
    points < 0 ~ paste0("R+", abs(points)),
    .default = "Even"
  )
}

# The HTML shown when hovering over a county: its margin, the top candidates'
# shares and votes, and how many of its precincts have reported. Candidates
# past the top few are combined into one row so the tooltip fits on the map.
county_tooltip <- function(county, margin, results, top_n = 3) {
  results <- results |> arrange(desc(votes), candidate)
  counting <- sum(results$votes) > 0

  if (nrow(results) > top_n + 1) {
    others <- results |>
      slice(-seq_len(top_n)) |>
      summarise(
        candidate = paste(n(), "other candidates"),
        party = NA_character_,
        votes = sum(votes),
        share = sum(share)
      )
    results <- bind_rows(slice(results, seq_len(top_n)), others)
  }

  rows <- pmap(results, \(candidate, party, votes, share, ...) {
    tags$tr(
      tags$td(span(class = "party-swatch", style = paste0("background:", party_color(party)))),
      tags$td(class = "map-tooltip-name", candidate),
      if (counting) tags$td(class = "map-tooltip-share", fmt_share(share)),
      if (counting) tags$td(class = "map-tooltip-votes", fmt_votes(votes))
    )
  })

  div(
    class = "map-tooltip",
    div(class = "map-tooltip-county", county),
    div(class = "map-tooltip-margin", margin_label(margin)),
    tags$table(rows),
    div(
      class = "map-tooltip-precincts",
      paste0(
        fmt_votes(first(results$precincts_reporting)), " of ",
        fmt_votes(first(results$precincts_total)), " precincts reporting"
      )
    )
  ) |>
    as.character()
}

# Interactive county map of the Democratic minus Republican margin.
# Diverging: Republican red, neutral gray at an even race, Democratic blue.
# Counties with no votes counted yet are white. Hovering over a county
# outlines it and shows its full results.
county_map <- function(margins, by_county, shapes = readRDS("data/nc_counties.rds")) {
  tooltips <- by_county |>
    summarise(results = list(pick(everything())), .by = county_id) |>
    left_join(margins, by = join_by(county_id), relationship = "one-to-one") |>
    mutate(tooltip = pmap_chr(list(county, margin, results), county_tooltip)) |>
    select(county_upper, margin, tooltip)

  map_data <- shapes |>
    left_join(tooltips, by = join_by(county_upper), relationship = "one-to-one")

  rep_color <- party_colors[["REP"]]
  dem_color <- party_colors[["DEM"]]
  # MapLibre blends colors in RGB, so the legend's in-between stops do too
  blend <- \(from, to) colorRampPalette(c(from, to))(3)[2]
  hovered <- list("boolean", list("feature-state", "hover"), FALSE)

  maplibre(
    style = carto_style("positron-no-labels"),
    bounds = map_data,
    # Leave a margin around the state so all of it shows on load
    fitBoundsOptions = list(padding = 40),
    projection = "mercator",
    height = "420px",
    # Scrolling the page shouldn't zoom the map: zoom with Ctrl/Cmd + scroll
    cooperativeGestures = TRUE,
    attributionControl = list(compact = TRUE)
  ) |>
    add_source(id = "counties", data = map_data, generateId = TRUE) |>
    add_fill_layer(
      id = "county-fill",
      source = "counties",
      fill_color = interpolate(
        column = "margin",
        values = c(-margin_limit, 0, margin_limit),
        stops = c(rep_color, margin_mid_color, dem_color),
        na_color = no_votes_color
      ),
      fill_opacity = 1,
      tooltip = "tooltip",
      # hover_options also sets the hover state that thickens the outline below
      hover_options = list(fill_opacity = 0.8)
    ) |>
    add_line_layer(
      id = "county-outline",
      source = "counties",
      line_color = list("case", hovered, "#1D2430", "#A9AEB5"),
      line_width = list("case", hovered, 2.5, 0.5)
    ) |>
    add_continuous_legend(
      legend_title = "Margin",
      values = margin_label(c(-1, -0.5, 0, 0.5, 1) * margin_limit),
      colors = c(
        rep_color, blend(rep_color, margin_mid_color), margin_mid_color,
        blend(margin_mid_color, dem_color), dem_color
      ),
      position = "bottom-left",
      width = "260px"
    )
}
