# =============================================================================
# One-time conversion script:  wide-format source CSVs  →  long-format assets
#
# Source format (3 or 4 curves per file):
#   Row 1:  Curve names  (e.g. "Unstressed,,Stressed,,Unstressed Residual,")
#   Row 2:  X,Y headers  (paired, one pair per curve)
#   Row 3+: Data (ragged — curves may have different lengths, empty cells = missing)
#
# Output format (one file per concrete type):
#   condition, temperature_F, strength_fraction
#   (fraction = percent / 100, capped at 1.0)
#
# Run once from the repo root:
#   julia scripts/convert_strength_csvs.jl
# =============================================================================

using CSV, DataFrames

const SRC_DIR    = raw"C:\Users\jborr\OneDrive\Desktop\My stuff\Career\RunToSolve\Fire Curves\ASI216.1m.14 Plots"
const ASSETS_DIR = raw"C:\Users\jborr\OneDrive\Desktop\My stuff\Career\RunToSolve\ACI216.jl\assets"

# -----------------------------------------------------------------------------
# Helper: read a wide-format CSV and return a long-format DataFrame
# curve_names: ordered list matching the X,Y column pairs (left-to-right)
# -----------------------------------------------------------------------------
function wide_to_long(path::String, curve_names::Vector{String})::DataFrame
    # Skip the two header rows; treat everything as Float64 (missing for blanks)
    raw = CSV.read(path, DataFrame;
                   header    = false,
                   skipto    = 3,
                   missingstring = "")

    out = DataFrame(condition        = String[],
                    temperature_F    = Float64[],
                    strength_fraction = Float64[])

    for (i, cname) in enumerate(curve_names)
        xcol = 2*i - 1   # 1-based column index for temperature
        ycol = 2*i        # 1-based column index for percent strength

        for r in 1:nrow(raw)
            x = raw[r, xcol]
            y = raw[r, ycol]
            (ismissing(x) || ismissing(y)) && continue
            frac = min(1.0, Float64(y) / 100.0)   # cap digitising overshoot at 1.0
            push!(out, (cname, Float64(x), frac))
        end
    end

    sort!(out, [:condition, :temperature_F])
    return out
end

# -----------------------------------------------------------------------------
# Steel (already a clean 2-column CSV — just convert percent → fraction)
# -----------------------------------------------------------------------------
steel_src = CSV.read(
    joinpath(SRC_DIR, "Strengthofflexuralreinforcementsteelbar_complete.csv"),
    DataFrame)

steel_out = DataFrame(
    temperature_F     = Float64.(steel_src.temperature_F),
    strength_fraction = Float64.(steel_src.percent_strength_at_70F) ./ 100.0)

CSV.write(joinpath(ASSETS_DIR, "steel_strength.csv"), steel_out)
println("Steel:          $(nrow(steel_out)) rows → steel_strength.csv")

# -----------------------------------------------------------------------------
# Carbonate  (3 curves)
# -----------------------------------------------------------------------------
carb = wide_to_long(
    joinpath(SRC_DIR, "Compressivestrengthofcarbonateaggregateconcreteathightemperatures.csv"),
    ["unstressed", "stressed", "unstressed_residual"])
CSV.write(joinpath(ASSETS_DIR, "carbonate_strength.csv"), carb)
println("Carbonate:      $(nrow(carb)) rows → carbonate_strength.csv  " *
        "(conditions: $(unique(carb.condition)))")

# -----------------------------------------------------------------------------
# Siliceous  (3 curves)
# -----------------------------------------------------------------------------
sil = wide_to_long(
    joinpath(SRC_DIR, "Compressivestrengthofsiliceoustconcreteathightemperaturesandunstressedresidual.csv"),
    ["unstressed", "stressed", "unstressed_residual"])
CSV.write(joinpath(ASSETS_DIR, "siliceous_strength.csv"), sil)
println("Siliceous:      $(nrow(sil)) rows → siliceous_strength.csv  " *
        "(conditions: $(unique(sil.condition)))")

# -----------------------------------------------------------------------------
# Semi-lightweight  (4 curves)
# -----------------------------------------------------------------------------
semi = wide_to_long(
    joinpath(SRC_DIR, "Compressivestrengthofsemilightweightconcreteathightemperaturesandunstressedresidual.csv"),
    ["unstressed_sanded", "unstressed_unsanded", "stressed", "unstressed_residual_sanded"])
CSV.write(joinpath(ASSETS_DIR, "semi_lightweight_strength.csv"), semi)
println("Semi-lightweight: $(nrow(semi)) rows → semi_lightweight_strength.csv  " *
        "(conditions: $(unique(semi.condition)))")

println("\nDone.  All strength assets written to:  $ASSETS_DIR")
