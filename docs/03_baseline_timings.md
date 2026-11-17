# Baseline Timings — Phase 2 Benchmark

**Machine:** MacBook (Apple Silicon, macOS)  
**PostgreSQL:** 18.7 (Postgres.app)  
**Database:** `gmaps_project` · schema `gmaps`  
**Method:** `benchmarks/run_benchmark.sh gmaps_project baseline 3`  
**Mode:** `EXPLAIN (ANALYZE, BUFFERS)`, no indexes beyond schema defaults, 3 cold-ish runs each  
**Write queries** executed inside `BEGIN … ROLLBACK` — data unchanged.

---

## Timing Table

| Query | Description | Type | Run 1 (ms) | Run 2 (ms) | Run 3 (ms) | Average (ms) |
|-------|-------------|------|----------:|----------:|----------:|-------------:|
| R01 | Restaurants near me (Koramangala, ≤1 km) | READ | 8.179 | 8.288 | 6.805 | **7.757** |
| R02 | Place page details + Tuesday hours for place 18 | READ | 0.076 | 0.078 | 0.073 | **0.076** |
| R03 | Search: "biryani" in Bengaluru, best-rated first | READ | 27.429 | 33.748 | 29.656 | **30.278** |
| R04 | "Open now" filter: Bengaluru restaurants open at 23:30 Sat | READ | 23.654 | 37.394 | 20.121 | **27.056** |
| R05 | 10 newest reviews of place 18 | READ | 0.436 | 0.419 | 0.254 | **0.370** |
| R06 | Saved places for user 1005 grouped by list | READ | 0.173 | 0.158 | 0.126 | **0.152** |
| R07 | Live traffic: latest reading per Outer Ring Road segment | READ | 10.231 | 6.998 | 8.664 | **8.631** |
| R08 | Traffic alerts: heavy/standstill Bengaluru since 18:00 Jun 30 | READ | 1.110 | 0.910 | 0.638 | **0.886** |
| R09 | Typical traffic by hour on segment 5 | READ | 0.693 | 0.503 | 0.562 | **0.586** |
| R10 | Incident layer: Bengaluru incidents on Jun 30 2026 | READ | 2.531 | 1.562 | 3.799 | **2.631** |
| R11 | ETA quality: avg error per mode per month in 2026 | READ | 74.347 | 44.977 | 45.606 | **54.977** |
| R12 | Top 10 most-navigated-to places in Mumbai (last 7 days Jun 2026) | READ | 20.636 | 22.098 | 24.094 | **22.276** |
| R13 | Places never used as navigation origin | READ | 42.617 | 47.171 | 47.213 | **45.667** |
| R14 | Local Guides leaderboard: most reviews in 2026 | READ | 21.465 | 18.389 | 23.284 | **21.046** |
| R15 | Data quality: places whose stored rating/count mismatches reviews | READ | 61.398 | 69.639 | 70.917 | **67.318** |
| R16 | Permanently closed places still navigated to in 2026 | READ | 28.646 | 27.558 | 30.127 | **28.777** |
| R17 | Destinations with most rerouting on average (≥5 trips) | READ | 66.937 | 67.651 | 66.755 | **67.114** |
| R18 | Share of cancelled navigations per travel mode | READ | 27.837 | 29.724 | 28.690 | **28.750** |
| R19 | Bengaluru hospitals: navigation count + last navigation | READ | 26300.380 | 25537.126 | 24932.409 | **25589.972** |
| R20 | Navigations per day + running total for June 2026 | READ | 18.613 | 18.653 | 18.495 | **18.587** |
| R21 | Places with no opening hours, counted per category | READ | 41.205 | 42.744 | 43.470 | **42.473** |
| R22 | Moderation console: reviews page 2001 (OFFSET 50000) | READ | 30.177 | 31.246 | 32.038 | **31.154** |
| R23 | Plus Code lookup: `22222222+2W` | READ | 0.049 | 0.039 | 0.040 | **0.043** |
| R24 | Duplicate listings: same name within ~100 m in Bengaluru | READ | 9.209 | 9.107 | 9.033 | **9.116** |
| R25 | Road safety: % readings over speed limit per road type | READ | 52.685 | 51.478 | 51.312 | **51.825** |
| W01 | Start navigation (INSERT into navigation_sessions) | WRITE | 1.175 | 1.084 | 1.025 | **1.095** |
| W02 | Write a review (INSERT with ON CONFLICT DO NOTHING) | WRITE | 1.023 | 0.917 | 0.913 | **0.951** |
| W03 | Save place to list (INSERT with ON CONFLICT DO NOTHING) | WRITE | 1.069 | 1.028 | 1.062 | **1.053** |
| W04 | Nightly job: recompute all place ratings (UPDATE) | WRITE | 64.006 | 67.962 | 66.683 | **66.217** |
| W05 | Housekeeping: delete expired incidents before Jun 2026 | WRITE | 4.015 | 4.171 | 4.206 | **4.131** |
| **Total** | | | **26,838.252** | **26,097.400** | **25,565.361** | **25,833.950** |

> **Note:** R19 intentionally takes ~25 s — it uses correlated subqueries with no index on `dest_place_id`. This is the "one slow query" mentioned in the README.

---

## Per-Query Notes

| Query | Scan Type | Why slow / fast |
|-------|-----------|-----------------|
| R01 | Seq Scan on places | Lat/lng range filter with haversine ORDER — no spatial index; full table scan on 40 k rows. |
| R02 | Index Scan places_pkey + opening_hours_pkey | PK lookups on tiny result sets — extremely fast. |
| R03 | Seq Scan on places | `ILIKE '%biryani%'` cannot use a B-tree; scans all 40 k place rows. |
| R04 | Seq Scan opening_hours + Seq Scan places | No composite index on `(place_id, weekday)`; two full scans joined. |
| R05 | Bitmap Heap + Bitmap Index on uq_place_reviews_user_place | Index narrows to place 18 reviews quickly; fast. |
| R06 | Index Scan saved_places_pkey + places_pkey | PK lookups for a single user's handful of rows — near-instant. |
| R07 | Index Scan road_segments_pkey + Bitmap on uq_traffic_segment_recorded | DISTINCT ON with index on (segment_id, recorded_at) works efficiently. |
| R08 | Seq Scan road_segments + Index on uq_traffic_segment_recorded | Road table is only 2000 rows; index covers traffic filter — moderate. |
| R09 | Bitmap Heap on uq_traffic_segment_recorded | Segment 5 filter via index; group-by over that subset only — fast. |
| R10 | Seq Scan incident_reports + Seq Scan road_segments | 24 k incidents, 2 k segments — small tables, moderate cost. |
| R11 | Seq Scan navigation_sessions | 200 k rows, no index on `(status, started_at)` — full scan needed. |
| R12 | Seq Scan navigation_sessions + Seq Scan places | Date range filter over 200 k rows, no index on `started_at`. |
| R13 | Seq Scan places + Seq Scan navigation_sessions | `NOT IN (SELECT …)` with NULLs in `origin_place_id` causes full anti-join scan; known SQL gotcha. |
| R14 | Seq Scan place_reviews + Seq Scan users | 90 k reviews, full scan; date filter not selective without index. |
| R15 | Seq Scan place_reviews + Seq Scan places | Full aggregate join across 90 k reviews; no shortcut possible without mat views. |
| R16 | Seq Scan navigation_sessions + Seq Scan places | 200 k session scan; `is_permanently_closed` not indexed. |
| R17 | Seq Scan navigation_sessions | Full GROUP BY over 200 k rows with no index on `dest_place_id`. |
| R18 | Seq Scan navigation_sessions | Full aggregate over all 200 k rows — straightforward but big table. |
| R19 | Seq Scan place_categories + places + navigation_sessions (correlated) | **Slowest query (~25 s).** Correlated scalar subqueries execute once per hospital row (×N places × 200 k sessions). No index on `dest_place_id`. |
| R20 | Seq Scan navigation_sessions | Date-cast filter; window function cheap once rows grouped. |
| R21 | Seq Scan opening_hours + places + place_categories | `NOT EXISTS` anti-join across 252 k opening_hours rows — slow without index. |
| R22 | Seq Scan place_reviews | `OFFSET 50000` forces reading and discarding 50 k rows; keyset pagination would avoid this. |
| R23 | Index Scan places_plus_code_key | Exact unique-key lookup — fastest read query (~0.04 ms). |
| R24 | Seq Scan places (self-join) | Self-join with coordinate proximity filter; restricted to city+category so only ~5 k rows considered. |
| R25 | Seq Scan traffic_readings + road_segments | 250 k readings joined to 2 k segments; full scan needed for aggregate. |
| W01 | (no scan) | Single-row INSERT by PK — constant time. |
| W02 | (no scan) | Single-row INSERT with conflict check on unique index — fast. |
| W03 | (no scan) | Single-row INSERT with conflict check on composite PK — fast. |
| W04 | Seq Scan places + Seq Scan place_reviews | Full aggregate recompute across 90 k reviews then bulk UPDATE — O(n). |
| W05 | Seq Scan incident_reports | Filter + delete on 24 k rows; no partial index on `expires_at`. |

---

## Raw Data

Full `EXPLAIN (ANALYZE, BUFFERS)` plans for every run are in:

```
benchmarks/results/baseline/R01.txt … R25.txt
benchmarks/results/baseline/W01.txt … W05.txt
```

Machine-readable summary: [`benchmarks/results/baseline/summary.csv`](../benchmarks/results/baseline/summary.csv)
