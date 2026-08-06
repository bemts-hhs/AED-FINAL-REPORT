###_____________________________________________________________________________
# Source code for the AED final report
###_____________________________________________________________________________
# Must at least first run setup.jl to load the necessary packages and data.
###_____________________________________________________________________________

#= 
Demographic analysis
=#

sex_distribution = @chain aed_final begin
    @count
end 