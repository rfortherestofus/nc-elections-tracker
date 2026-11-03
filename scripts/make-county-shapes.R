# Make data/nc_counties.rds: NC county outlines as a plain data frame.
#
# Run once on a Mac with sf and tigris installed. Saving plain polygon points
# (not an sf object) means the site, and the GitHub Action that renders it,
# can draw the map with ggplot2::geom_polygon() without installing sf or GDAL.
# This file is listed in .renvignore so renv doesn't add sf and tigris.

library(sf)
library(tigris)
library(dplyr)

options(tigris_use_cache = TRUE)

nc <- counties(state = "NC", cb = TRUE, resolution = "5m", year = 2024) |>
  st_transform(32119) |> # NC State Plane, meters
  st_simplify(dTolerance = 200) |>
  st_cast("MULTIPOLYGON") |>
  mutate(county_upper = toupper(NAME))

coords <- st_coordinates(nc) |>
  as_tibble()

# For MULTIPOLYGON: L1 = ring within polygon, L2 = polygon, L3 = feature (row)
nc_counties <- coords |>
  transmute(
    county_upper = nc$county_upper[L3],
    x = X,
    y = Y,
    polygon = paste(L3, L2, sep = "-"),
    ring = paste(L3, L2, L1, sep = "-")
  )

stopifnot(n_distinct(nc_counties$county_upper) == 100)

saveRDS(nc_counties, "data/nc_counties.rds")
