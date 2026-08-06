# _____________________________________________________________________________
# Package setup and documentation
# _____________________________________________________________________________

using Pkg

# Ensure required packages are available
# Pkg.activate(".");
# Pkg.instantiate();

# only need to install packages the first time

#= 
Pkg.add(
    [
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
	  "ZipFile"
    ]
); 
=#

# Load packages
using Tidier
using TidierDates
using TidierStrings
using Dates
using TidierPlots
using DotEnv
using CSV
using XLSX
using DataFrames
using Quarto
using PrettyTables
using Random
using Impute
using ZipFile
using Downloads

# load custom functions
include("functions.jl")

# load the EMS data if it has already been written to .xlsx within this project
if !(@isdefined ems_aed_runs) && isfile("./output/data/ems_aed_runs.xlsx")
    ems_aed_runs = DataFrame(
        XLSX.readtable("./output/data/ems_aed_runs.xlsx", "ems_data")
    )
    else
    "`ems_aed_runs.xlsx` either does not exist in the project directory, or has already been defined. Please check your environment and run the `data_load_ems.jl` script if necessary."
end

# load the AED data if it has already been written to .xlsx within this project
if !(@isdefined aed_final) && isfile("./output/data/aed_final.xlsx")
    aed_final = DataFrame(
        XLSX.readtable("./output/data/aed_final.xlsx", "aed_data")
    )
    else
    "`aed_final.xlsx` either does not exist in the project directory, or has already been defined. Please check your environment and run the `data_load_aed.jl` script if necessary."
end

# Create .env file if it does not exist
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

# Load .env file into ENV[]
DotEnv.config();
DotEnv.load!()

###_____________________________________________________________________________
# Get environment variables into the global environment
###_____________________________________________________________________________
aed_data_path = ENV["aed_env"];
ems_data_path = ENV["ems_data_env"];
iowa_county_district_path = ENV["iowa_county_district_env"];
output_folder = ENV["output_directory"];
us_zipcodes_path=ENV["us_zips"];
us_counties_path=ENV["us_counties"];