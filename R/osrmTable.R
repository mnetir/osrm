#' @name osrmTable
#' @title Get Travel Time Matrices Between Points
#' @description Build and send OSRM API queries to get travel time matrices 
#' between points. This function interfaces the \emph{table} OSRM service. 
#' @param loc a data frame containing 3 fields: points identifiers, longitudes 
#' and latitudes (WGS84). It can also be a SpatialPointsDataFrame, a 
#' SpatialPolygonsDataFrame or an sf object. If so, row names are used as identifiers.
#' If loc parameter is used, all pair-wise distances are computed.
#' @param src a data frame containing origin points identifiers, longitudes 
#' and latitudes (WGS84). It can also be a SpatialPointsDataFrame, a 
#' SpatialPolygonsDataFrame or an sf object. If so, row names are used as identifiers. 
#' If dst and src parameters are used, only pairs between scr/dst are computed.
#' @param dst a data frame containing destination points identifiers, longitudes 
#' and latitudes (WGS84). It can also be a SpatialPointsDataFrame a 
#' SpatialPolygonsDataFrame or an sf object. If so, row names are used as identifiers. 
#' @param measure a character indicating what measures are calculated. It can 
#' be "duration" (in minutes), "distance" (meters), or both c('duration',
#' 'distance'). The demo server only allows "duration". 
#' @param exclude pass an optional "exclude" request option to the OSRM API. 
#' @param gepaf a boolean indicating if coordinates are sent encoded with the
#' google encoded algorithm format (TRUE) or not (FALSE). Must be FALSE if using
#' the public OSRM API.
#' @return A list containing 3 data frames is returned. 
#' durations is the matrix of travel times (in minutes), 
#' sources and destinations are the coordinates of 
#' the origin and destination points actually used to compute the travel 
#' times (WGS84).
#' @details If loc, src or dst are data frames we assume that the 3 first 
#' columns of the data frame are: identifiers, longitudes and latitudes. 
#' @note 
#' If you want to get a large number of distances make sure to set the 
#' "max-table-size" argument (Max. locations supported in table) of the OSRM 
#' server accordingly.
#' @seealso \link{osrmIsochrone}
#' @importFrom sf st_as_sf
#' @examples
#' \dontrun{
#' # Load data
#' data("berlin")
#' 
#' # Inputs are data frames
#' # Travel time matrix
#' distA <- osrmTable(loc = apotheke.df[1:50, c("id","lon","lat")])
#' # First 5 rows and columns
#' distA$durations[1:5,1:5]
#' 
#' # Travel time matrix with different sets of origins and destinations
#' distA2 <- osrmTable(src = apotheke.df[1:10,c("id","lon","lat")],
#'                     dst = apotheke.df[11:20,c("id","lon","lat")])
#' # First 5 rows and columns
#' distA2$durations[1:5,1:5]
#' 
#' # Inputs are sf points
#' distA3 <- osrmTable(loc = apotheke.sf[1:10,])
#' # First 5 rows and columns
#' distA3$durations[1:5,1:5]
#' 
#' # Travel time matrix with different sets of origins and destinations
#' distA4 <- osrmTable(src = apotheke.sf[1:10,], dst = apotheke.sf[11:20,])
#' # First 5 rows and columns
#' distA4$durations[1:5,1:5]
#' }
#' @export
osrmTable <- function(loc, src = NULL, dst = NULL, exclude = NULL, 
                      gepaf = FALSE, measure="duration"){
  tryCatch({
    # input mgmt
    if (is.null(src)){
      if(methods::is(loc,"Spatial")){
        loc <- st_as_sf(x = loc)
      }
      if(testSf(loc)){
        loc <- sfToDf(x = loc)
      }
      names(loc) <- c("id", "lon", "lat")
      src <- loc
      dst <- loc
      sep <- "?"
      req <- tableLoc(loc = loc, gepaf = gepaf)
    }else{
      if(methods::is(src,"Spatial")){
        src <- st_as_sf(x = src)
      }
      if(testSf(src)){
        src <- sfToDf(x = src)
      }
      if(methods::is(dst,"Spatial")){
        dst <- st_as_sf(x = dst)
      }
      if(testSf(dst)){
        dst <- sfToDf(x = dst)
      }
      
      names(src) <- c("id", "lon", "lat")
      names(dst) <- c("id", "lon", "lat")
      
      
      # Build the query
      loc <- rbind(src, dst)
      sep = "&"
      req <- paste(tableLoc(loc = loc, gepaf = gepaf),
                   "?sources=", 
                   paste(0:(nrow(src)-1), collapse = ";"), 
                   "&destinations=", 
                   paste(nrow(src):(nrow(loc)-1), collapse = ";"),
                   sep="")
    }
    
    # exclude mngmnt
    if (!is.null(exclude)) {
      exclude_str <- paste0(sep,"exclude=", exclude, sep = "") 
      sep="&"
    }else{
      exclude_str <- ""
    }
    
    # annotation mngmnt
    annotations <- paste0(sep, "annotations=", paste0(measure, collapse=','))
    
    if(getOption("osrm.server") == "http://router.project-osrm.org/"){
      annotations <- ""
    }
    
    # final req
    req <- paste0(req, exclude_str, annotations)
    
    # print(req)
    req <- utils::URLencode(req)
    osrmLimit(nSrc = nrow(src), nDst = nrow(dst), nreq = nchar(req))
    
    # Get the result
    bo=0
    while(bo!=10){
      x = try({
        resRaw <- RCurl::getURL(req, useragent = "'osrm' R package")
        res <- jsonlite::fromJSON(resRaw)
        # print("try")
      }, silent = T)
      if (class(x)=="try-error") {
        Sys.sleep(1)
        bo <- bo+1
      } else
        break 
    }
    
    # Check results
    if(is.null(res$code)){
      e <- simpleError(res$message)
      stop(e)
    }else{
      e <- simpleError(paste0(res$code,"\n",res$message))
      if(res$code != "Ok"){stop(e)}
    }
    
    output <- list()
    if(!is.null(res$durations)){
      # get the duration table
      output$durations <- durTableFormat(res = res, src = src, dst = dst)
    }
    if(!is.null(res$distances)){
      # get the distance table
      output$distances <- distTableFormat(res = res, src = src, dst = dst)  
    }
    # get the coordinates
    coords <- coordFormat(res = res, src = src, dst = dst)
    output$sources <- coords$sources
    output$destinations = coords$destinations
    return(output)
  }, error=function(e) {message("The OSRM server returned an error:\n", e)})
  return(NULL)
}

