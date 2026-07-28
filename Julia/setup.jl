# _____________________________________________________________________________
# Package setup and documentation
# _____________________________________________________________________________

using Pkg

# Ensure required packages are available
# Pkg.activate(".");
# Pkg.instantiate();

# only need to install packages the first time
# Pkg.add(
#     [
#     "Tidier", 
#     "TidierPlots", 
#     "TidierDates", 
#     "Dates", 
#     "DotEnv", 
#     "CSV", 
#     "XLSX", 
#     "DataFrames", 
#     "Quarto", 
#     "PrettyTables",
#     "Random",
#	  "Impute"
#     ]
# );

# Load packages
using Tidier
using TidierDates
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
