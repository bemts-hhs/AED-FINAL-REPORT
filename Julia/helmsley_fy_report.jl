###_____________________________________________________________________________
# Report on FY performance of the Helmsley FRAED Grant ----
# Assumes that the aed_final object is in memory
###_____________________________________________________________________________

@chain aed_final begin
    @mutate helmsley_fy = case_when(
        date_of_use .> Date("2021-04-30") .&& date_of_use .< Date("2022-05-01") => "FY2022",
         date_of_use .> Date("2022-04-30") .&& date_of_use .< Date("2023-05-01") => "FY2023",
         date_of_use .> Date("2023-04-30") .&& date_of_use .< Date("2024-05-01") => "FY2024",
         date_of_use .> Date("2024-04-30") .&& date_of_use .< Date("2025-05-01") => "FY2025",
        date_of_use .> Date("2025-04-30") .&& date_of_use .< Date("2026-05-01") => "FY2026",
        date_of_use .>= Date("2026-05-01") => "FY2027",
        true => "Unknown"
    )
    @distinct unique_incident_id
    @group_by helmsley_fy
    @summarize(
        survival = sum(survival .== "Survived"),
        n = n()
    )
    @mutate percent = survival ./ n
    @arrange helmsley_fy
    @summarize(
        mean_n = mean(n),
        mean_pct = mean(percent)
    )
end