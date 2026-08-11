# _____________________________________________________________________________
# Package setup and documentation ----
# _____________________________________________________________________________

using Pkg

##  Ensure required packages are available ----
# Pkg.activate(".");
# Pkg.instantiate();

##  only need to install packages the first time ----

#= Pkg.add(
    [
    "ArchGDAL"
    "Tidier", 
    "TidierPlots", 
    "TidierDates",
	"TidierStrings", 
    "Dates", 
    "DotEnv", 
    "CSV", 
    "XLSX", 
    "DataFrames",
    "Quarto", 
    "PrettyTables",
    "Random",
	"Impute",
	"Downloads",
	"ZipFile",
    "GeoDataFrames",
    "GeoMakie",
    "CairoMakie",
    "Makie",
    "HTTP",
    "GADM",
    "GeometryOps",
    "InteractiveUtils",
    "ColorBrewer"
    ]
); =#

##  Load packages ----
using ArchGDAL
using CairoMakie
using ColorBrewer
using CSV
using DataFrames
using Dates
using DotEnv
using Downloads
using GADM
using GeoDataFrames
using GeoMakie
using GeometryOps
using HTTP
using Impute
using InteractiveUtils
using Makie
using PrettyTables
using Quarto
using Random
using Tidier
using TidierDates
using TidierPlots
using TidierStrings
using XLSX
using ZipFile

##  load custom functions ----
include("functions.jl")

##  load the EMS data if it has already been written to .xlsx within this project ----
if !(@isdefined ems_aed_runs) && isfile("./output/data/ems_aed_runs.xlsx")
    ems_aed_runs = DataFrame(
        XLSX.readtable("./output/data/ems_aed_runs.xlsx", "ems_data")
    )
    else
    "`ems_aed_runs.xlsx` either does not exist in the project directory, or has already been defined. Please check your environment and run the `data_load_ems.jl` script if necessary."
end

##  load the AED data if it has already been written to .xlsx within this project ----
if !(@isdefined aed_final) && isfile("./output/data/aed_final.xlsx")
    aed_final = DataFrame(
        XLSX.readtable("./output/data/aed_final.xlsx", "aed_data")
    )
    else
    "`aed_final.xlsx` either does not exist in the project directory, or has already been defined. Please check your environment and run the `data_load_aed.jl` script if necessary."
end

##  Create .env file if it does not exist ----
if !isfile(".env")
    write(
        ".env",
        """
        # Raw AED dataset
        aed_env=
        
        # EMS data
        ems_data_env=
        
        # Iowa county and district data
        iowa_county_district_env=
        
        # File outputs
        output_directory=
        """,
    )
else
    @info "File `.env` was found in the target directory."
end;

##  Load .env file into ENV[] ----
DotEnv.config();
DotEnv.load!();

###_____________________________________________________________________________
# Get environment variables into the global environment ----
###_____________________________________________________________________________

##  aed data ----
aed_data_path = ENV["aed_env"];

##  ems data ----
ems_data_path = ENV["ems_data_env"];

##  reference file for categorical county data from Iowa ----
iowa_county_district_path = ENV["iowa_county_district_env"];

##  define the output dir ----
output_folder = ENV["output_directory"];

##  US zipcode level data ----
us_zipcodes_path=ENV["us_zips"];

##  US county-level data ----
us_counties_path=ENV["us_counties"];

##  US county shapefiles from US Census Bureau ----
iowa_county_shapefiles=ENV["iowa_county_shapefiles_zip"];

##  US state shapefiles from US Census Bureau ----
us_state_shapefiles=ENV["us_states_shapefiles_zip"];

##  US heart disease mortality data from CDC OData connection ----
us_heart_disease_mortality=ENV["us_heart_disease_mortality_odata"];
