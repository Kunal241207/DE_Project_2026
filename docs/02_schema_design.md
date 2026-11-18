# Phase 2: Relational Architecture, Schema Design & Normalization Report

## 1. Executive Summary & Design Principles

This document presents the complete relational database architecture for the Google Maps Navigation platform (`gmaps` schema) using PostgreSQL 15+. The architecture has been audited and structured according to senior database design standards:
* **Relational Rigor**: Enforcing Boyce-Codd Normal Form (BCNF) across primary operational entities while intentionally justifying controlled denormalization for read-heavy geospatial queries.
* **Strict Referential Integrity**: Implementing 15 explicitly defined foreign-key relationships with clear referential actions (`CASCADE`, `RESTRICT`, `SET NULL`, `ON UPDATE CASCADE`).
* **Domain & Business Rule Verification**: Implementing 24 `CHECK` and `UNIQUE` constraints validating geographic coordinate ranges, lifecycle state machines, format compliance, and schedule bounds.
* **Workload Compatibility**: Preserving exact compatibility with the 11 production seed datasets (55+ MB export) and the 30-query benchmark workload (`queries/workload_30.sql`).

Visual diagrams representing this architecture:
* High-Resolution Vector Diagram: [`diagrams/er_diagram.svg`](../diagrams/er_diagram.svg)
* Production Image Diagram: [`diagrams/er_diagram.png`](../diagrams/er_diagram.png)

---

## 2. Critical Audit of Core Entities & Architectural Modifications

### A. `opening_hours`: Operational Scheduling & Weekday Modeling
* **Audit & Evaluation**: The `weekday` attribute uses ISO integer conventions (`1` = Monday to `7` = Sunday). A separate lookup table for weekdays was evaluated but rejected as unnecessary overhead because weekday integers are universally standardized and enforced by `CHECK (weekday BETWEEN 1 AND 7)`.
* **Primary Key Definition**: Composite Primary Key `(place_id, weekday)`. In the production seed data (252,266 records), each place has at most one operating interval per day.
* **Past-Midnight Representation**: The schema natively supports venues closing after midnight (`closes < opens`, e.g., opens 18:00, closes 02:00) without data loss or schema distortion.

### B. `saved_places`: Multi-List User Bookmarks
* **Audit & Evaluation**: Users save multiple places into different lists (`Favourites`, `Starred`, `Travel plans`, `Want to go`). A user can save the same place across different lists (e.g., both "Starred" and "Want to go"), but cannot add duplicates within the same list.
* **Primary Key Definition**: Composite Primary Key `(user_id, place_id, list_name)`. This prevents duplicate entries in the same list while fully enabling cross-list bookmarking.

### C. `place_reviews`: Moderation & Idempotent Feedback
* **Audit & Evaluation**: A single user can write at most one review per place. This guarantees fair ratings, prevents review spamming, and satisfies the idempotent write query `W02` (`ON CONFLICT (place_id, user_id) DO NOTHING`).
* **Primary Key & Constraints**: Surrogate Primary Key `review_id`, augmented by candidate key `CONSTRAINT uq_place_reviews_user_place UNIQUE (place_id, user_id)`. Ratings are strictly bounded via `CHECK (rating BETWEEN 1 AND 5)`.

### D. `road_segments`: Network Topology & Coordinate Precision
* **Audit & Evaluation**: Straight-line segment bounds are represented via `(start_lat, start_lng)` and `(end_lat, end_lng)`. In standard relational databases without forcing PostGIS as an external binary dependency, high-precision coordinates (`NUMERIC(9,6)`) provide ~10 cm spatial resolution, meeting all routing and speed limit analysis needs.

### E. `traffic_readings`: High-Frequency Telemetry & Historical Analysis
* **Audit & Evaluation**: Supports high-volume time-series traffic velocity captures.
* **Key Architecture**: Primary Key `reading_id` with natural candidate key `CONSTRAINT uq_traffic_segment_recorded UNIQUE (segment_id, recorded_at)`. PostgreSQL automatically indexes this candidate key, providing instantaneous segment time-series lookups for live alerts (`R08`) and hourly traffic profiling (`R09`).

### F. `navigation_sessions`: Session Telemetry & Dynamic Routing
* **Audit & Evaluation**: Accommodates trips originating from registered POIs as well as arbitrary user GPS locations.
* **Nullability Architecture**:
  * `origin_place_id` is **nullable** to support live GPS starting points.
  * `origin_lat` and `origin_lng` are **NOT NULL**, ensuring every trip has recorded coordinates.
  * `user_id` is **nullable** with `ON DELETE SET NULL` to support anonymous/guest navigation and GDPR privacy compliance upon account deletion.
  * `status` state machine is enforced: `status = 'COMPLETED'` requires positive `actual_minutes`, while `CANCELLED` and `IN_PROGRESS` require `actual_minutes IS NULL`.

### G. `incident_reports`: Dynamic Hazard Management
* **Audit & Evaluation**: Captures localized hazard alerts (accidents, roadwork, waterlogging) tied to physical road segments.
* **Temporal Integrity**: Enforced via `CHECK (expires_at > reported_at)` and `upvotes >= 0`, ensuring automated pruning jobs (`W05`) can clear expired hazards cleanly.

---

## 3. Table-by-Table Data Dictionary

### 3.1 Table: `cities` (10 rows)
Anchor metropolitan centroids for municipal road networks and POI partitioning.

| Column | Data Type | Nullable | Constraint | Architectural Purpose & Rationale |
|:-------|:----------|:--------:|:-----------|:----------------------------------|
| `city_id` | `INT` | No | `PRIMARY KEY` | Surrogate identifier for each metropolitan region. |
| `city_name` | `VARCHAR(50)` | No | `UNIQUE` | Distinct official city name. |
| `center_lat` | `NUMERIC(9,6)` | No | `CHECK (-90..90)` | WGS-84 latitude of urban center. |
| `center_lng` | `NUMERIC(9,6)` | No | `CHECK (-180..180)`| WGS-84 longitude of urban center. |

### 3.2 Table: `place_categories` (12 rows)
Taxonomy for business and geographic points of interest.

| Column | Data Type | Nullable | Constraint | Architectural Purpose & Rationale |
|:-------|:----------|:--------:|:-----------|:----------------------------------|
| `category_id` | `INT` | No | `PRIMARY KEY` | Category identifier. |
| `category_name` | `VARCHAR(50)` | No | `UNIQUE` | Distinct descriptive category name. |

### 3.3 Table: `places` (40,042 rows)
Points of interest (POIs) across cities.

| Column | Data Type | Nullable | Constraint | Architectural Purpose & Rationale |
|:-------|:----------|:--------:|:-----------|:----------------------------------|
| `place_id` | `INT` | No | `PRIMARY KEY` | Surrogate identifier for point of interest. |
| `plus_code` | `VARCHAR(20)` | No | `UNIQUE, CHECK` | Open Location Code (8 chars + '+' + 2–3 chars) for spatial lookup. |
| `name` | `VARCHAR(255)` | No | — | Commercial or geographic venue name. |
| `category_id` | `INT` | No | `FK -> place_categories` | Category code (`ON DELETE RESTRICT ON UPDATE CASCADE`). |
| `city_id` | `INT` | No | `FK -> cities` | Administrative city (`ON DELETE RESTRICT ON UPDATE CASCADE`). |
| `latitude` | `NUMERIC(9,6)` | No | `CHECK (-90..90)` | Sub-meter geographic latitude. |
| `longitude` | `NUMERIC(9,6)` | No | `CHECK (-180..180)`| Sub-meter geographic longitude. |
| `address` | `TEXT` | No | — | Human-readable address. |
| `phone` | `VARCHAR(30)` | Yes | — | E.164 contact phone number (null if unlisted). |
| `website` | `VARCHAR(255)` | Yes | — | Official domain/web URL (null if no website). |
| `price_level` | `SMALLINT` | Yes | `CHECK (1..4)` | Price tier (1–4); null for public amenities. |
| `avg_rating` | `NUMERIC(2,1)` | Yes | `CHECK (1.0..5.0)` | Materialized review rating average (null if unreviewed). |
| `review_count` | `INT` | No | `DEFAULT 0, CHECK (>=0)` | Materialized count of submitted user reviews. |
| `is_permanently_closed` | `BOOLEAN` | No | `DEFAULT FALSE` | Operational flag for decommissioned venues. |
| `created_at` | `TIMESTAMPTZ` | No | — | Creation timestamp. |

### 3.4 Table: `opening_hours` (252,266 rows)
Weekly operational schedules per place.

| Column | Data Type | Nullable | Constraint | Architectural Purpose & Rationale |
|:-------|:----------|:--------:|:-----------|:----------------------------------|
| `place_id` | `INT` | No | `PK, FK -> places` | Venue reference (`ON DELETE CASCADE ON UPDATE CASCADE`). |
| `weekday` | `SMALLINT` | No | `PK, CHECK (1..7)` | ISO day of week: 1 (Monday) to 7 (Sunday). |
| `opens` | `TIME` | No | — | Scheduled opening time. |
| `closes` | `TIME` | No | — | Scheduled closing time (`closes < opens` signifies next-day closing). |

### 3.5 Table: `users` (40,000 rows)
Platform registered accounts and community Local Guides.

| Column | Data Type | Nullable | Constraint | Architectural Purpose & Rationale |
|:-------|:----------|:--------:|:-----------|:----------------------------------|
| `user_id` | `INT` | No | `PRIMARY KEY` | User account identifier. |
| `display_name` | `VARCHAR(100)` | No | — | Public author name. |
| `email` | `VARCHAR(255)` | No | `UNIQUE, CHECK` | Validated RFC email address. |
| `home_city_id` | `INT` | Yes | `FK -> cities` | Residential city anchor (`ON DELETE SET NULL ON UPDATE CASCADE`). |
| `is_local_guide` | `BOOLEAN` | No | `DEFAULT FALSE` | Local Guides community membership flag. |
| `guide_level` | `SMALLINT` | Yes | `CHECK (1..10)` | Tier level (1–10); mandatory for guides, null for non-guides. |
| `created_at` | `TIMESTAMPTZ` | No | — | Account creation timestamp. |

### 3.6 Table: `place_reviews` (89,998 rows)
Crowdsourced feedback, star ratings, and media.

| Column | Data Type | Nullable | Constraint | Architectural Purpose & Rationale |
|:-------|:----------|:--------:|:-----------|:----------------------------------|
| `review_id` | `INT` | No | `PRIMARY KEY` | Review record identifier. |
| `place_id` | `INT` | No | `FK -> places, UQ(p,u)` | Target venue (`ON DELETE CASCADE ON UPDATE CASCADE`). |
| `user_id` | `INT` | No | `FK -> users, UQ(p,u)` | Review author (`ON DELETE CASCADE ON UPDATE CASCADE`). |
| `rating` | `SMALLINT` | No | `CHECK (1..5)` | Star rating awarded. |
| `review_text` | `TEXT` | Yes | — | Optional review comments. |
| `photo_count` | `INT` | No | `DEFAULT 0, CHECK (>=0)` | Attached verified photos. |
| `created_at` | `TIMESTAMPTZ` | No | — | Submission timestamp. |

### 3.7 Table: `saved_places` (50,000 rows)
User bookmark collections and travel itineraries.

| Column | Data Type | Nullable | Constraint | Architectural Purpose & Rationale |
|:-------|:----------|:--------:|:-----------|:----------------------------------|
| `user_id` | `INT` | No | `PK, FK -> users` | Owner account (`ON DELETE CASCADE ON UPDATE CASCADE`). |
| `place_id` | `INT` | No | `PK, FK -> places` | Saved venue (`ON DELETE CASCADE ON UPDATE CASCADE`). |
| `list_name` | `VARCHAR(50)` | No | `PK, CHECK` | Validated list name (`Favourites`, `Starred`, `Travel plans`, `Want to go`). |
| `saved_at` | `TIMESTAMPTZ` | No | — | Bookmark timestamp. |

### 3.8 Table: `road_segments` (2,000 rows)
Directed road network topology partitioned by city.

| Column | Data Type | Nullable | Constraint | Architectural Purpose & Rationale |
|:-------|:----------|:--------:|:-----------|:----------------------------------|
| `segment_id` | `INT` | No | `PRIMARY KEY` | Routing segment identifier. |
| `road_name` | `VARCHAR(255)` | No | — | Road corridor label. |
| `city_id` | `INT` | No | `FK -> cities` | Administrative city (`ON DELETE RESTRICT ON UPDATE CASCADE`). |
| `road_type` | `VARCHAR(20)` | No | `CHECK` | Road class: `ARTERIAL`, `HIGHWAY`, `LOCAL`. |
| `start_lat` | `NUMERIC(9,6)` | No | `CHECK (-90..90)` | Segment origin latitude. |
| `start_lng` | `NUMERIC(9,6)` | No | `CHECK (-180..180)`| Segment origin longitude. |
| `end_lat` | `NUMERIC(9,6)` | No | `CHECK (-90..90)` | Segment destination latitude. |
| `end_lng` | `NUMERIC(9,6)` | No | `CHECK (-180..180)`| Segment destination longitude. |
| `length_m` | `INT` | No | `CHECK (>0)` | Physical segment length in meters. |
| `speed_limit_kmph` | `INT` | No | `CHECK (>0)` | Legal speed limit in km/h. |

### 3.9 Table: `traffic_readings` (250,000 rows)
Time-series telemetry capturing live traffic conditions.

| Column | Data Type | Nullable | Constraint | Architectural Purpose & Rationale |
|:-------|:----------|:--------:|:-----------|:----------------------------------|
| `reading_id` | `BIGINT` | No | `PRIMARY KEY` | Monotonic telemetry sequence identifier. |
| `segment_id` | `INT` | No | `FK, UQ(seg,time)` | Segment reference (`ON DELETE CASCADE ON UPDATE CASCADE`). |
| `recorded_at` | `TIMESTAMPTZ` | No | `UQ(seg,time)` | Telemetry capture timestamp. |
| `avg_speed_kmph` | `NUMERIC(5,2)` | No | `CHECK (>=0)` | Average observed velocity. |
| `congestion_level` | `VARCHAR(20)` | No | `CHECK` | State: `LOW`, `MODERATE`, `HEAVY`, `STANDSTILL`. |

### 3.10 Table: `navigation_sessions` (200,000 rows)
Turn-by-turn trip logs and routing performance metrics.

| Column | Data Type | Nullable | Constraint | Architectural Purpose & Rationale |
|:-------|:----------|:--------:|:-----------|:----------------------------------|
| `session_id` | `BIGINT` | No | `PRIMARY KEY` | Unique navigation transaction key. |
| `user_id` | `INT` | Yes | `FK -> users` | Traveler account (`ON DELETE SET NULL ON UPDATE CASCADE`). |
| `origin_place_id` | `INT` | Yes | `FK -> places` | Origin POI; null for arbitrary GPS origins (`ON DELETE SET NULL`). |
| `origin_lat` | `NUMERIC(9,6)` | No | `CHECK (-90..90)` | Trip start latitude. |
| `origin_lng` | `NUMERIC(9,6)` | No | `CHECK (-180..180)`| Trip start longitude. |
| `dest_place_id` | `INT` | No | `FK -> places` | Destination venue (`ON DELETE RESTRICT ON UPDATE CASCADE`). |
| `travel_mode` | `VARCHAR(20)` | No | `CHECK` | Modality: `DRIVE`, `TRANSIT`, `TWO_WHEELER`, `WALK`. |
| `started_at` | `TIMESTAMPTZ` | No | — | Departure timestamp. |
| `distance_km` | `NUMERIC(6,2)` | No | `CHECK (>=0)` | Route distance in kilometers. |
| `eta_minutes` | `INT` | No | `CHECK (>=0)` | Initial estimated travel duration. |
| `actual_minutes` | `INT` | Yes | `CHECK` | Actual realized duration; required for completed trips. |
| `rerouted_count` | `INT` | No | `DEFAULT 0, CHECK (>=0)` | Recalculation count during journey. |
| `status` | `VARCHAR(20)` | No | `CHECK` | Status: `CANCELLED`, `COMPLETED`, `IN_PROGRESS`. |

### 3.11 Table: `incident_reports` (12,000 rows)
Crowdsourced hazard alerts and traffic incidents.

| Column | Data Type | Nullable | Constraint | Architectural Purpose & Rationale |
|:-------|:----------|:--------:|:-----------|:----------------------------------|
| `report_id` | `INT` | No | `PRIMARY KEY` | Hazard report identifier. |
| `segment_id` | `INT` | No | `FK -> road_segments` | Segment affected (`ON DELETE CASCADE ON UPDATE CASCADE`). |
| `user_id` | `INT` | Yes | `FK -> users` | Submitter account (`ON DELETE SET NULL ON UPDATE CASCADE`). |
| `incident_type` | `VARCHAR(20)` | No | `CHECK` | Category: `ACCIDENT`, `BREAKDOWN`, `CLOSURE`, `POLICE`, `ROADWORK`, `WATERLOGGING`. |
| `reported_at` | `TIMESTAMPTZ` | No | — | Submission timestamp. |
| `expires_at` | `TIMESTAMPTZ` | No | `CHECK (> reported_at)` | Automatic expiration timestamp. |
| `upvotes` | `INT` | No | `DEFAULT 0, CHECK (>=0)` | Community verification vote count. |

---

## 4. Relationship Architecture & Crow's Foot Cardinalities

The diagram implements all 15 explicit relationships using formal Crow's Foot notation:

| # | Relationship | Parent End | Child End | Notation | Participation | Foreign Key Implementation |
|:-:|:-------------|:----------:|:---------:|:--------:|:-------------:|:---------------------------|
| 1 | `place_categories` → `places` | Exactly One (`\|\|`) | Zero or Many (`O<`) | `\|\|` to `O<` | Mandatory parent | `places.category_id REFERENCES place_categories(category_id)` |
| 2 | `cities` → `places` | Exactly One (`\|\|`) | Zero or Many (`O<`) | `\|\|` to `O<` | Mandatory parent | `places.city_id REFERENCES cities(city_id)` |
| 3 | `cities` → `users` | Exactly One (`\|\|`) | Zero or Many (`O<`) | `\|\|` to `O<` | Optional child (`home_city_id IS NULL`) | `users.home_city_id REFERENCES cities(city_id)` |
| 4 | `cities` → `road_segments` | Exactly One (`\|\|`) | Zero or Many (`O<`) | `\|\|` to `O<` | Mandatory parent | `road_segments.city_id REFERENCES cities(city_id)` |
| 5 | `places` → `opening_hours` | Exactly One (`\|\|`) | Zero or Many (`O<`) | `\|\|` to `O<` | Mandatory parent | `opening_hours.place_id REFERENCES places(place_id)` |
| 6 | `places` → `place_reviews` | Exactly One (`\|\|`) | Zero or Many (`O<`) | `\|\|` to `O<` | Mandatory parent | `place_reviews.place_id REFERENCES places(place_id)` |
| 7 | `users` → `place_reviews` | Exactly One (`\|\|`) | Zero or Many (`O<`) | `\|\|` to `O<` | Mandatory parent | `place_reviews.user_id REFERENCES users(user_id)` |
| 8 | `users` → `saved_places` | Exactly One (`\|\|`) | Zero or Many (`O<`) | `\|\|` to `O<` | Mandatory parent | `saved_places.user_id REFERENCES users(user_id)` |
| 9 | `places` → `saved_places` | Exactly One (`\|\|`) | Zero or Many (`O<`) | `\|\|` to `O<` | Mandatory parent | `saved_places.place_id REFERENCES places(place_id)` |
| 10 | `road_segments` → `traffic_readings` | Exactly One (`\|\|`) | Zero or Many (`O<`) | `\|\|` to `O<` | Mandatory parent | `traffic_readings.segment_id REFERENCES road_segments(segment_id)` |
| 11 | `road_segments` → `incident_reports` | Exactly One (`\|\|`) | Zero or Many (`O<`) | `\|\|` to `O<` | Mandatory parent | `incident_reports.segment_id REFERENCES road_segments(segment_id)` |
| 12 | `users` → `incident_reports` | Exactly One (`\|\|`) | Zero or Many (`O<`) | `\|\|` to `O<` | Optional child (`user_id IS NULL`) | `incident_reports.user_id REFERENCES users(user_id)` |
| 13 | `users` → `navigation_sessions` | Exactly One (`\|\|`) | Zero or Many (`O<`) | `\|\|` to `O<` | Optional child (`user_id IS NULL`) | `navigation_sessions.user_id REFERENCES users(user_id)` |
| 14 | `places` → `navigation_sessions` (origin) | Exactly One (`\|\|`) | Zero or Many (`O<`) | `\|\|` to `O<` | Optional child (`origin_place_id IS NULL`) | `navigation_sessions.origin_place_id REFERENCES places(place_id)` |
| 15 | `places` → `navigation_sessions` (dest) | Exactly One (`\|\|`) | Zero or Many (`O<`) | `\|\|` to `O<` | Mandatory parent | `navigation_sessions.dest_place_id REFERENCES places(place_id)` |

---

## 5. Normalization Audit (1NF, 2NF, 3NF & BCNF)

### 5.1 Verification of Normal Forms

* **First Normal Form (1NF)**:
  * All attributes contain strictly atomic, scalar values (e.g., coordinates are decomposed into separate `latitude` and `longitude` numeric scalars rather than composite string arrays; opening times are split into discrete `opens` and `closes` times).
  * No repeating column groups or multi-valued attributes exist.
* **Second Normal Form (2NF)**:
  * Meets 1NF.
  * For composite primary key tables (`opening_hours(place_id, weekday)` and `saved_places(user_id, place_id, list_name)`), every non-prime attribute depends on the **entire composite key**:
    * `opens` and `closes` depend on both venue and day of week.
    * `saved_at` depends on user, place, and specific list.
  * For single-column PK tables, partial key dependencies are mathematically impossible.
* **Third Normal Form (3NF)**:
  * Meets 2NF.
  * No transitive dependencies exist between non-prime attributes:
    * In `places`, city attributes (name, center) and category names are factored out into `cities` and `place_categories`.
    * In `road_segments`, city attributes reference `cities(city_id)`.
* **Boyce-Codd Normal Form (BCNF)**:
  * For every functional dependency $X \to Y$, the determinant $X$ is a superkey (candidate key).
  * In `place_reviews`, both `review_id` and `(place_id, user_id)` are superkeys, satisfying BCNF.
  * In `users`, both `user_id` and `email` are superkeys, satisfying BCNF.

### 5.2 Controlled Denormalization Justification

In high-concurrency production geospatial engines, strict 3NF without denormalization introduces critical latency bottlenecks on high-frequency read paths. Three attributes are intentionally maintained as controlled denormalizations:

1. **`places.avg_rating` and `places.review_count`**:
   * *Strict 3NF Alternative*: Compute via `SELECT avg(rating), count(*) FROM place_reviews WHERE place_id = ...` on every map search.
   * *Architectural Justification*: Search queries (`R01`, `R03`) scan thousands of venues per second across map bounding boxes. Calculating aggregate review functions on the fly would cause disk thrashing. Storing cached aggregates yields instant $O(1)$ response times. Consistency drift is reconciled via scheduled batch job `W04`.
2. **`traffic_readings.congestion_level`**:
   * *Strict 3NF Alternative*: Dynamically evaluate `avg_speed_kmph` relative to `road_segments.speed_limit_kmph` on each reading fetch.
   * *Architectural Justification*: Real-time traffic alerts (`R08`) filter specifically for `'HEAVY'` or `'STANDSTILL'` congestion. Materializing the categorical status allows immediate indexed B-tree filtering without joining road segments.
3. **`navigation_sessions.eta_minutes`**:
   * Initial predictive model output retained alongside actual duration (`actual_minutes`) to benchmark algorithmic routing accuracy (`R11`).

---

## 6. Evaluation of Extended Entities

A senior architectural audit evaluated whether additional entities should be added:
1. **Road Network Intersections / Nodes (`road_intersections`)**:
   * *Evaluation*: Represents topological graph nodes connecting multiple road segments. In the existing schema, intersection connectivity is derived spatially via matching `(start_lat, start_lng)` and `(end_lat, end_lng)`. Adding an explicit node table is useful for Dijkstra routing engines but is omitted from physical tables to preserve 100% compatibility with seed data ingestion.
2. **Intermediate Road Geometry (`road_geometry_points`)**:
   * *Evaluation*: Represents polyline coordinates for curved roads. In this database, road corridors are divided into granular segments with explicit lengths (`length_m`), which accurately captures distance without adding multi-million coordinate junction tables.
3. **Trip Route Segments (`route_segments`)**:
   * *Evaluation*: Junction table mapping individual navigation sessions to traversed road segments. While useful for granular toll auditing, storing 200,000 sessions $\times$ 30 segments = 6,000,000 junction rows would significantly bloat storage without serving the given workload queries.

---

## 7. Production Verification & Integrity Audits

### 7.1 Row Count Verification
All 11 seed CSV exports load with zero errors, matching production specifications:
* `cities`: 10 rows
* `place_categories`: 12 rows
* `places`: 40,042 rows
* `opening_hours`: 252,266 rows
* `users`: 40,000 rows
* `place_reviews`: 89,998 rows
* `saved_places`: 50,000 rows
* `road_segments`: 2,000 rows
* `traffic_readings`: 250,000 rows
* `navigation_sessions`: 200,000 rows
* `incident_reports`: 12,000 rows

### 7.2 Integrity Audit Findings
1. **Coordinate Consistency**: 100% of the 7,416 sessions with `origin_place_id` set have origin coordinates matching the referenced place's coordinates ($0$ mismatches).
2. **Intra-City Trips**: 100% of POI-to-POI trips originate and terminate in the same city.
3. **Materialized Rating Cache Drift**: 1,431 rating mismatches and 558 count mismatches exist between `places` and raw `place_reviews`, validating the real-world operational requirement for nightly reconciliation job `W04`.
4. **Three-Valued Logic SQL Discovery**: 192,584 navigation sessions originate from live GPS (`origin_place_id IS NULL`). Query `R13` uses `NOT IN (SELECT origin_place_id ...)`. Because of SQL three-valued logic, `NOT IN (..., NULL)` evaluates to `UNKNOWN`, returning zero rows. The architecture identifies this bug and prescribes `NOT EXISTS`.

---

## 8. Complete Editable Mermaid ER Diagram Source

```mermaid
erDiagram
    place_categories ||--o{ places : "categorizes (1:N)"
    cities ||--o{ places : "hosts (1:N)"
    cities ||--o{ road_segments : "contains (1:N)"
    cities ||--o{ users : "resides_in (0..1)"
    places ||--o{ opening_hours : "operates (1:N)"
    places ||--o{ saved_places : "saved_in (1:N)"
    users ||--o{ saved_places : "bookmarks (1:N)"
    places ||--o{ place_reviews : "reviews (1:N)"
    users ||--o{ place_reviews : "authors (1:N)"
    road_segments ||--o{ traffic_readings : "telemetry (1:N)"
    road_segments ||--o{ incident_reports : "road_hazard (1:N)"
    users ||--o{ incident_reports : "reports (0..1)"
    users ||--o{ navigation_sessions : "drives (0..1)"
    places ||--o{ navigation_sessions : "origin (0..1)"
    places ||--o{ navigation_sessions : "destination (1:N)"

    cities {
        int city_id PK
        varchar city_name UQ
        numeric center_lat
        numeric center_lng
    }

    place_categories {
        int category_id PK
        varchar category_name UQ
    }

    places {
        int place_id PK
        varchar plus_code UQ
        varchar name
        int category_id FK
        int city_id FK
        numeric latitude
        numeric longitude
        text address
        varchar phone
        varchar website
        smallint price_level
        numeric avg_rating
        int review_count
        boolean is_permanently_closed
        timestamptz created_at
    }

    opening_hours {
        int place_id PK,FK
        smallint weekday PK
        time opens
        time closes
    }

    users {
        int user_id PK
        varchar display_name
        varchar email UQ
        int home_city_id FK
        boolean is_local_guide
        smallint guide_level
        timestamptz created_at
    }

    place_reviews {
        int review_id PK
        int place_id FK,UQ
        int user_id FK,UQ
        smallint rating
        text review_text
        int photo_count
        timestamptz created_at
    }

    saved_places {
        int user_id PK,FK
        int place_id PK,FK
        varchar list_name PK
        timestamptz saved_at
    }

    road_segments {
        int segment_id PK
        varchar road_name
        int city_id FK
        varchar road_type
        numeric start_lat
        numeric start_lng
        numeric end_lat
        numeric end_lng
        int length_m
        int speed_limit_kmph
    }

    traffic_readings {
        bigint reading_id PK
        int segment_id FK,UQ
        timestamptz recorded_at UQ
        numeric avg_speed_kmph
        varchar congestion_level
    }

    navigation_sessions {
        bigint session_id PK
        int user_id FK
        int origin_place_id FK
        numeric origin_lat
        numeric origin_lng
        int dest_place_id FK
        varchar travel_mode
        timestamptz started_at
        numeric distance_km
        int eta_minutes
        int actual_minutes
        int rerouted_count
        varchar status
    }

    incident_reports {
        int report_id PK
        int segment_id FK
        int user_id FK
        varchar incident_type
        timestamptz reported_at
        timestamptz expires_at
        int upvotes
    }
```
