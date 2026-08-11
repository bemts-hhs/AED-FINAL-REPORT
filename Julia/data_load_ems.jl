###_____________________________________________________________________________
# Only need to run this script if setup.jl does not pull in processed data
# Check the .\output\data\ directory and the global environment, first
###_____________________________________________________________________________
# Prepare EMS Data for Analysis ----
# Run this script first before moving on to analyses
# Must run setup.jl before running this script
###_____________________________________________________________________________

###_____________________________________________________________________________
##  read in the data ----
###_____________________________________________________________________________

##  read in the data ----
ems_raw = CSV.read(ems_data_path, DataFrame);

##  clean names ----
ems_raw = @chain ems_raw begin
    @clean_names
    @rename_with str -> str_remove_all(str, r"\(|\)")
    @rename_with str -> str_replace_all(str, r"=", "_")
end;

##  manipulations to prepare EMS data for analysis ----
# clean the EMS data for comparison
ems_aed = @chain ems_raw begin
    @distinct
    @mutate(
        incident_date = TidierDates.mdy.(incident_date),
        incident_date_time =
            TidierDates.mdy_hms.(incident_date_time), incident_unit_notified_by_dispatch_date_time_e_times_03 =
            TidierDates.mdy_hms.(incident_unit_notified_by_dispatch_date_time_e_times_03), incident_unit_arrived_on_scene_date_time_e_times_06 =
            TidierDates.mdy_hms.(incident_unit_arrived_on_scene_date_time_e_times_06), incident_unit_arrived_at_patient_date_time_e_times_07 =
            TidierDates.mdy_hms.(incident_unit_arrived_at_patient_date_time_e_times_07), procedure_performed_date_time_e_procedures_01 =
            TidierDates.mdy_hms.(procedure_performed_date_time_e_procedures_01)
    )
    @mutate(incident_dispatch_notified_to_unit_arrived_on_scene_in_minutes =
            difftime(incident_unit_arrived_on_scene_date_time_e_times_06, incident_unit_notified_by_dispatch_date_time_e_times_03, "minutes"
            ),
        incident_dispatch_notified_to_unit_arrived_at_patient_in_minutes =
            TidierDates.difftime.(
                incident_unit_arrived_at_patient_date_time_e_times_07,
                incident_unit_notified_by_dispatch_date_time_e_times_03,
                "minutes",
            ),
        cardiac_arrest_who_provided_cpr_prior_to_ems_arrival_list_3_4_e_arrest_06_3_5_it_arrest_106 = TidierStrings.str_remove_all.(
            cardiac_arrest_who_provided_cpr_prior_to_ems_arrival_list_3_4_e_arrest_06_3_5_it_arrest_106, "\"",
        )
    )
    @filter length.(string.(agency_number_d_agency_02)) .== 7
end;

###_____________________________________________________________________________
# Analyze EMS data ----
###_____________________________________________________________________________

##  get all unique procedures, examine ----
all_procedures = @chain ems_aed begin
    @select procedure_performed_description_e_procedures_03
    @distinct
    @arrange procedure_performed_description_e_procedures_03
end;

#= 
get patients with defibrillation procedures
select only procedure, date/time, and # attempts
get the unique run IDs with defib using filter
get the @distinct rows which will be unique run ID, procedure, date/time, and # of shocks, so you have each row as a @distinct procedure with date/time and # shocks
take the sum of the procedures per Run ID which gives you # of shocks total
over all defib procedures  
=#

##  1. Select relevant variables ----
df = select(
    ems_aed,
    :fact_incident_pk,
    :procedure_performed_description_e_procedures_03,
    :procedure_performed_date_time_e_procedures_01,
    :procedure_number_of_attempts_e_procedures_05,
)

##  2. Filter defibrillation procedures ----
pattern =
    r"automatic external cardiac defibrillator (physical object)|cv - automated external defibrillator|automatic cardiac defibrillator (physical object)|cv - defibrillation - manual|defibrillation, aed|electrical cardioversion (& defibrillation)|cv - cardioversion|cardiac resuscitation|management of external defibrillation"i

df = df[
    occursin.(pattern, coalesce.(df.procedure_performed_description_e_procedures_03, "")),
    :,
]

##  3. Distinct rows ----
df = @distinct df

##  4. Coalesce missings ----
df.procedure_performed_description_e_procedures_03 =
    coalesce.(df.procedure_performed_description_e_procedures_03, "")

df.procedure_performed_date_time_e_procedures_01 =
    coalesce.(df.procedure_performed_date_time_e_procedures_01, "")

df.procedure_number_of_attempts_e_procedures_05 =
    coalesce.(df.procedure_number_of_attempts_e_procedures_05, 1)

##  5. Group by run ID ----
gdf = groupby(df, :fact_incident_pk)

##  6. Summarize exactly as your mutate block intended ----
ems_aed_defib = combine(gdf,
    :procedure_number_of_attempts_e_procedures_05 => sum => :shocks,
    :procedure_performed_description_e_procedures_03 =>
        (x -> join(x, ", ")) => :procedure_performed_description_e_procedures_03,
    :procedure_performed_date_time_e_procedures_01 =>
        (x -> join(x, ", ")) => :procedure_performed_date_time_e_procedures_01,
    :procedure_number_of_attempts_e_procedures_05 =>
        (x -> join(string.(x), ", ")) => :procedure_number_of_attempts_e_procedures_05,
)

##  7. Final distinct ----
ems_aed_defib = unique(ems_aed_defib)

##  just get the shocks as a separate object for the join ----
ems_shocks = select(
    ems_aed_defib,
    :fact_incident_pk,
    :shocks
)

##  deal with multiple procedures to reduce the rows to 1 row = 1 run, no duplication ----

##  date manipulation and relocate new features ----
ems_aed_runs_dates = @chain ems_aed begin
    @distinct
    @mutate(
        incident_day = TidierDates.dayname(incident_date),
        incident_month = TidierDates.monthname(incident_date)
    )
    @mutate(
        weekday_weekend = incident_day ∈ ["Saturday" "Sunday"],
        season = ifelse(
            incident_month ∈ ["December" "January" "February"],
            "Winter",
            ifelse(
                incident_month ∈ ["March" "April" "May"],
                "Spring",
                ifelse(
                    incident_month ∈ ["June" "July" "August"],
                    "Summer",
                    "Fall",
                ),
            ),
        )
    )
    @relocate(incident_day, incident_month, weekday_weekend, season, after=incident_date
    )
end;

##  temporary dataframe to conduct some manipulations on one-to-many features ----
# procedures
ems_aed_runs_temp_unique_proc = unique(
    select(ems_aed_runs_dates, :fact_incident_pk,
        :incident_complaint_reported_by_dispatch_dispatch_reason_e_dispatch_01,
        :procedure_performed_date_time_e_procedures_01, :procedure_performed_description_e_procedures_03, :procedure_number_of_attempts_e_procedures_05)
)

##  split - group the temp table ----
ems_aed_runs_temp_proc_group = groupby(ems_aed_runs_temp_unique_proc,
    :fact_incident_pk)

##  apply string concatenation and combine the temp table - procedures ----
ems_aed_runs_temp_proc_concat = unique(
    combine(
        ems_aed_runs_temp_proc_group,
        :incident_complaint_reported_by_dispatch_dispatch_reason_e_dispatch_01 =>
            (x -> join(unique(x), ", ")) => :incident_complaint_reported_by_dispatch_dispatch_reason_e_dispatch_01,
        :procedure_performed_description_e_procedures_03 =>
            (x -> join(unique(x), ", ")) => :procedure_performed_description_e_procedures_03,
        :procedure_performed_date_time_e_procedures_01 =>
            (x -> join(x, ", ")) => :procedure_performed_date_time_e_procedures_01,
        :procedure_number_of_attempts_e_procedures_05 =>
            (x -> join(x, ", ")) => :procedure_number_of_attempts_e_procedures_05, renamecols=false
    )
)

##  temporary dataframe to conduct some manipulations on one-to-many features ----
# procedures
ems_aed_runs_temp_unique_med = unique(
    select(ems_aed_runs_dates, :fact_incident_pk,
        :medication_given_or_administered_description_e_medications_03, :medication_response_e_medications_07
    )
)

##  split - group the temp table ----
ems_aed_runs_temp_med_group = groupby(ems_aed_runs_temp_unique_med,
    :fact_incident_pk)

##  apply string concatenation and combine the temp table - medications ----
ems_aed_runs_temp_med_concat = unique(
    combine(
        ems_aed_runs_temp_med_group,
        :medication_given_or_administered_description_e_medications_03 =>
            (x -> join(x, ", ")) => :medication_given_or_administered_description_e_medications_03,
        :medication_response_e_medications_07 =>
            (x -> join(x, ", ")) => :medication_response_e_medications_07, renamecols=false
    )
);

##  get the distinct ems_aed table ----
ems_aed_unique = @chain ems_aed_runs_dates begin
    @distinct fact_incident_pk
end;

##  join now one-to-one EMS data to fact table ----
ems_aed_runs = @chain ems_aed_unique begin
    @ungroup
    @select(
        -(
        incident_complaint_reported_by_dispatch_dispatch_reason_e_dispatch_01, 
		procedure_performed_description_e_procedures_03,
		procedure_performed_date_time_e_procedures_01,
		procedure_number_of_attempts_e_procedures_05,
        medication_given_or_administered_description_e_medications_03,
        medication_response_e_medications_07,
        )
    )
    @left_join(ems_aed_runs_temp_proc_concat, fact_incident_pk = fact_incident_pk)
    @left_join(ems_aed_runs_temp_med_concat, fact_incident_pk = fact_incident_pk)
    @left_join(ems_shocks, fact_incident_pk = fact_incident_pk)
    @relocate(
        incident_complaint_reported_by_dispatch_dispatch_reason_e_dispatch_01, after = agency_name_d_agency_03
    )
    @relocate(
        procedure_performed_description_e_procedures_03, 
		procedure_performed_date_time_e_procedures_01,
		procedure_number_of_attempts_e_procedures_05,
        after = cardiac_arrest_who_provided_cpr_prior_to_ems_arrival_list_3_4_e_arrest_06_3_5_it_arrest_106
    )
    @relocate(
		medication_given_or_administered_description_e_medications_03,
		medication_response_e_medications_07,
        after = cardiac_arrest_patient_outcome_at_end_of_ems_event_e_arrest_18
    )
    @relocate(shocks, after = procedure_number_of_attempts_e_procedures_05)
    @mutate(
        witnessed = .!occursin.(r"not"i, coalesce.(cardiac_arrest_witnessed_by_list_e_arrest_04, "")),
        cardiac_arrest_cpr_provided_prior_to_ems_arrival_3_4_e_arrest_05_3_5_it_arrest_105 = coalesce.(cardiac_arrest_cpr_provided_prior_to_ems_arrival_3_4_e_arrest_05_3_5_it_arrest_105, "Not Recorded")
    )
    @mutate(
        cardiac_arrest_cpr_provided_prior_to_ems_arrival_3_4_e_arrest_05_3_5_it_arrest_105 = ifelse.(
            ismissing.(cardiac_arrest_cpr_provided_prior_to_ems_arrival_3_4_e_arrest_05_3_5_it_arrest_105) .&
            (
                .!ismissing.(cardiac_arrest_who_initiated_cpr_3_4_it_arrest_008_3_5_e_arrest_20)
                .&
                .!occursin.(r"responding ems personnel|first responder \(ems\)"i, coalesce.(cardiac_arrest_who_initiated_cpr_3_4_it_arrest_008_3_5_e_arrest_20, ""))
            ) .|
            .!ismissing.(cardiac_arrest_who_provided_cpr_prior_to_ems_arrival_list_3_4_e_arrest_06_3_5_it_arrest_106), "yes", cardiac_arrest_cpr_provided_prior_to_ems_arrival_3_4_e_arrest_05_3_5_it_arrest_105,
        )
    )
    @mutate(
        cardiac_arrest_cpr_provided_prior_to_ems_arrival_3_4_e_arrest_05_3_5_it_arrest_105 = coalesce.(cardiac_arrest_cpr_provided_prior_to_ems_arrival_3_4_e_arrest_05_3_5_it_arrest_105, "no"
        ),
        situation_possible_overdose = coalesce.(situation_possible_overdose, false),
        incident_dispatch_notified_to_unit_arrived_at_patient_in_minutes =
            coalesce.(
                incident_dispatch_notified_to_unit_arrived_at_patient_in_minutes,
                median(
                    skipmissing(incident_dispatch_notified_to_unit_arrived_at_patient_in_minutes),
                ),
            ),
        incident_dispatch_notified_to_unit_arrived_on_scene_in_minutes =
            coalesce.(
                incident_dispatch_notified_to_unit_arrived_on_scene_in_minutes,
                median(
                    skipmissing(
                        incident_dispatch_notified_to_unit_arrived_on_scene_in_minutes,
                    ),
                ),
            ),
        cardiac_arrest_patient_outcome_at_end_of_ems_event_e_arrest_18 = ifelse.(
            ismissing.(cardiac_arrest_patient_outcome_at_end_of_ems_event_e_arrest_18) .|
            occursin.(r"not applicable|not recorded"i, coalesce.(cardiac_arrest_patient_outcome_at_end_of_ems_event_e_arrest_18, "")) .&
            occursin.(r"dead"i, coalesce.(disposition_incident_patient_disposition_3_4_e_disposition_12_3_5_it_disposition_112, "")), "Expired in the Field", cardiac_arrest_patient_outcome_at_end_of_ems_event_e_arrest_18,
        )
    )
    @mutate(
        rosc_ed = occursin.(
            r"rosc in the ed"i,
            coalesce.(
                cardiac_arrest_patient_outcome_at_end_of_ems_event_e_arrest_18, "",
            ),
        ),
        rosc_field = occursin.(
            r"rosc in the field"i,
            coalesce.(
                cardiac_arrest_patient_outcome_at_end_of_ems_event_e_arrest_18, "",
            ),
        ),
        ongoing_resus_ems = occursin.(
            r"ongoing resuscitation by other ems"i,
            coalesce.(
                cardiac_arrest_patient_outcome_at_end_of_ems_event_e_arrest_18, "",
            ),
        ),
        ongoing_resus_ed = occursin.(
            r"ongoing resuscitation in ed"i,
            coalesce.(
                cardiac_arrest_patient_outcome_at_end_of_ems_event_e_arrest_18, "",
            ),
        ),
        expire_field = occursin.(
            r"expired in the field"i,
            coalesce.(
                cardiac_arrest_patient_outcome_at_end_of_ems_event_e_arrest_18, "",
            ),
        ),
        expire_ed = occursin.(
            r"expired in the ed"i,
            coalesce.(
                cardiac_arrest_patient_outcome_at_end_of_ems_event_e_arrest_18, "",
            ),
        ),
        survival = .!occursin.(
        r"expire"i, cardiac_arrest_patient_outcome_at_end_of_ems_event_e_arrest_18
    ),
        length_scene_incident_county_gnis_e_scene_21 = length.(
            string.(
                coalesce.(scene_incident_county_gnis_e_scene_21, ""),
            ),
        )
    )
    @mutate(
        county_id = ifelse.(
            length_scene_incident_county_gnis_e_scene_21 .== 1,
            lpad.(scene_incident_county_gnis_e_scene_21, 3, "0"),
            ifelse.(
                length_scene_incident_county_gnis_e_scene_21 .== 2,
                lpad.(scene_incident_county_gnis_e_scene_21, 3, "0"),
                ifelse.(
                    length_scene_incident_county_gnis_e_scene_21 .== 0,
                    missing,
                    scene_incident_county_gnis_e_scene_21,
                ),
            ),
        )
    )
    @mutate(
        county_fips = string.(scene_incident_state_gnis_e_scene_18, county_id)
    )
    @left_join(location, county_fips = county_fips)
end;

###_____________________________________________________________________________
# Write the final file to XLSX for further analysis ----
###_____________________________________________________________________________

XLSX.writetable("./output/data/ems_aed_runs.xlsx", "ems_data" => ems_aed_runs)