# _____________________________________________________________________________
# generate_random_id() ---- 
# creates random identifiers analogous to the R function 
# _____________________________________________________________________________

"""
	generate_random_id(n::Integer; seed::Union{Int, Nothing} = 12345)

Generate a vector of random identifiers for use in analytic workflows that
require non‑identifiable surrogate keys. Each identifier consists of ten
random alphabetic characters followed by a hyphen and a ten‑digit random
integer. The function is analogous to custom random ID generators often
used in R‑based epidemiologic data processing pipelines.

Arguments
---------
n::Integer  
	Number of identifiers to generate.

seed::Union{Int, Nothing}  
	Optional random seed. If an integer is supplied, the function sets the
	global RNG seed to ensure reproducible results. If `nothing` is supplied,
	the seed is not set and results will differ across executions.

Returns
-------
Vector{String}  
	A vector of length `n` containing unique string identifiers in the form  
	`LLLLLLLLLL-##########`, where `L` indicates an alphabetic character and
	`#` indicates a numeric digit.

Notes
-----
• If `seed` is not specified, a notification is produced to indicate that the
  output will not be reproducible.  
• Identifiers are not guaranteed to be globally unique but are highly unlikely
  to collide within realistic epidemiologic dataset sizes.

Examples
--------
julia> generate_random_id(3; seed=12345)
3-element Vector{String}:
 "xtRHQNilQd-1833503064"
 "tNGqszqrmT-9123483212"
 "RGJHeoGBCt-6704631508"
"""
function generate_random_id(n::Integer; seed::Union{Int,Nothing}=12345)
    if seed isa Int
        Random.seed!(seed)
    elseif isnothing(seed)
        @info "Random seed was not set. Results will not be reproducible."
    end

    # Character pool (upper + lower case letters)
    chars = [collect('A':'Z'); collect('a':'z')]

    out = Vector{String}(undef, n)

    for i in 1:n
        letters_part = String(rand(chars, 10))
        numbers_part = rand(1_000_000_000:9_999_999_999)
        out[i] = string(letters_part, "-", numbers_part)
    end

    return out
end;

###_____________________________________________________________________________
# xlsx_cell_range_to_df(): read an Excel cell range into a DataFrame ----
###_____________________________________________________________________________

"""
	xlsx_cell_range_to_df(path::String, sheet::String, range::String; clean_up::Bool=true, type_spec::Union{Nothing, Vector{DataType}}=nothing)

Read a rectangular cell range from an Excel worksheet and return a DataFrame
whose column names are taken from the first row of the range. This function
is intended for situations in which `XLSX.readtable` cannot be used because
the desired import area is not a full sheet or because the header row must be
manually extracted.

Optionally run the @clean_names macro from TidierData to clean up column names once the data are coerced to rectangular format.

Arguments
---------
path::String
	Full file path to the Excel workbook.

sheet::String
	Name of the worksheet from which to read data.

range::String
	Excel-style cell range (for example: `"A1:AL2399"`) that defines the exact
	block of data to import.


Keyword Arguments
-----------------
clean_up::Bool = true  
	
If `true`, the function applies `TidierData`'s `@clean_names` macro to the
	resulting DataFrame to standardize column names. If `false`, column names
	are returned exactly as they appear in the worksheet.

Optionally run the `@clean_names` macro from `TidierData` to clean up column names once the data are coerced to rectangular format.


type_spec::Union{Nothing, Vector{DataType}} = nothing  

Optional vector specifying the desired data type for each column in the resulting DataFrame. If supplied, the length of `type_spec` must match the number of columns. Each column will be converted using `convert` and `passmissing`. If `nothing`, no type coercion is performed.

Returns
-------
DataFrame
	
A `DataFrame` whose column names are taken from the first row of the
	imported cell range and whose remaining rows contain the data.

Notes
-----
* The function assumes that the first row of the provided cell range contains
  header names.  

* All cell values are imported as `Any` and will require downstream type
  cleaning if specific numeric, date, or time formats are needed.  

* This workflow mirrors common epidemiologic data ingestion patterns when
  handling EMS agency spreadsheets, AED extracts, or registry-style exports.

Examples
--------
	df = xlsx_cell_range_to_df(
		"C:/data/aed.xlsx",
		"VALID DATA ENTRY",
		"A1:AL2399";
		cleanup=false, type_spec=false
	)
"""
function xlsx_cell_range_to_df(path::String, sheet::String, range::String; clean_up::Bool=true, type_spec::Union{Nothing,Vector{DataType}}=nothing)

    # Read the cell range from the Excel sheet. XLSX.readdata returns a
    # Matrix{Any} whose first dimension is rows and second dimension is
    # columns. The entire range is loaded into memory.
    matrix = XLSX.readdata(path, sheet, range)

    # Extract the first row of the matrix and convert each element to a
    # String. These values will serve as DataFrame column names.
    column_names = string.(matrix[1, :])

    # Slice the matrix to remove the first row, leaving only data rows. The
    # result is a Matrix{Any} that preserves the original cell structure.
    data = matrix[2:end, :]

    # Construct a DataFrame with the extracted column names and the remaining
    # data rows. DataFrames.jl will treat all columns as Vector{Any} unless
    # subsequent type conversion is performed.
    out = DataFrame(data, column_names)


    # If type_spec is provided, apply column-wise type conversion.
    if !isnothing(type_spec)
        @assert length(type_spec) == ncol(out) "type_spec length mismatch."

        # Loop over each column and convert using the specified type.
        for (i, T) in enumerate(type_spec)

            # Apply conversion with passmissing so that missing values are
            # preserved rather than erroring.
            out[!, i] = passmissing(t -> convert(T, t)).(out[!, i])
        end
    end

    # Optionally clean column names using TidierData's @clean_names macro.
    # This standardizes names (snake_case, ASCII-safe, etc.) for workflow use.
    if clean_up
        out = @chain out begin
            @clean_names
        end
    end

    # Return the final DataFrame.
    return out

end;

###_____________________________________________________________________________
# correct_midnight_rollover(): vectorized rollover correction ----
###_____________________________________________________________________________

"""
    correct_midnight_rollover(df::DataFrame, time1::Symbol, time2::Symbol)

Vectorized correction for EMS documentation errors in date-time fields.

The function identifies cases where:
• The `time1` time is the earliest time recorded in a sequence,
• The `time2` time is the later time recorded in a sequence,
• Both timestamps share the same documented date,
• Both fields are non-missing.

For those rows, the date of `time2` field is incremented by one day.

Returns: a `Vector{Union{Missing, DateTime}}` with corrected values.
"""
function correct_midnight_rollover(df::DataFrame, time1::Symbol, time2::Symbol)

    time_1 = df[!, time1]
    time_2 = df[!, time2]

    # Safe hour extraction that propagates missing values
    h_1 = passmissing(hour).(time_1)
    h_2 = passmissing(hour).(time_2)

    # Logical condition for rollover
    cond = (.!ismissing.(time_1)) .&
           (.!ismissing.(time_2)) .&
           (h_1 .> h_2)

    # Create copy of early times
    corrected = deepcopy(time_2)

    # Increment early times by one day where rollover occurs
    corrected[cond] .= corrected[cond] .+ Day(1)

    return corrected
end

###_____________________________________________________________________________
# time_string_extract() ----
# convert Time values to components and add to target
###_____________________________________________________________________________

"""
    time_string_extract(df::DataFrame, time::Symbol, target::Symbol)

Extract hour, minute, and second components from a `Time` column and add those components to another `Time` column. The function operates in a vectorized manner and returns a new vector that reflects the adjusted time.

Arguments
---------
df::DataFrame
    The DataFrame containing the two columns of interest.

time::Symbol
    The column name for the time variable whose components (hours,
    minutes, seconds) will be extracted.

target::Symbol
    The column name for the time variable to which the extracted time
    components will be added.

Details
-------
The function performs type checks to ensure both input columns contain
`Time` values (allowing `Missing`). Missing values are replaced with 
`Time(0, 0, 0)` to maintain vectorized arithmetic. The function then
formats each `Time` value as "HH", "MM", and "SS", parses these string
components into integers, constructs `Hour`, `Minute`, and `Second`
objects, and adds them to the target vector.

Returns
-------
Vector{Union{Missing, Time}}
    A vector of adjusted `Time` objects that reflect the addition of the
    extracted hour, minute, and second values.

Notes
-----
• Missing values in either the `time` or `target` columns are replaced with 
  `Time(00, 00, 00)` to enable vectorized arithmetic. The function will therefore produce adjusted time values that include `00:00:00` when either input is missing. If this behavior is not desired, users will need to post-process the returned vector to reintroduce true `missing` values where appropriate.
"""
function time_string_extract(df::DataFrame, time::Symbol, target::Symbol)

    # Extract the source and target vectors from the DataFrame
    time_vec = df[!, time]
    target_vec = df[!, target]

    # Extract the non-missing element types
    time_vec_eltype = eltype(time_vec) |> nonmissingtype
    target_vec_eltype = eltype(target_vec) |> nonmissingtype

    # Verify both inputs are Time vectors (allowing missing values)
    if time_vec_eltype != Time
        error("`time` must be of type `Vector{Time}`, please check your data.")
    end
    if target_vec_eltype != Time
        error("`target` must be of type `Vector{Time}`, please check your data.")
    end

    # Replace missing values to support vectorized processing
    time_vec = coalesce.(time_vec, Time(0, 0, 0))
    target_vec = coalesce.(target_vec, Time(0, 0, 0))

    # Extract hour, minute, and second strings from each Time value
    hrs_str = Dates.format.(time_vec, "HH")
    mins_str = Dates.format.(time_vec, "MM")
    secs_str = Dates.format.(time_vec, "SS")

    # Parse the extracted components into integers
    hrs_int = parse.(Int64, hrs_str)
    mins_int = parse.(Int64, mins_str)
    secs_int = parse.(Int64, secs_str)

    # Convert integer components into Hour, Minute, and Second objects
    hrs = Hour.(hrs_int)
    mins = Minute.(mins_int)
    secs = Second.(secs_int)

    # Compute the adjusted time: target plus extracted components
    adjusted = target_vec .+ hrs .+ mins .+ secs

    return adjusted
end

###_____________________________________________________________________________
# make_regex_from_vector() ----
# construct a safe alternation regex from a vector
###_____________________________________________________________________________

"""
    make_regex_from_vector(values::Vector{String};
                           word_boundary::Bool = true,
                           case_insensitive::Bool = true)

Construct a deterministic alternation-style regular expression from a
vector of strings. All elements are escaped for regex safety, then joined
using the pipe operator (`|`). Users may optionally enforce word
boundaries and case-insensitive matching.

Arguments
---------
values::Vector{String}
    The observed strings that will form the alternation pattern.

word_boundary::Bool = true
    If `true`, the pattern is wrapped with `\\b` boundaries to ensure
    whole-word matching.

case_insensitive::Bool = true
    If `true`, the regex is compiled with the `i` flag for
    case-insensitive matching.

Returns
-------
Regex
    A compiled Julia `Regex` object representing an alternation of the
    supplied values.

Notes
-----
• All elements are escaped to preserve literal interpretation.
• `join(values, "|")` is used to ensure correct alternation construction.
• This is suitable for city, county, or other location-name pattern
  generation in EMS epidemiology pipelines.
"""
function make_regex_from_vector(values::Vector{String};
    word_boundary::Bool=true,
    case_insensitive::Bool=true)

    # Clean input by removing missing and trimming whitespace
    clean_values = strip.(filter(!ismissing, values))

    # Escape regex special characters so all names match literally
    escaped_values = replace.(clean_values, r"([\.^$|?*+()[]{}])" => s"\\\1")

    # base alternation
    alternation = join(escaped_values, "|")

    # Add word boundaries if requested
    if word_boundary
        alternation = "\\b(?:$alternation)\\b"
    else
        alternation = "$alternation"
    end

    # Apply case-insensitive flag if requested
    if case_insensitive
        return Regex(alternation, "i")
    else
        return Regex(alternation)
    end
end


###_____________________________________________________________________________
# safe_occursin() ----
# missing-safe Boolean string matcher
###_____________________________________________________________________________

"""
safe_occursin(pattern::Union{AbstractString,AbstractPattern,AbstractChar}, string::AbstractString)

Perform missing-safe pattern matching. Returns `false` when `string` is
`missing`, and `true`/`false` for actual string comparisons. This prevents
missing propagation that would break boolean logic in `ifelse`, `case_when`,
or TidierData filtering.

Arguments
---------
pattern::Union{AbstractString, AbstractPattern, AbstractChar}
    Literal string, compiled Regex, or single character.

string::AbstractString
    The string to be tested. May be `missing`.

Returns
-------
Bool
    `true` if the pattern matches, `false` if it does not or if the `string`
    is `missing`.
"""
function safe_occursin(pattern::Union{AbstractString,AbstractPattern,AbstractChar}, string::AbstractString)

    # If the string is missing, return FALSE (avoids missing propagation)
    if ismissing(string)
        return false
    end

    # Ensure the pattern is the correct type
    if !(pattern isa AbstractString ||
         pattern isa AbstractPattern ||
         pattern isa AbstractChar)
        error("`pattern` must be `AbstractString`, `AbstractPattern`, or AbstractChar.")
    end

    # Ensure the string is a string
    if !(string isa AbstractString)
        error("`string` must be an AbstractString or missing.")
    end

    # Perform literal or regex match and return a Bool
    out = occursin(pattern, string)

    # Exit the function
    return out

end

"""
    get_versioninfo_table()

Capture the console output produced by `InteractiveUtils.versioninfo()` and
convert it into a two‑column `DataFrame` containing keys and values. This
provides a clean, tabular representation similar to R's `sessionInfo()` that is
easy to copy and paste out of the Julia REPL or VS Code terminal.

Returns
-------
DataFrame
    A DataFrame with columns:
    - `Key`: The attribute name parsed from the version info output.
    - `Value`: The associated value for the attribute.

Notes
-----
- The function captures `versioninfo()` output by writing it to an in‑memory
  `IOBuffer`.  
- Each line is parsed by splitting on the first colon character.  
- Lines without a colon are included under the `Misc` key.

Examples
--------
```julia
version_table = get_versioninfo_table()
println(version_table)
```
"""
function get_versioninfo_table()

    # Capture the printed output into an IOBuffer
    io_buffer = IOBuffer()
    InteractiveUtils.versioninfo(io_buffer)
    raw_text = String(take!(io_buffer))

    # Split raw text into lines
    lines = split(raw_text, "\n")

    parsed_table = DataFrame(Category = String[], Detail = String[])

    current_category = "General"  # Default category

    for ln in lines
        stripped = strip(ln)

        # Category detection: lines ending with ":" denote sections
        if endswith(stripped, ":")
            current_category = replace(stripped, ":" => "")
            continue
        end

        # Skip empty lines
        if stripped == ""
            continue
        end

        # Otherwise treat as detail belonging to last seen category
        push!(parsed_table, (current_category, stripped))
    end

    return parsed_table
end