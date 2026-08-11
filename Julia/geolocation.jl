###_____________________________________________________________________________
# Only need to run this script if setup.jl does not pull in processed data
# Check the .\output\data\ directory and the global environment, first
###_____________________________________________________________________________
# Read in location data ----
###_____________________________________________________________________________

## read in location data for Iowa counties, districts / urbanicity ----
location = DataFrame(
    XLSX.readtable(iowa_county_district_path, "IA Counties, Regions"),
)

## improve location DataFrame column names ----
location = @chain location begin
    @clean_names
    @mutate county_fips = string.(county_fips)
end;

###_____________________________________________________________________________
# Download, unzip, read, and type the Geonames US dataset ----
###_____________________________________________________________________________

## Create a temporary file to hold the downloaded zip ----
temp_zip = tempname()

##  Download the US.zip file to the temporary location ----
Downloads.download(
    "https://download.geonames.org/export/dump/US.zip",
    temp_zip
)

##  Open the zip file using ZipFile.jl ----
zip_reader = ZipFile.Reader(temp_zip)

##  Extract the "US.txt" entry ----
us_entry = filter(e -> endswith(e.name, "US.txt"), zip_reader.files)[1]

##  Read the file directly from the zip entry ----
# CSV.File accepts an IO stream, so this works without extracting to disk
geo_df = CSV.File(
    us_entry,
    delim=('\t'),
    header=false,
    ignorerepeated=false,
    escapechar=('\\')
) |> DataFrame

###_____________________________________________________________________________
#  Apply column names and column types ----
###_____________________________________________________________________________

##  Geonames US.txt specification: define names ----
geo_colnames = [
    "geonameid", "name", "asciiname", "alternatenames",
    "latitude", "longitude", "feature_class", "feature_code",
    "country_code", "cc2", "admin1_code", "admin2_code",
    "admin3_code", "admin4_code", "population", "elevation",
    "dem", "timezone", "modification_date"
]

##  rename geo_df using column names supplied at  ----
rename!(geo_df, geo_colnames)

##  Close the zip file ----
close(zip_reader)

##  Remove temp file ----
rm(temp_zip)

##  filter geo_df down to Iowa locations ----
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

##  use CSV and DataFrames to shape the file ----
us_counties_temp = CSV.File(
    us_counties_file,
    delim=('\t'),
    header=false,
    ignorerepeated=false,
    escapechar=('\\')
) |> DataFrame

##  define column names ----
geo_counties_colnames = [
    "code", "name", "asciiname", "geonameID"
]

##  assign the correct column names ----
us_counties_names = rename(us_counties_temp, geo_counties_colnames)

##  handle formatting issues within the code vector ----
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

##  final manipulations of the Iowa data to join to the AED data ----
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
    geonameid=generate_random_id(7),
    # Generating random geoname IDs
    name=[
        "TERRILL",
        "LEMARS",
        "FREDRICKSBURG",
        "MOLVILLE",
        "CALLENDAR",
        "SYDNEY",
        "DESOTO"
    ],
    name_county=[
        "Dickinson",
        "Plymouth",
        "Chickasaw",
        "Woodbury",
        "Webster",
        "Fremont",
        "Dallas"
    ],
    latitude=[
        43.305473,
        42.7942,
        42.964586,
        42.488210,
        42.362592,
        40.7592,
        41.5316
    ],
    longitude=[
        -94.971433,
        -96.1656,
        -92.198465,
        -96.069997,
        -94.293268,
        -95.6668,
        -94.0078
    ],
    population=fill(missing, 7),
    elevation=fill(missing, 7),
    dem=fill(missing, 7),
    timezone=fill(missing, 7),
    modification_date=fill(missing, 7),
    district=c("7", "3", "2", "3", "7", "4", "1A"),
    # Adding region information
    asciiname=fill(missing, 7),
    alternatenames=fill(missing, 7),
    feature_class=fill(missing, 7),
    feature_code=fill(missing, 7),
    country_code=fill(missing, 7),
    cc2=fill(missing, 7),
    admin1_code=fill(missing, 7),
    admin2_code=c("059", "149", "037", "193", "187", "071", "049"),
    # Adding admin2_code
    admin3_code=fill(missing, 7),
    admin4_code=fill(missing, 7)
)

##  helper vector with iowa_data_final column names ----
iowa_data_final_names = names(iowa_data_final);

##  finish by joining needed features to union this with the larger dataset ----
missing_location_join = @chain missing_locations begin
    @left_join(
        location,
        name_county = county
    )
end

##  select the needed columns ----
missing_location_data = select(missing_location_join, iowa_data_final_names)

##  final Iowa cities dataframe ----
iowa_data_final = vcat(iowa_data_final, missing_location_data)

##  export the iowa_data_final ----
if isfile("./output/data/iowa_data_final.xlsx")

    # remove the file if it exists
    rm("./output/data/iowa_data_final.xlsx")

    # write the updated file
    XLSX.writetable(
    "./output/data/iowa_data_final.xlsx",
    "iowa_data" => iowa_data_final 
)
else
XLSX.writetable(
    "./output/data/iowa_data_final.xlsx",
    "iowa_data" => iowa_data_final 
)
end

###_____________________________________________________________________________
# Get county shapefiles from US Census Bureau ----
###_____________________________________________________________________________

##  Download shapefile from US Census Bureau ----
county_shapefile_src = Downloads.download(iowa_county_shapefiles)

##  Extract specific zip file ----
county_shapefile_zip = ZipFile.Reader(county_shapefile_src)

##  Extract ALL files from the ZIP into .\output\geo ----
for f in county_shapefile_zip.files
    outdir = joinpath(".", "output", "geo", "county")
    mkpath(outdir)
    outpath = joinpath(outdir, f.name)
    write(outpath, read(f))
end

##  convert the shapefile to a GeoDataFrame ----
county_geo_df = filter(:STATEFP => x -> x .== "19",
    GeoDataFrames.read("./output/geo/county/tl_2025_us_county.shp")
    )

##  gain the needed COUNTYFIPS feature to join the AED and other data ----
county_geo = @chain county_geo_df begin
    @mutate COUNTYFIPS = STATEFP .* COUNTYFP
    @relocate(
        COUNTYFIPS, after = COUNTYFP
    )
end

###_____________________________________________________________________________
# Get all state shapefiles from US Census Bureau ----
###_____________________________________________________________________________

##  Download shapefile from US Census Bureau ----
state_shapefile_src = Downloads.download(us_state_shapefiles)

##  Extract specific zip file ----
state_shapefile_zip = ZipFile.Reader(state_shapefile_src)

##  Extract ALL files from the ZIP into .\output\geo ----
for f in state_shapefile_zip.files
    outdir = joinpath(".", "output", "geo", "state")
    mkpath(outdir)
    outpath = joinpath(outdir, f.name)
    write(outpath, read(f))
end

#= 
Define a vecotr of STATEFPs for Alaska, Hawaii, American Samoa, Northern Mariana Islands, Guam, Puerto Rico, and the US Virgin Islands
=#
not_states = ["02", "11", "15", "60", "66", "69", "72", "78"];

##  convert the shapefile to a GeoDataFrame ----
state_geo = filter(row -> !(row.STATEFP in not_states),
    GeoDataFrames.read("./output/geo/state/tl_2025_us_state.shp")
    )
