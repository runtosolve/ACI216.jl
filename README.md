# ACI216.jl

A Julia package for concrete slab fire resistance per **ACI/TMS 216.1M-14** and **ACI 318M-14**.

## Installation

```julia
using Pkg
Pkg.add(url = "https://github.com/runtosolve/ACI216.jl")
```

## Capabilities

| Function | Description |
|---|---|
| `temperature_within_slab` | Temperature at depth within a slab (ASTM E119 fire) |
| `temperature_profile` | Temperatures at multiple depths |
| `fire_resistance_rating` | Pass/fail check — Table 4.2 thickness + Table 4.3.1.1 cover |
| `maximum_fire_rating` | Highest rating (minutes) the slab achieves |
| `equivalent_thickness` | Equivalent thickness for ribbed slabs (§4.2.4) |
| `concrete_strength_reduction` | f'c retention fraction at elevated temperature |
| `steel_strength_reduction` | fy retention fraction at elevated temperature |
| `concrete_critical_temperature` | Temperature at which f'c drops below a threshold |
| `steel_critical_temperature` | Temperature at which fy drops below a threshold |

Supported aggregate types: `"carbonate"`, `"siliceous"`, `"semi_lightweight"`, `"lightweight"`

## Usage

```julia
using ACI216

# Temperature at 40 mm depth after 120 min — carbonate slab
T = temperature_within_slab(120.0, 40.0, "carbonate")           # °F
T = temperature_within_slab(120.0, 40.0, "carbonate"; temperature_unit=:celsius)

# Equivalent thickness — ribbed slab (tmin=65 mm, spacing=180 mm, avg=100 mm)
te = equivalent_thickness(65.0, 180.0, 100.0)

# Fire resistance rating check — unrestrained, interior, nonprestressed
res = fire_resistance_rating("carbonate", false, 150.0, 30.0)
print_fire_resistance_summary(res)

# With ACI 318M-14 durability cover — exterior slab
res = fire_resistance_rating("carbonate", false, 150.0, 40.0;
    exposure_condition = "exposed_to_weather",
    bar_diameter_mm    = 16.0)

# Prestressed slab — bonded tendons
res = fire_resistance_rating("carbonate", false, 150.0, 40.0;
    prestressed = true,
    tendon_type = "bonded")

# Maximum achievable fire rating (minutes)
m = maximum_fire_rating("carbonate", false, 150.0, 30.0)

# Material strength at 1000 °F
f_concrete = concrete_strength_reduction(1000.0, "carbonate", "unstressed")
f_steel    = steel_strength_reduction(1000.0)

# Critical temperatures
T_concrete = concrete_critical_temperature(0.75, "carbonate", "unstressed")
T_steel    = steel_critical_temperature(0.80)
```

## Demo

```
julia --project=. scripts/demo.jl
```

## Standards

- ACI/TMS 216.1M-14 — Tables 4.2, 4.3.1.1 and Section 4.2.4
- ACI 318M-14 — Tables 20.6.1.3.1 (nonprestressed) and 20.6.1.4.1 (prestressed)
