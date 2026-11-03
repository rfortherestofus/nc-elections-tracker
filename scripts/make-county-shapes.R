# Make data/nc_counties.rds: NC county outlines as an sf object for the
# interactive county map.
#
# Run once with sf and tigris installed. tigris is only needed here, so this
# file is listed in .renvignore and renv doesn't add tigris to the lockfile.
# The site itself only needs sf (mapgl depends on it) to read the saved file.

library(sf)
library(tigris)
library(dplyr)

options(tigris_use_cache = TRUE)

nc_counties <- counties(state = "NC", cb = TRUE, resolution = "5m", year = 2024) |>
  st_transform(32119) |> # NC State Plane, meters, so the tolerance is in meters
  st_simplify(dTolerance = 200, preserveTopology = TRUE) |>
  st_transform(4326) |> # Longitude and latitude, which web maps expect
  transmute(county_upper = toupper(NAME))

stopifnot(n_distinct(nc_counties$county_upper) == 100)

saveRDS(nc_counties, "data/nc_counties.rds")
