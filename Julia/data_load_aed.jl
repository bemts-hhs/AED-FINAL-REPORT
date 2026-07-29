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

# define the data type specifications for the custom function xlsx_cell_range_to_df

spec = [Date, Time, Time, Time, Time, String, Number, Any, Any, Any, Any, String, Any, String, Bool, Bool, String, Bool, Bool, Bool, Bool, Number, String, String, Bool, Bool, Bool, Bool, Bool, Any, Bool, Number, Number, Number, Number, Number, Number, String]

# read in AED data using a custom function
aed_raw = xlsx_cell_range_to_df(
    aed_data_path, "VALID DATA ENTRY", "A1:AL2399"; 
    clean_up = true, 
    type_spec = spec
);


