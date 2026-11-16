# Phase 1: Problem Understanding & Requirements Specification

## 1. Executive Overview

Google Maps India manages massive geospatial and temporal workloads encompassing Points of Interest (POIs/Places), road network topologies, dynamic traffic sensors, user telemetry, and navigation services. Rapid prototype growth without formal relational constraints resulted in significant latency bottlenecks, data inconsistencies, and slow reporting queries across eight major functional areas (P1–P8).

---

## 2. Problem Statements Analysis (P1 – P8)

### Problem 1 (P1): "Near Me" and "Open Now" Geospatial/Temporal Search Latency
* **Business Need**: Commuters and travellers need instantaneous (<5 ms) identification of nearby active amenities (e.g., restaurants, petrol stations, hospitals) within a dynamic radius (approx. 1 km). The query must evaluate spherical distance while concurrently validating operating schedules—specifically accounting for venues closing past midnight (e.g., closing at 02:00 AM on the following calendar day).
* **Stakeholders Affected**: Mobile travellers, drivers, local merchant owners (loss of business if open venues appear closed).
* **Impacted Queries**: `R01`, `R03`, `R04`, `R23`.
* **Classification**: **Customer-Facing / Real-Time** (SLA Target: `< 5 ms` for POI retrieval, `< 250 ms` for fuzzy text matching).

### Problem 2 (P2): Place Profile Loading and Personal Bookmarks Degradation
* **Business Need**: High-throughput rendering of complete POI detail screens—including contact info, weekly operating hours, aggregated ratings, and the latest user reviews—alongside rapid retrieval of user-curated bookmark lists ("Starred", "Want to go", "Favourites").
* **Stakeholders Affected**: End users exploring places, Local Guides contributing content, business managers monitoring listings.
* **Impacted Queries**: `R02`, `R05`, `R06`, `W02`, `W03`.
* **Classification**: **Customer-Facing / Real-Time** (SLA Target: `< 5 ms`).

### Problem 3 (P3): Real-Time Traffic Ingestion and Map Layer Refreshes
* **Business Need**: Ingest high-frequency telemetry sensor feeds across urban road networks and refresh driver map overlays every 60 seconds with current congestion levels (`LOW`, `MODERATE`, `HEAVY`, `STANDSTILL`) and active road hazard incidents (accidents, waterlogging, police checkpoints). Expired hazard reports must be pruned in batches.
* **Stakeholders Affected**: Active drivers, dynamic navigation route-recalculators, municipal emergency responders.
* **Impacted Queries**: `R07`, `R08`, `R10`, `W05`.
* **Classification**: **Customer-Facing / Real-Time** (SLA Target: `< 5 ms` for live map queries, `< 2,000 ms` for maintenance jobs).

### Problem 4 (P4): "Typical Traffic" Profiles and Road Safety Telemetry
* **Business Need**: Aggregation of historical traffic speeds by hour of day for specific road corridors to power predictive route duration models ("Typically 25 mins at 5 PM"), as well as macro-level audit reports evaluating speed limit compliance across road classifications (Arterial, Highway, Local).
* **Stakeholders Affected**: Traffic engineering teams, civil road planners, route-planning commuters.
* **Impacted Queries**: `R09`, `R25`.
* **Classification**: **Reporting / Analytics** (SLA Target: `< 250 ms` for corridor profile, `< 5,000 ms` for fleet-wide safety report).

### Problem 5 (P5): Navigation Initiation and Telemetry Routing Accuracy
* **Business Need**: Zero-latency initiation when a user starts trip navigation (`W01`), coupled with analytical pipelines evaluating predictive model accuracy (ETA variance: actual travel time minus estimated travel time), re-routing hotspots indicative of unexpected bottlenecks, and route cancellation rates across transit modes.
* **Stakeholders Affected**: Active navigators, routing algorithm engineers, machine learning ETA teams.
* **Impacted Queries**: `W01` (Trip Start), `R11`, `R12`, `R17`, `R18`.
* **Classification**:
  * `W01`: **Customer-Facing / Real-Time** (SLA Target: `< 5 ms`).
  * `R11`, `R12`, `R17`, `R18`: **Reporting / Analytics** (SLA Target: `< 5,000 ms`).

### Problem 6 (P6): Identifying Inactive Origin Places ("Unused Start Points")
* **Business Need**: The data curation team needs to identify inactive places that have never served as the starting origin of any trip, facilitating map pruning and partner outreach. The existing query paradoxically returns zero rows despite tens of thousands of unused places.
* **Root Cause & Business Context**: The legacy query uses an anti-pattern `p.place_id NOT IN (SELECT origin_place_id FROM navigation_sessions)`. Because guest users start navigations from raw GPS coordinates, `origin_place_id` contains `NULL`s. In three-valued SQL logic, `val NOT IN (..., NULL)` evaluates to `UNKNOWN`/`FALSE` for all rows, completely wiping out valid results.
* **Stakeholders Affected**: Map data curation team, GIS database administrators.
* **Impacted Queries**: `R13`.
* **Classification**: **Interactive Search / Internal Analytics Tool** (SLA Target: `< 250 ms`).

### Problem 7 (P7): Automated Data Quality Audits and Consistency Enforcement
* **Business Need**: Nightly integrity scans to detect desynchronized materialized ratings (`avg_rating`, `review_count`) versus actual stored reviews, identify closed venues still targeted by active navigations, flag POIs lacking operating hours, and deduplicate duplicate business entries within close physical proximity (~100 m).
* **Stakeholders Affected**: Data quality engineers, platform trust & safety, verified business owners.
* **Impacted Queries**: `R15`, `R16`, `R21`, `R24`, `W04`.
* **Classification**: **Reporting / Batch Quality Audits** (SLA Target: `< 2,000 ms` to `< 5,000 ms`).

### Problem 8 (P8): Community Leaderboards, Moderation Queues & 20x Scale Resilience
* **Business Need**: Local Guides community gamification rankings, deeply paginated moderation consoles for review spam detection, urban healthcare infrastructure access tracking (hospital trip trends), and cumulative navigation volume growth monitoring—designed to remain performant under a 20× increase in database volume.
* **Stakeholders Affected**: Local Guides community, trust & safety moderators, healthcare logistics analysts, database architects.
* **Impacted Queries**: `R14`, `R19`, `R20`, `R22`.
* **Classification**:
  * `R22`: **Interactive Moderation Console** (SLA Target: `< 250 ms`).
  * `R14`, `R19`, `R20`: **Reporting / Analytics** (SLA Target: `< 5,000 ms`).

---

## 3. Workload Classification Matrix

| Problem | Workload Type | SLA Latency Target | Impacted Queries | Primary Stakeholder |
|:-------:|:--------------|:------------------:|:-----------------|:--------------------|
| **P1** | Customer-Facing / Real-Time | `< 5 ms` / `< 250 ms` | R01, R03, R04, R23 | Travellers & Commuters |
| **P2** | Customer-Facing / Real-Time | `< 5 ms` | R02, R05, R06, W02, W03 | Mobile App Users |
| **P3** | Real-Time Map & Telemetry | `< 5 ms` / `< 2,000 ms` | R07, R08, R10, W05 | Active Drivers & Traffic Monitors |
| **P4** | Reporting / Analytics | `< 250 ms` / `< 5,000 ms` | R09, R25 | Traffic Planners |
| **P5** | Real-Time Write + Analytics | `< 5 ms` (W) / `< 5,000 ms` | W01, R11, R12, R17, R18 | Routing & ETA Team |
| **P6** | Internal Tool / Search | `< 250 ms` | R13 | Data Curation Team |
| **P7** | Batch Quality & Maintenance | `< 2,000 ms` – `< 5,000 ms` | R15, R16, R21, R24, W04 | Data Quality Team |
| **P8** | Moderation & Analytics | `< 250 ms` / `< 5,000 ms` | R14, R19, R20, R22 | Community & Platform Ops |

---

## 4. Engineering Assumptions

1. **Spatial Representation & Distance**: Geographic coordinates use standard WGS-84 decimal degrees. Latitudes are within `[-90.0, 90.0]` and longitudes within `[-180.0, 180.0]`. Initial candidate filtering uses Euclidean bounding boxes (`0.009° ≈ 1.0 km`, `0.001° ≈ 111 m`) prior to exact Great-Circle Haversine calculations.
2. **Calendar and Weekday Convention**: Weekdays follow ISO standard numbering from `1` (Monday) through `7` (Sunday).
3. **Overnight Operating Hours**: A record with `closes < opens` signifies operating hours that extend past midnight into the early morning of the subsequent day.
4. **Anonymous & GPS Navigation Sessions**:
   - `navigation_sessions.user_id` is nullable to accommodate guest/unauthenticated sessions.
   - `navigation_sessions.origin_place_id` is nullable because sessions initiated from live device GPS coordinates do not possess a pre-existing POI identifier.
5. **Session Lifecycle States**:
   - `status = 'COMPLETED'` strictly requires a positive `actual_minutes` value.
   - `status IN ('CANCELLED', 'IN_PROGRESS')` requires `actual_minutes IS NULL`.
6. **Local Guide Membership**: A user is a Local Guide (`is_local_guide = TRUE`) if and only if they hold an integer `guide_level` between 1 and 10; non-guides have `guide_level IS NULL`.
7. **Idempotency & Duplicate Prevention**:
   - A user may submit at most one review per place (`UNIQUE (place_id, user_id)`).
   - A place can only appear once within any single user list (`PRIMARY KEY (user_id, place_id, list_name)`).
8. **Controlled Denormalization**: `places.avg_rating` and `places.review_count` are materialized aggregates cached for read performance; temporary drift from raw review sums is expected and reconciled via scheduled batch job `W04`.

