# HTML pieces and the county map.

library(htmltools)
library(ggplot2)
library(scales)

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

# County map of the Democratic minus Republican margin.
# Diverging: Republican red, neutral gray at an even race, Democratic blue.
# Counties with no votes counted yet are white.
county_map <- function(margins, shapes = readRDS("data/nc_counties.rds")) {
  map_data <- shapes |>
    left_join(margins, by = join_by(county_upper), relationship = "many-to-one")

  margin_label <- function(x) {
    case_when(
      x > 0 ~ paste0("D+", round(x * 100)),
      x < 0 ~ paste0("R+", round(abs(x) * 100)),
      .default = "Even"
    )
  }

  ggplot(map_data, aes(x, y, group = polygon, subgroup = ring, fill = margin)) +
    geom_polygon(color = "#A9AEB5", linewidth = 0.2) +
    scale_fill_gradient2(
      low = party_colors[["REP"]],
      mid = "#E4E4E4",
      high = party_colors[["DEM"]],
      midpoint = 0,
      limits = c(-0.6, 0.6),
      breaks = c(-0.6, -0.3, 0, 0.3, 0.6),
      labels = margin_label,
      oob = squish,
      na.value = "white",
      name = NULL
    ) +
    coord_equal() +
    theme_void(base_family = "sans", base_size = 13) +
    theme(
      legend.position = "bottom",
      legend.key.width = unit(3, "lines"),
      legend.key.height = unit(0.6, "lines"),
      plot.background = element_rect(fill = "white", color = NA)
    )
}
