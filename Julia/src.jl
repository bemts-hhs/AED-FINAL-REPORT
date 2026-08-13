###_____________________________________________________________________________
# Source code for the AED final report ----
###_____________________________________________________________________________
# Must at least first run setup.jl to load the necessary packages and data.
###_____________________________________________________________________________

# Ingest heart disease mortality data ----
# Access the CDC heart disease data Socrata API feed for heart disease mortality data
heart_disease_response = HTTP.get(us_heart_disease_mortality)

## full US heart disease mortality dataset ----
heart_disease_data_full = CSV.read(IOBuffer(heart_disease_response.body), DataFrame)

## base dataset for future work, take out sex and race based adjustments ----
heart_disease_data = @chain heart_disease_data_full begin
    @filter begin
        stratification1 == "Overall" && stratification2 == "Overall"
    end
end

## Filter data down to states ----
heart_disease_data_state = @chain heart_disease_data begin
    @mutate locationid = lpad.(string.(locationid), 2, "0")
    @filter begin
        geographiclevel == "State" &&

        # remove states outside the continental US
            !(locationid ∈ ["02", "11", "15", "60", "66", "69", "72", "78"])
    end
    @right_join(
        state_geo, locationid = STATEFP
    )
end

## filter data down to county ----
heart_disease_data_county = @chain heart_disease_data begin
    @mutate locationid = lpad.(string.(locationid), 3, "0")
    @filter begin
        geographiclevel == "County" &&

        # remove states outside the continental US
            locationabbr == "IA"
    end
    @right_join(
        county_geo, locationid = COUNTYFIPS
    )
    @mutate COUNTY_NAME = str_squish.(
        str_remove(locationdesc, r"\s+county$"i)
    )
    @left_join(
        select(location, :county, :region_preparedness), COUNTY_NAME = county
    )
end

## Filter data down to national ----
heart_disease_data_national = @chain heart_disease_data begin
    @filter geographiclevel == "Nation"
    @select data_value
end

###_____________________________________________________________________________
# Geographic analysis - heart disease data for the US ----
###_____________________________________________________________________________


## get the centroid of the continental US ----

#= 
This uses GeometryOps to compute a single (lon, lat) coordinate that represents
the center of all state geometries. It is used to center the orthographic 
projection so the United States appears centered and natural on the map.
=#
us_centroid = GeometryOps.centroid(heart_disease_data_state.geometry)

## Create a GeoMakie scene ----

#= 
A Makie `Figure` is the plotting canvas; `GeoAxis` is the spatial axis that 
understands geographic projections and can draw polygon geometries correctly.
=#
us_map = Figure();
us_ax = GeoAxis(us_map[1, 1],

    # remove grids
    # These settings hide all gridlines and minor gridlines for a cleaner map.
    xgridvisible=false,
    ygridvisible=false,
    xminorgridvisible=false,
    yminorgridvisible=false,

    # remove axis labels and tick labels 
    # Maps generally do not need numeric axes, so we hide them for aesthetics.
    xlabelvisible=false,
    ylabelvisible=false,
    xticklabelsvisible=false,
    yticklabelsvisible=false,

    # set limits to zoom in map
    # This defines the geographic bounding box for the map before projection.
    # The values correspond to (min_lon, max_lon, min_lat, max_lat), which 
    # tighten the view around the continental U.S. to remove excess whitespace.
    limits=(-122, -70, 25, 48);

    # Build a GeoAxis with an orthographic projection centered on the U.S.
    # Orthographic projection creates a "globe-like" view. Here it is centered 
    # using the centroid computed above, ensuring the U.S. appears in the middle
    # of the projection and is not distorted by off-center geometry.
    dest="+proj=ortho +lon_0=$(us_centroid[1]) +lat_0=$(us_centroid[2])"
);

## Build a color map based on data_value ----
# `vals` contains the CDC age-adjusted mortality rates. Missing values are 
# replaced with NaN so Makie’s color pipeline can handle them. Then we compute 
# the min/max to ensure the colorbar matches the actual range of the data.
us_vals = coalesce.(heart_disease_data_state.data_value, NaN);
us_min_val = minimum(skipmissing(heart_disease_data_state.data_value));
us_max_val = maximum(skipmissing(heart_disease_data_state.data_value));

## A reversed Viridis colormap (longer dark-to-light gradient) ----
# This gives high mortality rates brighter/lighter color tones.
cmap = cgrad(:inferno, 256, rev=true); # Makie colormap

## Build polygon objects from your geometries ----
# `poly!` directly plots the vector geometries stored in the `geometry` column.
# All state polygons are drawn using the orthographic projection defined above.
poly!(us_ax, heart_disease_data_state.geometry,
    color=us_vals,
    colormap=cmap,
    strokewidth=0.5,
    strokecolor=:white
);

## Add a colorbar below the map ----
# The colorbar uses the same colormap and data range. Font settings align with
# HHS design style (Work Sans). Setting `vertical = false` makes it horizontal.
Colorbar(
    us_map[2, 1],
    limits=(us_min_val, us_max_val),
    colormap=cmap,
    vertical=false,
    label="Age-adjusted rate per 100k population",
    labelfont="Work Sans",
    ticklabelfont="Work Sans"
)

## Save the output image to disk ----
# This writes the entire figure to a PNG file in your output directory.
save("./output/plots/us_map.png", us_map)

###_____________________________________________________________________________
# Geographic analysis - heart disease data for the state of Iowa, USA ----
###_____________________________________________________________________________

## get the centroid of the state of Iowa, USA ----

#= 
This uses GeometryOps to compute a single (lon, lat) coordinate that represents
the center of all state geometries. It is used to center the orthographic 
projection so the United States appears centered and natural on the map.
=#
ia_centroid = GeometryOps.centroid(heart_disease_data_county.geometry);

## Create a GeoMakie scene ----
#= 
A Makie `Figure` is the plotting canvas; `GeoAxis` is the spatial axis that 
understands geographic projections and can draw polygon geometries correctly.
=#
ia_map = Figure();
ia_ax = GeoAxis(ia_map[1, 1],

    # remove grids
    # These settings hide all gridlines and minor gridlines for a cleaner map.
    xgridvisible=false,
    ygridvisible=false,
    xminorgridvisible=false,
    yminorgridvisible=false,

    # remove axis labels and tick labels 
    # Maps generally do not need numeric axes, so we hide them for aesthetics.
    xlabelvisible=false,
    ylabelvisible=false,
    xticklabelsvisible=false,
    yticklabelsvisible=false,

    # Build a GeoAxis with an orthographic projection centered on the U.S.
    # Orthographic projection creates a "globe-like" view. Here it is centered 
    # using the centroid computed above, ensuring the U.S. appears in the middle
    # of the projection and is not distorted by off-center geometry.
    dest="+proj=ortho +lon_0=$(ia_centroid[1]) +lat_0=$(ia_centroid[2])");

## Build a color map based on data_value ----
# `vals` contains the CDC age-adjusted mortality rates. Missing values are 
# replaced with NaN so Makie’s color pipeline can handle them. Then we compute 
# the min/max to ensure the colorbar matches the actual range of the data.
ia_vals = coalesce.(heart_disease_data_county.data_value, NaN);
ia_min_val = minimum(skipmissing(heart_disease_data_county.data_value));
ia_max_val = maximum(skipmissing(heart_disease_data_county.data_value));

## A reversed Viridis colormap (longer dark-to-light gradient) ----
# This gives high mortality rates brighter/lighter color tones.
cmap = cgrad(:inferno, 256, rev=true); # Makie colormap

## Build polygon objects from your geometries ----
# `poly!` directly plots the vector geometries stored in the `geometry` column.
# All state polygons are drawn using the orthographic projection defined above.
poly!(ia_ax, heart_disease_data_county.geometry,
    color=ia_vals,
    colormap=cmap,
    strokewidth=0.5,
    strokecolor=:white
);

## Add a colorbar below the map ----
# The colorbar uses the same colormap and data range. Font settings align with
# HHS design style (Work Sans). Setting `vertical = false` makes it horizontal.
Colorbar(
    ia_map[2, 1],
    limits=(ia_min_val, ia_max_val),
    colormap=cmap,
    vertical=false,
    label="Age-adjusted rate per 100k population",
    labelfont="Work Sans",
    ticklabelfont="Work Sans"
)

## Save the output image to disk ----
# This writes the entire figure to a PNG file in your output directory.
save("./output/plots/ia_map.png", ia_map)

###_____________________________________________________________________________
# Geographic analysis - AED deployment data for the project ----
###_____________________________________________________________________________

## get aed deployoments by district ----
aed_deployments_by_district = @chain aed_final begin
    @distinct unique_incident_id
    @mutate district = str_squish.(string.(district))
    @mutate district = coalesce.(district, "Not Recorded")
    @count district
    @mutate percent = n ./ sum(n)
    @arrange desc(percent)
end

## caluclate aed deployments by city
aed_deployments_by_city = @chain aed_final begin
    @distinct unique_incident_id
    @mutate location = str_squish.(string.(location))
    @mutate location = coalesce.(location, "Not Recorded")
    @count(location, sort=true)
    @mutate percent = n ./ sum(n)
    @arrange desc(percent)
    @filter n .> 46
end

## Use the ia_centroid object from before ----

## get counts by location from the aed data ----
aed_location_counts = @chain aed_final begin
    @distinct unique_incident_id
    @filter begin
        !ismissing(location) &&
            !ismissing(latitude) &&
            !ismissing(longitude)
    end
    @count(
        location, latitude, longitude
    )
    @mutate quantiles = case_when(
        n <= quantile(n, 0.8) => 10,
        n < quantile(n, 0.9) => 15,
        n < quantile(n, 0.99) => 20,
        true => 25
    )
    @mutate quantile_labels = case_when(
        quantiles .== 10 => "01-06",
        quantiles .== 15 => "06-11",
        quantiles .== 20 => "11-47",
        true => "47+"
    )
    @arrange location
end;

## AED Deployment locations ----

#= 
Create a GeoMakie scene
A Makie `Figure` is the plotting canvas; `GeoAxis` is the spatial axis that 
understands geographic projections and can draw polygon geometries correctly.
=#
aed_map = Figure();
aed_ax = GeoAxis(aed_map[1, 1],

    # remove grids
    # These settings hide all gridlines and minor gridlines for a cleaner map.
    xgridvisible=false,
    ygridvisible=false,
    xminorgridvisible=false,
    yminorgridvisible=false,

    # remove axis labels and tick labels 
    # Maps generally do not need numeric axes, so we hide them for aesthetics.
    xlabelvisible=false,
    ylabelvisible=false,
    xticklabelsvisible=false,
    yticklabelsvisible=false,

    # Build a GeoAxis with an orthographic projection centered on the U.S.
    # Orthographic projection creates a "globe-like" view. Here it is centered 
    # using the centroid computed above, ensuring the U.S. appears in the middle
    # of the projection and is not distorted by off-center geometry.
    dest="+proj=ortho +lon_0=$(ia_centroid[1]) +lat_0=$(ia_centroid[2])");

## Get distinct vector of districts ----
districts =
    string.(unique(heart_disease_data_county.region_preparedness)) |> sort;

## number of districts ----
num_districts = length(districts);

## get the vector of districts in the raw data ----
aed_districts = heart_disease_data_county.region_preparedness;

## map each district to an integer as index ----
district_lookup = Dict(
    "1A" => 1,
    "1C" => 2,
    "2" => 3,
    "3" => 4,
    "4" => 5,
    "5" => 6,
    "6" => 7,
    "7" => 8
);

## map each district index to a county ----
aed_color_index = [district_lookup[string(d)] for d in aed_districts];

## Makie colormap ----
aed_cmap = ColorBrewer.palette("Spectral", num_districts);

## Build polygon objects from your geometries ----
# `poly!` directly plots the vector geometries stored in the `geometry` column.
# All state polygons are drawn using the orthographic projection defined above.
poly!(aed_ax, heart_disease_data_county.geometry,
    color=aed_color_index,
    colormap=aed_cmap,
    strokewidth=0.8,
    strokecolor=:white,
    label="Preparedness District"
);
GeoMakie.scatter!(
    aed_ax,
    aed_location_counts.longitude,
    aed_location_counts.latitude,
    color=:black,
    markersize=aed_location_counts.quantiles,
    transparency=true,
    overdraw=true,
    alpha=0.5,
    label="AED Deployment Locations"
);

## create the swatch for the district colors ----
district_swatches = [
    PolyElement(color=aed_cmap[i], strokecolor=:white)
    for i in 1:num_districts
];

## district labels for the legend ----
district_labels = districts;   # e.g. ["1A", "1C", "2", ..., "7", "8"]

## marker size swatch ----
size_values = unique(aed_location_counts.quantiles) |> sort;
size_swatches = [
    MarkerElement(marker=:circle,
        color=:gray25,
        strokecolor=:transparent,
        markersize=s)
    for s in size_values
];

size_labels = str_remove_all.(
    sort(unique(aed_location_counts.quantile_labels)), "0"
);

## combine swatches ----
# Add a Legend to the bottom right of the map
# size legend at the bottom
legend = Legend(
    aed_map[2, 1],
    [district_swatches, size_swatches],
    [districts, size_labels],
    ["Preparedness District", "AED Call Volume"],
    orientation=:horizontal,
    nbanks=2,
    labelfont="Work Sans",
    labelsize=16,
    titlefont="Work Sans",
    titlesize=16,
    autosize=true,
    framevisible=false,
    tellheight=true,
    tellwidth=false
);


## Save the output image to disk ----
# This writes the entire figure to a PNG file in your output directory.
save("./output/plots/aed_map.png", aed_map)

###_____________________________________________________________________________
# Deployment details ----
###_____________________________________________________________________________

## get total deployments ----
total_deployments = unique(aed_final, :unique_incident_id) |> nrow;

## get total responding agencies ----
total_responding_agencies = unique(aed_final.agency) |> length;

## get total responding agencies by year ----
total_responding_agencies_years = @chain aed_final begin
    @distinct year, agency
    @count(year)
    @arrange year
end;

## summarize deploymnets by year ----
aed_deployments_by_year = combine(
    groupby(
        unique(aed_final, :unique_incident_id), :year
    ),
    nrow => :count
);

### plot the deployments by year ----
aed_deployments_plot = Figure();
aed_deployments_plot_axis = Axis(
    aed_deployments_plot[1, 1],
    xticks=(2021:2026, ["2021", "2022", "2023", "2024", "2025", "2026"]),
    title="AED Deployments by Year",
    titlefont="Work Sans",
    titlealign=:left,
    titlesize=18,
    yticklabelsvisible=false,
    xticklabelsize=16,
    xticklabelfont="Work Sans"
);

### aed deployments bar plot ----
barplot!(
    aed_deployments_by_year.year,
    aed_deployments_by_year.count,
    color=aed_deployments_by_year.count,
    strokecolor=:transparent,
    label_size=16,
    bar_labels=:y,
    label_font="Work Sans",
    flip_labels_at=400,
    label_formatter=x -> string(Int(round(x)))
);

### colorbar for the aed deployments bar plot ----
Colorbar(
    aed_deployments_plot[1, 2],
    limits=(
        minimum(aed_deployments_by_year.count),
        maximum(aed_deployments_by_year.count)
    ),
    colormap=:viridis,
    vertical=true,
    labelfont="Work Sans",
    labelsize=16
);

### save the aed deployments bar plot ----
save("./output/plots/aed_deployments_plot.png", aed_deployments_plot);

### get percent change ----
aed_deployments_by_year_add = combine(
    sort(aed_deployments_by_year, :year),
    :year => :year,
    :count => :count,
    :count => (x -> x - lag(x)) => :change,
    :count => (x -> (x - lag(x)) ./ x * 100) => :pct_change
);

## get distinct locations from the aed data ----
distinct_locations = unique(
    filter(:location => l -> !ismissing.(l), aed_final).location
) |> length;

## get missing locations ----
missing_locations = filter(:location => l -> ismissing.(l), aed_final) |> nrow;

## deployments by call type ----
aed_deployments_by_calltype = sort(
    combine(
        groupby(
            unique(aed_final, :unique_incident_id), :call_type
        ),
        nrow => :count,
        proprow => :percent
    ),
    :call_type
);

### get deployments by call type over the years ----
aed_deployments_calltype_year = sort(
    combine(
        groupby(
            unique(aed_final, :unique_incident_id), [:year, :call_type]
        ),
        nrow => :count
    )
);

### get deployments by call type over the years with percent ----
aed_deployments_calltype_year_add = combine(
    groupby(
        filter(
            :call_type => c -> .!(c .== "Unknown"), aed_deployments_calltype_year
        ), :year),
    :call_type => :call_type,
    :count => :count,
    :count => (x -> x ./ sum(x)) => :percent
);

### map call types to integers ----
call_type_dict = Dict(
    "Cardiac Arrest" => 1,
    "Overdose" => 2,
    "Other Cause" => 3
);

### create the call type index ----
call_type_index = [
    call_type_dict[string(d)] for d in aed_deployments_calltype_year_add.call_type
];

### assign plot colors ----
stack_colors = @chain aed_deployments_calltype_year_add begin
    @mutate stack_color = ifelse(
        occursin.(r"Cardiac Arrest|Other Cause"i, call_type) .& (count .> 20), :black,
        ifelse(occursin.(r"Overdose"i, call_type) .& (count .> 20), :white, :transparent)
    )
    @pull stack_color
end;

### deployments by call type horizontal 100% stacked bars ----

### set up the figure ----
aed_deployments_call_type_stacked = Figure();
aed_deployments_call_type_axis = Axis(
    aed_deployments_call_type_stacked[1, 1],
    xticks=(2021:2026, ["2021", "2022", "2023", "2024", "2025", "2026"]),
    #yticks=(0.0:0.25:1.0, ["0.0", "0.25", "0.5", "0.75", "1.0"]),
    title="AED Deployments by Year and Call Type",
    titlefont="Work Sans",
    titlealign=:left,
    titlesize=18,
    yticklabelsvisible=false,
    xticklabelsvisible=true,
    xticklabelsize=16
);

### set a colormap for the stacked bars ----
stacked_cmap = ColorBrewer.palette("Paired", 3);

### need to supply a label vector for stacked bars to avoid cumulative ----
stacked_bar_labels = aed_deployments_calltype_year_add.count;

### create the bar plot ----
barplot!(
    aed_deployments_calltype_year_add.year,
    aed_deployments_calltype_year_add.count,
    stack=call_type_index,
    color=call_type_index,
    colormap=stacked_cmap,
    strokecolor=:white,
    label_color=stack_colors,
    label_size=16,
    label_font="Work Sans",
    bar_labels=stacked_bar_labels,
    label_position=:center,
    label_formatter=x -> string(Int(x)),
    label=["Cardiac Arrest", "Overdose", "Other Cause"]
);

### set the theme for the stacked bars ----
set_theme!(theme_minimal());

### create the swatch for the district colors ----
stacked_swatch = [
    PolyElement(color=stacked_cmap[i])
    for i in 1:length(unique(call_type_index))
];

### design a legend for the stacked plot ----
stacked_legend = Legend(
    aed_deployments_call_type_stacked[2, 1],
    stacked_swatch,
    ["Cardiac Arrest", "Overdose", "Other Cause"],
    "Call Type",
    titlefont="Work Sans",
    titlesize=18,
    labelfont="Work Sans",
    labelsize=16,
    autosize=true,
    tellheight=true,
    tellwidth=false,
    orientation=:horizontal
);

### save the aed deployment by call type stacked bar plot ----
save("./output/plots/aed_deployments_call_type_stacked.png", aed_deployments_call_type_stacked);

## explore witnessed arrests and bystander cpr ----
# we can use this to get the conditional probabilities

## first get total cases with non-missing witnessed and bystander cpr data ----
non_missing_witnessed_bcpr = filter(
    [:witnessed, :bystander_cpr] => (x, y) -> !ismissing(x) && !ismissing(y),
    unique(aed_final, :unique_incident_id)
) |> nrow;

## get marginal and joint probabilities and counts 
witnessed_bystander_cpr = @chain aed_final begin
    @distinct unique_incident_id
    @filter begin
        !ismissing.(witnessed) & !ismissing.(bystander_cpr)
    end
    @count(witnessed, bystander_cpr)
    @pivot_wider(
        names_from = bystander_cpr,
        values_from = n
    )
    @mutate total = `true` .+ `false`
    @mutate total =
        string.(total) .* " (" .* string.(round(total ./ sum(total) * 100; digits=2)) .* "%)"
    @bind_rows(
        @chain aed_final begin
            @distinct unique_incident_id
            @filter begin
                !ismissing.(witnessed) & !ismissing.(bystander_cpr)
            end
            @summarize begin
                witnessed = "total"
                `true` = sum(skipmissing(bystander_cpr))
                `false` = sum(skipmissing(!bystander_cpr))
                total = n()
            end
            @mutate `true` = string.(`true`) .* " (" .* string.(round(`true` ./ sum(total) * 100; digits=2)) .* "%)"
            @mutate `false` = string.(`false`) .* " (" .* string.(round(`false` ./ sum(total) * 100; digits=2)) .* "%)"
        end
    )
end;

## export the witnessed_bystander_cpr data to .xlsx ----
XLSX.writetable(
    "./output/data/witnessed_bystander_cpr.xlsx",
    "witnessed_bcpr" => witnessed_bystander_cpr
)

## get conditional probabilities, conditioning on witnessed ----
conditional_probabilities_witnessed = @chain aed_final begin
    @distinct unique_incident_id
    @filter begin
        !ismissing.(witnessed) & !ismissing.(bystander_cpr)
    end
    @count(witnessed, bystander_cpr)
    @pivot_wider(
        names_from = bystander_cpr,
        values_from = n
    )
    @mutate true_bcpr =
        string.(`true`) .* " (" .* string.(round(`true` ./ (`true` .+ `false`) * 100; digits=2), "%)")
    @mutate false_bcpr =
        string.(`false`) .* " (" .* string.(round(`false` ./ (`true` .+ `false`) * 100; digits=2)) .* "%)"
    @select -(`true`, `false`)
end

## export the conditional_probabilities_witnessed data to .xlsx ----
XLSX.writetable(
    "./output/data/conditional_probabilities_witnessed.xlsx",
    "conditional_witnessed" => conditional_probabilities_witnessed
)

## get conditional probabilities, conditioning on bystander cpr ----
conditional_probabilities_bcpr = @chain aed_final begin
    @distinct unique_incident_id
    @filter begin
        !ismissing.(witnessed) & !ismissing.(bystander_cpr)
    end
    @count(witnessed, bystander_cpr)
    @pivot_wider(
        names_from = bystander_cpr,
        values_from = n
    )
    @mutate true_bcpr =
        string.(`true`) .* " (" .* string.(round(`true` ./ sum(`true`) * 100; digits=2), "%)")
    @mutate false_bcpr =
        string.(`false`) .* " (" .* string.(round(`false` ./ sum(`true`) * 100; digits=2)) .* "%)"
    @select -(`true`, `false`)
end

## export the conditional_probabilities_witnessed data to .xlsx ----
XLSX.writetable(
    "./output/data/conditional_probabilities_bcpr.xlsx",
    "conditional_bcpr" => conditional_probabilities_bcpr
)

## get aed deployments by agency type ----
aed_deployments_by_agencytype = sort(
    combine(
        groupby(
            unique(aed_final, :unique_incident_id), :agency_type
        ),
        nrow => :count,
    ), :count, rev=false
);

### update the categories of agency type due to small counts ----
aed_deployments_by_agencytype_update =
    @chain aed_deployments_by_agencytype begin
        @mutate agency_type = ifelse(count < 6, "Other", agency_type)
        @group_by agency_type
        @summarize(
            agency_type = agency_type,
            count = sum(count)
        )
        @ungroup
        @distinct agency_type
        @mutate(
            percent = count ./ sum(count),
            cumpercent = cumsum(count) ./ sum(count)
        )
    end

### create a pareto chart of cumulative proportions ----

#### data ----
agency_types = aed_deployments_by_agencytype_update.agency_type;
agency_type_counts = aed_deployments_by_agencytype_update.count;

#### cumulative percent ----
agency_type_props_cumulative = aed_deployments_by_agencytype_update.cumpercent;

#### set pareto chart label positions ----
pareto_label_positions = ifelse(agency_type_counts .< 1000, :end, :center);

#### figure + axis ----
aed_deployments_by_agencytype_pareto = Figure();
aed_deployments_by_agencytype_ax = Axis(
    aed_deployments_by_agencytype_pareto[1, 1],
    title="AED Deployments by Agency Type",
    titlefont="Work Sans",
    titlesize = 18,
    subtitle="Line: cumulative percent",
    subtitlefont="Work Sans",
    subtitlecolor = :orange,
    subtitlesize = 16,
    titlealign=:left,
    xticks=(1:length(agency_types), agency_types),
    yticks=0:200:1400,
    yticklabelfont="Work Sans",
    yticklabelsize = 16,
    xticklabelsvisible=false,
    xticklabelfont="Work Sans",
    xticklabelsize = 16,
    xticksvisible=false
);

#### bar layer (frequency) ----
barplot!(
    aed_deployments_by_agencytype_ax,
    agency_type_counts,
    color=:lightblue,
    strokecolor=:transparent
);

#### right-side cumulative percent axis ----
aed_deployments_by_agencytype_ax2 = Axis(
    aed_deployments_by_agencytype_pareto[1, 1],
    yaxisposition=:right,
    yticks=0:0.20:1,
    yticklabelfont="Work Sans",
    yticklabelsize = 16,
    xticks=(1:length(agency_types), agency_types),
    xticklabelsvisible=true,
    xticklabelfont="Work Sans",
    xticklabelsize = 16,
    xticksvisible=false,
    xticklabelrotation=π/4,
    ytickformat=ys -> [Format.format("{:.0f}%", y * 100) for y in ys]
);

lines!(
    aed_deployments_by_agencytype_ax2,
    agency_type_props_cumulative,
    color=:orange,
    linewidth=2
);

Makie.scatter!(
    aed_deployments_by_agencytype_ax2,
    agency_type_props_cumulative,
    color=:darkorange
);

#### save the pareto plot for aed deployments by agency type ----
save("./output/plots/aed_deployments_by_agencytype_pareto.png", aed_deployments_by_agencytype_pareto)

###_____________________________________________________________________________
# Demographic analysis ----
###_____________________________________________________________________________

## gender distribution ----
sex_distribution = @chain aed_final begin
    @count sex
    @mutate sex = coalesce.(
        sex, "Unknown"
    )
    @mutate percent = string.(
        round(n ./ sum(n) * 100; digits=2), "%"
    )
end

