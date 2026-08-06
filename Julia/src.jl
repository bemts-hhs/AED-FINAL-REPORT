###_____________________________________________________________________________
# Source code for the AED final report
###_____________________________________________________________________________
# Must at least first run setup.jl to load the necessary packages and data.
###_____________________________________________________________________________

#= 
Demographic analysis
=#

sex_distribution = @chain aed_final begin
    @count sex
    @mutate sex = coalesce.(
        sex, "Unknown"
    )
    @mutate percent = string.(
                round(n ./ sum(n) * 100; digits = 2), "%"
            )
end