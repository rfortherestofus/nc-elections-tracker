# Load everything the pages need. Each .qmd sources this file.

source("R/fetch.R")
source("R/tidy.R")
source("R/display.R")

counties <- read_counties()
