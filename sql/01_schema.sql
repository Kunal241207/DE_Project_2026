CREATE SCHEMA IF NOT EXISTS gmaps;
SET search_path TO gmaps;

DROP TABLE IF EXISTS incident_reports CASCADE;
DROP TABLE IF EXISTS navigation_sessions CASCADE;
DROP TABLE IF EXISTS traffic_readings CASCADE;
DROP TABLE IF EXISTS road_segments CASCADE;
DROP TABLE IF EXISTS saved_places CASCADE;
DROP TABLE IF EXISTS place_reviews CASCADE;
DROP TABLE IF EXISTS users CASCADE;
DROP TABLE IF EXISTS opening_hours CASCADE;
DROP TABLE IF EXISTS places CASCADE;
DROP TABLE IF EXISTS place_categories CASCADE;
DROP TABLE IF EXISTS cities CASCADE;

CREATE TABLE cities (
    city_id         INT PRIMARY KEY,
    city_name       VARCHAR(50) NOT NULL UNIQUE,
    center_lat      NUMERIC(9,6) NOT NULL,
    center_lng      NUMERIC(9,6) NOT NULL,
    CONSTRAINT chk_cities_coords CHECK (
        center_lat BETWEEN -90.0 AND 90.0 AND
        center_lng BETWEEN -180.0 AND 180.0
    )
);

CREATE TABLE place_categories (
    category_id     INT PRIMARY KEY,
    category_name   VARCHAR(50) NOT NULL UNIQUE
);

CREATE TABLE places (
    place_id                INT PRIMARY KEY,
    plus_code               VARCHAR(20) NOT NULL UNIQUE,
    name                    VARCHAR(255) NOT NULL,
    category_id             INT NOT NULL REFERENCES place_categories(category_id) ON DELETE RESTRICT ON UPDATE CASCADE,
    city_id                 INT NOT NULL REFERENCES cities(city_id) ON DELETE RESTRICT ON UPDATE CASCADE,
    latitude                NUMERIC(9,6) NOT NULL,
    longitude               NUMERIC(9,6) NOT NULL,
    address                 TEXT NOT NULL,
    phone                   VARCHAR(30),
    website                 VARCHAR(255),
    price_level             SMALLINT,
    avg_rating              NUMERIC(2,1),
    review_count            INT NOT NULL DEFAULT 0,
    is_permanently_closed   BOOLEAN NOT NULL DEFAULT FALSE,
    created_at              TIMESTAMPTZ NOT NULL,
    CONSTRAINT chk_places_plus_code CHECK (
        plus_code ~ '^[0-9A-Z]{8}\+[0-9A-Z]{2,3}$'
    ),
    CONSTRAINT chk_places_coords CHECK (
        latitude BETWEEN -90.0 AND 90.0 AND
        longitude BETWEEN -180.0 AND 180.0
    ),
    CONSTRAINT chk_places_price_level CHECK (
        price_level IS NULL OR price_level BETWEEN 1 AND 4
    ),
    CONSTRAINT chk_places_rating CHECK (
        avg_rating IS NULL OR avg_rating BETWEEN 1.0 AND 5.0
    ),
    CONSTRAINT chk_places_review_count CHECK (
        review_count >= 0
    )
);

CREATE TABLE opening_hours (
    place_id        INT NOT NULL REFERENCES places(place_id) ON DELETE CASCADE ON UPDATE CASCADE,
    weekday         SMALLINT NOT NULL,
    opens           TIME NOT NULL,
    closes          TIME NOT NULL,
    PRIMARY KEY (place_id, weekday),
    CONSTRAINT chk_opening_hours_weekday CHECK (
        weekday BETWEEN 1 AND 7
    )
);

CREATE TABLE users (
    user_id         INT PRIMARY KEY,
    display_name    VARCHAR(100) NOT NULL,
    email           VARCHAR(255) NOT NULL UNIQUE,
    home_city_id    INT REFERENCES cities(city_id) ON DELETE SET NULL ON UPDATE CASCADE,
    is_local_guide  BOOLEAN NOT NULL DEFAULT FALSE,
    guide_level     SMALLINT,
    created_at      TIMESTAMPTZ NOT NULL,
    CONSTRAINT chk_users_email CHECK (
        email ~* '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$'
    ),
    CONSTRAINT chk_users_guide_level CHECK (
        (is_local_guide = TRUE AND guide_level BETWEEN 1 AND 10) OR
        (is_local_guide = FALSE AND guide_level IS NULL)
    )
);

CREATE TABLE place_reviews (
    review_id       INT PRIMARY KEY,
    place_id        INT NOT NULL REFERENCES places(place_id) ON DELETE CASCADE ON UPDATE CASCADE,
    user_id         INT NOT NULL REFERENCES users(user_id) ON DELETE CASCADE ON UPDATE CASCADE,
    rating          SMALLINT NOT NULL,
    review_text     TEXT,
    photo_count     INT NOT NULL DEFAULT 0,
    created_at      TIMESTAMPTZ NOT NULL,
    CONSTRAINT uq_place_reviews_user_place UNIQUE (place_id, user_id),
    CONSTRAINT chk_reviews_rating CHECK (
        rating BETWEEN 1 AND 5
    ),
    CONSTRAINT chk_reviews_photos CHECK (
        photo_count >= 0
    )
);

CREATE TABLE saved_places (
    user_id         INT NOT NULL REFERENCES users(user_id) ON DELETE CASCADE ON UPDATE CASCADE,
    place_id        INT NOT NULL REFERENCES places(place_id) ON DELETE CASCADE ON UPDATE CASCADE,
    list_name       VARCHAR(50) NOT NULL,
    saved_at        TIMESTAMPTZ NOT NULL,
    PRIMARY KEY (user_id, place_id, list_name),
    CONSTRAINT chk_saved_list_name CHECK (
        list_name IN ('Favourites', 'Starred', 'Travel plans', 'Want to go')
    )
);

CREATE TABLE road_segments (
    segment_id          INT PRIMARY KEY,
    road_name           VARCHAR(255) NOT NULL,
    city_id             INT NOT NULL REFERENCES cities(city_id) ON DELETE RESTRICT ON UPDATE CASCADE,
    road_type           VARCHAR(20) NOT NULL,
    start_lat           NUMERIC(9,6) NOT NULL,
    start_lng           NUMERIC(9,6) NOT NULL,
    end_lat             NUMERIC(9,6) NOT NULL,
    end_lng             NUMERIC(9,6) NOT NULL,
    length_m            INT NOT NULL,
    speed_limit_kmph    INT NOT NULL,
    CONSTRAINT chk_road_segments_type CHECK (
        road_type IN ('ARTERIAL', 'HIGHWAY', 'LOCAL')
    ),
    CONSTRAINT chk_road_segments_coords CHECK (
        start_lat BETWEEN -90.0 AND 90.0 AND
        start_lng BETWEEN -180.0 AND 180.0 AND
        end_lat BETWEEN -90.0 AND 90.0 AND
        end_lng BETWEEN -180.0 AND 180.0
    ),
    CONSTRAINT chk_road_segments_metrics CHECK (
        length_m > 0 AND
        speed_limit_kmph > 0
    )
);

CREATE TABLE traffic_readings (
    reading_id          BIGINT PRIMARY KEY,
    segment_id          INT NOT NULL REFERENCES road_segments(segment_id) ON DELETE CASCADE ON UPDATE CASCADE,
    recorded_at         TIMESTAMPTZ NOT NULL,
    avg_speed_kmph      NUMERIC(5,2) NOT NULL,
    congestion_level    VARCHAR(20) NOT NULL,
    CONSTRAINT uq_traffic_segment_recorded UNIQUE (segment_id, recorded_at),
    CONSTRAINT chk_traffic_speed CHECK (
        avg_speed_kmph >= 0
    ),
    CONSTRAINT chk_traffic_congestion CHECK (
        congestion_level IN ('LOW', 'MODERATE', 'HEAVY', 'STANDSTILL')
    )
);

CREATE TABLE navigation_sessions (
    session_id          BIGINT PRIMARY KEY,
    user_id             INT REFERENCES users(user_id) ON DELETE SET NULL ON UPDATE CASCADE,
    origin_place_id     INT REFERENCES places(place_id) ON DELETE SET NULL ON UPDATE CASCADE,
    origin_lat          NUMERIC(9,6) NOT NULL,
    origin_lng          NUMERIC(9,6) NOT NULL,
    dest_place_id       INT NOT NULL REFERENCES places(place_id) ON DELETE RESTRICT ON UPDATE CASCADE,
    travel_mode         VARCHAR(20) NOT NULL,
    started_at          TIMESTAMPTZ NOT NULL,
    distance_km         NUMERIC(6,2) NOT NULL,
    eta_minutes         INT NOT NULL,
    actual_minutes      INT,
    rerouted_count      INT NOT NULL DEFAULT 0,
    status              VARCHAR(20) NOT NULL,
    CONSTRAINT chk_nav_coords CHECK (
        origin_lat BETWEEN -90.0 AND 90.0 AND
        origin_lng BETWEEN -180.0 AND 180.0
    ),
    CONSTRAINT chk_nav_travel_mode CHECK (
        travel_mode IN ('DRIVE', 'TRANSIT', 'TWO_WHEELER', 'WALK')
    ),
    CONSTRAINT chk_nav_status CHECK (
        status IN ('CANCELLED', 'COMPLETED', 'IN_PROGRESS')
    ),
    CONSTRAINT chk_nav_status_completion CHECK (
        (status = 'COMPLETED' AND actual_minutes IS NOT NULL AND actual_minutes > 0) OR
        (status IN ('IN_PROGRESS', 'CANCELLED') AND actual_minutes IS NULL)
    ),
    CONSTRAINT chk_nav_metrics CHECK (
        distance_km >= 0 AND
        eta_minutes >= 0 AND
        rerouted_count >= 0
    )
);

CREATE TABLE incident_reports (
    report_id           INT PRIMARY KEY,
    segment_id          INT NOT NULL REFERENCES road_segments(segment_id) ON DELETE CASCADE ON UPDATE CASCADE,
    user_id             INT REFERENCES users(user_id) ON DELETE SET NULL ON UPDATE CASCADE,
    incident_type       VARCHAR(20) NOT NULL,
    reported_at         TIMESTAMPTZ NOT NULL,
    expires_at          TIMESTAMPTZ NOT NULL,
    upvotes             INT NOT NULL DEFAULT 0,
    CONSTRAINT chk_incidents_type CHECK (
        incident_type IN ('ACCIDENT', 'BREAKDOWN', 'CLOSURE', 'POLICE', 'ROADWORK', 'WATERLOGGING')
    ),
    CONSTRAINT chk_incidents_lifecycle CHECK (
        expires_at > reported_at
    ),
    CONSTRAINT chk_incidents_upvotes CHECK (
        upvotes >= 0
    )
);
