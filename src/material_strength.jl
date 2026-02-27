# =============================================================================
# ACI/TMS 216.1M-14 — Material strength reduction at elevated temperatures
#
# Implements the strength-temperature relationships from:
#   Fig. 4.4.3.4.1 — Hot-rolled steel flexural reinforcement (yield strength)
#   Fig. 4.4.3.4.2 — Siliceous aggregate concrete (compressive strength)
#   Fig. 4.4.3.4.3 — Carbonate aggregate concrete (compressive strength)
#   Fig. 4.4.3.4.4 — Semi-lightweight aggregate concrete (compressive strength)
#
# All curves are digitised from the ACI/TMS 216.1M-14 figures.
#
# Interpolation:  1D piecewise linear per curve.
# Below first data point → first data value  (≈ 1.0, full ambient strength).
# Above last  data point → last  data value  (material effectively failed;
#   curves in the source figures stop before reaching the plot boundary
#   because the material has lost structural viability at that point).
# =============================================================================

# Filenames for the long-format concrete strength assets
const _CONCRETE_STRENGTH_FILES = Dict{String,String}(
    "carbonate"        => "carbonate_strength.csv",
    "siliceous"        => "siliceous_strength.csv",
    "semi_lightweight" => "semi_lightweight_strength.csv",
)

# Valid condition strings per aggregate type (for error messages)
const _VALID_CONDITIONS = Dict{String,Vector{String}}(
    "carbonate"        => ["unstressed", "stressed", "unstressed_residual"],
    "siliceous"        => ["unstressed", "stressed", "unstressed_residual"],
    "semi_lightweight" => ["unstressed_sanded", "unstressed_unsanded",
                           "stressed", "unstressed_residual_sanded"],
)

# Module-level cache:  aggregate_type → condition → (temps, fractions)
const _CONCRETE_STRENGTH = Dict{String,
                                Dict{String,Tuple{Vector{Float64},Vector{Float64}}}}()

# Steel data held in Refs so they can be assigned in __init__
const _STEEL_TEMPS = Ref{Vector{Float64}}(Float64[])
const _STEEL_FRACS = Ref{Vector{Float64}}(Float64[])


# -----------------------------------------------------------------------------
# Data loader  (called from ACI216.__init__)
# -----------------------------------------------------------------------------

"""
    _load_strength_data()

Load all concrete and steel strength-reduction CSVs from the assets directory
into the module-level caches.  Called once from `ACI216.__init__()`.
"""
function _load_strength_data()
    # --- Concrete ---
    for (ct, fname) in _CONCRETE_STRENGTH_FILES
        path = joinpath(_ASSETS_DIR, fname)
        df   = CSV.read(path, DataFrame)
        _CONCRETE_STRENGTH[ct] = Dict{String,Tuple{Vector{Float64},Vector{Float64}}}()
        for cond in unique(df.condition)
            sub   = sort(filter(:condition => ==(cond), df), :temperature_F)
            temps = Float64.(sub.temperature_F)
            fracs = Float64.(sub.strength_fraction)
            _CONCRETE_STRENGTH[ct][cond] = (temps, fracs)
        end
    end

    # --- Steel ---
    path  = joinpath(_ASSETS_DIR, "steel_strength.csv")
    steel = sort(CSV.read(path, DataFrame), :temperature_F)
    _STEEL_TEMPS[] = Float64.(steel.temperature_F)
    _STEEL_FRACS[] = Float64.(steel.strength_fraction)

    return nothing
end


# -----------------------------------------------------------------------------
# Internal interpolation helper
# -----------------------------------------------------------------------------

"""
    _strength_interp(temps, fracs, temp_F) -> Float64

Piecewise-linear interpolation over a (sorted) temperature–fraction vector pair.
Clamps to the first value below the data range and to the last value above it.
"""
function _strength_interp(
    temps  :: Vector{Float64},
    fracs  :: Vector{Float64},
    temp_F :: Float64,
) :: Float64
    temp_F <= temps[1]   && return fracs[1]
    temp_F >= temps[end] && return fracs[end]
    idx  = searchsortedfirst(temps, temp_F)
    t_lo, t_hi = temps[idx-1], temps[idx]
    f_lo, f_hi = fracs[idx-1], fracs[idx]
    α = (temp_F - t_lo) / (t_hi - t_lo)
    return f_lo + α * (f_hi - f_lo)
end


# -----------------------------------------------------------------------------
# Public API — concrete
# -----------------------------------------------------------------------------

"""
    concrete_strength_reduction(temperature, aggregate_type, condition;
                                temperature_unit=:fahrenheit) -> Float64

Return the compressive strength of concrete at `temperature` as a fraction
(0–1) of its initial ambient compressive strength, based on the digitised
ACI/TMS 216.1M-14 strength-temperature figures.

# Arguments
- `temperature::Real`      — temperature in °F (default) or °C (see `temperature_unit`).
- `aggregate_type::String` — `"carbonate"`, `"siliceous"`, or `"semi_lightweight"`.
- `condition::String`      — stress state during (or after) heating:
  - `"unstressed"`               — unloaded during heating *(carbonate, siliceous)*
  - `"stressed"`                 — loaded to 0.4 f'c during heating *(all types)*
  - `"unstressed_residual"`      — tested after cooling back to ambient
                                    *(carbonate, siliceous)*
  - `"unstressed_sanded"`        — semi-lightweight sanded, unloaded *(semi_lightweight)*
  - `"unstressed_unsanded"`      — semi-lightweight unsanded, unloaded *(semi_lightweight)*
  - `"unstressed_residual_sanded"` — semi-lightweight sanded residual *(semi_lightweight)*

# Keyword arguments
- `temperature_unit::Symbol` — `:fahrenheit` (default) or `:celsius`.

# Returns
Fraction in [0, 1], where 1.0 = full initial compressive strength.
Values below the digitised temperature range return the first data value (≈ 1.0).
Values above the digitised range return the last data value (near 0 — material
has lost structural viability; the source curve stops before the plot boundary).

# Examples
```julia
f = concrete_strength_reduction(1000.0, "carbonate", "unstressed")
f = concrete_strength_reduction(538.0,  "carbonate", "unstressed"; temperature_unit=:celsius)
```
"""
function concrete_strength_reduction(
    temperature    :: Real,
    aggregate_type :: String,
    condition      :: String;
    temperature_unit :: Symbol = :fahrenheit,
) :: Float64

    _resolve_unit(temperature_unit)
    temp_F = temperature_unit == :celsius ? C_to_F(temperature) : Float64(temperature)

    haskey(_CONCRETE_STRENGTH, aggregate_type) || throw(ArgumentError(
        "Unknown aggregate_type: \"$aggregate_type\". " *
        "Valid options: $(join(sort(collect(keys(_CONCRETE_STRENGTH))), ", "))",
    ))

    cond_map = _CONCRETE_STRENGTH[aggregate_type]
    haskey(cond_map, condition) || throw(ArgumentError(
        "Unknown condition: \"$condition\" for aggregate_type \"$aggregate_type\". " *
        "Valid conditions: $(join(sort(collect(keys(cond_map))), ", "))",
    ))

    temps, fracs = cond_map[condition]
    return _strength_interp(temps, fracs, temp_F)
end


# -----------------------------------------------------------------------------
# Public API — steel
# -----------------------------------------------------------------------------

"""
    steel_strength_reduction(temperature; temperature_unit=:fahrenheit) -> Float64

Return the yield strength of hot-rolled steel flexural reinforcement at
`temperature` as a fraction (0–1) of its yield strength at 70 °F, based on
the digitised ACI/TMS 216.1M-14 Figure 4.4.3.4.1.

# Arguments
- `temperature::Real` — temperature in °F (default) or °C (see `temperature_unit`).

# Keyword arguments
- `temperature_unit::Symbol` — `:fahrenheit` (default) or `:celsius`.

# Returns
Fraction in [0, 1], where 1.0 = full yield strength at 70 °F (~86–1399 °F data
range; clamped to first/last data values outside that range).

# Examples
```julia
f = steel_strength_reduction(1000.0)
f = steel_strength_reduction(538.0; temperature_unit=:celsius)
```
"""
function steel_strength_reduction(
    temperature      :: Real;
    temperature_unit :: Symbol = :fahrenheit,
) :: Float64
    _resolve_unit(temperature_unit)
    temp_F = temperature_unit == :celsius ? C_to_F(temperature) : Float64(temperature)
    return _strength_interp(_STEEL_TEMPS[], _STEEL_FRACS[], temp_F)
end


# -----------------------------------------------------------------------------
# Internal helper for critical-temperature search
# -----------------------------------------------------------------------------

"""
    _critical_temp_from_data(temps, fracs, threshold) -> Float64

Return the temperature at which `fracs` first drops to or below `threshold`
by linear interpolation between adjacent knots.

- Returns `temps[1]` if `fracs[1] ≤ threshold` (already at or below from the start).
- Returns `Inf` if `fracs[end] > threshold` (never reaches threshold in the data range).
- `threshold` must be in [0, 1].
"""
function _critical_temp_from_data(
    temps     :: Vector{Float64},
    fracs     :: Vector{Float64},
    threshold :: Float64,
) :: Float64
    0.0 <= threshold <= 1.0 || throw(ArgumentError(
        "threshold must be in [0, 1]. Got: $threshold",
    ))
    fracs[1] <= threshold && return temps[1]   # already at or below threshold at first knot
    fracs[end] > threshold && return Inf        # never reaches threshold in data range

    idx  = findfirst(f -> f <= threshold, fracs)
    t_lo, t_hi = temps[idx-1], temps[idx]
    f_lo, f_hi = fracs[idx-1], fracs[idx]
    α = (threshold - f_lo) / (f_hi - f_lo)
    return t_lo + α * (t_hi - t_lo)
end


# -----------------------------------------------------------------------------
# Public API — critical temperature
# -----------------------------------------------------------------------------

"""
    steel_critical_temperature(threshold; temperature_unit=:fahrenheit) -> Float64

Return the temperature at which the steel yield-strength fraction first drops
to or below `threshold`, interpolated from the ACI/TMS 216.1M-14 data.

`threshold` must be in [0, 1].  Returns `Inf` if the fraction never reaches
`threshold` within the digitised data range.

# Keyword arguments
- `temperature_unit::Symbol` — `:fahrenheit` (default) or `:celsius`.

# Example
```julia
T = steel_critical_temperature(0.5)         # temperature where fy = 50 % of ambient
T = steel_critical_temperature(0.5; temperature_unit=:celsius)
```
"""
function steel_critical_temperature(
    threshold        :: Real;
    temperature_unit :: Symbol = :fahrenheit,
) :: Float64
    _resolve_unit(temperature_unit)
    T_F = _critical_temp_from_data(_STEEL_TEMPS[], _STEEL_FRACS[], Float64(threshold))
    isinf(T_F) && return T_F
    return temperature_unit == :celsius ? F_to_C(T_F) : T_F
end


"""
    concrete_critical_temperature(threshold, aggregate_type, condition;
                                   temperature_unit=:fahrenheit) -> Float64

Return the temperature at which the concrete compressive-strength fraction
first drops to or below `threshold`, interpolated from the ACI/TMS 216.1M-14
data for the given `aggregate_type` and `condition`.

`threshold` must be in [0, 1].  Returns `Inf` if the fraction never reaches
`threshold` within the digitised data range.

# Arguments
- `threshold::Real`        — target fraction in [0, 1].
- `aggregate_type::String` — `"carbonate"`, `"siliceous"`, or `"semi_lightweight"`.
- `condition::String`      — stress condition (see `concrete_strength_reduction`).

# Keyword arguments
- `temperature_unit::Symbol` — `:fahrenheit` (default) or `:celsius`.

# Example
```julia
T = concrete_critical_temperature(0.5, "carbonate", "unstressed")
```
"""
function concrete_critical_temperature(
    threshold        :: Real,
    aggregate_type   :: String,
    condition        :: String;
    temperature_unit :: Symbol = :fahrenheit,
) :: Float64
    _resolve_unit(temperature_unit)

    haskey(_CONCRETE_STRENGTH, aggregate_type) || throw(ArgumentError(
        "Unknown aggregate_type: \"$aggregate_type\". " *
        "Valid options: $(join(sort(collect(keys(_CONCRETE_STRENGTH))), ", "))",
    ))
    cond_map = _CONCRETE_STRENGTH[aggregate_type]
    haskey(cond_map, condition) || throw(ArgumentError(
        "Unknown condition: \"$condition\" for aggregate_type \"$aggregate_type\". " *
        "Valid conditions: $(join(sort(collect(keys(cond_map))), ", "))",
    ))

    temps, fracs = cond_map[condition]
    T_F = _critical_temp_from_data(temps, fracs, Float64(threshold))
    isinf(T_F) && return T_F
    return temperature_unit == :celsius ? F_to_C(T_F) : T_F
end


# -----------------------------------------------------------------------------
# Public API — strength summary printer
# -----------------------------------------------------------------------------

"""
    print_strength_summary(aggregate_type, condition;
                           temperatures=nothing, temperature_unit=:fahrenheit,
                           io=stdout)

Print a formatted table of concrete and steel retained-strength fractions at
standard (or user-supplied) temperatures.

# Arguments
- `aggregate_type::String` — `"carbonate"`, `"siliceous"`, or `"semi_lightweight"`.
- `condition::String`      — stress condition (see `concrete_strength_reduction`).

# Keyword arguments
- `temperatures`            — optional vector of temperatures to evaluate.
  Defaults to `[200, 400, 600, 800, 1000, 1200, 1400]` °F (or rounded-°C
  equivalents when `temperature_unit=:celsius`).
- `temperature_unit::Symbol` — `:fahrenheit` (default) or `:celsius` — controls
  the unit of any user-supplied `temperatures` vector.
- `io::IO`                  — output stream (default: `stdout`).

# Example
```julia
print_strength_summary("carbonate", "unstressed")
print_strength_summary("siliceous", "stressed"; temperature_unit=:celsius)
```
"""
function print_strength_summary(
    aggregate_type   :: String,
    condition        :: String;
    temperatures     :: Union{AbstractVector{<:Real},Nothing} = nothing,
    temperature_unit :: Symbol = :fahrenheit,
    io               :: IO    = stdout,
)
    _resolve_unit(temperature_unit)

    haskey(_CONCRETE_STRENGTH, aggregate_type) || throw(ArgumentError(
        "Unknown aggregate_type: \"$aggregate_type\". " *
        "Valid options: $(join(sort(collect(keys(_CONCRETE_STRENGTH))), ", "))",
    ))
    cond_map = _CONCRETE_STRENGTH[aggregate_type]
    haskey(cond_map, condition) || throw(ArgumentError(
        "Unknown condition: \"$condition\" for aggregate_type \"$aggregate_type\". " *
        "Valid conditions: $(join(sort(collect(keys(cond_map))), ", "))",
    ))

    # Default temperature set in °F; if user chose Celsius, convert to round values
    default_F = [200.0, 400.0, 600.0, 800.0, 1000.0, 1200.0, 1400.0]
    default_C = [100.0, 200.0, 300.0, 400.0, 500.0,  600.0,  700.0 ]

    # Resolve temperatures → always store as °F for computation
    temps_F = if isnothing(temperatures)
        temperature_unit == :celsius ? C_to_F.(default_C) : default_F
    elseif temperature_unit == :celsius
        C_to_F.(Float64.(temperatures))
    else
        Float64.(temperatures)
    end

    println(io, "\n", "="^70)
    println(io, " MATERIAL STRENGTH SUMMARY — ACI/TMS 216.1M-14")
    Printf.@printf(io, " Concrete: %s / %s\n", aggregate_type, condition)
    println(io, "="^70)
    Printf.@printf(io, " %-14s  %-14s  %-14s  %-10s\n",
        "Temp (°F)", "Temp (°C)", "Concrete f'c", "Steel fy")
    println(io, "-"^70)
    for T_F in temps_F
        T_C = F_to_C(T_F)
        f_c = concrete_strength_reduction(T_F, aggregate_type, condition)
        f_s = steel_strength_reduction(T_F)
        Printf.@printf(io, " %12.1f    %12.1f    %10.4f      %10.4f\n",
            T_F, T_C, f_c, f_s)
    end
    println(io, "="^70)
    println(io, " Code ref: ACI/TMS 216.1M-14, Figs. 4.4.3.4.1–4.4.3.4.4")
    println(io, "="^70, "\n")
end


# -----------------------------------------------------------------------------
# Public API — rebar condition check
# -----------------------------------------------------------------------------

"""
    rebar_condition(fire_time, cover_mm, concrete_type;
                    concrete_condition=nothing) -> NamedTuple

Convenience wrapper that returns the temperature at the rebar and both the
concrete and steel retained-strength fractions in a single call.

Internally calls `temperature_within_slab` then `steel_strength_reduction` and
`concrete_strength_reduction`.

# Arguments
- `fire_time::Real`      — fire exposure duration in minutes.
- `cover_mm::Real`       — clear cover from the fire-exposed surface to the
  rebar in mm (passed directly to `temperature_within_slab`).
- `concrete_type::String` — `"carbonate"`, `"siliceous"`, or `"semi_lightweight"`.

# Keyword arguments
- `concrete_condition::Union{String,Nothing}` — stress condition for the
  concrete strength curve (see `concrete_strength_reduction`).  Defaults to
  `"unstressed"` for carbonate/siliceous and `"unstressed_sanded"` for
  semi-lightweight when `nothing`.

# Returns
A `NamedTuple` with fields:
- `temperature_F::Float64`   — temperature at the rebar depth (°F)
- `temperature_C::Float64`   — temperature at the rebar depth (°C)
- `steel_fraction::Float64`  — retained fy fraction (0–1)
- `concrete_fraction::Float64` — retained f'c fraction at rebar depth (0–1)

# Example
```julia
rc = rebar_condition(120, 25.0, "carbonate")
println("Steel retains \$(round(rc.steel_fraction*100, digits=1)) % of fy")
println("Rebar temperature: \$(round(rc.temperature_C, digits=1)) °C")
```
"""
function rebar_condition(
    fire_time    :: Real,
    cover_mm     :: Real,
    concrete_type :: String;
    concrete_condition :: Union{String,Nothing} = nothing,
)
    cond = if isnothing(concrete_condition)
        concrete_type == "semi_lightweight" ? "unstressed_sanded" : "unstressed"
    else
        concrete_condition
    end

    T_F = temperature_within_slab(fire_time, cover_mm, concrete_type)

    return (
        temperature_F     = T_F,
        temperature_C     = F_to_C(T_F),
        steel_fraction    = steel_strength_reduction(T_F),
        concrete_fraction = concrete_strength_reduction(T_F, concrete_type, cond),
    )
end
