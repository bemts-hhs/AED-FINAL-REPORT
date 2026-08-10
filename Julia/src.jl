###_____________________________________________________________________________
# Source code for the AED final report
###_____________________________________________________________________________
# Must at least first run setup.jl to load the necessary packages and data.
###_____________________________________________________________________________

# Ingest heart disease mortality data
# Access the CDC heart disease data Socrata API feed for heart disease mortality data
heart_disease_response = HTTP.get(us_heart_disease_mortality)

# full US heart disease mortality dataset
heart_disease_data_full = CSV.read(IOBuffer(heart_disease_response.body), DataFrame)

# base dataset for future work, take out sex and race based adjustments
heart_disease_data = @chain heart_disease_data_full begin
    @filter begin
        stratification1 == "Overall" && stratification2 == "Overall"
    end
end

# Filter data down to states
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

# filter data down to county
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

# Filter data down to national
heart_disease_data_national = @chain heart_disease_data begin
    @filter geographiclevel == "Nation"
    @select data_value
end

###_____________________________________________________________________________
# Geographic analysis - heart disease data for the US
###_____________________________________________________________________________

#= 
get the centroid of the continental US
This uses GeometryOps to compute a single (lon, lat) coordinate that represents
the center of all state geometries. It is used to center the orthographic 
projection so the United States appears centered and natural on the map.
 =#
us_centroid = GeometryOps.centroid(heart_disease_data_state.geometry)

#= 
Create a GeoMakie scene
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

# Build a color map based on data_value
# `vals` contains the CDC age-adjusted mortality rates. Missing values are 
# replaced with NaN so Makie’s color pipeline can handle them. Then we compute 
# the min/max to ensure the colorbar matches the actual range of the data.
us_vals = coalesce.(heart_disease_data_state.data_value, NaN);
us_min_val = minimum(skipmissing(heart_disease_data_state.data_value));
us_max_val = maximum(skipmissing(heart_disease_data_state.data_value));

# A reversed Viridis colormap (longer dark-to-light gradient)
# This gives high mortality rates brighter/lighter color tones.
cmap = cgrad(:inferno, 256, rev=true); # Makie colormap

# Build polygon objects from your geometries
# `poly!` directly plots the vector geometries stored in the `geometry` column.
# All state polygons are drawn using the orthographic projection defined above.
poly!(us_ax, heart_disease_data_state.geometry,
    color=vals,
    colormap=cmap,
    strokewidth=0.5,
    strokecolor=:white
);

# Add a colorbar below the map
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

# Save the output image to disk
# This writes the entire figure to a PNG file in your output directory.
save("./output/plots/us_map.png", us_map)

###_____________________________________________________________________________
# Geographic analysis - heart disease data for the state of Iowa, USA
###_____________________________________________________________________________

#= 
get the centroid of the continental US
This uses GeometryOps to compute a single (lon, lat) coordinate that represents
the center of all state geometries. It is used to center the orthographic 
projection so the United States appears centered and natural on the map.
 =#
ia_centroid = GeometryOps.centroid(heart_disease_data_county.geometry);

#= 
Create a GeoMakie scene
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

# Build a color map based on data_value
# `vals` contains the CDC age-adjusted mortality rates. Missing values are 
# replaced with NaN so Makie’s color pipeline can handle them. Then we compute 
# the min/max to ensure the colorbar matches the actual range of the data.
ia_vals = coalesce.(heart_disease_data_county.data_value, NaN);
ia_min_val = minimum(skipmissing(heart_disease_data_county.data_value));
ia_max_val = maximum(skipmissing(heart_disease_data_county.data_value));

# A reversed Viridis colormap (longer dark-to-light gradient)
# This gives high mortality rates brighter/lighter color tones.
cmap = cgrad(:inferno, 256, rev=true); # Makie colormap

# Build polygon objects from your geometries
# `poly!` directly plots the vector geometries stored in the `geometry` column.
# All state polygons are drawn using the orthographic projection defined above.
poly!(ia_ax, heart_disease_data_county.geometry,
    color=ia_vals,
    colormap=cmap,
    strokewidth=0.5,
    strokecolor=:white
);

# Add a colorbar below the map
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

# Save the output image to disk
# This writes the entire figure to a PNG file in your output directory.
save("./output/plots/ia_map.png", ia_map)

###_____________________________________________________________________________
# Geographic analysis - heart disease data for the state of Iowa, USA
###_____________________________________________________________________________

# Use the ia_centroid object from before

# get counts by location from the aed data
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

#= 
AED Deployment locations
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

# Get distinct vector of districts
districts =
    string.(unique(heart_disease_data_county.region_preparedness)) |> sort;

# number of districts
num_districts = length(districts);

# get the vector of districts in the raw data
aed_districts = heart_disease_data_county.region_preparedness;

# map each district to an integer as index
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

# map each district index to a county
aed_color_index = [district_lookup[string(d)] for d in aed_districts];

# Makie colormap
aed_cmap = ColorBrewer.palette("Spectral", num_districts);

# Build polygon objects from your geometries
# `poly!` directly plots the vector geometries stored in the `geometry` column.
# All state polygons are drawn using the orthographic projection defined above.
poly!(aed_ax, heart_disease_data_county.geometry,
    color=aed_color_index,
    colormap=aed_cmap,
    strokewidth=0.8,
    strokecolor=:white,
    label="Preparedness District"
);
scatter!(
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

# create the swatch for the district colors
district_swatches = [
    PolyElement(color=aed_cmap[i], strokecolor=:white)
    for i in 1:num_districts
];

# district labels for the legend
district_labels = districts;   # e.g. ["1A", "1C", "2", ..., "7", "8"]

# create a swatch for marker size

# marker size swatch
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

# combine swatches

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


# Save the output image to disk
# This writes the entire figure to a PNG file in your output directory.
save("./output/plots/aed_map.png", aed_map)

###_____________________________________________________________________________
# Deployment details
###_____________________________________________________________________________

# summarize deploymnets by year
aed_deployments_by_year = combine(
    groupby(
        unique(aed_final, :unique_incident_id), :year
    ),
    nrow => :count
)

# plot the deployments by year
aed_deployments_plot = Makie.with_theme(theme_minimal()) do
    barplot(
        aed_deployments_by_year.year,
        aed_deployments_by_year.count,
        color=aed_deployments_by_year.count,
        strokecolor=:transparent,
        axis = (
            xticks = (2021:2026, ["2021", "2022", "2023", "2024", "2025", "2026"]),
            title = "AED Deployments by Year",
            titlealign = :left,
            titlesize = 18,
            yticklabelsvisible = false,
            xticklabelsize = 16
        ),
        label_size = 16,
        bar_labels = :y,
        flip_labels_at = 400,
        label_formatter = x -> string(Int(round(x)))
    )
end;

# get distinct locations from the aed data
distinct_locations = unique(
    filter(:location => l -> !ismissing.(l), aed_final).location
) |> length;

# get missing locations
missing_locations = filter(:location => l -> ismissing.(l), aed_final) |> nrow;

###_____________________________________________________________________________
# Demographic analysis
###_____________________________________________________________________________

sex_distribution = @chain aed_final begin
    @count sex
    @mutate sex = coalesce.(
        sex, "Unknown"
    )
    @mutate percent = string.(
        round(n ./ sum(n) * 100; digits=2), "%"
    )
end