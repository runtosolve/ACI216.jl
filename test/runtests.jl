# =============================================================================
# ACI216.jl — Comprehensive Stress Test
#
# Run with:
#   julia --project=ACI216.jl ACI216.jl/test/runtests.jl
# or from inside the ACI216.jl directory:
#   julia --project test/runtests.jl
# or via:
#   using Pkg; Pkg.test("ACI216")
#
# Test categories:
#   1.  Data integrity        — unique depths per CSV, monotone time knots
#   2.  Exact CSV values      — spot checks at grid points
#   3.  Time interpolation    — linear interp between adjacent time knots
#   4.  Depth interpolation   — linear interp between adjacent depth curves
#   5.  Boundary values       — min/max depth, min/max time per depth curve
#   6.  Out-of-range errors   — ArgumentError for all invalid inputs
#   7.  Fire resistance table — pass/fail boundary cases, all aggregate types
#   8.  Fire resistance errors — invalid aggregate type, invalid duration
#   9.  Strength data integrity — row counts, sorted temps, bounded fracs
#   10. Strength exact values  — spot checks at CSV grid temperatures
#   11. Strength interpolation — linear interp between adjacent knots
#   12. Strength clamping      — below/above data range returns endpoint value
#   13. Strength invalid inputs — ArgumentError for unknown type/condition
#   14. Unit conversion          — F_to_C/C_to_F helpers, :celsius keyword on all functions
#   15. Rebar condition          — rebar_condition field consistency, defaults, error propagation
#   16. Maximum fire rating      — maximum_fire_rating: highest passing duration, nothing on all-fail
#   17. Critical temperature     — steel/concrete_critical_temperature round-trip, Inf sentinel, errors
#   18. Print strength summary   — print_strength_summary output sanity, invalid input errors
#   19. Temperature profile      — temperature_profile length, element match, error propagation
# =============================================================================

using Test
using ACI216

# Tolerance for floating-point comparisons
const RTOL = 1e-6

println("\n", "="^70)
println(" ACI216.jl Stress Test Suite")
println("="^70)

# =============================================================================
# 1. DATA INTEGRITY
# =============================================================================
@testset "1. Data integrity" begin

    for ct in ("carbonate", "siliceous", "semi_lightweight")
        df     = ACI216._TEMP_DATA[ct]
        depths = df.Distance_mm

        # 1a. No duplicate distance values
        unique_depths = unique(depths)
        @testset "$ct — unique depths" begin
            @test length(unique_depths) * 7 >= size(df, 1)  # ≥7 rows per depth curve
            # More precise: each depth_mm appears ≥5 and ≤8 times (shallow caps early)
            for d in unique_depths
                cnt = count(==(d), depths)
                @test 4 <= cnt <= 8
            end
        end

        # 1b. Within each depth curve, times are strictly increasing
        @testset "$ct — monotone time knots" begin
            for d in unique_depths
                sub   = filter(:Distance_mm => ==(d), df)
                times = sort(Float64.(sub.Time_min))
                @test times == unique(times)          # no duplicate times
                @test issorted(times; lt=<)           # strictly sorted
            end
        end

        # 1c. Temperature increases with time at every depth (net monotone, with 1 °F noise tolerance).
        # Digitized curves may have tiny fluctuations at cold, deep curves.
        @testset "$ct — temp increases with time" begin
            for d in unique_depths
                sub   = sort(filter(:Distance_mm => ==(d), df), :Time_min)
                temps = Float64.(sub[!, "Temperature_F"])
                # Allow up to 1 °F drop (digitizing artifact) but overall must rise
                for i in 2:length(temps)
                    @test temps[i] >= temps[i-1] - 1.0
                end
                @test temps[end] > temps[1]   # net increase over full time range
            end
        end

        # 1d. Temperature decreases with depth at every time (surface is hottest)
        @testset "$ct — temp decreases with depth at t=30" begin
            t30   = filter(:Time_min => ==(30), df)
            t30s  = sort(t30, :Distance_mm)
            temps = Float64.(t30s[!, "Temperature_F"])
            @test issorted(reverse(temps))   # decreasing as depth increases
        end
    end
end


# =============================================================================
# 2. EXACT CSV VALUES
# Interpolating at a grid point must return the CSV value within tolerance.
# =============================================================================
@testset "2. Exact CSV grid values" begin

    # --- carbonate ---
    @testset "carbonate exact values" begin
        @test isapprox(temperature_within_slab(30,  5,   "carbonate"), 1000.133165,   rtol=RTOL)
        @test isapprox(temperature_within_slab(60,  5,   "carbonate"), 1303.695836,   rtol=RTOL)
        @test isapprox(temperature_within_slab(30,  25,  "carbonate"), 508.5850262,   rtol=RTOL)
        @test isapprox(temperature_within_slab(60,  25,  "carbonate"), 827.2756436,   rtol=RTOL)
        @test isapprox(temperature_within_slab(240, 25,  "carbonate"), 1283.043811,   rtol=RTOL)
        @test isapprox(temperature_within_slab(120, 40,  "carbonate"), 862.409037,    rtol=RTOL)  # docstring example
        @test isapprox(temperature_within_slab(180, 80,  "carbonate"), 596.3115783,   rtol=RTOL)
        @test isapprox(temperature_within_slab(30,  90,  "carbonate"), 166.0586783,   rtol=RTOL)
        @test isapprox(temperature_within_slab(240, 150, "carbonate"), 341.5495649,   rtol=RTOL)
        @test isapprox(temperature_within_slab(240, 180, "carbonate"), 294.8376353,   rtol=RTOL)
    end

    # --- siliceous ---
    # Depth grid: 5,10,15,20,25,30,40,50,60,70,80,90,100,110,125,150,180 (17 curves)
    # Labels match carbonate exactly; siliceous adds a 4 3/8 in. curve at 110 mm.
    @testset "siliceous exact values" begin
        @test isapprox(temperature_within_slab(30,  5,   "siliceous"), 1017.593529,   rtol=RTOL)
        @test isapprox(temperature_within_slab(60,  25,  "siliceous"), 881.0920121,   rtol=RTOL)
        @test isapprox(temperature_within_slab(30,  50,  "siliceous"), 288.1108864,   rtol=RTOL)
        @test isapprox(temperature_within_slab(120, 50,  "siliceous"), 786.5099427,   rtol=RTOL)
        # 60 mm = "2 3/8 in." curve (corrected from original mis-labelling)
        @test isapprox(temperature_within_slab(30,  60,  "siliceous"), 260.3050219,   rtol=RTOL)
        @test isapprox(temperature_within_slab(240, 60,  "siliceous"), 933.7546343,   rtol=RTOL)
        # 70 mm = "2 3/4 in." curve (corrected); 80 mm = "3 1/8 in." curve (corrected)
        @test isapprox(temperature_within_slab(120, 70,  "siliceous"), 553.1092012,   rtol=RTOL)
        @test isapprox(temperature_within_slab(120, 80,  "siliceous"), 475.1685204,   rtol=RTOL)
        # 110 mm = siliceous-only "4 3/8 in." curve
        @test isapprox(temperature_within_slab(30,  110, "siliceous"), 162.0014605,   rtol=RTOL)
        @test isapprox(temperature_within_slab(240, 110, "siliceous"), 510.2769352,   rtol=RTOL)
        @test isapprox(temperature_within_slab(180, 150, "siliceous"), 306.8236715,   rtol=RTOL)
        @test isapprox(temperature_within_slab(240, 180, "siliceous"), 305.0682508,   rtol=RTOL)
    end

    # --- semi_lightweight ---
    @testset "semi_lightweight exact values" begin
        @test isapprox(temperature_within_slab(30,  5,   "semi_lightweight"), 1014.322164,  rtol=RTOL)
        @test isapprox(temperature_within_slab(60,  25,  "semi_lightweight"), 840.9073662,  rtol=RTOL)
        @test isapprox(temperature_within_slab(30,  50,  "semi_lightweight"), 249.3704753,  rtol=RTOL)
        @test isapprox(temperature_within_slab(120, 50,  "semi_lightweight"), 661.4165981,  rtol=RTOL)
        @test isapprox(temperature_within_slab(180, 70,  "semi_lightweight"), 603.142814,   rtol=RTOL)
        @test isapprox(temperature_within_slab(240, 100, "semi_lightweight"), 481.9331101,  rtol=RTOL)
        @test isapprox(temperature_within_slab(120, 150, "semi_lightweight"), 177.7891807,  rtol=RTOL)
        @test isapprox(temperature_within_slab(240, 180, "semi_lightweight"), 200.3208952,  rtol=RTOL)
    end
end


# =============================================================================
# 3. TIME INTERPOLATION
# Pick an intermediate time within a depth curve and check against manual
# linear interpolation of the two bounding knots.
# =============================================================================
@testset "3. Time interpolation" begin

    # carbonate, depth=25 mm, time=150 min  (between 120→1072.593472 and 180→1207.514571)
    let t_lo=120, T_lo=1072.593472, t_hi=180, T_hi=1207.514571, t=150
        α = (t - t_lo) / (t_hi - t_lo)
        expected = T_lo + α * (T_hi - T_lo)   # 1140.054022
        @test isapprox(temperature_within_slab(t, 25, "carbonate"), expected, rtol=RTOL)
    end

    # carbonate, depth=25 mm, time=52.5 min  (between 45→703.788367 and 60→827.2756436)
    let t_lo=45, T_lo=703.788367, t_hi=60, T_hi=827.2756436, t=52.5
        α = (t - t_lo) / (t_hi - t_lo)
        expected = T_lo + α * (T_hi - T_lo)   # 765.5320053
        @test isapprox(temperature_within_slab(t, 25, "carbonate"), expected, rtol=RTOL)
    end

    # carbonate, depth=90 mm, time=210 min  (between 180→492.887491 and 240→605.9995666)
    let t_lo=180, T_lo=492.887491, t_hi=240, T_hi=605.9995666, t=210
        α = (t - t_lo) / (t_hi - t_lo)
        expected = T_lo + α * (T_hi - T_lo)   # 549.4435288
        @test isapprox(temperature_within_slab(t, 90, "carbonate"), expected, rtol=RTOL)
    end

    # siliceous, depth=180 mm, time=67.5 min (between 60→162.0014605 and 90→195.3544546)
    let t_lo=60, T_lo=162.0014605, t_hi=90, T_hi=195.3544546, t=67.5
        α = (t - t_lo) / (t_hi - t_lo)
        expected = T_lo + α * (T_hi - T_lo)   # 170.3397090
        @test isapprox(temperature_within_slab(t, 180, "siliceous"), expected, rtol=RTOL)
    end

    # siliceous, depth=50 mm, time=105 min  (between 90→661.1729019 and 120→786.5099427)
    let t_lo=90, T_lo=661.1729019, t_hi=120, T_hi=786.5099427, t=105
        α = (t - t_lo) / (t_hi - t_lo)
        expected = T_lo + α * (T_hi - T_lo)   # 723.8414223
        @test isapprox(temperature_within_slab(t, 50, "siliceous"), expected, rtol=RTOL)
    end

    # semi_lightweight, depth=50 mm, time=105 min (between 90→526.4628462 and 120→661.4165981)
    let t_lo=90, T_lo=526.4628462, t_hi=120, T_hi=661.4165981, t=105
        α = (t - t_lo) / (t_hi - t_lo)
        expected = T_lo + α * (T_hi - T_lo)   # 593.9397222
        @test isapprox(temperature_within_slab(t, 50, "semi_lightweight"), expected, rtol=RTOL)
    end

    # semi_lightweight, depth=100 mm, time=210 min (between 180→380.4726906 and 240→481.9331101)
    let t_lo=180, T_lo=380.4726906, t_hi=240, T_hi=481.9331101, t=210
        α = (t - t_lo) / (t_hi - t_lo)
        expected = T_lo + α * (T_hi - T_lo)   # 431.2029004
        @test isapprox(temperature_within_slab(t, 100, "semi_lightweight"), expected, rtol=RTOL)
    end
end


# =============================================================================
# 4. DEPTH INTERPOLATION
# Pick an intermediate depth between two adjacent depth curves and verify
# the result equals a hand-computed linear interpolation.
# =============================================================================
@testset "4. Depth interpolation" begin

    # carbonate, depth=37.5 mm (between 30→438.5214091 and 40→345.7697923) at t=30
    # Note: carbonate has a 30 mm depth curve, so bounding depths are 30 & 40, not 25 & 40
    let d_lo=30.0, T_lo=438.5214091, d_hi=40.0, T_hi=345.7697923, d=37.5, t=30
        α = (d - d_lo) / (d_hi - d_lo)
        expected = T_lo + α * (T_hi - T_lo)   # 368.9576965
        @test isapprox(temperature_within_slab(t, d, "carbonate"), expected, rtol=RTOL)
    end

    # carbonate, depth=75 mm (between 70→204.9817219 and 80→180.5158087) at t=30
    let d_lo=70.0, T_lo=204.9817219, d_hi=80.0, T_hi=180.5158087, d=75, t=30
        α = (d - d_lo) / (d_hi - d_lo)
        expected = T_lo + α * (T_hi - T_lo)   # 192.7487653
        @test isapprox(temperature_within_slab(t, d, "carbonate"), expected, rtol=RTOL)
    end

    # carbonate, depth=112.5 mm (between 100→153.8257217 and 125→138.2565043) at t=30
    let d_lo=100.0, T_lo=153.8257217, d_hi=125.0, T_hi=138.2565043, d=112.5, t=30
        α = (d - d_lo) / (d_hi - d_lo)
        expected = T_lo + α * (T_hi - T_lo)   # 146.041113
        @test isapprox(temperature_within_slab(t, d, "carbonate"), expected, rtol=RTOL)
    end

    # siliceous, depth=52.5 mm (between 50→288.1108864 and 60→260.3050219) at t=30
    # α = (52.5-50)/(60-50) = 0.25
    let d_lo=50.0, T_lo=288.1108864, d_hi=60.0, T_hi=260.3050219, d=52.5, t=30
        α = (d - d_lo) / (d_hi - d_lo)
        expected = T_lo + α * (T_hi - T_lo)   # 281.1594203
        @test isapprox(temperature_within_slab(t, d, "siliceous"), expected, rtol=RTOL)
    end

    # siliceous, depth=65 mm (between 60→260.3050219 and 70→231.3405797) at t=30
    # 60mm="2 3/8 in.", 70mm="2 3/4 in." after correction; α=0.5
    let d_lo=60.0, T_lo=260.3050219, d_hi=70.0, T_hi=231.3405797, d=65, t=30
        α = (d - d_lo) / (d_hi - d_lo)
        expected = T_lo + α * (T_hi - T_lo)   # 245.8228008
        @test isapprox(temperature_within_slab(t, d, "siliceous"), expected, rtol=RTOL)
    end

    # siliceous, depth=75 mm (between 70→313.6698124 and 80→287.1629592) at t=60
    # 70mm="2 3/4 in." T=313.6698124, 80mm="3 1/8 in." T=287.1629592 at t=60; α=0.5
    let d_lo=70.0, T_lo=313.6698124, d_hi=80.0, T_hi=287.1629592, d=75, t=60
        α = (d - d_lo) / (d_hi - d_lo)
        expected = T_lo + α * (T_hi - T_lo)   # 300.4163858
        @test isapprox(temperature_within_slab(t, d, "siliceous"), expected, rtol=RTOL)
    end

    # siliceous, depth=105 mm (between 100→248.3681609 and 110→226.9520279) at t=60
    # Tests the siliceous-only 110 mm curve; α=0.5
    let d_lo=100.0, T_lo=248.3681609, d_hi=110.0, T_hi=226.9520279, d=105, t=60
        α = (d - d_lo) / (d_hi - d_lo)
        expected = T_lo + α * (T_hi - T_lo)   # 237.6600944
        @test isapprox(temperature_within_slab(t, d, "siliceous"), expected, rtol=RTOL)
    end

    # semi_lightweight, depth=65 mm (between 60→523.6338238 and 70→430.9372452) at t=120
    let d_lo=60.0, T_lo=523.6338238, d_hi=70.0, T_hi=430.9372452, d=65, t=120
        α = (d - d_lo) / (d_hi - d_lo)
        expected = T_lo + α * (T_hi - T_lo)   # 477.2855345
        @test isapprox(temperature_within_slab(t, d, "semi_lightweight"), expected, rtol=RTOL)
    end

    # semi_lightweight, depth=162.5 mm (between 150→215.4852123 and 180→173.9234811) at t=180
    let d_lo=150.0, T_lo=215.4852123, d_hi=180.0, T_hi=173.9234811, d=162.5, t=180
        α = (d - d_lo) / (d_hi - d_lo)
        expected = T_lo + α * (T_hi - T_lo)   # 198.1565259
        @test isapprox(temperature_within_slab(t, d, "semi_lightweight"), expected, rtol=RTOL)
    end
end


# =============================================================================
# 5. BOUNDARY VALUES
# Queries at exact min/max depth and min/max time should return CSV values.
# =============================================================================
@testset "5. Boundary values" begin

    # Min depth (5 mm), first and last time points
    @test isapprox(temperature_within_slab(30,  5, "carbonate"),       1000.133165,  rtol=RTOL)
    @test isapprox(temperature_within_slab(150, 5, "carbonate"),       1600.0,       rtol=RTOL)   # last point
    @test isapprox(temperature_within_slab(30,  5, "siliceous"),       1017.593529,  rtol=RTOL)
    @test isapprox(temperature_within_slab(100, 5, "siliceous"),       1598.988878,  rtol=RTOL)   # last point
    @test isapprox(temperature_within_slab(30,  5, "semi_lightweight"),1014.322164,  rtol=RTOL)
    @test isapprox(temperature_within_slab(105, 5, "semi_lightweight"),1600.915832,  rtol=RTOL)   # last point

    # Max depth (180 mm), first and last time points
    @test isapprox(temperature_within_slab(30,  180, "carbonate"),     116.0140522,  rtol=RTOL)
    @test isapprox(temperature_within_slab(240, 180, "carbonate"),     294.8376353,  rtol=RTOL)
    @test isapprox(temperature_within_slab(30,  180, "siliceous"),     115.4828109,  rtol=RTOL)
    @test isapprox(temperature_within_slab(240, 180, "siliceous"),     305.0682508,  rtol=RTOL)
    @test isapprox(temperature_within_slab(30,  180, "semi_lightweight"),89.67267189, rtol=RTOL)
    @test isapprox(temperature_within_slab(240, 180, "semi_lightweight"),200.3208952, rtol=RTOL)

    # Min time (30 min) and max time (240 min) at mid-range depth
    @test isapprox(temperature_within_slab(30,  80, "carbonate"),      180.5158087,  rtol=RTOL)
    @test isapprox(temperature_within_slab(240, 80, "carbonate"),      689.4096529,  rtol=RTOL)

    # Shallow curves that cap before 240 min
    # siliceous 10mm: last time = 130 min
    @test isapprox(temperature_within_slab(130, 10, "siliceous"),      1600.252781,  rtol=RTOL)
    # semi_lightweight 10mm: last time = 145 min
    @test isapprox(temperature_within_slab(145, 10, "semi_lightweight"),1600.827957, rtol=RTOL)
    # semi_lightweight 15mm: last time = 215 min
    @test isapprox(temperature_within_slab(215, 15, "semi_lightweight"),1600.838078, rtol=RTOL)
end


# =============================================================================
# 6. OUT-OF-RANGE ERRORS
# All invalid inputs must throw ArgumentError — no extrapolation.
# =============================================================================
@testset "6. Out-of-range errors" begin

    # Bad concrete_type
    @test_throws ArgumentError temperature_within_slab(120, 40, "lightweight")
    @test_throws ArgumentError temperature_within_slab(120, 40, "")
    @test_throws ArgumentError temperature_within_slab(120, 40, "Carbonate")   # case-sensitive

    # depth below minimum (5 mm)
    @test_throws ArgumentError temperature_within_slab(30, 4.9,  "carbonate")
    @test_throws ArgumentError temperature_within_slab(30, 0,    "siliceous")
    @test_throws ArgumentError temperature_within_slab(30, -1,   "semi_lightweight")

    # depth above maximum (180 mm)
    @test_throws ArgumentError temperature_within_slab(30, 180.1, "carbonate")
    @test_throws ArgumentError temperature_within_slab(30, 200,   "siliceous")

    # time below minimum at various depths (first time knot is always 30 min)
    @test_throws ArgumentError temperature_within_slab(0,   25, "carbonate")
    @test_throws ArgumentError temperature_within_slab(1,   80, "siliceous")
    @test_throws ArgumentError temperature_within_slab(29.9, 50, "semi_lightweight")

    # time above maximum at max-depth curves (240 min)
    @test_throws ArgumentError temperature_within_slab(240.1, 180, "carbonate")
    @test_throws ArgumentError temperature_within_slab(241,   180, "siliceous")
    @test_throws ArgumentError temperature_within_slab(999,   180, "semi_lightweight")

    # time above maximum at shallow curves (cap < 240 min)
    # siliceous depth=5mm: max time = 100 min
    @test_throws ArgumentError temperature_within_slab(101, 5, "siliceous")
    @test_throws ArgumentError temperature_within_slab(200, 5, "siliceous")
    # carbonate depth=5mm: max time = 150 min
    @test_throws ArgumentError temperature_within_slab(151, 5, "carbonate")
    # semi_lightweight depth=5mm: max time = 105 min
    @test_throws ArgumentError temperature_within_slab(106, 5, "semi_lightweight")
    # siliceous depth=10mm: max time = 130 min
    @test_throws ArgumentError temperature_within_slab(131, 10, "siliceous")
    # semi_lightweight depth=15mm: max time = 215 min
    @test_throws ArgumentError temperature_within_slab(216, 15, "semi_lightweight")
end


# =============================================================================
# 7. FIRE RESISTANCE TABLE — pass/fail boundary cases
# Each check uses a slab value exactly at the ACI table threshold (PASS),
# 1 unit below (FAIL thickness or cover), and both below (FAIL both).
# =============================================================================
@testset "7. Fire resistance table" begin

    # Table 4.2 minimums for unrestrained (Table 4.3.1.1):
    #   carbonate:        60→(80,20), 90→(100,20), 120→(115,20), 180→(145,30), 240→(170,30)
    #   siliceous:        60→(90,20), 90→(110,20), 120→(125,25), 180→(155,30), 240→(175,40)
    #   semi_lightweight: 60→(70,20), 90→(85,20),  120→(95,20),  180→(115,30), 240→(135,30)
    #   lightweight:      60→(65,20), 90→(80,20),  120→(90,20),  180→(110,30), 240→(130,30)

    # ---- carbonate, unrestrained ----
    @testset "carbonate unrestrained" begin
        res = fire_resistance_rating(:carbonate, false, 170.0, 30.0; ratings=[240])
        @test res.ratings[1].overall_pass     # thickness=170≥170, cover=30≥30 → PASS

        res = fire_resistance_rating(:carbonate, false, 169.9, 30.0; ratings=[240])
        @test !res.ratings[1].overall_pass
        @test !res.ratings[1].thickness_pass
        @test  res.ratings[1].cover_pass

        res = fire_resistance_rating(:carbonate, false, 170.0, 29.9; ratings=[240])
        @test !res.ratings[1].overall_pass
        @test  res.ratings[1].thickness_pass
        @test !res.ratings[1].cover_pass

        res = fire_resistance_rating(:carbonate, false, 169.9, 29.9; ratings=[240])
        @test !res.ratings[1].overall_pass
        @test !res.ratings[1].thickness_pass
        @test !res.ratings[1].cover_pass

        # 2-hour check (req_thickness=115, req_cover=20)
        res = fire_resistance_rating(:carbonate, false, 115.0, 20.0; ratings=[120])
        @test res.ratings[1].overall_pass

        res = fire_resistance_rating(:carbonate, false, 114.9, 20.0; ratings=[120])
        @test !res.ratings[1].thickness_pass

        res = fire_resistance_rating(:carbonate, false, 115.0, 19.9; ratings=[120])
        @test !res.ratings[1].cover_pass
    end

    # ---- siliceous, unrestrained ----
    @testset "siliceous unrestrained" begin
        # 1-hour: 90mm / 20mm
        res = fire_resistance_rating(:siliceous, false, 90.0, 20.0; ratings=[60])
        @test res.ratings[1].overall_pass

        res = fire_resistance_rating(:siliceous, false, 89.9, 20.0; ratings=[60])
        @test !res.ratings[1].thickness_pass

        # 2-hour: 125mm / 25mm
        res = fire_resistance_rating(:siliceous, false, 125.0, 25.0; ratings=[120])
        @test res.ratings[1].overall_pass

        res = fire_resistance_rating(:siliceous, false, 125.0, 24.9; ratings=[120])
        @test !res.ratings[1].cover_pass

        # 4-hour: 175mm / 40mm
        res = fire_resistance_rating(:siliceous, false, 175.0, 40.0; ratings=[240])
        @test res.ratings[1].overall_pass

        res = fire_resistance_rating(:siliceous, false, 174.9, 39.9; ratings=[240])
        @test !res.ratings[1].overall_pass
    end

    # ---- semi_lightweight, restrained ----
    # Restrained cover = 20 mm for ALL ratings and aggregate types
    @testset "semi_lightweight restrained" begin
        # 3-hour: thickness=115mm, cover=20mm
        res = fire_resistance_rating(:semi_lightweight, true, 115.0, 20.0; ratings=[180])
        @test res.ratings[1].overall_pass

        res = fire_resistance_rating(:semi_lightweight, true, 114.9, 20.0; ratings=[180])
        @test !res.ratings[1].thickness_pass

        res = fire_resistance_rating(:semi_lightweight, true, 115.0, 19.9; ratings=[180])
        @test !res.ratings[1].cover_pass

        # 4-hour restrained: thickness=135mm, cover=20mm
        res = fire_resistance_rating(:semi_lightweight, true, 135.0, 20.0; ratings=[240])
        @test res.ratings[1].overall_pass

        res = fire_resistance_rating(:semi_lightweight, true, 135.0, 19.9; ratings=[240])
        @test !res.ratings[1].cover_pass
    end

    # ---- lightweight (table only, no temperature interpolation) ----
    @testset "lightweight table" begin
        # 1-hour: 65mm / 20mm
        res = fire_resistance_rating(:lightweight, false, 65.0, 20.0; ratings=[60])
        @test res.ratings[1].overall_pass

        res = fire_resistance_rating(:lightweight, false, 64.9, 20.0; ratings=[60])
        @test !res.ratings[1].thickness_pass

        # 3-hour unrestrained: 110mm / 30mm
        res = fire_resistance_rating(:lightweight, false, 110.0, 30.0; ratings=[180])
        @test res.ratings[1].overall_pass

        res = fire_resistance_rating(:lightweight, false, 110.0, 29.9; ratings=[180])
        @test !res.ratings[1].cover_pass

        # 4-hour restrained: 130mm / 20mm
        res = fire_resistance_rating(:lightweight, true, 130.0, 20.0; ratings=[240])
        @test res.ratings[1].overall_pass
    end

    # ---- All five ratings at once, check array length and types ----
    @testset "all-ratings call" begin
        res = fire_resistance_rating(:carbonate, false, 175.0, 30.0)
        @test length(res.ratings) == 5
        @test all(r -> r isa ACI216.FireResistanceRatingResult, res.ratings)
        # 175 mm slab, 30 mm cover should pass 1–3 hr for carbonate:
        # 60→(80,20)✓, 90→(100,20)✓, 120→(115,20)✓, 180→(145,30)✓, 240→(170,30)✓
        @test all(r -> r.overall_pass, res.ratings)
    end

    # ---- Marginal slab: exactly fails 4-hr but passes 3-hr ----
    @testset "pass-3hr fail-4hr boundary" begin
        # carbonate unrestrained: 3-hr needs (145,30), 4-hr needs (170,30)
        # slab = 169mm, cover = 30mm → passes 3-hr, fails 4-hr
        res = fire_resistance_rating(:carbonate, false, 169.0, 30.0; ratings=[180, 240])
        @test  res.ratings[1].overall_pass   # 180 min → PASS
        @test !res.ratings[2].overall_pass   # 240 min → FAIL thickness
    end
end


# =============================================================================
# 8. FIRE RESISTANCE — INVALID INPUTS
# =============================================================================
@testset "8. Fire resistance invalid inputs" begin

    # Unknown aggregate type
    @test_throws ArgumentError fire_resistance_rating(:gravel,   false, 150, 25)
    @test_throws ArgumentError fire_resistance_rating(:concrete, false, 150, 25)

    # Invalid (unsupported) duration
    @test_throws ArgumentError fire_resistance_rating(:carbonate, false, 150, 25; ratings=[30])
    @test_throws ArgumentError fire_resistance_rating(:carbonate, false, 150, 25; ratings=[300])
    @test_throws ArgumentError fire_resistance_rating(:carbonate, false, 150, 25; ratings=[120, 300])

end



# =============================================================================
# 9. STRENGTH DATA INTEGRITY
# =============================================================================
@testset "9. Strength data integrity" begin

    # --- steel: 86 rows, strictly sorted, fractions in [0,1] ---
    @testset "steel — row count, ordering, bounds" begin
        temps = ACI216._STEEL_TEMPS[]
        fracs = ACI216._STEEL_FRACS[]
        @test length(temps) == 86
        @test length(fracs) == 86
        @test issorted(temps; lt=<)
        @test all(0.0 .<= fracs .<= 1.0)
        @test fracs[1]   > 0.95   # near-ambient ≈ 100 %
        @test fracs[end] < 0.25   # catastrophic loss at ~1400 °F
    end

    # --- concrete: every declared condition is present, sorted, bounded ---
    for ct in ("carbonate", "siliceous", "semi_lightweight")
        @testset "$ct — conditions valid" begin
            for cond in ACI216._VALID_CONDITIONS[ct]
                cmap = ACI216._CONCRETE_STRENGTH[ct]
                @test haskey(cmap, cond)
                temps, fracs = cmap[cond]
                @test length(temps) >= 30
                @test length(temps) == length(fracs)
                @test issorted(temps; lt=<)
                @test all(0.0 .<= fracs .<= 1.0)
                @test fracs[1] > 0.85   # near-ambient should be close to 1
            end
        end
    end

    # --- known condition key sets ---
    @testset "condition key sets" begin
        @test sort(collect(keys(ACI216._CONCRETE_STRENGTH["carbonate"]))) ==
              sort(ACI216._VALID_CONDITIONS["carbonate"])
        @test sort(collect(keys(ACI216._CONCRETE_STRENGTH["siliceous"]))) ==
              sort(ACI216._VALID_CONDITIONS["siliceous"])
        @test sort(collect(keys(ACI216._CONCRETE_STRENGTH["semi_lightweight"]))) ==
              sort(ACI216._VALID_CONDITIONS["semi_lightweight"])
    end

    # --- known total row counts from conversion script ---
    @testset "row counts" begin
        total(ct) = sum(length(v[1]) for v in values(ACI216._CONCRETE_STRENGTH[ct]))
        @test total("carbonate")        == 224
        @test total("siliceous")        == 166
        @test total("semi_lightweight") == 269
    end
end


# =============================================================================
# 10. EXACT CSV GRID SPOT CHECKS — strength functions
# Interpolating at a known data-grid temperature must return the stored value.
# =============================================================================
@testset "10. Exact CSV grid spot checks (strength)" begin

    # --- steel ---
    @testset "steel exact values" begin
        @test isapprox(steel_strength_reduction(85.81390257),  0.9892625228999999, rtol=RTOL)
        @test isapprox(steel_strength_reduction(641.4665992),  0.8020519532,       rtol=RTOL)
        @test isapprox(steel_strength_reduction(1200.700935),  0.36193640289999995, rtol=RTOL)
        @test isapprox(steel_strength_reduction(1399.244524),  0.1588903653,        rtol=RTOL)
    end

    # --- carbonate ---
    @testset "carbonate exact values" begin
        @test isapprox(concrete_strength_reduction(107.73809681493125,  "carbonate", "unstressed"),          0.9939191663703595, rtol=RTOL)
        @test isapprox(concrete_strength_reduction(627.0685108166541,   "carbonate", "unstressed"),          0.8711832518773952, rtol=RTOL)
        @test isapprox(concrete_strength_reduction(1277.2569112774122,  "carbonate", "stressed"),            0.9220714502710164, rtol=RTOL)
        @test isapprox(concrete_strength_reduction(788.6029857368567,   "carbonate", "unstressed_residual"), 0.509761388286334,  rtol=RTOL)
    end

    # --- siliceous ---
    @testset "siliceous exact values" begin
        @test isapprox(concrete_strength_reduction(172.64729552321995, "siliceous", "unstressed"),          0.9988285448509544, rtol=RTOL)
        @test isapprox(concrete_strength_reduction(679.7240682786205,  "siliceous", "stressed"),            1.0,                rtol=RTOL)  # capped from 100.038 %
        @test isapprox(concrete_strength_reduction(700.3858150769152,  "siliceous", "stressed"),            0.9970738198317446, rtol=RTOL)
        @test isapprox(concrete_strength_reduction(86.25726504878082,  "siliceous", "unstressed_residual"), 0.9976551673354015, rtol=RTOL)
    end

    # --- semi_lightweight ---
    @testset "semi_lightweight exact values" begin
        @test isapprox(concrete_strength_reduction(107.32986598303617, "semi_lightweight", "unstressed_sanded"),          0.9970590801295862, rtol=RTOL)
        @test isapprox(concrete_strength_reduction(174.81240747293802, "semi_lightweight", "unstressed_unsanded"),         0.9990812131674947, rtol=RTOL)
        @test isapprox(concrete_strength_reduction(262.91159057889615, "semi_lightweight", "stressed"),                   0.9983713733347895, rtol=RTOL)
        @test isapprox(concrete_strength_reduction(333.81981556415883, "semi_lightweight", "unstressed_residual_sanded"),  0.938949173433605,  rtol=RTOL)
    end
end


# =============================================================================
# 11. STRENGTH INTERPOLATION
# Midpoint between adjacent grid knots must equal the linear average.
# =============================================================================
@testset "11. Strength interpolation" begin

    # --- steel: midpoint between rows 35–36 ---
    # (641.4666, 0.80205) and (658.2146, 0.79899)
    let T1=641.4665992, f1=0.8020519532, T2=658.2145985, f2=0.7989930866999999
        midT     = (T1 + T2) / 2.0
        expected = (f1 + f2) / 2.0
        @test isapprox(steel_strength_reduction(midT), expected, rtol=RTOL)
    end

    # steel: α = 0.25 between rows 35–36
    let T1=641.4665992, f1=0.8020519532, T2=658.2145985, f2=0.7989930866999999
        T        = T1 + 0.25 * (T2 - T1)
        expected = f1 + 0.25 * (f2 - f1)
        @test isapprox(steel_strength_reduction(T), expected, rtol=RTOL)
    end

    # --- carbonate unstressed: midpoint between rows 1–2 ---
    # (107.738, 0.99392) and (130.130, 0.98844)
    let T1=107.73809681493125, f1=0.9939191663703595,
        T2=130.1295006404516,  f2=0.9884406136846485
        midT     = (T1 + T2) / 2.0
        expected = (f1 + f2) / 2.0
        @test isapprox(concrete_strength_reduction(midT, "carbonate", "unstressed"), expected, rtol=RTOL)
    end

    # carbonate unstressed_residual: midpoint between rows 1–2
    let T1=115.2896707647997, f1=0.9912756235966649,
        T2=136.0488470961714, f2=0.9811786150180944
        midT     = (T1 + T2) / 2.0
        expected = (f1 + f2) / 2.0
        @test isapprox(concrete_strength_reduction(midT, "carbonate", "unstressed_residual"), expected, rtol=RTOL)
    end

    # --- siliceous unstressed: midpoint between rows 1–2 ---
    # (172.647, 0.99883) and (193.307, 0.99779)
    let T1=172.64729552321995, f1=0.9988285448509544,
        T2=193.30698398640686, f2=0.9977866805016612
        midT     = (T1 + T2) / 2.0
        expected = (f1 + f2) / 2.0
        @test isapprox(concrete_strength_reduction(midT, "siliceous", "unstressed"), expected, rtol=RTOL)
    end

    # --- siliceous unstressed_residual: midpoint between rows 1–2 ---
    # (86.257, 0.99766) and (106.921, 0.99227)
    let T1=86.25726504878082, f1=0.9976551673354015,
        T2=106.9208998571184, f2=0.9922747897860783
        midT     = (T1 + T2) / 2.0
        expected = (f1 + f2) / 2.0
        @test isapprox(concrete_strength_reduction(midT, "siliceous", "unstressed_residual"), expected, rtol=RTOL)
    end

    # --- semi_lightweight stressed: midpoint between rows 1–2 ---
    # (262.912, 0.99837) and (283.531, 0.99839)
    let T1=262.91159057889615, f1=0.9983713733347895,
        T2=283.5307150611836,  f2=0.9983899507110915
        midT     = (T1 + T2) / 2.0
        expected = (f1 + f2) / 2.0
        @test isapprox(concrete_strength_reduction(midT, "semi_lightweight", "stressed"), expected, rtol=RTOL)
    end
end


# =============================================================================
# 12. STRENGTH CLAMPING BEHAVIOUR
# Queries below the minimum temperature return the first value;
# queries above the maximum return the last value.
# =============================================================================
@testset "12. Strength clamping" begin

    # --- steel ---
    let T_min = ACI216._STEEL_TEMPS[][1],
        T_max = ACI216._STEEL_TEMPS[][end],
        f_min = ACI216._STEEL_FRACS[][1],
        f_max = ACI216._STEEL_FRACS[][end]

        @test isapprox(steel_strength_reduction(0.0),        f_min, rtol=RTOL)   # well below
        @test isapprox(steel_strength_reduction(T_min - 1),  f_min, rtol=RTOL)   # just below
        @test isapprox(steel_strength_reduction(T_min),      f_min, rtol=RTOL)   # at exact lower bound
        @test isapprox(steel_strength_reduction(T_max),      f_max, rtol=RTOL)   # at exact upper bound
        @test isapprox(steel_strength_reduction(T_max + 1),  f_max, rtol=RTOL)   # just above
        @test isapprox(steel_strength_reduction(9999.0),     f_max, rtol=RTOL)   # well above
    end

    # --- concrete: clamp below min temperature ---
    for (ct, cond) in [("carbonate",        "unstressed"),
                       ("siliceous",         "unstressed_residual"),
                       ("semi_lightweight",  "stressed")]
        temps, fracs = ACI216._CONCRETE_STRENGTH[ct][cond]
        @testset "$ct / $cond — clamp below" begin
            @test isapprox(concrete_strength_reduction(temps[1] - 100.0, ct, cond), fracs[1], rtol=RTOL)
            @test isapprox(concrete_strength_reduction(temps[1],          ct, cond), fracs[1], rtol=RTOL)
        end
    end

    # --- concrete: clamp above max temperature ---
    for (ct, cond) in [("carbonate",        "stressed"),
                       ("siliceous",         "unstressed"),
                       ("semi_lightweight",  "unstressed_residual_sanded")]
        temps, fracs = ACI216._CONCRETE_STRENGTH[ct][cond]
        @testset "$ct / $cond — clamp above" begin
            @test isapprox(concrete_strength_reduction(temps[end] + 100.0, ct, cond), fracs[end], rtol=RTOL)
            @test isapprox(concrete_strength_reduction(temps[end],          ct, cond), fracs[end], rtol=RTOL)
            @test isapprox(concrete_strength_reduction(9999.0,              ct, cond), fracs[end], rtol=RTOL)
        end
    end
end


# =============================================================================
# 13. STRENGTH INVALID INPUTS
# =============================================================================
@testset "13. Strength invalid inputs" begin

    # Unknown aggregate type
    @test_throws ArgumentError concrete_strength_reduction(500.0, "lightweight",   "unstressed")
    @test_throws ArgumentError concrete_strength_reduction(500.0, "Carbonate",     "unstressed")   # case-sensitive
    @test_throws ArgumentError concrete_strength_reduction(500.0, "gravel",        "unstressed")
    @test_throws ArgumentError concrete_strength_reduction(500.0, "",              "unstressed")

    # Unknown condition for a valid aggregate type
    @test_throws ArgumentError concrete_strength_reduction(500.0, "carbonate",        "stressed_residual")
    @test_throws ArgumentError concrete_strength_reduction(500.0, "carbonate",        "")
    @test_throws ArgumentError concrete_strength_reduction(500.0, "siliceous",        "unstressed_sanded")    # semi_lw only
    @test_throws ArgumentError concrete_strength_reduction(500.0, "semi_lightweight", "unstressed")           # not defined for semi_lw
    @test_throws ArgumentError concrete_strength_reduction(500.0, "semi_lightweight", "unstressed_residual")  # wrong spelling
end



# =============================================================================
# 14. UNIT CONVERSION
# =============================================================================
@testset "14. Unit conversion" begin

    # --- F_to_C / C_to_F identity checks ---
    @testset "F_to_C / C_to_F" begin
        @test isapprox(F_to_C(32.0),   0.0,   atol=1e-10)
        @test isapprox(F_to_C(212.0),  100.0, atol=1e-10)
        @test isapprox(F_to_C(68.0),   20.0,  atol=1e-10)
        @test isapprox(C_to_F(0.0),    32.0,  atol=1e-10)
        @test isapprox(C_to_F(100.0),  212.0, atol=1e-10)
        @test isapprox(C_to_F(20.0),   68.0,  atol=1e-10)
        # round-trip
        for T_F in [0.0, 70.0, 500.0, 1000.0, 1399.0]
            @test isapprox(C_to_F(F_to_C(T_F)), T_F, atol=1e-9)
        end
    end

    # --- temperature_within_slab: Celsius output ---
    @testset "temperature_within_slab Celsius output" begin
        for (t, d, ct) in [(30, 25, "carbonate"), (120, 50, "siliceous"),
                           (180, 80, "semi_lightweight")]
            T_F = temperature_within_slab(t, d, ct)
            T_C = temperature_within_slab(t, d, ct; temperature_unit=:celsius)
            @test isapprox(T_C, F_to_C(T_F), rtol=RTOL)
            @test T_C < T_F   # always true above 0 °F
        end
    end

    # --- concrete_strength_reduction: Celsius input ---
    @testset "concrete_strength_reduction Celsius input" begin
        for (T_F, ct, cond) in [(800.0, "carbonate", "unstressed"),
                                (1200.0, "siliceous", "stressed"),
                                (600.0, "semi_lightweight", "unstressed_sanded")]
            f_F = concrete_strength_reduction(T_F, ct, cond)
            f_C = concrete_strength_reduction(F_to_C(T_F), ct, cond;
                                              temperature_unit=:celsius)
            @test isapprox(f_F, f_C, rtol=RTOL)
        end
    end

    # --- steel_strength_reduction: Celsius input ---
    @testset "steel_strength_reduction Celsius input" begin
        for T_F in [200.0, 700.0, 1100.0, 1399.0]
            f_F = steel_strength_reduction(T_F)
            f_C = steel_strength_reduction(F_to_C(T_F); temperature_unit=:celsius)
            @test isapprox(f_F, f_C, rtol=RTOL)
        end
    end

    # --- invalid temperature_unit ---
    @testset "invalid temperature_unit" begin
        @test_throws ArgumentError temperature_within_slab(120, 40, "carbonate";
                                                           temperature_unit=:kelvin)
        @test_throws ArgumentError concrete_strength_reduction(500.0, "carbonate",
                                                               "unstressed";
                                                               temperature_unit=:K)
        @test_throws ArgumentError steel_strength_reduction(500.0; temperature_unit=:C)
    end
end


# =============================================================================
# 15. REBAR CONDITION
# =============================================================================
@testset "15. Rebar condition" begin

    # --- return type and field consistency ---
    @testset "carbonate, 25 mm cover, 120 min" begin
        rc = rebar_condition(120, 25.0, "carbonate")
        @test rc isa NamedTuple
        @test haskey(rc, :temperature_F)
        @test haskey(rc, :temperature_C)
        @test haskey(rc, :steel_fraction)
        @test haskey(rc, :concrete_fraction)

        T_F_expected = temperature_within_slab(120, 25.0, "carbonate")
        @test isapprox(rc.temperature_F, T_F_expected, rtol=RTOL)
        @test isapprox(rc.temperature_C, F_to_C(T_F_expected), rtol=RTOL)
        @test isapprox(rc.steel_fraction, steel_strength_reduction(T_F_expected), rtol=RTOL)
        @test isapprox(rc.concrete_fraction,
                       concrete_strength_reduction(T_F_expected, "carbonate", "unstressed"),
                       rtol=RTOL)
    end

    # --- default concrete_condition for semi_lightweight is "unstressed_sanded" ---
    @testset "semi_lightweight default condition" begin
        rc = rebar_condition(120, 40.0, "semi_lightweight")
        T_F = temperature_within_slab(120, 40.0, "semi_lightweight")
        @test isapprox(rc.concrete_fraction,
                       concrete_strength_reduction(T_F, "semi_lightweight",
                                                   "unstressed_sanded"),
                       rtol=RTOL)
    end

    # --- custom concrete_condition is forwarded correctly ---
    @testset "custom concrete_condition" begin
        rc_u = rebar_condition(120, 25.0, "siliceous";
                               concrete_condition="unstressed")
        rc_s = rebar_condition(120, 25.0, "siliceous";
                               concrete_condition="stressed")
        @test rc_u.temperature_F ≈ rc_s.temperature_F   # same temperature
        @test rc_u.concrete_fraction != rc_s.concrete_fraction  # different fractions
        T_F = rc_u.temperature_F
        @test isapprox(rc_s.concrete_fraction,
                       concrete_strength_reduction(T_F, "siliceous", "stressed"),
                       rtol=RTOL)
    end

    # --- fractions are bounded ---
    @testset "fractions in [0, 1]" begin
        for (ct, cov) in [("carbonate", 20.0), ("siliceous", 30.0),
                          ("semi_lightweight", 25.0)]
            rc = rebar_condition(240, cov, ct)
            @test 0.0 <= rc.steel_fraction    <= 1.0
            @test 0.0 <= rc.concrete_fraction <= 1.0
        end
    end

    # --- errors propagate from underlying functions ---
    @testset "error propagation" begin
        @test_throws ArgumentError rebar_condition(120, 25.0, "lightweight")
        @test_throws ArgumentError rebar_condition(120, 25.0, "carbonate";
                                                   concrete_condition="stressed_residual")
        @test_throws ArgumentError rebar_condition(120, 250.0, "carbonate")   # depth OOB
    end
end


# =============================================================================
# 16. MAXIMUM FIRE RATING
# =============================================================================
@testset "16. Maximum fire rating" begin

    # Passes all five standard ratings
    @testset "passes all ratings" begin
        m = maximum_fire_rating(:carbonate, false, 200.0, 40.0)
        @test m isa Int
        @test m == 240
    end

    # :carbonate, unrestrained, thickness=100 mm, cover=20 mm
    # Table 4.2: 100≥80(60✓) 100≥100(90✓) 100<115(120✗)
    # Table 4.3.1.1 unrestrained: 20≥20(60✓) 20≥20(90✓)  → max = 90
    @testset "passes 60 and 90 min" begin
        m = maximum_fire_rating(:carbonate, false, 100.0, 20.0)
        @test m == 90
    end

    # :siliceous, unrestrained, thickness=95 mm, cover=20 mm
    # Table 4.2: 95≥90(60✓) 95<110(90✗)  → max = 60
    @testset "passes 60 min only" begin
        m = maximum_fire_rating(:siliceous, false, 95.0, 20.0)
        @test m == 60
    end

    # Slab too thin and cover too small — fails everything
    @testset "fails all → nothing" begin
        m = maximum_fire_rating(:siliceous, false, 50.0, 10.0)
        @test isnothing(m)
    end

    # Cover limits to 120 min: :carbonate, unrestrained, cover=29 mm
    # Unrestrained cover: 29≥20(60✓) 29≥20(90✓) 29≥20(120✓) 29<30(180✗) → max = 120
    # Thickness 200 passes all.
    @testset "cover limits to 120 min" begin
        m = maximum_fire_rating(:carbonate, false, 200.0, 29.0)
        @test m == 120
    end

    # Consistent with fire_resistance_rating manual filter
    @testset "consistent with fire_resistance_rating" begin
        for (at, t, cc) in [(:siliceous, 175.0, 40.0), (:carbonate, 90.0, 18.0)]
            res       = fire_resistance_rating(at, false, t, cc)
            pass_durs = [r.duration_min for r in res.ratings if r.overall_pass]
            expected  = isempty(pass_durs) ? nothing : maximum(pass_durs)
            @test maximum_fire_rating(at, false, t, cc) == expected
        end
    end

    # Custom ratings subset
    @testset "custom ratings subset" begin
        # thickness 120 ≥ 80(60✓) ≥ 115(120✓); cover 25 ≥ 20(60✓) ≥ 20(120✓) → 120
        m = maximum_fire_rating(:carbonate, false, 120.0, 25.0; ratings=[60, 120])
        @test m == 120
    end

    # Restrained vs unrestrained: restrained cover is 20 mm for all durations
    # :siliceous, thickness=200, cover=35
    # Unrestrained: 35≥20(60✓) 35≥20(90✓) 35≥25(120✓) 35≥30(180✓) 35<40(240✗) → 180
    # Restrained:   20 mm for all → all pass → 240
    @testset "restrained relaxes cover at 240 min" begin
        m_unrest = maximum_fire_rating(:siliceous, false, 200.0, 35.0)
        m_rest   = maximum_fire_rating(:siliceous, true,  200.0, 35.0)
        @test m_unrest == 180
        @test m_rest   == 240
    end

    # Invalid aggregate_type propagates
    @testset "invalid aggregate_type propagates" begin
        @test_throws ArgumentError maximum_fire_rating(:stone, false, 150.0, 25.0)
    end
end


# =============================================================================
# 17. CRITICAL TEMPERATURE
# =============================================================================
@testset "17. Critical temperature" begin

    # --- invalid threshold ---
    @testset "invalid threshold" begin
        @test_throws ArgumentError steel_critical_temperature(-0.1)
        @test_throws ArgumentError steel_critical_temperature(1.1)
        @test_throws ArgumentError concrete_critical_temperature(-0.1, "carbonate", "unstressed")
        @test_throws ArgumentError concrete_critical_temperature(1.1,  "carbonate", "unstressed")
    end

    # --- invalid aggregate / condition ---
    @testset "invalid aggregate or condition" begin
        @test_throws ArgumentError concrete_critical_temperature(0.5, "lightweight",   "unstressed")
        @test_throws ArgumentError concrete_critical_temperature(0.5, "carbonate",     "stressed_residual")
        @test_throws ArgumentError concrete_critical_temperature(0.5, "semi_lightweight", "unstressed")
    end

    # --- steel round-trip: plugging result back into steel_strength_reduction → threshold ---
    @testset "steel round-trip" begin
        for thresh in [0.9, 0.8, 0.6, 0.4]
            T = steel_critical_temperature(thresh)
            @test isfinite(T)
            @test T > 0.0
            @test isapprox(steel_strength_reduction(T), thresh, atol=1e-9)
        end
    end

    # --- concrete round-trip ---
    @testset "concrete round-trip" begin
        for (thresh, ct, cond) in [(0.8, "carbonate",       "unstressed"),
                                   (0.5, "siliceous",        "stressed"),
                                   (0.7, "semi_lightweight", "unstressed_sanded")]
            T = concrete_critical_temperature(thresh, ct, cond)
            @test isfinite(T)
            @test isapprox(concrete_strength_reduction(T, ct, cond), thresh, atol=1e-9)
        end
    end

    # --- monotonicity: higher threshold → lower critical temperature ---
    @testset "monotonicity" begin
        T_80 = steel_critical_temperature(0.8)
        T_60 = steel_critical_temperature(0.6)
        T_40 = steel_critical_temperature(0.4)
        @test T_80 < T_60
        @test T_60 < T_40
    end

    # --- returns Inf when fraction never reaches threshold in data range ---
    @testset "returns Inf for threshold below data minimum" begin
        f_end_steel = ACI216._STEEL_FRACS[][end]
        if f_end_steel > 0.0
            @test isinf(steel_critical_temperature(f_end_steel * 0.5))
        end
        # Same check for concrete
        temps_c, fracs_c = ACI216._CONCRETE_STRENGTH["carbonate"]["unstressed"]
        if fracs_c[end] > 0.0
            @test isinf(concrete_critical_temperature(fracs_c[end] * 0.5,
                                                      "carbonate", "unstressed"))
        end
    end

    # --- celsius unit ---
    @testset "celsius unit" begin
        T_F = steel_critical_temperature(0.7)
        T_C = steel_critical_temperature(0.7; temperature_unit=:celsius)
        @test isapprox(T_C, F_to_C(T_F), rtol=RTOL)

        T_F2 = concrete_critical_temperature(0.6, "carbonate", "unstressed")
        T_C2 = concrete_critical_temperature(0.6, "carbonate", "unstressed";
                                             temperature_unit=:celsius)
        @test isapprox(T_C2, F_to_C(T_F2), rtol=RTOL)
    end

    # --- invalid temperature_unit propagates ---
    @testset "invalid temperature_unit" begin
        @test_throws ArgumentError steel_critical_temperature(0.5; temperature_unit=:kelvin)
        @test_throws ArgumentError concrete_critical_temperature(0.5, "carbonate",
                                                                 "unstressed";
                                                                 temperature_unit=:K)
    end
end


# =============================================================================
# 18. PRINT STRENGTH SUMMARY
# =============================================================================
@testset "18. Print strength summary" begin

    # --- runs without error and produces expected header text ---
    @testset "default temperatures, carbonate/unstressed" begin
        buf = IOBuffer()
        print_strength_summary("carbonate", "unstressed"; io=buf)
        out = String(take!(buf))
        @test occursin("MATERIAL STRENGTH SUMMARY", out)
        @test occursin("carbonate", out)
        @test occursin("unstressed", out)
        @test occursin("Concrete f'c", out)
        @test occursin("Steel fy", out)
    end

    # --- celsius unit changes default temperatures but still runs ---
    @testset "celsius unit runs cleanly" begin
        buf = IOBuffer()
        print_strength_summary("siliceous", "stressed"; temperature_unit=:celsius, io=buf)
        out = String(take!(buf))
        @test occursin("MATERIAL STRENGTH SUMMARY", out)
        @test occursin("siliceous", out)
        @test occursin("stressed", out)
    end

    # --- custom temperature vector produces correct number of data rows ---
    @testset "custom temperatures row count" begin
        temps = [500.0, 800.0, 1100.0]
        buf   = IOBuffer()
        print_strength_summary("semi_lightweight", "unstressed_sanded";
                               temperatures=temps, io=buf)
        out   = String(take!(buf))
        # Each of the 3 temps should produce a line with the value
        @test occursin("500", out)
        @test occursin("800", out)
        @test occursin("1100", out)
    end

    # --- invalid aggregate_type throws ---
    @testset "invalid inputs throw" begin
        @test_throws ArgumentError print_strength_summary("lightweight", "unstressed")
        @test_throws ArgumentError print_strength_summary("carbonate", "unstressed_sanded")
        @test_throws ArgumentError print_strength_summary("carbonate", "unstressed";
                                                          temperature_unit=:kelvin)
    end

    # --- all aggregate/condition combos run without error ---
    @testset "all combos run" begin
        buf = IOBuffer()
        for (ct, cond) in [("carbonate",       "unstressed"),
                            ("carbonate",       "stressed"),
                            ("siliceous",        "unstressed_residual"),
                            ("semi_lightweight", "unstressed_sanded"),
                            ("semi_lightweight", "stressed")]
            print_strength_summary(ct, cond; io=buf)
        end
        @test length(String(take!(buf))) > 0
    end
end


# =============================================================================
# 19. TEMPERATURE PROFILE
# =============================================================================
@testset "19. Temperature profile" begin

    # --- single depth matches temperature_within_slab ---
    @testset "single depth matches scalar call" begin
        for (t, d, ct) in [(60, 25.0, "carbonate"),
                           (120, 50.0, "siliceous"),
                           (180, 70.0, "semi_lightweight")]
            @test isapprox(
                temperature_profile(t, [d], ct)[1],
                temperature_within_slab(t, d, ct),
                rtol=RTOL,
            )
        end
    end

    # --- result length matches input length ---
    @testset "result length" begin
        depths = [10.0, 25.0, 40.0, 60.0, 80.0]
        T      = temperature_profile(120, depths, "carbonate")
        @test length(T) == length(depths)
        @test T isa Vector{Float64}
    end

    # --- each element matches individual call ---
    @testset "each element matches scalar call" begin
        depths = [15.0, 30.0, 55.0, 90.0]
        T_vec  = temperature_profile(90, depths, "siliceous")
        for (i, d) in enumerate(depths)
            @test isapprox(T_vec[i], temperature_within_slab(90, d, "siliceous"), rtol=RTOL)
        end
    end

    # --- temperatures decrease monotonically with depth ---
    @testset "monotone decrease with depth" begin
        depths = [10.0, 25.0, 50.0, 75.0, 100.0]
        T = temperature_profile(120, depths, "carbonate")
        for i in 2:length(T)
            @test T[i] < T[i-1]   # farther from fire → cooler
        end
    end

    # --- empty vector returns empty vector ---
    @testset "empty input" begin
        T = temperature_profile(60, Float64[], "carbonate")
        @test T isa Vector{Float64}
        @test isempty(T)
    end

    # --- celsius unit: each element matches F_to_C of Fahrenheit call ---
    @testset "celsius unit" begin
        depths = [20.0, 40.0, 80.0]
        T_F    = temperature_profile(120, depths, "carbonate")
        T_C    = temperature_profile(120, depths, "carbonate"; temperature_unit=:celsius)
        for i in eachindex(depths)
            @test isapprox(T_C[i], F_to_C(T_F[i]), rtol=RTOL)
        end
    end

    # --- out-of-range depth propagates ArgumentError ---
    @testset "error propagation" begin
        @test_throws ArgumentError temperature_profile(120, [5.0, 250.0], "carbonate")
        @test_throws ArgumentError temperature_profile(120, [10.0], "lightweight")
    end

    # --- all three concrete types work ---
    @testset "all concrete types" begin
        depths = [20.0, 50.0]
        for ct in ("carbonate", "siliceous", "semi_lightweight")
            T = temperature_profile(120, depths, ct)
            @test length(T) == 2
            @test all(isfinite, T)
        end
    end
end


println("\n", "="^70)
println(" All test sets completed.")
println("="^70, "\n")
