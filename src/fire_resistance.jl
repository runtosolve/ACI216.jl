# =============================================================================
# ACI 216.1M-14 — Prescriptive fire resistance checker for concrete slabs
#
# Implements:
#   Table 4.2       — Minimum equivalent slab thickness (mm)
#   Table 4.3.1.1   — Minimum clear cover for nonprestressed slabs (mm)
#
# Both criteria must be satisfied for a slab to achieve a given fire rating.
# Cover is measured from the fire-exposed surface to the nearest surface of
# the longitudinal reinforcement (per Table 4.3.1.1 footnote).
#
# Supported aggregate types: :siliceous, :carbonate, :semi_lightweight, :lightweight
# Supported durations (min):  60, 90, 120, 180, 240
#
# Verified against ACI 216.1M-14 PDF (scanned original).
# Bug fixed in prior standalone script: lightweight 3-hr unrestrained cover
#   was 20 mm; correct value is 30 mm.
# =============================================================================


# -----------------------------------------------------------------------------
# Table 4.2 — Minimum Equivalent Thickness (mm)
# -----------------------------------------------------------------------------

const _MIN_THICKNESS_MM = Dict{Symbol,Dict{Int,Int}}(
    :siliceous        => Dict(60 => 90,  90 => 110, 120 => 125, 180 => 155, 240 => 175),
    :carbonate        => Dict(60 => 80,  90 => 100, 120 => 115, 180 => 145, 240 => 170),
    :semi_lightweight => Dict(60 => 70,  90 => 85,  120 => 95,  180 => 115, 240 => 135),
    :lightweight      => Dict(60 => 65,  90 => 80,  120 => 90,  180 => 110, 240 => 130),
)


# -----------------------------------------------------------------------------
# Table 4.3.1.1 — Minimum Cover (mm), Restrained
# All aggregate types: 20 mm for all ratings 1 through 4 hours.
# -----------------------------------------------------------------------------

const _MIN_COVER_RESTRAINED_MM = Dict{Symbol,Dict{Int,Int}}(
    :siliceous        => Dict(60 => 20, 90 => 20, 120 => 20, 180 => 20, 240 => 20),
    :carbonate        => Dict(60 => 20, 90 => 20, 120 => 20, 180 => 20, 240 => 20),
    :semi_lightweight => Dict(60 => 20, 90 => 20, 120 => 20, 180 => 20, 240 => 20),
    :lightweight      => Dict(60 => 20, 90 => 20, 120 => 20, 180 => 20, 240 => 20),
)


# -----------------------------------------------------------------------------
# Table 4.3.1.1 — Minimum Cover (mm), Unrestrained
# -----------------------------------------------------------------------------

const _MIN_COVER_UNRESTRAINED_MM = Dict{Symbol,Dict{Int,Int}}(
    :siliceous        => Dict(60 => 20, 90 => 20, 120 => 25, 180 => 30, 240 => 40),
    :carbonate        => Dict(60 => 20, 90 => 20, 120 => 20, 180 => 30, 240 => 30),
    :semi_lightweight => Dict(60 => 20, 90 => 20, 120 => 20, 180 => 30, 240 => 30),
    :lightweight      => Dict(60 => 20, 90 => 20, 120 => 20, 180 => 30, 240 => 30),
)

const _VALID_AGGREGATE_TYPES = (:siliceous, :carbonate, :semi_lightweight, :lightweight)


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
    aggregate_type        :: Symbol
    restrained            :: Bool
    duration_min          :: Int
    duration_hr           :: Float64
    slab_thickness_mm     :: Float64
    slab_thickness_in     :: Float64
    clear_cover_mm        :: Float64
    clear_cover_in        :: Float64
    # Required values (ACI 216.1M-14 tables)
    required_thickness_mm :: Float64
    required_thickness_in :: Float64
    required_cover_mm     :: Float64
    required_cover_in     :: Float64
    # Pass / fail
    thickness_pass        :: Bool
    cover_pass            :: Bool
    overall_pass          :: Bool
    failure_reason        :: String
    code_ref              :: String
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
- `aggregate_type::Symbol`     — one of `:siliceous`, `:carbonate`,
  `:semi_lightweight`, `:lightweight`.
- `restrained::Bool`           — `true` for restrained per Table 4.3.1;
  `false` for unrestrained (conservative default).
- `slab_thickness_mm::Real`    — total slab thickness in mm.  For solid slabs
  with flat surfaces, equivalent thickness equals actual thickness (Section 4.2).
- `clear_cover_mm::Real`       — clear cover from the fire-exposed surface to
  the nearest surface of the longitudinal reinforcement (Table 4.3.1.1 footnote).
- `ratings::Vector{Int}`       — fire durations to check in minutes.
  Default: `[60, 90, 120, 180, 240]` (all five ACI ratings).

# Returns
`FireResistanceResults` with per-rating pass/fail results.
Use `print_fire_resistance_summary` to display.

# Example
```julia
res = fire_resistance_rating(:carbonate, false, 127.0, 25.0; ratings=[60, 120, 180])
print_fire_resistance_summary(res)
```
"""
function fire_resistance_rating(
    aggregate_type::Symbol,
    restrained::Bool,
    slab_thickness_mm::Real,
    clear_cover_mm::Real;
    ratings::Vector{Int} = [60, 90, 120, 180, 240],
)::FireResistanceResults

    aggregate_type in _VALID_AGGREGATE_TYPES || throw(ArgumentError(
        "aggregate_type must be one of $_VALID_AGGREGATE_TYPES. Got: $aggregate_type",
    ))

    cover_table     = restrained ? _MIN_COVER_RESTRAINED_MM : _MIN_COVER_UNRESTRAINED_MM
    restraint_label = restrained ? "restrained" : "unrestrained"
    t_mm            = Float64(slab_thickness_mm)
    cc_mm           = Float64(clear_cover_mm)
    results         = FireResistanceRatingResult[]

    for dur in ratings
        haskey(_MIN_THICKNESS_MM[aggregate_type], dur) || throw(ArgumentError(
            "Duration $dur min is not in ACI 216.1M-14 Table 4.2. " *
            "Supported durations: $(sort(collect(keys(_MIN_THICKNESS_MM[aggregate_type]))))",
        ))

        req_t_mm  = Float64(_MIN_THICKNESS_MM[aggregate_type][dur])
        req_cc_mm = Float64(cover_table[aggregate_type][dur])

        thickness_pass = t_mm  >= req_t_mm
        cover_pass     = cc_mm >= req_cc_mm
        overall_pass   = thickness_pass && cover_pass

        failure_reason = if overall_pass
            "PASS"
        elseif !thickness_pass && !cover_pass
            "FAIL: thickness $(round(t_mm, digits=1)) mm < required $req_t_mm mm (Table 4.2); " *
            "cover $(round(cc_mm, digits=1)) mm < required $req_cc_mm mm (Table 4.3.1.1)"
        elseif !thickness_pass
            "FAIL: thickness $(round(t_mm, digits=1)) mm < required $req_t_mm mm (Table 4.2)"
        else
            "FAIL: cover $(round(cc_mm, digits=1)) mm < required $req_cc_mm mm " *
            "(Table 4.3.1.1, $restraint_label)"
        end

        push!(results, FireResistanceRatingResult(
            aggregate_type,
            restrained,
            dur,
            dur / 60.0,
            t_mm,     _mm_to_in(t_mm),
            cc_mm,    _mm_to_in(cc_mm),
            req_t_mm, _mm_to_in(req_t_mm),
            req_cc_mm, _mm_to_in(req_cc_mm),
            thickness_pass,
            cover_pass,
            overall_pass,
            failure_reason,
            "ACI 216.1M-14: Table 4.2, Table 4.3.1.1",
        ))
    end

    inputs_summary = (
        aggregate_type    = string(aggregate_type),
        restrained        = restrained,
        slab_thickness_mm = t_mm,
        slab_thickness_in = _mm_to_in(t_mm),
        clear_cover_mm    = cc_mm,
        clear_cover_in    = _mm_to_in(cc_mm),
        ratings_checked   = ratings,
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

    println("\n", "="^76)
    println(" FIRE RESISTANCE SUMMARY — ACI 216.1M-14")
    println("="^76)
    Printf.@printf(" Aggregate type:  %s\n",                      inp.aggregate_type)
    Printf.@printf(" Restraint class: %s\n",                      restraint_str)
    Printf.@printf(" Slab thickness:  %.1f mm  (%.3f in.)\n",     inp.slab_thickness_mm, inp.slab_thickness_in)
    Printf.@printf(" Clear cover:     %.1f mm  (%.3f in.)\n",     inp.clear_cover_mm,    inp.clear_cover_in)
    println("-"^76)
    Printf.@printf(" %-7s  %-18s  %-18s  %-12s  %s\n",
        "Rating", "Req. thickness", "Req. cover", "Provided", "Status")
    Printf.@printf(" %-7s  %-18s  %-18s  %-12s  %s\n",
        "", "(mm / in.)", "(mm / in.)", "cover (mm)", "")
    println("-"^76)
    for r in res.ratings
        status    = r.overall_pass ? "PASS" : "FAIL"
        dur_label = "$(r.duration_min ÷ 60)-hr"
        Printf.@printf(" %-7s  %5.0f / %-10.3f  %5.0f / %-10.3f  %-12.1f  %s\n",
            dur_label,
            r.required_thickness_mm, r.required_thickness_in,
            r.required_cover_mm,     r.required_cover_in,
            r.clear_cover_mm,
            status)
        r.overall_pass || Printf.@printf("          → %s\n", r.failure_reason)
    end
    println("="^76)
    println(" Code reference: ACI 216.1M-14, Table 4.2 and Table 4.3.1.1")
    println("="^76, "\n")
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
m = maximum_fire_rating(:carbonate, false, 150.0, 30.0)
# → 240 (or smaller, depending on cover)
```
"""
function maximum_fire_rating(
    aggregate_type    :: Symbol,
    restrained        :: Bool,
    slab_thickness_mm :: Real,
    clear_cover_mm    :: Real;
    ratings           :: Vector{Int} = [60, 90, 120, 180, 240],
) :: Union{Int,Nothing}
    res    = fire_resistance_rating(aggregate_type, restrained,
                                    slab_thickness_mm, clear_cover_mm;
                                    ratings=ratings)
    passed = filter(r -> r.overall_pass, res.ratings)
    isempty(passed) && return nothing
    return maximum(r.duration_min for r in passed)
end
