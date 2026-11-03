# Turn the raw NCSBE files into tidy tibbles.
#
# Every value in the raw files is a string. Field notes, checked against the
# 2024 precinct file:
#   evc = Election Day votes      ovc = early (one-stop) votes
#   avc = absentee by mail votes  pvc = provisional votes
#   prt / ptl = precincts reporting / total
#   col = the state's party color, hex without the "#"

library(dplyr)
library(stringr)
library(purrr)
library(jsonlite)
library(tibble)

# The statewide race at the top of the site. 2024 had no US Senate race,
# so the 2024 preview uses the presidential race instead.
headline_contest <- function(date = election_date()) {
  if (date == "20241105") "US PRESIDENT" else "US SENATE"
}

is_test_data <- function(date = election_date()) {
  date != "20261103"
}

read_raw <- function(file, date = election_date()) {
  fromJSON(file.path(raw_dir(date), file)) |>
    as_tibble()
}

read_counties <- function(date = election_date()) {
  read_raw("county.txt", date) |>
    transmute(
      county_id = as.integer(cid),
      county_upper = cnm,
      county = str_to_title(cnm) |> str_replace("^Mcdowell$", "McDowell"),
      precincts_reporting = as.integer(prt),
      precincts_total = as.integer(ptl),
      ballots_cast = as.numeric(bct),
      registered_voters = as.numeric(rtl),
      turnout = as.numeric(str_remove(bpt, "%")) / 100,
      state_updated = imp
    )
}

read_results <- function(file_id = 0, date = election_date()) {
  read_raw(paste0("results_", file_id, ".txt"), date) |>
    transmute(
      county_id = as.integer(cid),
      contest = str_remove(cnm, "\\s*\\(VOTE FOR \\d+\\)$"),
      vote_for = as.integer(vfr),
      candidate = bnm,
      party = na_if(str_trim(pty), ""),
      votes = as.numeric(vct),
      share = as.numeric(pct),
      votes_election_day = as.numeric(evc),
      votes_early = as.numeric(ovc),
      votes_mail = as.numeric(avc),
      votes_provisional = as.numeric(pvc),
      precincts_reporting = as.integer(prt),
      precincts_total = as.integer(ptl),
      color = paste0("#", col)
    )
}

headline_results <- function(date = election_date()) {
  read_results(0, date) |>
    filter(contest == headline_contest(date))
}

headline_by_county <- function(date = election_date()) {
  map(1:100, \(id) read_results(id, date)) |>
    list_rbind() |>
    filter(contest == headline_contest(date))
}

house_results <- function(date = election_date()) {
  read_results(0, date) |>
    filter(str_detect(contest, "^US HOUSE OF REPRESENTATIVES DISTRICT")) |>
    mutate(district = as.integer(str_extract(contest, "\\d+$")))
}

# Democratic minus Republican share of all votes cast, by county.
# NA where a county has no votes counted yet.
county_margins <- function(by_county, counties) {
  by_county |>
    summarise(
      total = sum(votes),
      dem = sum(votes[party %in% "DEM"]),
      rep = sum(votes[party %in% "REP"]),
      .by = county_id
    ) |>
    mutate(margin = if_else(total > 0, (dem - rep) / total, NA_real_)) |>
    left_join(
      counties |> select(county_id, county, county_upper),
      by = join_by(county_id)
    )
}
