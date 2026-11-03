# Download live results from the NC State Board of Elections.
#
# Files come from https://er.ncsbe.gov/enr/{date}/data/:
#   county.txt                     precincts reporting, ballots cast, turnout
#   results_0.txt                  statewide results
#   results_1.txt ... results_100.txt  results for each county
#
# Each file's ETag is saved next to it. The next request sends it back, and
# the server answers "304 Not Modified" when nothing changed, so polling is
# cheap and unchanged files are never rewritten.
#
# Run as a script (Quarto does this before every render):
#   Rscript R/fetch.R
# It writes data/raw/{date}/status.json, which the publish loop reads.

library(httr2)
library(jsonlite)
library(purrr, warn.conflicts = FALSE)

election_date <- function() {
  Sys.getenv("ELECTION_DATE", "20261103")
}

raw_dir <- function(date = election_date()) {
  file.path("data", "raw", date)
}

results_url <- function(file, date = election_date()) {
  paste0("https://er.ncsbe.gov/enr/", date, "/data/", file)
}

build_request <- function(file, date, dir) {
  etag_path <- file.path(dir, paste0(file, ".etag"))

  req <- request(results_url(file, date)) |>
    req_user_agent("nc-elections-tracker (R for the Rest of Us)") |>
    req_timeout(30) |>
    req_retry(max_tries = 3) |>
    req_error(is_error = \(resp) resp_status(resp) >= 400)

  if (file.exists(etag_path) && file.exists(file.path(dir, file))) {
    req <- req |>
      req_headers(`If-None-Match` = readLines(etag_path, warn = FALSE))
  }

  req
}

# Save one response. Returns TRUE if the file changed, FALSE on a 304.
save_response <- function(resp, file, dir) {
  if (resp_status(resp) == 304) {
    return(FALSE)
  }

  body <- resp_body_raw(resp)

  # Never overwrite good data with a truncated or empty download
  parsed <- tryCatch(fromJSON(rawToChar(body)), error = \(e) NULL)
  if (is.null(parsed) || NROW(parsed) == 0) {
    stop("Download of ", file, " was not valid, non-empty JSON")
  }

  tmp <- tempfile(tmpdir = dir)
  writeBin(body, tmp)
  file.rename(tmp, file.path(dir, file))

  etag <- resp_header(resp, "etag")
  if (!is.null(etag)) {
    writeLines(etag, file.path(dir, paste0(file, ".etag")))
  }

  TRUE
}

fetch_files <- function(files, date, dir) {
  reqs <- map(files, \(file) build_request(file, date, dir))
  resps <- req_perform_parallel(reqs, on_error = "continue", progress = FALSE)

  map2_lgl(resps, files, \(resp, file) {
    if (inherits(resp, "error")) {
      stop("Could not download ", file, ": ", conditionMessage(resp))
    }
    save_response(resp, file, dir)
  })
}

fetch_results <- function(date = election_date()) {
  dir <- raw_dir(date)
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)

  main_changed <- fetch_files(c("county.txt", "results_0.txt"), date, dir)

  # County files only matter when the statewide numbers moved
  county_files <- paste0("results_", 1:100, ".txt")
  county_missing <- !all(file.exists(file.path(dir, county_files)))
  if (any(main_changed) || county_missing) {
    fetch_files(county_files, date, dir)
  }

  counties <- fromJSON(file.path(dir, "county.txt"))
  state <- counties[counties$cid == "0", ]

  status <- list(
    election_date = date,
    data_date = regmatches(state$tle, regexpr("\\d{2}/\\d{2}/\\d{4}", state$tle)),
    changed = any(main_changed),
    precincts_reporting = as.integer(state$prt),
    precincts_total = as.integer(state$ptl),
    all_reporting = as.integer(state$prt) == as.integer(state$ptl),
    state_updated = state$imp
  )
  write_json(status, file.path(dir, "status.json"), auto_unbox = TRUE, pretty = TRUE)

  invisible(status)
}

if (sys.nframe() == 0) {
  status <- fetch_results()
  message(
    "Election ", status$election_date, ": ",
    if (status$changed) "new data" else "no change", ", ",
    status$precincts_reporting, " of ", status$precincts_total,
    " precincts reporting"
  )
}
