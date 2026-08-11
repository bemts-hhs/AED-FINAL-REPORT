###_____________________________________________________________________________
# Only need to run this script if setup.jl does not pull in processed data
# Check the .\output\data\ directory and the global environment, first
###_____________________________________________________________________________
# Prepare AED Data for Analysis ----
# Run this script first before moving on to analyses
# Must run setup.jl before running this script
###_____________________________________________________________________________

###_____________________________________________________________________________
## read in the data ----
###_____________________________________________________________________________

##  define the data type specifications for the custom function xlsx_cell_range_to_df ----

spec = [Date, Time, Time, Time, Time, String, Number, Any, Any, Any, Any, String, Any, String, Bool, Bool, String, Bool, Bool, Bool, Bool, Number, String, String, Bool, Bool, Bool, Bool, Bool, Any, Bool, Number, Number, Number, Number, Number, Number, String]

##  read in AED data using a custom function ----
aed_raw = xlsx_cell_range_to_df(
    aed_data_path, "VALID DATA ENTRY", "A1:AL2399";
    clean_up=true,
    type_spec=spec
);

##  aed observations ----
aed_n_obs = nrow(aed_raw)

#= 
conduct manipulations on the aed_raw dataset in order to create new features
mostly for time intelligence and convenient categories
=#

##  make a copy of the aed_raw dataset ----
aed_data = deepcopy(aed_raw)

##  add the unique incident id directly, cannot do this inside @chain ----
aed_data.unique_incident_id = generate_random_id(aed_n_obs; seed=10232015)

##  manipulations using @chain ----
aed_final_init = @chain aed_data begin
    @relocate(
        unique_incident_id, before = date_of_use
    )
    @mutate(
        amb_toc_timestamp = date_of_use .+ amb_toc,
        amb_pat_timestamp = date_of_use .+ amb_pat,
        time_aed_on_timestamp = date_of_use .+ time_aed_on,
        location_city_event = ifelse(
            occursin.(
                r"iowa state fair grounds"i, coalesce.(location_city_event, "")
            ),
            "Des Moines",
            location_city_event
        )
    )
    @relocate(amb_toc_timestamp, after = amb_toc)
    @relocate(amb_pat_timestamp, after = amb_pat)
    @relocate(time_aed_on_timestamp, after = time_aed_on)
end

##  correct the ambulance to patient timestamp ----
aed_final_init.amb_pat_timestamp_fix =
    correct_midnight_rollover(aed_final_init, :amb_toc_timestamp, :amb_pat_timestamp)

##  calculate the time aed off ----
aed_final_init.time_aed_off = time_string_extract(
    aed_final_init, :total_time_aed_actually_used_min_sec, :time_aed_on
)

##  get the time aed off timestamp ----
aed_final_init = @chain aed_final_init begin
    @mutate(
        time_aed_off_timestamp = date_of_use .+ time_aed_off
    )
    @mutate(
        time_aed_off = ifelse(
            coalesce.(time_aed_on .== time_aed_off, false),
            missing,
            time_aed_off
        ),
        time_aed_off_timestamp = ifelse(
            coalesce.(time_aed_on_timestamp .== time_aed_off_timestamp, false),
            missing,
            time_aed_off_timestamp
        )
    )
    @relocate(amb_pat_timestamp_fix, after = amb_pat_timestamp)
    @relocate(time_aed_off, after = total_time_aed_actually_used_min_sec)
    @relocate(time_aed_off_timestamp, after = time_aed_off)
end

##  correct the time aed off and on relationship ----
aed_final_init.time_aed_off_timestamp_fix =
    correct_midnight_rollover(aed_final_init, :time_aed_on_timestamp, :time_aed_off_timestamp)

##  approach final manipulations for the aed data ----
aed_clean = @chain aed_final_init begin
    @relocate(
        time_aed_off_timestamp_fix, after = time_aed_off_timestamp
    )
    @mutate(
        time_from_call_to_patient = difftime.(
            amb_pat_timestamp_fix,
            amb_toc_timestamp,
            "minutes"
        ),
        time_from_call_to_aed_on = difftime.(
            time_aed_on_timestamp,
            amb_toc_timestamp,
            "minutes"
        ),
        time_from_patient_to_aed = difftime.(
            time_aed_on_timestamp,
            amb_pat_timestamp_fix,
            "minutes"
        ),
        total_time_aed_used = difftime.(
            time_aed_off_timestamp_fix,
            time_aed_on_timestamp,
            "minutes"
        ),
        time_at_patient_to_end_aed = difftime.(
            time_aed_off_timestamp_fix,
            amb_pat_timestamp_fix,
            "minutes"
        ),
        time_from_call_to_end_aed = difftime.(
            time_aed_off_timestamp_fix,
            amb_toc_timestamp,
            "minutes"
        ),
        unknown_if_witnessed = coalesce.(unknown_if_witnessed, false),
        bystander_cpr = coalesce.(bystander_cpr, false),
        utstein_survival = (
            bystander_cpr .== true .&
                              witnessed .== true .&
                                            shock_no_shock .> 0
        ),
        age_unit = str_to_title.(
            coalesce.(age_unit, "Not Recorded")
        )
    )
    @mutate(
        age_years = case_when(
            age_unit .== "Days" => age ./ 365.25,
            age_unit .== "Months" => age ./ 12,
            age_unit .== "Weeks" => age ./ 52.1786,
            true => age
        )
    )
    @mutate(
        age_range = case_when(
            ismissing.(age_years) => missing,
            age_years .<= 4 => "00-04",
            age_years .<= 9 => "05-09",
            age_years .<= 14 => "10-14",
            age_years .<= 19 => "15-19",
            age_years .<= 24 => "20-24",
            age_years .<= 29 => "25-29",
            age_years .<= 34 => "30-34",
            age_years .<= 39 => "35-39",
            age_years .<= 44 => "40-44",
            age_years .<= 49 => "45-49",
            age_years .<= 54 => "50-54",
            age_years .<= 59 => "55-59",
            age_years .<= 64 => "60-64",
            age_years .<= 69 => "65-69",
            age_years .<= 74 => "70-74",
            age_years .<= 79 => "75-79",
            age_years .<= 84 => "80-84",
            true => "85+"
        ),
        agency = str_squish.(
            coalesce.(agency, "Not Recorded")
        )
    )
    @mutate(
        agency_type = case_when(
            occursin.(r"ISP", agency) => "ISP",
            occursin.(r"PD|West Des Moines", agency) => "PD",
            occursin.(r"SO|S0", agency) => "SO",
            occursin.(r"Cons", agency) => "Cons",
            occursin.(r"IDNR\s(-\s)?Parks|Iowa DNR|Iowa Parks", agency) => "IDNR Parks",
            occursin.(r"IDOT|MVE", agency) => "IDOT MVE",
            occursin.(r"Fair", agency) => "Fairground LE",
            occursin.(r"Iowa Department of Public Safety", agency) => "IDPS",
            true => "Unknown"),
        location_city_event_clean = str_remove_all(
            str_squish.(
                coalesce.(location_city_event, "Not Recorded")
            ),
            r"Rural(?:\s)*|\bUrban\b(?:\s)*|Suburban(?:\s)*|-(?:\s)*|\(|\)"i
        )
    )
    @relocate(
        age_years, after = age_unit
    )
    @relocate(
        age_range, after = age_years
    )
    @relocate(
        agency_type, after = agency
    )
end


###_____________________________________________________________________________
# deterministic match between aed_clean and geonames location data ----
###_____________________________________________________________________________

##  create a pattern for the words after the first name of a city ----
# e.g. Council (Bluffs)

##  a df to observe ----
iowa_cities = @chain iowa_data_final begin
    @select name
    @distinct
    @arrange name
end

##  a vector to create the regex ----
iowa_cities_vec = @chain iowa_data_final begin
    @select name
    @distinct
    @arrange name
    @pull name
end

##  an additional vector to help clean out county names from the location names ----
iowa_counties_vec = @chain iowa_data_final begin
    @select name_county
    @distinct
    @arrange name_county
    @pull name_county
end

##  the city regex ----
city_extension_pattern = make_regex_from_vector(iowa_cities_vec, word_boundary=true)

##  get the base county pattern ----
base_county_pattern =
    make_regex_from_vector(iowa_counties_vec).pattern
    
##  the county regex ----
county_pattern = Regex("$(base_county_pattern)(?:\\sCO|\\sCOUNTY)\$")

###_____________________________________________________________________________
# matching ----
# in each implementation look out for a warning from dplyr
# indicating that there are many to many relationships among x and y
# this means that we found another city that is assigned to more than 1 county
# within geonames and those are mostly errors.
# Fix this by adding to the list of filtered items for Iowa_Data_Final in the sameformat that the code is written in
###_____________________________________________________________________________

# _____________________________________________________________________________
# Clean location_city_event_clean ----
# using deterministic regex and string utilities
# _____________________________________________________________________________

aed_adjust = @chain aed_clean begin

###_____________________________________________________________________________
## Basic string cleaning and normalization ----
###_____________________________________________________________________________

    # Replace "Ft." with "Fort"
    @mutate location_city_event_clean =
        replace.(location_city_event_clean, r"Ft\." => "Fort")

    # Upper-case for deterministic joining behavior
    @mutate location_city_event_clean = str_to_upper(location_city_event_clean)
end

##  Remove county names using county_pattern ----
aed_adjust.location_city_event_clean = str_replace.(aed_adjust.location_city_event_clean, county_pattern, "")

    # __________________________________________________________________________
    # Deterministic fixes for common mis-recorded locations
    # __________________________________________________________________________
aed_final = @chain aed_adjust begin
    @mutate(
        cardiac_episode = coalesce.(cardiac_episode, false),
        od_case = coalesce.(od_case, false),
        other_case_binary = ifelse(ismissing.(other_case), false, true)
    )
    @mutate other_case_binary = ifelse(
        cardiac_episode .& other_case_binary, false, other_case_binary
        )
    @mutate(year = TidierDates.year.(date_of_use),
            call_type = case_when(
                cardiac_episode => "Cardiac Arrest",
                od_case => "Overdose",
                other_case_binary => "Other Cause",
                true => "Unknown"
            )
    )
    @relocate(
        call_type, after = other_case
    )
    @relocate(
        year, after = date_of_use
    )
    @relocate(
        location_city_event_clean, after = location_city_event
    )

    @mutate location_city_event_clean = str_replace.(
        location_city_event_clean, r"SGT\.", "SERGEANT"
        )

    @mutate location_city_event_clean = str_replace.(
        location_city_event_clean, 
        r"mucatine\sco\.|,\sia\s.+$|\sboone\smva$|\s?\bunty\b\s?|\s*hwy.*$"i, ""
    )

    @mutate location_city_event_clean = ifelse(
        coalesce.(
            occursin.(
                r"delaware"i, location_city_event_clean
            ), false
        ), "DELAWARE", location_city_event_clean
    )

    @mutate location_city_event_clean = str_replace.(
        location_city_event_clean, r"(?:twn|town)ship|twnshp|twn"i, "TOWNSHIP"
    )

    @mutate location_city_event_clean = case_when(
        coalesce.(
            occursin.(
                r"altoona"i, location_city_event_clean
            ), false
        ) => "ALTOONA",
        coalesce.(
            occursin.(
                r"floyd"i, location_city_event_clean
            ), false
        ) => "FLOYD",
        coalesce.(
            occursin.(
                r"saylor township"i, location_city_event_clean
            ), false
        ) => "SAYLOR TOWNSHIP",
        coalesce.(
            occursin.(
                r"delaware"i, location_city_event_clean
            ), false
        ) => "DELAWARE",
        coalesce.(
            occursin.(
                r"INDEPENCE"i, location_city_event_clean), false
                ) => "INDEPENDENCE",
        coalesce.(
            occursin.(r"AAMOSA"i,
                            location_city_event_clean), false
                            ) => "ANAMOSA",
        coalesce.(
            occursin.(r"MEDIC AMBULANCE"i,
                            location_city_event_clean
                            ), false) => "",
        coalesce.(
            occursin.(r"mount air"i,
                            location_city_event_clean), false
                            ) => "MOUNT AYR",
        coalesce.(
            occursin.(r"nemha"i,
                            location_city_event_clean), false
                            ) => "NEMAHA",
        coalesce.(
            occursin.(r"smithville"i,
                            location_city_event_clean), false
                            ) => "MOUNT AYR",
        coalesce.(
            occursin.(r"st.*charles"i,
                            location_city_event_clean), false
                            ) => "SAINT CHARLES",
        coalesce.(
            occursin.(r"odeboldt"i,
                            location_city_event_clean), false
                            ) => "ODEBOLT",
        coalesce.(
            occursin.(r"kilduff"i,
                            location_city_event_clean), false
                            ) => "KILLDUFF",
        coalesce.(
            occursin.(r"cresent"i,
                            location_city_event_clean), false
                            ) => "CRESCENT",
        coalesce.(
            occursin.(r"melcher"i,
                            location_city_event_clean), false
                            ) => "MELCHER-DALLAS",
        true => location_city_event_clean
    )
    @mutate location_city_event_clean = str_squish.(location_city_event_clean)
    @mutate location_city_event_clean = str_replace_all.(location_city_event_clean, r"[^A-Za-z0-9\s]+", " ")
    @mutate location_city_event_clean = ifelse(
        coalesce.(
            occursin.(r"melcher"i, location_city_event_clean), false),
            "MELCHER-DALLAS", location_city_event_clean
        )
end

    # __________________________________________________________________________
    # Extract actual location using city_extension_pattern
    # __________________________________________________________________________
    aed_final.location = str_extract.(aed_final.location_city_event_clean, city_extension_pattern)

    ###_________________________________________________________________________
    # If location is missing and the event is not "MEDIC AMBULANCE",
    # fall back to location_city_event_clean
    ###_________________________________________________________________________

    aed_final = @chain aed_final begin
        @relocate(location, after = location_city_event_clean)
        @mutate(
        location = ifelse.(
            ismissing.(location) .&
            (location_city_event_clean .!= "MEDIC AMBULANCE"),
            coalesce.(location, ""),
            location
        )
    )

    # __________________________________________________________________________
    # Join Iowa_Data_Final attributes
    # __________________________________________________________________________
    @left_join(
        select(iowa_data_final, :name, :name_county, :county_fips, :district,
            :designation, :urbanicity, :asciiname, :latitude, :longitude, :population, :elevation),
        location = name
    )

    # Relocate associated attributes next to location
    @relocate(
        name_county, county_fips, district, designation, urbanicity, asciiname,
        latitude, longitude, population, elevation,
        after = location
    )
end

###_____________________________________________________________________________
# Write the AED data to XLSX ----
###_____________________________________________________________________________

XLSX.writetable("./output/data/aed_final.xlsx", "aed_data" => aed_final)