rm(list=ls())
.libPaths("C:/Program Files/R/R-3.3.1/library" )
source("set-up.R") # load packages needed - commented as run in buildmaster
start_time <- Sys.time() # for timing the script

if(!exists("region")) region <- "greater-manchester" # create LA name if none exists,  then set-up data repo
pct_data <- file.path("..", "pct-data")
pct_bigdata <- file.path("..", "pct-bigdata")
pct_shiny_regions <- file.path("..", "pct-shiny", "regions_www")
if(!file.exists(pct_data)) stop(paste("The pct-data repository cannot be found.  Please clone https://github.com/npct/pct-data in", dirname(getwd())))
if(!file.exists(pct_bigdata)) stop(paste("The pct-bigdata repository cannot be found.  Please clone https://github.com/npct/pct-bigdata in", dirname(getwd())))
scens <- c("govtarget_slc", "gendereq_slc", "dutch_slc", "ebike_slc")

# Set local authority and ttwa zone names
region_path <- file.path(pct_data, region)
if(!dir.exists(region_path)) dir.create(region_path) # create data directory

params <- NULL # build parameters (saved for future reference)
params$mflow <- 400 # minimum flow between od pairs to show for longer lines, high means fewer lines
params$mflow_short <- 400 # minimum flow between od pairs to show for short lines, high means fewer lines
params$mdist <- 20 # maximum euclidean distance (km) for subsetting lines
params$max_all_dist <- 7 # maximum distance (km) below which more lines are selected
params$buff_dist <- 0 # buffer (km) used to select additional zones (often zero = ok)
# parameters related to the route network
params$buff_geo_dist <- 100 # buffer (m) for removing line start and end points for network
# params$min_rnet_length <- 2 # minimum segment length for the Route Network to display (may create holes in rnet)
params$rft_keep = 0.05 # how aggressively to simplify the route network (higher values - longer to run but rnet less likely to fail)
if(!exists("ukmsoas")){ # MSOA zones
  ukmsoas <- readRDS(file.path(pct_bigdata, "ukmsoas-scenarios_GM.rds"))
  ukmsoas$avslope = ukmsoas$avslope * 100
}

## Lower the case of variable names
names(ukmsoas) <- tolower(names(ukmsoas))

if(!exists("centsa")) # Population-weighted centroids
  centsa <- readRDS(file.path(pct_bigdata, "cents-scenarios_GM.rds"))
centsa$geo_code <- as.character(centsa$geo_code)

source('shared_build.R')

# load in codebook data
codebook_l = readr::read_csv("../pct-shiny/static/codebook_lines.csv")
codebook_z = readr::read_csv("../pct-shiny/static/codebook_zones.csv")

# select msoas of interest
if(proj4string(region_shape) != proj4string(centsa))
  region_shape <- spTransform(region_shape, proj4string(centsa))

# Read centsa as cents
cents <- centsa
# Subset zones to GM area
zones <- ukmsoas[ukmsoas@data$geo_code %in% cents$geo_code, ]

# Remove ukmsoas object
rm(ukmsoas)

# load flow dataset, depending on availability
if(!exists("flow_nat"))
  flow_nat <- readRDS(file.path(pct_bigdata, "lines_oneway_shapes_updated_GM.Rds"))
flow_nat <- flow_nat[flow_nat$dist > 0,]
summary(flow_nat$dutch_slc / flow_nat$all)

# Subset by zones in the study area
# centsa instead
o <- flow_nat$msoa1 %in% cents$geo_code
d <- flow_nat$msoa2 %in% cents$geo_code
flow <- flow_nat[o & d, ] # subset OD pairs with o and d in study area
backup_flow <- flow

# Check if id column doesn't exist, then add it
if (!"id" %in% names(flow)){
  flow$id <- paste(flow$msoa2, flow$msoa1)
}


# Remove national flows from the memory
rm(flow_nat)

flow <- flow[!is.na(flow$dutch_slc),] # remove flows with no scenario data

params$n_flow_region <- nrow(flow)
params$n_commutes_region <- sum(flow$all)

# Subset lines
# subset OD pairs by n. people using it
params$sel_long <- flow$all > params$mflow & flow$dist < params$mdist
params$sel_short <- flow$dist < params$max_all_dist & flow$all > params$mflow_short
sel <- params$sel_long | params$sel_short
flow <- flow[sel, ]
# summary(flow$dist)

l <- flow

# add geo_label of the lines
l$geo_label1 = left_join(l@data["msoa1"], zones@data[c("geo_code", "geo_label")], by = c("msoa1" = "geo_code"))[[2]]
l$geo_label2 = left_join(l@data["msoa2"], zones@data[c("geo_code", "geo_label")], by = c("msoa2" = "geo_code"))[[2]]

# proportion of OD pairs in min-flow based subset
params$pmflow <- round(nrow(l) / params$n_flow_region * 100, 1)
# % all trips covered
params$pmflowa <- round(sum(l$all) / params$n_commutes_region * 100, 1)

# # # # # # # # # # # # # # # # # # #
# Get route allocated data          #
# Use 1 of the following 3 options  #
# # # # # # # # # # # # # # # # # # #

# # 1: Load rf and rq data pre-saved for region, comment for 2 or 3
# rf = readRDS(file.path(pct_bigdata, "rf_gm1.rds"))
# rq = readRDS(file.path(pct_bigdata, "rq_gm1.rds"))

# 2: Load routes pre-generated and stored in pct-bigdata

# Read files by file chooser
# if(!exists("rf_nat"))
#   rf_nat <- readRDS(file.choose()) # 'C:/temp/pct.releases/rf_nat.Rds')
# if(!exists("rq_nat"))
#   rq_nat <- readRDS(file.choose()) # 'C:/temp/pct.releases/rq_nat.Rds')
# rf <- rf[rf$id %in% l$id,]
# rq <- rq[rq$id %in% l$id,]  ; l=l[l$id %in% rf$id, ]
# if(nrow(rf) != nrow(rq)) next()
#
# # Remove national routes
# rm(rf_nat, rq_nat)

# # 3: Create routes on-the-fly, uncomment the next 4 lines:
rf = line2route(l=l, route_fun = route_cyclestreet, base_url = "http://pct.cyclestreets.net", plan = "fastest",n_print = 20)
saveRDS(rf, '../pct-bigdata/rf_gm.rds')

rq = line2route(l=l, route_fun = route_cyclestreet, base_url = "http://pct.cyclestreets.net", plan = "quietest",n_print = 20)
saveRDS(rq, '../pct-bigdata/rq_gm.rds')

if(nrow(rf) != nrow(rq)) next()
rf$id = l$id
rq$id = l$id

# Remove unwanted columns from routes
rf <- remove_cols(rf, "(waypoint|co2_saving|calories|busyness|plan|start|finish|nv)")
rq <- remove_cols(rq, "(waypoint|co2_saving|calories|busyness|plan|start|finish|nv)")

# Allocate route characteristics to OD pairs
l$dist_fast <- rf$length / 1000 # convert m to km
l$dist_quiet <- rq$length / 1000 # convert m to km
l$time_fast <- rf$time
l$time_quiet <- rq$time
l$cirquity <- l$dist_fast / l$dist
l$distq_f <- rq$length / rf$length
l$avslope <- rf$av_incline * 100
l$avslope_q <- rq$av_incline * 100

# Simplify line geometries (if mapshaper is available)
# this greatly speeds up the build (due to calls to overline)
# needs mapshaper installed and available to system():
# see https://github.com/mbloch/mapshaper/wiki/
rft <- rf
rft@data <- cbind(rft@data, l@data[c("bicycle", scens)])
rft <- ms_simplify(input = rft, keep = params$rft_keep, method = "dp", keep_shapes = TRUE, no_repair = FALSE, snap = TRUE)
# Stop rnet lines going to centroid (optional)
# rft <- toptailgs(rf, toptail_dist = params$buff_geo_dist) # commented as failing
# if(length(rft) == length(rf)){
#   row.names(rft) <- row.names(rf)
#   rft <- SpatialLinesDataFrame(rft, rf@data)
# } else print("Error: toptailed lines do not match lines")

# Rename region-
region <- "greater-manchester"

# Fix the path to all-trips folder
region <- "greater-manchester/all-trips"

source("R/generate_rnet.R") # comment out to avoid slow rnet build
#rnet = readRDS(file.path(pct_data, region, "rnet.Rds")) # uncomment if built

# debug rnet so it is smaller and contains only useful results
# summary(rnet) # diagnostic check of what it contains
sel_rnet_zero = rnet$govtarget_slc > 0
# plot(rnet[!sel_rnet_zero,]) # diagnostic check of the segments with no cyclists
# links to: https://github.com/npct/pct-shiny/issues/336
rnet = rnet[rnet$govtarget_slc > 0,] # remove segments with zero cycling flows
# # Add maximum amount of interzone flow to rnet
# create line midpoints (sp::over does not work with lines it seems)
rnet_osgb <- spTransform(rnet, CRS("+init=epsg:27700"))
rnet_lengths = gLength(rnet_osgb, byid = T)
summary(rnet_lengths)
# rnet = rnet[rnet_lengths > params$min_rnet_length,]

proj4string(rnet) = proj4string(zones)

# Are the lines contained by a single zone?
rnet$Singlezone = rowSums(gContains(zones, rnet, byid = TRUE))
rnet@data[rnet$Singlezone == 0, grep(pattern = "upto", names(rnet))] = NA

if(!"gendereq_slc" %in% scens)
  rnet$gendereq_slc <- NA

# # # # # # # # #
# Save the data #
# # # # # # # # #

# Creation of clc current cycling variable (temp)
l$clc <- l$bicycle / l$all * 100

# Transfer cents data to zones
cents@data$avslope <- NULL
cents@data <- left_join(cents@data, zones@data)

# # Save objects
l@data <- as.data.frame(l@data) # convert from tibble to data.frame
# the next line diagnoses missing variables or incorrectly names variables
# codebook_l$`Variable name`[! codebook_l$`Variable name` %in% names(l)]
l@data <- l@data[codebook_l$`Variable name`] # fix order and vars kept in l
zones@data <- zones@data[codebook_z$`Variable name`]
save_formats(zones, 'z')
save_formats(l)
save_formats(rf)
save_formats(rq)
save_formats(rnet)
save_formats(cents, 'c')

# gather params
params$nrow_flow = nrow(flow)
params$build_date = Sys.Date()
params$run_time = Sys.time() - start_time

saveRDS(params, file.path(pct_data, region, "params.Rds"))

# Save the initial parameters to reproduce results

# # Save the script that loaded the lines into the data directory
file.copy("build_regionGM.R", file.path(pct_data, region, "build_regionGM.R"), overwrite = T)
