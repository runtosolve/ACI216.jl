# =============================================================================
# ACI 216.1M-14 — Prescriptive fire resistance checker for concrete slabs
#
# Implements:
#   Table 4.2              — Minimum equivalent slab thickness (mm)
#   Section 4.2.4          — Equivalent thickness for ribbed/undulating slabs
#   Table 4.3.1.1          — Minimum clear cover for nonprestressed slabs (mm)
#   Table 4.3.1.1          — Minimum clear cover for prestressed slabs (mm)
#   ACI 318M-14 §20.6.1.3  — Minimum cover for durability (cast-in-place nonprestressed)
#   ACI 318M-14 §20.6.1.4  — Minimum cover for durability (cast-in-place prestressed)
#
# Both criteria must be satisfied for a slab to achieve a given fire rating.
# Cover is measured from the fire-exposed surface to the nearest surface of
# the longitudinal reinforcement (per Table 4.3.1.1 footnote).
#
# Supported aggregate types: "siliceous", "carbonate", "semi_lightweight", "lightweight"
# Supported durations (min):  60, 90, 120, 180, 240
#
# Verified against ACI 216.1M-14 PDF (scanned original).
# Bug fixed in prior standalone script: lightweight 3-hr unrestrained cover
#   was 20 mm; correct value is 30 mm.
# =============================================================================


# -----------------------------------------------------------------------------
# Table 4.2 — Minimum Equivalent Thickness (mm)
# -----------------------------------------------------------------------------

const _MIN_THICKNESS_MM = Dict{String,Dict{Int,Int}}(
    "siliceous"        => Dict(60 => 90,  90 => 110, 120 => 125, 180 => 155, 240 => 175),
    "carbonate"        => Dict(60 => 80,  90 => 100, 120 => 115, 180 => 145, 240 => 170),
    "semi_lightweight" => Dict(60 => 70,  90 => 85,  120 => 95,  180 => 115, 240 => 135),
    "lightweight"      => Dict(60 => 65,  90 => 80,  120 => 90,  180 => 110, 240 => 130),
)


# -----------------------------------------------------------------------------
# Table 4.3.1.1 — Minimum Cover (mm), Restrained
# All aggregate types: 20 mm for all ratings 1 through 4 hours.
# -----------------------------------------------------------------------------

const _MIN_COVER_RESTRAINED_MM = Dict{String,Dict{Int,Int}}(
    "siliceous"        => Dict(60 => 20, 90 => 20, 120 => 20, 180 => 20, 240 => 20),
    "carbonate"        => Dict(60 => 20, 90 => 20, 120 => 20, 180 => 20, 240 => 20),
    "semi_lightweight" => Dict(60 => 20, 90 => 20, 120 => 20, 180 => 20, 240 => 20),
    "lightweight"      => Dict(60 => 20, 90 => 20, 120 => 20, 180 => 20, 240 => 20),
)


# -----------------------------------------------------------------------------
# Table 4.3.1.1 — Minimum Cover (mm), Unrestrained
# -----------------------------------------------------------------------------

const _MIN_COVER_UNRESTRAINED_MM = Dict{String,Dict{Int,Int}}(
    "siliceous"        => Dict(60 => 20, 90 => 20, 120 => 25, 180 => 30, 240 => 40),
    "carbonate"        => Dict(60 => 20, 90 => 20, 120 => 20, 180 => 30, 240 => 30),
    "semi_lightweight" => Dict(60 => 20, 90 => 20, 120 => 20, 180 => 30, 240 => 30),
    "lightweight"      => Dict(60 => 20, 90 => 20, 120 => 20, 180 => 30, 240 => 30),
)

# -----------------------------------------------------------------------------
# Table 4.3.1.1 — Minimum Cover (mm), Prestressed, Restrained
# All aggregate types: 20 mm for all ratings.
# -----------------------------------------------------------------------------

const _MIN_COVER_PRESTRESSED_RESTRAINED_MM = Dict{String,Dict{Int,Int}}(
    "siliceous"        => Dict(60 => 20, 90 => 20, 120 => 20, 180 => 20, 240 => 20),
    "carbonate"        => Dict(60 => 20, 90 => 20, 120 => 20, 180 => 20, 240 => 20),
    "semi_lightweight" => Dict(60 => 20, 90 => 20, 120 => 20, 180 => 20, 240 => 20),
    "lightweight"      => Dict(60 => 20, 90 => 20, 120 => 20, 180 => 20, 240 => 20),
)

# -----------------------------------------------------------------------------
# Table 4.3.1.1 — Minimum Cover (mm), Prestressed, Unrestrained
# -----------------------------------------------------------------------------

const _MIN_COVER_PRESTRESSED_UNRESTRAINED_MM = Dict{String,Dict{Int,Int}}(
    "siliceous"        => Dict(60 => 30, 90 => 40, 120 => 45, 180 => 60, 240 => 70),
    "carbonate"        => Dict(60 => 25, 90 => 35, 120 => 40, 180 => 55, 240 => 55),
    "semi_lightweight" => Dict(60 => 25, 90 => 35, 120 => 40, 180 => 50, 240 => 55),
    "lightweight"      => Dict(60 => 25, 90 => 35, 120 => 40, 180 => 50, 240 => 55),
)

const _VALID_AGGREGATE_TYPES       = ("siliceous", "carbonate", "semi_lightweight", "lightweight")
const _VALID_EXPOSURE_CONDITIONS   = ("not_exposed", "exposed_to_weather", "cast_against_ground")
const _VALID_TENDON_TYPES          = ("bonded", "unbonded")


# -----------------------------------------------------------------------------
# ACI 318M-14 — Minimum cover for durability (cast-in-place slabs only)
#   Nonprestressed: Table 20.6.1.3.1
#   Prestressed:    Table 20.6.1.4.1
# -----------------------------------------------------------------------------

function _aci318_min_cover(
    exposure_condition :: String,
    bar_diameter_mm    :: Real;
    prestressed        :: Bool   = false,
    tendon_type        :: String = "bonded",
)::Float64
    if prestressed
        # ACI 318M-14 Table 20.6.1.4.1 — cast-in-place prestressed slabs
        if exposure_condition == "not_exposed"
            # Unbonded tendons: 20 mm; bonded tendons: 25 mm
            return tendon_type == "unbonded" ? 20.0 : 25.0
        elseif exposure_condition == "exposed_to_weather"
            return 50.0
        elseif exposure_condition == "cast_against_ground"
            return 75.0
        else
            throw(ArgumentError(
                "exposure_condition must be one of $_VALID_EXPOSURE_CONDITIONS. " *
                "Got: \"$exposure_condition\"",
            ))
        end
    else
        # ACI 318M-14 Table 20.6.1.3.1 — cast-in-place nonprestressed slabs
        if exposure_condition == "not_exposed"
            # D43 and D57 bars (nominal diameter > 36 mm) require 40 mm
            return Float64(bar_diameter_mm) > 36.0 ? 40.0 : 20.0
        elseif exposure_condition == "exposed_to_weather"
            return Float64(bar_diameter_mm) <= 16.0 ? 40.0 : 50.0
        elseif exposure_condition == "cast_against_ground"
            return 75.0
        else
            throw(ArgumentError(
                "exposure_condition must be one of $_VALID_EXPOSURE_CONDITIONS. " *
                "Got: \"$exposure_condition\"",
            ))
        end
    end
end


# -----------------------------------------------------------------------------
# Result types
# -----------------------------------------------------------------------------

"""
    FireResistanceRatingResult

Result for a single fire-resistance rating duration.  Contains echoed inputs,
required values from ACI 216.1M-14 tables, pass/fail flags, and a failure
description.
"""
struct FireResistanceRatingResult
    # Inputs
    aggregate_type        :: String
    restrained            :: Bool
    duration_min          :: Int
    duration_hr           :: Float64
    slab_thickness_mm     :: Float64
    slab_thickness_in     :: Float64
    clear_cover_mm        :: Float64
    clear_cover_in        :: Float64
    prestressed           :: Bool
    tendon_type           :: String
    # Required values — thickness (ACI 216.1M-14 Table 4.2)
    required_thickness_mm     :: Float64
    required_thickness_in     :: Float64
    # Required values — cover (governing = max of ACI 216 fire and ACI 318M durability)
    required_cover_aci216_mm  :: Float64    # ACI 216.1M-14 Table 4.3.1.1
    required_cover_aci216_in  :: Float64
    required_cover_aci318m_mm :: Float64    # ACI 318M-14 Table 20.6.1.3.1
    required_cover_aci318m_in :: Float64
    required_cover_mm         :: Float64    # governing = max(aci216, aci318m)
    required_cover_in         :: Float64
    # Pass / fail
    thickness_pass            :: Bool
    cover_pass                :: Bool
    overall_pass              :: Bool
    failure_reason            :: String
    code_ref                  :: String
end

"""
    FireResistanceResults

Collection of per-rating results returned by `fire_resistance_rating`.
Pass to `print_fire_resistance_summary` for a formatted console report.
"""
struct FireResistanceResults
    inputs_summary :: NamedTuple
    ratings        :: Vector{FireResistanceRatingResult}
end

# Allow JSON3 to serialize these structs directly as JSON objects
StructTypes.StructType(::Type{FireResistanceRatingResult}) = StructTypes.Struct()
StructTypes.StructType(::Type{FireResistanceResults})       = StructTypes.Struct()


# -----------------------------------------------------------------------------
# Unit helper (internal)
# -----------------------------------------------------------------------------

_mm_to_in(x::Real) = x / 25.4


# -----------------------------------------------------------------------------
# Public API
# -----------------------------------------------------------------------------

"""
    fire_resistance_rating(aggregate_type, restrained, slab_thickness_mm,
                           clear_cover_mm; ratings=[60,90,120,180,240])
        -> FireResistanceResults

Perform a prescriptive ACI 216.1M-14 fire resistance check for a concrete slab.

Both criteria from the standard must be satisfied for a rating to pass:
1. Slab thickness  ≥  Table 4.2 minimum equivalent thickness
2. Clear cover     ≥  Table 4.3.1.1 minimum cover

# Arguments
- `aggregate_type::String`     — one of `"siliceous"`, `"carbonate"`,
  `"semi_lightweight"`, `"lightweight"`.
- `restrained::Bool`           — `true` for restrained per Table 4.3.1;
  `false` for unrestrained (conservative default).
- `slab_thickness_mm::Real`    — total slab thickness in mm.  For solid slabs
  with flat surfaces, equivalent thickness equals actual thickness (Section 4.2).
- `clear_cover_mm::Real`       — clear cover from the fire-exposed surface to
  the nearest surface of the longitudinal reinforcement (Table 4.3.1.1 footnote).
- `ratings::Vector{Int}`       — fire durations to check in minutes.
  Default: `[60, 90, 120, 180, 240]` (all five ACI ratings).
- `exposure_condition::String` — ACI 318M-14 §20.6.1.3 exposure class for durability cover.
  One of `"not_exposed"` (interior, default), `"exposed_to_weather"`,
  or `"cast_against_ground"`. The governing cover is `max(ACI 216 fire cover,
  ACI 318M durability cover)`.
- `bar_diameter_mm::Real`      — bar diameter in mm; used only for the
  `"exposed_to_weather"` branch to select 40 mm (≤ 16 mm bar) or 50 mm.
  Default: `16.0`.
- `prestressed::Bool`          — `true` for prestressed reinforcement.  Selects
  ACI 216.1M-14 Table 4.3.1.1 prestressed cover values and ACI 318M-14 Table
  20.6.1.4.1 durability cover.  Default: `false` (nonprestressed).
- `tendon_type::String`        — `"bonded"` or `"unbonded"`.  Only affects the
  `not_exposed` durability cover for prestressed slabs (25 mm bonded, 20 mm
  unbonded per Table 20.6.1.4.1).  Default: `"bonded"`.

# Returns
`FireResistanceResults` with per-rating pass/fail results.
Use `print_fire_resistance_summary` to display.

# Example
```julia
res = fire_resistance_rating("carbonate", false, 127.0, 25.0; ratings=[60, 120, 180])
print_fire_resistance_summary(res)

# With ACI 318M durability cover (exterior slab, 16 mm bars)
res2 = fire_resistance_rating("carbonate", false, 127.0, 40.0;
                               exposure_condition="exposed_to_weather",
                               bar_diameter_mm=16.0)
```
"""
function fire_resistance_rating(
    aggregate_type::String,
    restrained::Bool,
    slab_thickness_mm::Real,
    clear_cover_mm::Real;
    ratings::Vector{Int}       = [60, 90, 120, 180, 240],
    exposure_condition::String = "not_exposed",
    bar_diameter_mm::Real      = 16.0,
    prestressed::Bool          = false,
    tendon_type::String        = "bonded",
)::FireResistanceResults

    aggregate_type in _VALID_AGGREGATE_TYPES || throw(ArgumentError(
        "aggregate_type must be one of $_VALID_AGGREGATE_TYPES. Got: $aggregate_type",
    ))
    exposure_condition in _VALID_EXPOSURE_CONDITIONS || throw(ArgumentError(
        "exposure_condition must be one of $_VALID_EXPOSURE_CONDITIONS. " *
        "Got: \"$exposure_condition\"",
    ))
    tendon_type in _VALID_TENDON_TYPES || throw(ArgumentError(
        "tendon_type must be one of $_VALID_TENDON_TYPES. Got: \"$tendon_type\"",
    ))

    cover_table = if restrained
        prestressed ? _MIN_COVER_PRESTRESSED_RESTRAINED_MM : _MIN_COVER_RESTRAINED_MM
    else
        prestressed ? _MIN_COVER_PRESTRESSED_UNRESTRAINED_MM : _MIN_COVER_UNRESTRAINED_MM
    end
    restraint_label = restrained ? "restrained" : "unrestrained"
    t_mm            = Float64(slab_thickness_mm)
    cc_mm           = Float64(clear_cover_mm)
    results         = FireResistanceRatingResult[]

    for dur in ratings
        haskey(_MIN_THICKNESS_MM[aggregate_type], dur) || throw(ArgumentError(
            "Duration $dur min is not in ACI 216.1M-14 Table 4.2. " *
            "Supported durations: $(sort(collect(keys(_MIN_THICKNESS_MM[aggregate_type]))))",
        ))

        req_t_mm      = Float64(_MIN_THICKNESS_MM[aggregate_type][dur])
        aci216_cover  = Float64(cover_table[aggregate_type][dur])
        aci318m_cover = _aci318_min_cover(exposure_condition, bar_diameter_mm;
                                         prestressed=prestressed, tendon_type=tendon_type)
        req_cc_mm     = max(aci216_cover, aci318m_cover)
        cover_by_318m = aci318m_cover > aci216_cover

        thickness_pass = t_mm  >= req_t_mm
        cover_pass     = cc_mm >= req_cc_mm
        overall_pass   = thickness_pass && cover_pass

        cover_std = cover_by_318m ?
            "ACI 318M-14 Table 20.6.1.3.1 ($exposure_condition, governs)" :
            "ACI 216.1M-14 Table 4.3.1.1 ($restraint_label)"

        failure_reason = if overall_pass
            "PASS"
        elseif !thickness_pass && !cover_pass
            "FAIL: thickness $(round(t_mm, digits=1)) mm < required $req_t_mm mm (Table 4.2); " *
            "cover $(round(cc_mm, digits=1)) mm < required $req_cc_mm mm ($cover_std)"
        elseif !thickness_pass
            "FAIL: thickness $(round(t_mm, digits=1)) mm < required $req_t_mm mm (Table 4.2)"
        else
            "FAIL: cover $(round(cc_mm, digits=1)) mm < required $req_cc_mm mm ($cover_std)"
        end

        code_ref = prestressed ?
            "ACI 216.1M-14: Table 4.2, Table 4.3.1.1, Sec. 4.3.1 (ACI 318M-14: Table 20.6.1.4.1)" :
            "ACI 216.1M-14: Table 4.2, Table 4.3.1.1, Sec. 4.3.1 (ACI 318M-14: Table 20.6.1.3.1)"

        push!(results, FireResistanceRatingResult(
            aggregate_type,
            restrained,
            dur,
            dur / 60.0,
            t_mm,          _mm_to_in(t_mm),
            cc_mm,         _mm_to_in(cc_mm),
            prestressed,
            tendon_type,
            req_t_mm,      _mm_to_in(req_t_mm),
            aci216_cover,  _mm_to_in(aci216_cover),
            aci318m_cover, _mm_to_in(aci318m_cover),
            req_cc_mm,     _mm_to_in(req_cc_mm),
            thickness_pass,
            cover_pass,
            overall_pass,
            failure_reason,
            code_ref,
        ))
    end

    inputs_summary = (
        aggregate_type     = string(aggregate_type),
        restrained         = restrained,
        slab_thickness_mm  = t_mm,
        slab_thickness_in  = _mm_to_in(t_mm),
        clear_cover_mm     = cc_mm,
        clear_cover_in     = _mm_to_in(cc_mm),
        exposure_condition = exposure_condition,
        bar_diameter_mm    = Float64(bar_diameter_mm),
        prestressed        = prestressed,
        tendon_type        = tendon_type,
        ratings_checked    = ratings,
    )

    return FireResistanceResults(inputs_summary, results)
end


# -----------------------------------------------------------------------------
# Console summary printer
# -----------------------------------------------------------------------------

"""
    print_fire_resistance_summary(res::FireResistanceResults)

Print a formatted ACI 216.1M-14 fire resistance summary to stdout.
"""
function print_fire_resistance_summary(res::FireResistanceResults)
    inp           = res.inputs_summary
    restraint_str = inp.restrained ? "Restrained" : "Unrestrained"

    println("\n", "="^80)
    println(" FIRE RESISTANCE SUMMARY — ACI 216.1M-14 / ACI 318M-14")
    println("="^80)
    Printf.@printf(" Aggregate type:      %s\n",                      inp.aggregate_type)
    Printf.@printf(" Restraint class:     %s\n",                      restraint_str)
    Printf.@printf(" Slab thickness:      %.1f mm  (%.3f in.)\n",     inp.slab_thickness_mm, inp.slab_thickness_in)
    Printf.@printf(" Clear cover:         %.1f mm  (%.3f in.)\n",     inp.clear_cover_mm,    inp.clear_cover_in)
    Printf.@printf(" Exposure condition:  %s\n",                      inp.exposure_condition)
    Printf.@printf(" Bar diameter:        %.1f mm\n",                 inp.bar_diameter_mm)
    Printf.@printf(" Prestressed:         %s\n",                      inp.prestressed ? "Yes" : "No")
    inp.prestressed && Printf.@printf(" Tendon type:         %s\n",   inp.tendon_type)
    println("-"^80)
    Printf.@printf(" %-7s  %-18s  %-14s  %-14s  %-12s  %-7s  %s\n",
        "Rating", "Req. thickness", "Req. cover", "Req. cover", "Provided", "Status", "Cover governed by")
    Printf.@printf(" %-7s  %-18s  %-14s  %-14s  %-12s  %-7s\n",
        "", "(mm / in.)", "ACI 216 (mm)", "ACI 318M (mm)", "cover (mm)", "")
    println("-"^80)
    for r in res.ratings
        status    = r.overall_pass ? "PASS" : "FAIL"
        dur_label = isinteger(r.duration_hr) ?
            "$(Int(r.duration_hr))-hr" :
            "$(r.duration_hr)-hr"
        governed_by = r.required_cover_aci318m_mm > r.required_cover_aci216_mm ? "ACI 318M-14" : "ACI 216.1M-14"
        Printf.@printf(" %-7s  %5.0f / %-10.3f  %-14.1f  %-14.1f  %-12.1f  %-7s  %s\n",
            dur_label,
            r.required_thickness_mm, r.required_thickness_in,
            r.required_cover_aci216_mm,
            r.required_cover_aci318m_mm,
            r.clear_cover_mm,
            status,
            governed_by)
        r.overall_pass || Printf.@printf("          → %s\n", r.failure_reason)
    end
    println("="^80)
    if !isempty(res.ratings)
        println(" Code reference: ", res.ratings[1].code_ref)
    end
    println("="^80, "\n")
end


# -----------------------------------------------------------------------------
# Maximum achievable rating
# -----------------------------------------------------------------------------

"""
    maximum_fire_rating(aggregate_type, restrained, slab_thickness_mm,
                        clear_cover_mm; ratings=[60,90,120,180,240])
        -> Union{Int,Nothing}

Return the maximum fire-resistance rating (in minutes) that the slab satisfies
under ACI 216.1M-14, or `nothing` if no rating passes.

Both the thickness (Table 4.2) and cover (Table 4.3.1.1) criteria must pass
for a rating to count.

# Arguments
Same as `fire_resistance_rating`.

# Returns
The largest passing duration in `ratings`, or `nothing`.

# Example
```julia
m = maximum_fire_rating("carbonate", false, 150.0, 30.0)
# → 240 (or smaller, depending on cover)
```
"""
function maximum_fire_rating(
    aggregate_type    :: String,
    restrained        :: Bool,
    slab_thickness_mm :: Real,
    clear_cover_mm    :: Real;
    ratings              :: Vector{Int} = [60, 90, 120, 180, 240],
    exposure_condition   :: String      = "not_exposed",
    bar_diameter_mm      :: Real        = 16.0,
    prestressed          :: Bool        = false,
    tendon_type          :: String      = "bonded",
) :: Union{Int,Nothing}
    res    = fire_resistance_rating(aggregate_type, restrained,
                                    slab_thickness_mm, clear_cover_mm;
                                    ratings=ratings,
                                    exposure_condition=exposure_condition,
                                    bar_diameter_mm=bar_diameter_mm,
                                    prestressed=prestressed,
                                    tendon_type=tendon_type)
    passed = filter(r -> r.overall_pass, res.ratings)
    isempty(passed) && return nothing
    return maximum(r.duration_min for r in passed)
end


# -----------------------------------------------------------------------------
# Equivalent thickness for ribbed / undulating slabs (ACI 216.1M-14 §4.2.4)
# -----------------------------------------------------------------------------

"""
    equivalent_thickness(tmin_mm, s_mm, avg_thickness_mm) -> Float64

Compute the equivalent thickness of a ribbed or undulating concrete slab per
ACI 216.1M-14 Section 4.2.4 (Eq. 4.2.4.3).

The equivalent thickness is used in place of the actual slab thickness when
checking Table 4.2 fire-resistance requirements for non-flat slab soffits.

# Arguments
- `tmin_mm::Real`          — minimum concrete thickness at the thinnest point
  of the rib (mm).
- `s_mm::Real`             — centre-to-centre rib spacing (mm).
- `avg_thickness_mm::Real` — net cross-sectional area of the slab per unit
  width divided by the unit width (mm).  The caller pre-computes this from
  the slab geometry; this function caps it internally at `2*tmin_mm` where
  required by the branching logic.

# Returns
Equivalent thickness `te` in mm (Float64).  Branching per §4.2.4:
- `s > 4·tmin`: returns `tmin`
- `s ≤ 2·tmin`: returns `min(avg_thickness_mm, 2·tmin)`
- otherwise:   Eq. 4.2.4.3  `te = tmin + (4·tmin/s − 1) · (te2 − tmin)`

# Example
```julia
te = equivalent_thickness(65.0, 180.0, 100.0)
```
"""
function equivalent_thickness(
    tmin_mm          :: Real,
    s_mm             :: Real,
    avg_thickness_mm :: Real,
)::Float64
    tmin = Float64(tmin_mm)
    s    = Float64(s_mm)
    avg  = Float64(avg_thickness_mm)

    tmin > 0 || throw(ArgumentError("tmin_mm must be positive. Got: $tmin"))
    s    > 0 || throw(ArgumentError("s_mm must be positive. Got: $s"))
    avg  > 0 || throw(ArgumentError("avg_thickness_mm must be positive. Got: $avg"))

    if s > 4.0 * tmin
        return tmin
    elseif s <= 2.0 * tmin
        return min(avg, 2.0 * tmin)
    else
        te2 = min(avg, 2.0 * tmin)
        return tmin + (4.0 * tmin / s - 1.0) * (te2 - tmin)
    end
end
