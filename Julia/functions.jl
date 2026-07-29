# _____________________________________________________________________________
# generate_random_id(): creates random identifiers analogous to the R function
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
function generate_random_id(n::Integer; seed::Union{Int, Nothing} = 12345)
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
# xlsx_cell_range_to_df(): read an Excel cell range into a DataFrame
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
function xlsx_cell_range_to_df(path::String, sheet::String, range::String; clean_up::Bool=true, type_spec::Union{Nothing, Vector{DataType}}=nothing)

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
