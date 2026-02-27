# ACI216.jl

A Julia package for concrete fire resistance checks per **ACI/TMS 216.1M-14**.

## What it does

- **Temperature interpolation** — estimates the temperature at any depth inside a concrete slab exposed to a standard ASTM E119 fire, based on digitized ACI 216.1M-14 test curves for carbonate, siliceous, and semi-lightweight aggregate concrete.
- **Fire resistance rating check** — evaluates whether a slab passes the prescriptive ACI 216.1M-14 requirements (Table 4.2 minimum thickness, Table 4.3.1.1 minimum cover) for ratings from 1 to 4 hours.

## Usage

### Temperature at a depth

```julia
using ACI216

# Temperature (°F) at 50 mm depth in a carbonate slab after 120 minutes
T = temperature_within_slab(120, 50, "carbonate")
```

Supported concrete types: `"carbonate"`, `"siliceous"`, `"semi_lightweight"`

### Fire resistance rating check

```julia
using ACI216

# Check a 150 mm carbonate slab with 25 mm cover, unrestrained
res = fire_resistance_rating(:carbonate, false, 150.0, 25.0)
print_fire_resistance_summary(res)
```

Arguments: `aggregate_type` (Symbol), `restrained` (Bool), `slab_thickness_mm`, `clear_cover_mm`

To check specific ratings only:

```julia
res = fire_resistance_rating(:siliceous, true, 125.0, 20.0; ratings=[60, 120, 180])
```

### Material strength reduction

Returns the retained strength fraction (0.0–1.0) at elevated temperature.

**Concrete compressive strength:**

```julia
using ACI216

# Fraction of f'c remaining at 800 °F for unstressed carbonate concrete
f = concrete_strength_reduction(800.0, "carbonate", "unstressed")
```

Aggregate types: `"carbonate"`, `"siliceous"`, `"semi_lightweight"`

Conditions for carbonate and siliceous: `"unstressed"`, `"stressed"`, `"unstressed_residual"`

Conditions for semi-lightweight: `"unstressed_sanded"`, `"unstressed_unsanded"`, `"stressed"`, `"unstressed_residual_sanded"`

Temperatures outside the data range are clamped to the nearest endpoint (no extrapolation).

**Steel yield strength:**

```julia
# Fraction of fy remaining at 1000 °F for hot-rolled flexural reinforcement
f = steel_strength_reduction(1000.0)
```
