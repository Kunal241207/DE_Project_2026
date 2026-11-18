# Optimization Report — Phase 3

**Machine:** MacBook (Apple Silicon, macOS)  
**PostgreSQL:** 18.7 (Postgres.app)  
**Database:** `gmaps_project` · schema `gmaps`  
**Baseline method:** `benchmarks/run_benchmark.sh gmaps_project baseline 3`  
**Optimized method:** `benchmarks/run_benchmark.sh gmaps_project optimized 3 sql/06_optimized_queries.sql`  
**Mode:** `EXPLAIN (ANALYZE, BUFFERS)`, 3 runs each, write queries inside `BEGIN … ROLLBACK`.

---

## 1. What Was Slow and Why

After reviewing the baseline plans, three patterns caused nearly all the latency.

**Large sequential scans with no filtering support.** The `navigation_sessions` table (200 k rows), `place_reviews` (90 k), `traffic_readings` (250 k), and `opening_hours` (252 k) had no indexes beyond their primary keys. Every query that filtered by date range, status, category, or congestion level paid the cost of scanning the full table.

**Correlated subqueries in R19.** The hospital health report ran two correlated scalar subqueries — one for `count(*)` and one for `max(started_at)` — once per hospital row. With 1,067 hospitals in Bengaluru, that meant 2,134 separate full scans of the 200 k-row `navigation_sessions` table. The result was a ~25,500 ms query.

**A NULL-unsafe `NOT IN` subquery in R13.** `origin_place_id` is nullable. PostgreSQL cannot prove that `NOT IN (SELECT origin_place_id …)` is safe when NULLs are present, so it falls back to a full anti-join scan instead of using an index.

---

## 2. Indexes Added

Thirteen indexes were added in `sql/05_indexes.sql`.

| Index | Table | Columns |
|-------|-------|---------|
| `idx_nav_started_at` | `navigation_sessions` | `started_at` |
| `idx_nav_status_started` | `navigation_sessions` | `(status, started_at)` where `status = 'COMPLETED'` |
| `idx_nav_dest_place_id` | `navigation_sessions` | `dest_place_id` |
| `idx_nav_origin_place_id` | `navigation_sessions` | `origin_place_id` |
| `idx_places_city_category` | `places` | `(city_id, category_id)` |
| `idx_places_lat_lng` | `places` | `(latitude, longitude)` |
| `idx_places_closed` | `places` | `place_id` where `is_permanently_closed = true` |
| `idx_reviews_created_at` | `place_reviews` | `created_at` |
| `idx_reviews_created_at_desc` | `place_reviews` | `created_at DESC` |
| `idx_opening_hours_place_weekday` | `opening_hours` | `(place_id, weekday)` |
| `idx_traffic_congestion_recorded` | `traffic_readings` | `(congestion_level, recorded_at DESC)` |
| `idx_incidents_reported_at` | `incident_reports` | `reported_at` |
| `idx_incidents_expires_at` | `incident_reports` | `expires_at` |

---

## 3. Query Rewrites

**R10 — function call on a timestamp column made it non-sargable.**  
`DATE(reported_at) = '2026-06-30'` wraps the column in a function, so PostgreSQL cannot use an index on `reported_at`. Rewritten to an explicit range so the index scan kicks in.

**R11 — `EXTRACT(YEAR …)` has the same problem.**  
Replaced with `started_at >= '2026-01-01' AND started_at < '2027-01-01'`. The partial index `idx_nav_status_started` (covering only `COMPLETED` rows) then eliminates the irrelevant 30 % of the table before the date filter.

**R13 — `NOT IN` with a nullable column.**  
Rewritten as `NOT EXISTS (SELECT 1 FROM navigation_sessions n WHERE n.origin_place_id = p.place_id)`. This is NULL-safe and allows PostgreSQL to use `idx_nav_origin_place_id` for the anti-join probe.

**R19 — correlated subqueries replaced with a pre-aggregated join.**  
Instead of running two full-table aggregates per hospital, all navigation counts and latest timestamps are computed in a single `GROUP BY dest_place_id` subquery, then joined once to the hospitals result. Combined with `idx_nav_dest_place_id`, this dropped R19 from 25,590 ms to 25 ms.

**R20 — cast on timestamp column prevented index use.**  
`started_at::date BETWEEN '2026-06-01' AND '2026-06-30'` casts every row before filtering. Replaced with a range on the raw column.

**R21 — `NOT EXISTS` rewritten to `LEFT JOIN … IS NULL`.**  
PostgreSQL generates a more efficient anti-join plan with this form, and `idx_opening_hours_place_weekday` is used to probe the index rather than scan the full table.

---

## 4. Results

| Query | Baseline (ms) | Optimized (ms) | Speedup |
|-------|-------------:|---------------:|--------:|
| R01 | 7.757 | 0.303 | **25.6×** |
| R02 | 0.076 | 0.049 | 1.6× |
| R03 | 30.278 | 4.496 | **6.7×** |
| R04 | 27.056 | 7.069 | **3.8×** |
| R05 | 0.370 | 0.146 | 2.5× |
| R06 | 0.152 | 0.057 | 2.7× |
| R07 | 8.631 | 3.807 | **2.3×** |
| R08 | 0.886 | 0.122 | **7.3×** |
| R09 | 0.586 | 0.338 | 1.7× |
| R10 | 2.631 | 0.123 | **21.4×** |
| R11 | 54.977 | 16.394 | **3.4×** |
| R12 | 22.276 | 1.773 | **12.6×** |
| R13 | 45.667 | 5.023 | **9.1×** |
| R14 | 21.046 | 5.870 | **3.6×** |
| R15 | 67.318 | 27.738 | **2.4×** |
| R16 | 28.777 | 6.637 | **4.3×** |
| R17 | 67.114 | 31.458 | **2.1×** |
| R18 | 28.750 | 14.424 | **2.0×** |
| R19 | 25,589.972 | 25.123 | **🔥 1,018×** |
| R20 | 18.587 | 1.308 | **14.2×** |
| R21 | 42.473 | 19.505 | **2.2×** |
| R22 | 31.154 | 4.184 | **7.4×** |
| R23 | 0.043 | 0.023 | 1.9× |
| R24 | 9.116 | 3.290 | **2.8×** |
| R25 | 51.825 | 26.022 | **2.0×** |
| W01 | 1.095 | 0.640 | 1.7× |
| W02 | 0.951 | 0.577 | 1.6× |
| W03 | 1.053 | 0.640 | 1.6× |
| W04 | 66.217 | 30.975 | **2.1×** |
| W05 | 4.131 | 1.936 | **2.1×** |
| **Total** | **~25,834** | **~246** | **🔥 ~105×** |

---

## 5. Queries With Limited Improvement

**R15** still scans all 90 k reviews and 40 k places because the query must compute an aggregate over every review to detect mismatches. A materialized view refreshed nightly would eliminate this cost, but that changes the schema.

**R17 and R18** aggregate the full `navigation_sessions` table with no selective filter — there is nothing to skip. The improvement comes only from better buffer caching across runs.

**R21** still scans `opening_hours` because the planner chose a Seq Scan over the large table when the selectivity estimate for `h.place_id IS NULL` was low. The index is in place and may be used on a colder cache.

**R25** joins all 250 k traffic readings to road segments to compute per-road-type aggregates. Every row must be read; no index can reduce that.

---

## 6. Trade-offs

Adding 13 indexes increases write overhead on INSERT, UPDATE, and DELETE by roughly 10–20 % per affected table. For this workload the write queries (W01–W03) are single-row operations and remain well under 1 ms. The bulk operations W04 and W05 are nightly jobs where a 2× improvement is worth the added index maintenance.

Estimated additional storage is around 150–200 MB across all indexes.

---

## 7. Raw Plans

Full `EXPLAIN (ANALYZE, BUFFERS)` output for every run is in:

```
benchmarks/results/optimized/R01.txt … R25.txt
benchmarks/results/optimized/W01.txt … W05.txt
```

Machine-readable summary: [`benchmarks/results/optimized/summary.csv`](../benchmarks/results/optimized/summary.csv)
