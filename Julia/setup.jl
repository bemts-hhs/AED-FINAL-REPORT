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

###_____________________________________________________________________________
# Read in location data
###_____________________________________________________________________________

#=
read in location data for Iowa counties, districts / urbanicity
=#
location = DataFrame(
    XLSX.readtable(iowa_county_district_path, "IA Counties, Regions"),
)

#=
improve location DataFrame column names
=#
location = @chain location begin
    @clean_names
    @mutate county_fips = string.(county_fips)
end;

#=
download the us zipcodes from the Census Bureau
=#
us_zips_file = Downloads.download(
    us_zipcodes_path
);

#=
get us zips downloaded data as a DataFrame
=#
us_zips_init = CSV.File(
    us_zips_file,
    delim=('|'),
    header=true,
    ignorerepeated=false,
) |> DataFrame;

#=
get the distinct table of us_zips
=#
us_zips = @chain us_zips_init begin
    @distinct GEOID_ZCTA5_20
end;

# ------------------------------------------------------------------------------
# Download, unzip, read, and type the Geonames US dataset
# ------------------------------------------------------------------------------

# Create a temporary file to hold the downloaded zip
temp_zip = tempname()

# Download the US.zip file to the temporary location
Downloads.download(
    "https://download.geonames.org/export/dump/US.zip",
    temp_zip
)

# Open the zip file using ZipFile.jl
zip_reader = ZipFile.Reader(temp_zip)

# Extract the "US.txt" entry
us_entry = filter(e -> endswith(e.name, "US.txt"), zip_reader.files)[1]

# Read the file directly from the zip entry
# CSV.File accepts an IO stream, so this works without extracting to disk
geo_df = CSV.File(
    us_entry,
    delim=('\t'),
    header=false,
    ignorerepeated=false,
    escapechar=('\\')
) |> DataFrame

# ------------------------------------------------------------------------------
# Apply column names and column types
# ------------------------------------------------------------------------------

# Geonames US.txt specification: define names
geo_colnames = [
    "geonameid", "name", "asciiname", "alternatenames",
    "latitude", "longitude", "feature_class", "feature_code",
    "country_code", "cc2", "admin1_code", "admin2_code",
    "admin3_code", "admin4_code", "population", "elevation",
    "dem", "timezone", "modification_date"
]

# rename geo_df using column names supplied at 
rename!(geo_df, geo_colnames)

# Close the zip file
close(zip_reader)

# Remove temp file
rm(temp_zip)

# filter geo_df down to Iowa locations
geo_df_iowa = @chain geo_df begin
    @filter admin1_code == "IA"
    @filter feature_class == "P"
    @mutate(name = str_squish.(
            #= 
            remove the (historical) suffix to the "abandonded" populated places 
            =#
            str_remove.(name, r"\s\(historical\)"i
            )
        ),
        admin2_code = string.(admin2_code)
    )
	@mutate admin2_code = lpad.(admin2_code, 3, "0")
end

#= 
read in US county data from geonames
=#
us_counties_file = Downloads.download(
    us_counties_path
)

# use CSV and DataFrames to shape the file
us_counties_temp = CSV.File(
    us_counties_file,
    delim=('\t'),
    header=false,
    ignorerepeated=false,
    escapechar=('\\')
) |> DataFrame

# define column names
geo_counties_colnames = [
    "code", "name", "asciiname", "geonameID"
]

# assign the correct column names
us_counties_names = rename(us_counties_temp, geo_counties_colnames)

# handle formatting issues within the code vector
ia_counties = @chain us_counties_names begin
    @mutate(
        # everything before the first period
        country_code = str_squish.(
			str_extract.(code, r"^[^\.]+")
			),
        state_code = str_extract.(
			code, r"(?<=^[A-Z]{2}\.)(?:\d{2}|[A-Z]{2})"
			),
        county_code = str_extract.(code, r"(?<=\.)\d+$")
    )
    @mutate name_county = str_squish.(
        str_remove.(name, r"\scounty"i)
    )
    @filter country_code == "US"
    @filter state_code == "IA"
end

#= 
join the county names / codes from geonames to the city data from geonames as their codes are unique

geonames does not use the same codes as Census Bureau
=#

# final manipulations of the Iowa data to join to the AED data
iowa_data_final = @chain geo_df_iowa begin
    @left_join(
        select(ia_counties, :county_code, :name_county), admin2_code = county_code
    )
    @mutate(
        name = str_to_upper(name)
    )
    @left_join(
        location, name_county = county
    )
    @mutate(name = coalesce.(name, ""),
            name_county = coalesce.(name_county, "")
    )
    @mutate(
        name_name_county = string.(name, " ", name_county)
    )
    @filter name_name_county .!= "CENTERVILLE Boone"
    @filter name_name_county .!= "PLEASANT HILL Van Buren"
    @filter name_name_county .!= "HOLY CROSS Delaware"
    @filter name_name_county .!= "FOREST CITY Howard"
    @filter name_name_county .!= "GENEVA Benton"
    @filter name_name_county .!= "WESTFIELD Poweshiek"
    @filter name_name_county .!= "TROY Lucas"
    @filter name_name_county .!= "WASHINGTON Woodbury"
    @filter name_name_county .!= "WEBSTER Madison"
    @filter name_name_county .!= "RIVERSIDE Woodbury"
    @filter name_name_county .!= "WASHINGTON Franklin"
    @filter name_name_county .!= "VAN Marshall"
    @select -name_name_county
    @rename district = region_preparedness
    @relocate(
        district, after = name_county
    )
end

#= 
geonames is missing some of the cities / towns in Iowa, this is a product of the analyses below and may need to be revised periodically
=#
missing_locations = DataFrame(
  geonameid = generate_random_id(7),
  # Generating random geoname IDs
  name = [
    "TERRILL",
    "LEMARS",
    "FREDRICKSBURG",
    "MOLVILLE",
    "CALLENDAR",
    "SYDNEY",
    "DESOTO"
  ],
  name_county = [
    "Dickinson",
    "Plymouth",
    "Chickasaw",
    "Woodbury",
    "Webster",
    "Fremont",
    "Dallas"
  ],
  latitude = [
    43.305473,
    42.7942,
    42.964586,
    42.488210,
    42.362592,
    40.7592,
    41.5316
  ],
  longitude = [
    -94.971433,
    -96.1656,
    -92.198465,
    -96.069997,
    -94.293268,
    -95.6668,
    -94.0078
  ],
  population = fill(missing, 7),
  elevation = fill(missing, 7),
  dem = fill(missing, 7),
  timezone = fill(missing, 7),
  modification_date = fill(missing, 7),
  district = c("7", "3", "2", "3", "7", "4", "1A"),
  # Adding region information
  asciiname = fill(missing, 7),
  alternatenames = fill(missing, 7),
  feature_class = fill(missing, 7),
  feature_code = fill(missing, 7),
  country_code = fill(missing, 7),
  cc2 = fill(missing, 7),
  admin1_code = fill(missing, 7),
  admin2_code = c("059", "149", "037", "193", "187", "071", "049"),
  # Adding admin2_code
  admin3_code = fill(missing, 7),
  admin4_code = fill(missing, 7)
)

# helper vector with iowa_data_final column names
iowa_data_final_names = names(iowa_data_final);

# finish by joining needed features to union this with the larger dataset
missing_location_join = @chain missing_locations begin
  @left_join(
    location,
    name_county = county
  ) 
end

# select the needed columns
missing_location_data = select(missing_location_join, iowa_data_final_names)

# final Iowa cities dataframe
iowa_data_final = vcat(iowa_data_final, missing_location_data)