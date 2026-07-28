###_____________________________________________________________________________
# Prepare EMS Data for Analysis
# Run this script first before moving on to analyses
# Must run setup.jl before running this script
###_____________________________________________________________________________

# first load custom functions
include("functions.jl")

###_____________________________________________________________________________
# read in the data
###_____________________________________________________________________________

# read in AED data using a custom function
aed_raw = xlsx_cell_range_to_df(
    aed_data_path, "VALID DATA ENTRY", "A1:AL2399"; clean_up=true
)