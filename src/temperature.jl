# =============================================================================
# ACI/TMS 216.1M-14 — Temperature within concrete slab
#
# Source:     CSV data files in assets/ (digitized from ACI/TMS 216.1M-14 figures)
# Reference:  Fig. 4.4.2.2.1a(a) — carbonate aggregate concrete
#             Fig. 4.4.2.2.1a(b) — siliceous aggregate concrete
#             Fig. 4.4.2.2.1a(c) — semi-lightweight aggregate concrete
#
# Interpolation strategy: controlled linear 2D
#   Step 1 — 1D linear interpolation in fire time at each of the two bounding
#             depth curves (the curves immediately shallower and deeper than the
#             requested distance_from_fire).
#   Step 2 — 1D linear interpolation in depth between the two temperature results.
#
# No extrapolation is performed. ArgumentError is thrown for out-of-range inputs.
# Shallow curves (close to the fire surface) have shorter maximum fire times
# because they reach ~1600 °F quickly; queries must respect per-depth time ranges.
# =============================================================================

const _ASSETS_DIR = joinpath(@__DIR__, "..", "assets")


# -----------------------------------------------------------------------------
# Temperature unit helpers
# -----------------------------------------------------------------------------

"""
    F_to_C(T_F) -> Float64

Convert a temperature from °F to °C.
"""
F_to_C(T_F::Real) = (Float64(T_F) - 32.0) * 5.0 / 9.0

"""
    C_to_F(T_C) -> Float64

Convert a temperature from °C to °F.
"""
C_to_F(T_C::Real) = Float64(T_C) * 9.0 / 5.0 + 32.0

# Internal helper — validate and resolve the temperature_unit keyword
function _resolve_unit(u::Symbol)
    u in (:fahrenheit, :celsius) || throw(ArgumentError(
        "temperature_unit must be :fahrenheit or :celsius. Got: $u",
    ))
    return u
end


const _CONCRETE_FILENAMES = Dict{String,String}(
    "carbonate"        => "carbonate_concrete.csv",
    "siliceous"        => "siliceous_concrete.csv",
    "semi_lightweight" => "semi_lightweight_concrete.csv",
)

# Module-level data cache — populated in ACI216.__init__()
const _TEMP_DATA = Dict{String,DataFrame}()

"""
    _load_temperature_data()

Load all three concrete-type CSV files into the module cache `_TEMP_DATA`.
Called once from `ACI216.__init__()`.
"""
function _load_temperature_data()
    for (ct, fname) in _CONCRETE_FILENAMES
        path = joinpath(_ASSETS_DIR, fname)
        df   = CSV.read(path, DataFrame)
        # Normalise the temperature column name (contains parentheses in the CSV header)
        temp_col = only(filter(n -> occursin("Temperature", n), names(df)))
        rename!(df, temp_col => "Temperature_F")
        _TEMP_DATA[ct] = df
    end
    return nothing
end


# -----------------------------------------------------------------------------
# Public API
# -----------------------------------------------------------------------------

"""
    temperature_within_slab(fire_time, distance_from_fire, concrete_type) -> Float64

Return the temperature (°F) at a given depth within a concrete slab that is
exposed to an ASTM E119 standard fire test, using the digitised curves from
ACI/TMS 216.1M-14.

# Arguments
- `fire_time::Real`           — fire test duration in minutes.  Must lie within
  the data range for the two bounding depth curves; shallow depths (close to the
  fire surface) have shorter maximum times because they reach ~1600 °F quickly.
- `distance_from_fire::Real`  — distance from the fire-exposed surface in mm.
  Must lie within [5, 180] mm (the range digitised from the ACI figures).
- `concrete_type::String`     — one of `"carbonate"`, `"siliceous"`,
  or `"semi_lightweight"`.

# Returns
Temperature (°F by default, or °C when `temperature_unit=:celsius`), interpolated
using a controlled linear 2D scheme:
1. 1D linear interpolation in time at each of the two bounding depth curves.
2. 1D linear interpolation in depth between the two temperature results.

# Keyword arguments
- `temperature_unit::Symbol` — `:fahrenheit` (default) or `:celsius`.

# Errors
Throws `ArgumentError` if any input is out of range.  No extrapolation is
performed.

# Examples
```julia
T_F = temperature_within_slab(120.0, 40.0, "carbonate")          # → ≈ 862 °F
T_C = temperature_within_slab(120.0, 40.0, "carbonate";
                               temperature_unit=:celsius)          # → ≈ 461 °C
```
"""
function temperature_within_slab(
    fire_time::Real,
    distance_from_fire::Real,
    concrete_type::String;
    temperature_unit::Symbol = :fahrenheit,
)::Float64
    _resolve_unit(temperature_unit)

    haskey(_TEMP_DATA, concrete_type) || throw(ArgumentError(
        "Unknown concrete_type: \"$concrete_type\". " *
        "Valid options: " * join(sort(collect(keys(_CONCRETE_FILENAMES))), ", "),
    ))

    df     = _TEMP_DATA[concrete_type]
    depths = sort(unique(df.Distance_mm))
    d_min, d_max = depths[1], depths[end]

    d_min <= distance_from_fire <= d_max || throw(ArgumentError(
        "distance_from_fire = $distance_from_fire mm is out of range " *
        "[$d_min, $d_max] mm for concrete_type = \"$concrete_type\"",
    ))

    # ---- Find bounding depth curves -----------------------------------------
    idx = searchsortedfirst(depths, distance_from_fire)

    if depths[idx] == distance_from_fire
        # Exact depth match — skip depth interpolation
        T_F = _interp_time(df, depths[idx], fire_time, concrete_type)
        return temperature_unit == :celsius ? F_to_C(T_F) : T_F
    end

    d_lo = depths[idx - 1]  # smaller depth (closer to fire, hotter)
    d_hi = depths[idx]      # larger depth  (farther from fire, cooler)

    # ---- 1D interpolation in time at each bounding depth --------------------
    T_lo = _interp_time(df, d_lo, fire_time, concrete_type)
    T_hi = _interp_time(df, d_hi, fire_time, concrete_type)

    # ---- 1D linear interpolation in depth -----------------------------------
    α   = (distance_from_fire - d_lo) / (d_hi - d_lo)
    T_F = T_lo + α * (T_hi - T_lo)
    return temperature_unit == :celsius ? F_to_C(T_F) : T_F
end


# -----------------------------------------------------------------------------
# Vectorised profile
# -----------------------------------------------------------------------------

"""
    temperature_profile(fire_time, depths_mm, concrete_type;
                        temperature_unit=:fahrenheit) -> Vector{Float64}

Return the temperature at each depth in `depths_mm` for the given `fire_time`
and `concrete_type`.  This is a vectorised wrapper around
`temperature_within_slab`.

# Arguments
- `fire_time::Real`                     — fire exposure duration (minutes).
- `depths_mm::AbstractVector{<:Real}`   — depths from the fire-exposed surface
  (mm).  Each depth is validated independently; the first out-of-range depth
  raises an `ArgumentError`.
- `concrete_type::String`               — `"carbonate"`, `"siliceous"`, or
  `"semi_lightweight"`.

# Keyword arguments
- `temperature_unit::Symbol` — `:fahrenheit` (default) or `:celsius`.

# Returns
`Vector{Float64}` of temperatures, one per entry in `depths_mm`, in the same
order.

# Example
```julia
depths = [10.0, 25.0, 40.0, 60.0, 80.0]
T = temperature_profile(120.0, depths, "carbonate")
```
"""
function temperature_profile(
    fire_time        :: Real,
    depths_mm        :: AbstractVector{<:Real},
    concrete_type    :: String;
    temperature_unit :: Symbol = :fahrenheit,
) :: Vector{Float64}
    return Float64[
        temperature_within_slab(fire_time, d, concrete_type;
                                temperature_unit=temperature_unit)
        for d in depths_mm
    ]
end


# -----------------------------------------------------------------------------
# Internal helper
# -----------------------------------------------------------------------------

"""
    _interp_time(df, depth_mm, fire_time, concrete_type) -> Float64

Build a 1D linear interpolant over time for a single depth curve and evaluate
it at `fire_time`.  Throws `ArgumentError` if `fire_time` is out of range.
"""
function _interp_time(
    df::DataFrame,
    depth_mm::Real,
    fire_time::Real,
    concrete_type::String,
)::Float64
    sub = filter(:Distance_mm => ==(depth_mm), df)
    sort!(sub, :Time_min)

    times = Float64.(sub.Time_min)
    temps = Float64.(sub[!, "Temperature_F"])

    t_min, t_max = times[1], times[end]
    t_min <= fire_time <= t_max || throw(ArgumentError(
        "fire_time = $fire_time min is out of range [$t_min, $t_max] min " *
        "for depth $depth_mm mm in concrete_type = \"$concrete_type\". " *
        "Shallow curves reach ~1600 °F before 240 min and have shorter time ranges.",
    ))

    itp = linear_interpolation(times, temps)
    return itp(fire_time)
end
