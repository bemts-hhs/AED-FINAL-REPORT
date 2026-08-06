# Iowa First Responder AED (FRAED) Initiative

## Data Engineering and Processing Workflow

### 2021–2026 Analytical Pipeline

## Overview

This repository contains the full data‑processing workflow used to prepare, clean, and integrate Automated External Defibrillator (AED) deployment records with Iowa ImageTrend Elite EMS registry data for the 2021–2026 Iowa First Responder AED (FRAED) Initiative. The analysis supports epidemiologic surveillance of out‑of‑hospital cardiac arrest (OHCA), describes law enforcement officer (LEO) involvement in early defibrillation, and provides the analytic foundation for the FRAED Initiative Report produced by the Bureau of Emergency Medical and Trauma Services (BEMTS).

In 2020, Iowa Health and Human Services received a $10,116,557 Helmsley Charitable Trust grant to equip LEOs with AEDs statewide. The AED distribution process, survey‑based data collection, EMS registry augmentation, and the final integrated analytical dataset are produced through the scripts documented in this repository.

## Repository Structure

```
├──Julia/
│   └── data_load_aed.jl # AED data ingestion and preprocessing
│   └── data_load_ems.jl # EMS data ingestion and preprocessing
│   └── functions.jl # Custom parsing, regex, timestamp correction utilities
│   └── geolocatoin.jl # Data ingestion and processing for geolocation
│   └── setup.jl # Environment, package loading, .env configuration
│   └── src.jl # Code to produce all analyses and plots
└── Project.toml # Project dependencies
└── README.md
```

## Dependencies

The project uses Julia and the following key packages:

* CSV
* DataFrames
* DataFramesMeta
* Dates
* DotEnv
* Downloads
* Impute
* PrettyTables
* Quarto
* Random
* Tidier
* TidierDates
* TidierPlots
* TidierStrings
* XLSX
* ZipFile

All packages are instantiated through `Pkg.activate()` and `Pkg.instantiate()`.

## Environment Variables

A `.env` file controls file paths and output locations.

Variables include:

* `aed_env` – Raw AED survey data file
* `ems_data_env` – ImageTrend Elite EMS registry export
* `iowa_county_district_env` – Reference table for Iowa municipalities and counties
* `output_directory` – Output data folder
* `us_zips`, `us_counties` – Geospatial reference files

The file is created automatically if missing and then loaded into `ENV[]`.

## AED Data Processing

`data_load_aed.jl` implements an end‑to‑end cleaning pipeline:

### Key Steps

1. **Ingest XLSX AED dataset** using a custom parser `xlsx_cell_range_to_df()`.
2. **Feature Engineering**
   * Timestamp reconstruction (AED on/off, EMS arrival times).
   * Midnight‑rollover correction using `correct_midnight_rollover()`.
   * Time‑interval calculations (call‑to‑patient, call‑to‑AED, total AED use).
3. **Clinical Feature Derivation**
   * Utstein indicators (bystander CPR, witnessed, shock).
   * Age standardization and categorization.
   * Agency and agency‑type classification.
4. **Location Standardization**
   * Regex‑driven normalization.
   * Deterministic corrections for mis‑recorded city names.
   * Integration with Iowa GNIS‑based city/county reference data.
5. **Output**
   * Cleaned dataset written to `./output/data/aed_final.xlsx`.

## EMS Data Processing

`data_load_ems.jl` prepares EMS registry data for linkage and analysis.

### Key Steps

1. **Ingest EMS CSV export** and normalize variable names.
2. **Timestamp Parsing** using TidierDates (MDY, MDY‑HMS).
3. **Interval Construction**
   * Dispatch‑to‑scene
   * Dispatch‑to‑patient
4. **Defibrillation Procedure Extraction**
   * Regex identification of AED and manual defibrillation procedures.
   * Per‑incident shock count summarization.
5. **One‑to‑Many to One‑Row Restructuring**
   * Grouped concatenation of procedures and medications.
6. **Clinical Indicators**
   * Witnessed status.
   * CPR prior to EMS arrival.
   * ROSC classifications (field/ED).
   * Survival categorization.
7. **County FIPS Reconstruction**
   * GNIS code length‑based correction and left joins with geography.
8. **Output**
   * Final analytical dataset written to `./output/data/ems_aed_runs.xlsx`.

## Custom Functions

All custom utilities (timestamp correction, regex generators, ID creation, string parsing) are stored in `functions.jl`. These functions enable consistent processing across AED and EMS datasets.

## Geospatial Reference Processing

`geolocation.jl` ingests and prepares geolocation data for this project.

The project uses several external geospatial datasets to support deterministic city‑to‑county matching for AED and EMS incidents. These data are processed in a dedicated step prior to AED and EMS integration.

### Iowa County, District, and Urbanicity Reference Table

The script ingests the Iowa county and regional preparedness table from the file specified in `iowa_county_district_env`. Column names are standardized and county FIPS values are coerced to character type.

### United States ZIP Code Data

ZIP Code Tabulation Area (ZCTA) data are downloaded from the U.S. Census Bureau and imported as a delimited pipe (`|`) file. The workflow retains the distinct ZCTA GEOIDs for downstream geospatial joins.

### Geonames U.S. Populated Places

The Geonames U.S. dataset is downloaded, unzipped, and read in‑memory. The script assigns official Geonames column names, filters the dataset to Iowa, removes historical place labels, corrects county codes, and pads numeric codes to ensure join integrity.

### Geonames U.S. Counties

County names and codes are imported from the Geonames county dataset. Codes are parsed to extract country, state, and county components. Iowa counties are retained and cleaned for matching.

### Construction of the Iowa City‑County Reference Table

The Iowa city table (`iowa_data_final`) is constructed by:

* Joining Geonames cities to Geonames counties.
* Joining both to the Iowa county/district reference table.
* Applying deterministic filters to remove known Geonames mismatches.
* Standardizing names to uppercase.
* Selecting and relocating geographic attributes for consistency.

### Manual Additions for Missing Municipalities

Several Iowa municipalities are absent from Geonames. These locations are added manually with verified coordinates, county assignments, and regional preparedness districts. The records are harmonized to match the `iowa_data_final` schema and appended to the main dataset.

### Output

The finalized statewide reference table is exported to:

```
./output/data/iowa_data_final.xlsx
```

## Reproducibility

### To run the project with similar data:

```
julia setup.jl
julia geolocation.jl
julia functions.jl
julia data_load_aed.jl
julia data_load_ems.jl
julia src.jl
```

Ensure all paths in `.env` are set correctly.

## Contact

For questions related to epidemiologic methods, data ingestion, or analytic reproducibility, contact BEMTS via iowahhsbemts@hhs.iowa.gov.