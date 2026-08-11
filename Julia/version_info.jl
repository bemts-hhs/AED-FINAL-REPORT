###_____________________________________________________________________________
# Create the version info table for the corresponding AED report section ----
###_____________________________________________________________________________

##  load custom functions if not already done ----
include("functions.jl");

##  get the version info as a DataFrame ----
version_info = get_versioninfo_table()

##  write to disk as a .xlsx file ----
XLSX.writetable(
    "output/version/version_info.xlsx",
    "version" => version_info
);