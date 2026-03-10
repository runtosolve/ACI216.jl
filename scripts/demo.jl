# =============================================================================
# ACI216.jl — Demo Script
#
# Run from the package root:
#   julia --project=. scripts/demo.jl
#
# Demonstrates all major public functions in the package.
# =============================================================================

using ACI216
using Printf
using Plots

println("\n", "="^70)
println(" ACI216.jl DEMO")
println("="^70)


# -----------------------------------------------------------------------------
# 1. Temperature within a concrete slab
#
# Estimates the temperature at a given distance from the fire-exposed surface
# of a slab exposed to an ASTM E119 standard fire.
# Based on digitised curves from ACI 216.1M-14 Figures 4.4.2.2.1a(a-c).
# -----------------------------------------------------------------------------

println("\n--- 1. Temperature within slab ---")

T1 = temperature_within_slab(120.0, 40.0, "carbonate")
T2 = temperature_within_slab(120.0, 40.0, "carbonate"; temperature_unit=:celsius)
T3 = temperature_within_slab(120.0, 40.0, "siliceous")
T4 = temperature_within_slab(120.0, 40.0, "semi_lightweight")

println("At 120 min, 40 mm from fire-exposed surface:")
@printf("  Carbonate:        %.1f °F  /  %.1f °C\n", T1, T2)
@printf("  Siliceous:        %.1f °F\n", T3)
@printf("  Semi-lightweight: %.1f °F\n", T4)


# -----------------------------------------------------------------------------
# 2. Temperature at cover depth (nearest bar surface)
#
# A practical use case: find the temperature at the clear cover distance
# (to the nearest surface of the bar, per Table 4.3.1.1 footnote),
# then assess strength reduction.
# -----------------------------------------------------------------------------

println("\n--- 2. Temperature at cover depth (nearest bar surface) ---")

cover_mm   = 25.0
fire_min   = 120.0
T_rebar_F  = temperature_within_slab(fire_min, cover_mm, "carbonate")
T_rebar_C  = temperature_within_slab(fire_min, cover_mm, "carbonate"; temperature_unit=:celsius)

@printf("  Cover = %.0f mm, fire time = %.0f min\n", cover_mm, fire_min)
@printf("  Temperature at cover depth: %.1f °F  /  %.1f °C\n", T_rebar_F, T_rebar_C)


# -----------------------------------------------------------------------------
# 3. Material strength reduction at elevated temperature
#
# Returns the fraction of ambient strength that remains (0.0 – 1.0).
# Concrete: carbonate, siliceous, or semi-lightweight; several stress conditions.
# Steel: hot-rolled flexural reinforcement.
# -----------------------------------------------------------------------------

println("\n--- 3. Material strength reduction ---")

fc_frac = concrete_strength_reduction(T_rebar_F, "carbonate", "unstressed")
fy_frac = steel_strength_reduction(T_rebar_F)

@printf("  At %.1f °F (rebar location after %.0f min):\n", T_rebar_F, fire_min)
@printf("  Concrete f'c retention (carbonate, unstressed): %.2f  (%.0f%%)\n",
        fc_frac, fc_frac * 100)
@printf("  Steel fy retention (hot-rolled):                %.2f  (%.0f%%)\n",
        fy_frac, fy_frac * 100)


# -----------------------------------------------------------------------------
# 4. Critical temperatures
#
# Finds the temperature at which a material's strength drops below a
# user-defined threshold fraction of its ambient value.
# Useful for determining the fire duration at which a member loses capacity.
# -----------------------------------------------------------------------------

println("\n--- 4. Critical temperatures ---")

T_crit_fc = concrete_critical_temperature(0.75, "carbonate", "unstressed")
T_crit_fy = steel_critical_temperature(0.80)

@printf("  Carbonate concrete (unstressed) drops below 75%% f'c at: %.1f °F\n", T_crit_fc)
@printf("  Hot-rolled steel drops below 80%% fy at:                 %.1f °F\n", T_crit_fy)


# -----------------------------------------------------------------------------
# 5. Equivalent thickness for ribbed/undulating slabs  (ACI 216.1M-14 §4.2.4)
#
# For slabs with a non-flat soffit, the actual thickness cannot be used
# directly in Table 4.2. equivalent_thickness() computes the value to use.
# -----------------------------------------------------------------------------

println("\n--- 5. Equivalent thickness (ribbed slab) ---")

# Example: tmin=65 mm, rib spacing=180 mm, avg net thickness=100 mm
te = equivalent_thickness(65.0, 180.0, 100.0)
@printf("  tmin=65 mm, s=180 mm, avg=100 mm  →  te = %.1f mm\n", te)

# Sparse ribs (s > 4·tmin): equivalent thickness falls back to tmin
te_sparse = equivalent_thickness(65.0, 300.0, 100.0)
@printf("  tmin=65 mm, s=300 mm (sparse ribs)  →  te = %.1f mm  (= tmin)\n", te_sparse)


# -----------------------------------------------------------------------------
# 6. Fire resistance rating check  (ACI 216.1M-14 Table 4.2 + Table 4.3.1.1,
#                                   ACI 318M-14 Table 20.6.1.3.1)
#
# Checks both minimum thickness and minimum cover for each standard fire
# rating (1–4 hr). The governing cover is max(ACI 216 fire cover,
# ACI 318M durability cover) per ACI 216.1M-14 Section 4.3.1.
# -----------------------------------------------------------------------------

println("\n--- 6. Fire resistance rating check ---")

# Interior slab (default exposure: "not_exposed", 20 mm ACI 318M floor)
res = fire_resistance_rating("carbonate", false, 150.0, 30.0)
print_fire_resistance_summary(res)

# Exterior slab (exposed_to_weather raises ACI 318M floor to 40 mm for ≤16 mm bars)
println("  [ Exterior slab - exposed_to_weather ]")
res_ext = fire_resistance_rating("carbonate", false, 150.0, 40.0;
                                  exposure_condition = "exposed_to_weather",
                                  bar_diameter_mm    = 16.0)
print_fire_resistance_summary(res_ext)

# Prestressed slab - bonded tendons, interior (ACI 318M floor = 25 mm; ACI 216 cover higher)
println("  [ Prestressed slab - bonded tendons, not_exposed ]")
res_ps = fire_resistance_rating("carbonate", false, 150.0, 40.0;
                                 prestressed = true,
                                 tendon_type = "bonded")
print_fire_resistance_summary(res_ps)

# Prestressed slab - unbonded tendons, exposed to weather (ACI 318M floor = 50 mm)
println("  [ Prestressed slab - unbonded tendons, exposed_to_weather ]")
res_ps_ext = fire_resistance_rating("carbonate", false, 150.0, 50.0;
                                     prestressed        = true,
                                     tendon_type        = "unbonded",
                                     exposure_condition = "exposed_to_weather")
print_fire_resistance_summary(res_ps_ext)


# -----------------------------------------------------------------------------
# 7. Maximum fire rating
#
# Convenience function — returns the single highest rating (in minutes)
# that the slab achieves, or nothing if it fails the 1-hr check.
# -----------------------------------------------------------------------------

println("\n--- 7. Maximum achievable fire rating ---")

max_rating = maximum_fire_rating("carbonate", false, 150.0, 30.0)
println("  Maximum fire rating: $(isnothing(max_rating) ? "none" : "$(max_rating ÷ 60) hr  ($max_rating min)")")


# -----------------------------------------------------------------------------
# 8. Combined rebar check
#
# rebar_condition() bundles temperature interpolation + strength reduction
# into a single call for the rebar location.
# -----------------------------------------------------------------------------

println("\n--- 8. Combined rebar condition ---")

rc = rebar_condition(120.0, 30.0, "carbonate")
@printf("  Fire time: 120 min, cover: 30 mm, carbonate\n")
@printf("  Temperature at rebar: %.1f °F  /  %.1f °C\n", rc.temperature_F, rc.temperature_C)
@printf("  Steel fy retention:       %.2f  (%.0f%%)\n", rc.steel_fraction,    rc.steel_fraction    * 100)
@printf("  Concrete f'c retention:   %.2f  (%.0f%%)\n", rc.concrete_fraction, rc.concrete_fraction * 100)

# -----------------------------------------------------------------------------
# 9. Temperature within slab — carbonate aggregate (plot)
#
# Plots all digitised depth curves and overlays a single interpolated point
# at a depth and fire time that falls between two curves, demonstrating the
# 2D linear interpolation capability of temperature_within_slab().
# -----------------------------------------------------------------------------

println("\n--- 9. Temperature within slab plot (carbonate) ---")

_max_time = Dict(
    5 => 30, 10 => 60, 15 => 90, 20 => 120, 25 => 150, 30 => 180,
    40 => 240, 50 => 240, 60 => 240, 70 => 240, 80 => 240,
    90 => 240, 100 => 240, 125 => 240, 150 => 240, 180 => 240,
)

_plot_depths = [10, 20, 30, 50, 70, 100, 150]
_colours = range(colorant"steelblue", colorant"firebrick"; length = length(_plot_depths))

p = plot(
    xlabel         = "Fire exposure time (min)",
    ylabel         = "Temperature (°F)",
    title          = "Temperature Within Slab — Carbonate Aggregate\n(ACI 216.1M-14 Fig. 4.4.2.2.1a(a))",
    legend         = :bottomright,
    size           = (800, 520),
    framestyle     = :box,
    grid           = true,
    gridalpha      = 0.3,
    minorgrid      = true,
    minorgridalpha = 0.15,
    titlefont      = font(11),
    guidefont      = font(10),
    tickfont       = font(9),
    legendfont     = font(6),
    legendtitle    = "",
)

for (d, col) in zip(_plot_depths, _colours)
    times = range(30.0, _max_time[d]; length = 60)
    temps = [temperature_within_slab(t, Float64(d), "carbonate") for t in times]
    plot!(p, times, temps; label = "$(d) mm", color = col, lw = 1.8, alpha = 0.85)
end

# Interpolated point: 35 mm depth, 105 min — between digitised curves in both axes
_interp_depth = 35.0
_interp_time  = 105.0
_interp_temp  = temperature_within_slab(_interp_time, _interp_depth, "carbonate")

_t30 = range(30.0, _max_time[30]; length = 60)
_t40 = range(30.0, _max_time[40]; length = 60)
plot!(p, _t30, [temperature_within_slab(t, 30.0, "carbonate") for t in _t30];
      label = "30 mm (bracket)", color = :darkorange, lw = 2.2, ls = :dash, alpha = 0.9)
plot!(p, _t40, [temperature_within_slab(t, 40.0, "carbonate") for t in _t40];
      label = "40 mm (bracket)", color = :darkgreen,  lw = 2.2, ls = :dash, alpha = 0.9)

vline!(p, [_interp_time]; color = :grey50, lw = 1.0, ls = :dot, label = "")
hline!(p, [_interp_temp]; color = :grey50, lw = 1.0, ls = :dot, label = "")

scatter!(p, [_interp_time], [_interp_temp];
         markersize = 9, markercolor = :white,
         markerstrokecolor = :black, markerstrokewidth = 2,
         label = @sprintf("Interp. (%.0f mm, %.0f min) → %.0f °F",
                           _interp_depth, _interp_time, _interp_temp))

annotate!(p,
    _interp_time + 6, _interp_temp + 30,
    text(@sprintf("  (%.0f mm, %.0f min)\n  %.0f °F  /  %.0f °C",
                  _interp_depth, _interp_time, _interp_temp, F_to_C(_interp_temp)),
         :left, 8, :black))

_outpath = joinpath(@__DIR__, "..", "outputs", "temperature_within_slab_carbonate.png")
mkpath(dirname(_outpath))
savefig(p, _outpath)
println("  Plot saved → $(_outpath)")
display(p)

println("="^70)
println(" End of demo")
println("="^70, "\n")
