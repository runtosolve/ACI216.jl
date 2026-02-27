# =============================================================================
# ACI216.jl
#
# Julia package implementing ACI/TMS 216.1M-14:
#   "Code Requirements for Determining Fire Resistance of Concrete and
#    Masonry Construction Assemblies"
#
# Exports:
#   temperature_within_slab         — 2D linear interpolation of ACI figure data
#   temperature_profile             — vectorised temperature at multiple depths
#   fire_resistance_rating          — prescriptive table check (Table 4.2 / 4.3.1.1)
#   maximum_fire_rating             — highest fire rating a slab achieves
#   FireResistanceResults           — result container type
#   FireResistanceRatingResult      — per-rating result type
#   print_fire_resistance_summary   — formatted console output (fire resistance)
#   concrete_strength_reduction     — f'c retention fraction vs. temperature
#   steel_strength_reduction        — fy retention fraction vs. temperature
#   concrete_critical_temperature   — temperature where f'c drops below threshold
#   steel_critical_temperature      — temperature where fy drops below threshold
#   print_strength_summary          — formatted console output (material strength)
#   rebar_condition                 — combined temperature + strength check at rebar depth
#   F_to_C, C_to_F                 — temperature unit conversion helpers
#
# Data:
#   CSV files in assets/ contain digitised curves from the ACI figures
#   (WebPlotDigitizer).
#   Three aggregate types are supported for temperature interpolation and
#   strength reduction: "carbonate", "siliceous", "semi_lightweight".
#   A fourth type, "lightweight", is supported for the prescriptive table
#   check only (no digitised figure data available).
# =============================================================================

module ACI216

using CSV
using DataFrames
using Interpolations
using Printf

include("temperature.jl")
include("fire_resistance.jl")
include("material_strength.jl")

export temperature_within_slab,
       temperature_profile,
       fire_resistance_rating,
       maximum_fire_rating,
       FireResistanceResults,
       FireResistanceRatingResult,
       print_fire_resistance_summary,
       concrete_strength_reduction,
       steel_strength_reduction,
       concrete_critical_temperature,
       steel_critical_temperature,
       print_strength_summary,
       rebar_condition,
       F_to_C,
       C_to_F

function __init__()
    _load_temperature_data()
    _load_strength_data()
end

end # module ACI216
