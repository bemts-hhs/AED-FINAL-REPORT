###_____________________________________________________________________________
# Prepare EMS Data for Analysis
# Run this script first before moving on to analyses
# Must run setup.jl before running this script
###_____________________________________________________________________________

###_____________________________________________________________________________
# read in the data
###_____________________________________________________________________________

# define the data type specifications for the custom function xlsx_cell_range_to_df

spec = [Date, Time, Time, Time, Time, String, Number, Any, Any, Any, Any, String, Any, String, Bool, Bool, String, Bool, Bool, Bool, Bool, Number, String, String, Bool, Bool, Bool, Bool, Bool, Any, Bool, Number, Number, Number, Number, Number, Number, String]

# read in AED data using a custom function
aed_raw = xlsx_cell_range_to_df(
    aed_data_path, "VALID DATA ENTRY", "A1:AL2399";
    clean_up=true,
    type_spec=spec
);

# aed observations
aed_n_obs = nrow(aed_raw)

#= 
conduct manipulations on the aed_raw dataset in order to create new features
mostly for time intelligence and convenient categories
=#

# make a copy of the aed_raw dataset
aed_data = deepcopy(aed_raw)

# add the unique incident id directly, cannot do this inside @chain
aed_data.unique_incident_id = generate_random_id(aed_n_obs; seed=10232015)

# manipulations using @chain
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

# correct the ambulance to patient timestamp
aed_final_init.amb_pat_timestamp_fix =
    correct_midnight_rollover(aed_final_init, :amb_toc_timestamp, :amb_pat_timestamp)

# calculate the time aed off
aed_final_init.time_aed_off = time_string_extract(
    aed_final_init, :total_time_aed_actually_used_min_sec, :time_aed_on
    )

# get the time aed off timestamp
aed_final = @chain aed_final_init begin
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

# correct the time aed off and on relationship
aed_final.time_aed_off_timestamp_fix = 
    correct_midnight_rollover(aed_final, :time_aed_on_timestamp, :time_aed_off_timestamp)