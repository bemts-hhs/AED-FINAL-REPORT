# Iowa First Responder AED (FRAED) Initiative

## Julia Data Engineering, Geospatial Integration, and Analytical Pipeline

### 2021–2026 Workflow Overview

## Overview

This repository contains the full Julia‑based data preparation, geospatial processing, and analytic workflow for the 2021–2026 Iowa First Responder AED (FRAED) Initiative. The workflow integrates statewide Automated External Defibrillator (AED) deployment records with ImageTrend Elite EMS registry data to support epidemiologic surveillance of out‑of‑hospital cardiac arrest and characterize law enforcement officer (LEO) involvement in early defibrillation. All outputs generated from this codebase contribute directly to the FRAED Initiative Final Report produced by the Bureau of Emergency Medical and Trauma Services (BEMTS).

In support of the Helmsley Charitable Trust investment that equipped LEOs with AEDs statewide, this pipeline produces a clean, reproducible AED analytic file, standardized EMS defibrillation and clinical indicators, and all geospatial and descriptive products used throughout the report.

## Repository Structure

```
Julia/
│   setup.jl              # Environment setup, package loading, .env configuration
│   geolocation.jl        # Geonames, Census shapefiles, county/district integration
│   functions.jl          # Custom utilities: regex, ID generation, timestamp correction
│   data_load_aed.jl      # AED ingestion, preprocessing, feature engineering
│   data_load_ems.jl      # EMS ingestion, timestamp parsing, clinical indicators
│   src.jl                # Full analytical pipeline, visualizations, tables, maps
Project.toml              # Julia project dependencies
```

## Core Workflow

### 1. Data Ingestion and Pre‑processing

The pipeline ingests raw AED and EMS extracts and constructs all analytic features needed for epidemiologic analysis:

* Structured ingestion of XLSX AED data via `xlsx_cell_range_to_df()`.
* Deterministic construction and correction of AED and EMS timestamps, including midnight rollover fixes.
* Time‑interval derivation (call‑to‑patient, call‑to‑AED‑on, AED duration).
* Age normalization and grouping, call‑type derivation, agency classification.
* Standardization and deterministic correction of location names using regex utilities and reference data.
* Creation of privacy‑preserving surrogate incident identifiers.

Final AED output:  
`./output/data/aed_final.xlsx`

Final EMS output:  
`./output/data/ems_aed_runs.xlsx`

### 2. Geospatial Reference Integration

The project incorporates multiple geospatial sources to support deterministic city‑to‑county matching and statewide spatial analysis:

* Geonames U.S. populated places and counties.
* U.S. Census county and state shapefiles.
* Iowa county, preparedness district, and urbanicity reference data.
* Manual additions for Iowa municipalities absent from Geonames.

Final geographic reference output:  
`./output/data/iowa_data_final.xlsx`

### 3. Analytical Outputs for the FRAED Report

`src.jl` generates all descriptive and geospatial products used throughout the final report:

* AED deployments by year, call type, agency type, district, and city.
* Witnessed arrest and bystander CPR conditional probability tables.
* Survival outcomes by year, sex, age group, call type, and urbanicity.
* National and Iowa heart disease mortality maps.
* AED deployment location maps and district overlays.

These outputs establish the quantitative foundation for the FRAED narrative and data visualizations.

## Running the Pipeline

Execute the workflow in sequence:

```
julia setup.jl
julia functions.jl
julia geolocation.jl
julia data_load_aed.jl
julia data_load_ems.jl
julia src.jl
```

Ensure all paths in `.env` are configured for your environment.

## Contact

For questions related to epidemiologic methods, data ingestion, or analytic reproducibility, contact BEMTS via iowahhsbemts@hhs.iowa.gov.