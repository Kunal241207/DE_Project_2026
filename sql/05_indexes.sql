SET search_path TO gmaps;

DROP INDEX IF EXISTS idx_nav_started_at;
CREATE INDEX idx_nav_started_at ON navigation_sessions (started_at);

DROP INDEX IF EXISTS idx_nav_status_started;
CREATE INDEX idx_nav_status_started ON navigation_sessions (status, started_at)
    WHERE status = 'COMPLETED';

DROP INDEX IF EXISTS idx_nav_dest_place_id;
CREATE INDEX idx_nav_dest_place_id ON navigation_sessions (dest_place_id);

DROP INDEX IF EXISTS idx_nav_origin_place_id;
CREATE INDEX idx_nav_origin_place_id ON navigation_sessions (origin_place_id);

DROP INDEX IF EXISTS idx_places_city_category;
CREATE INDEX idx_places_city_category ON places (city_id, category_id);

DROP INDEX IF EXISTS idx_places_lat_lng;
CREATE INDEX idx_places_lat_lng ON places (latitude, longitude);

DROP INDEX IF EXISTS idx_places_closed;
CREATE INDEX idx_places_closed ON places (place_id)
    WHERE is_permanently_closed = TRUE;

DROP INDEX IF EXISTS idx_reviews_created_at;
CREATE INDEX idx_reviews_created_at ON place_reviews (created_at);

DROP INDEX IF EXISTS idx_reviews_created_at_desc;
CREATE INDEX idx_reviews_created_at_desc ON place_reviews (created_at DESC);

DROP INDEX IF EXISTS idx_opening_hours_place_weekday;
CREATE INDEX idx_opening_hours_place_weekday ON opening_hours (place_id, weekday);

DROP INDEX IF EXISTS idx_traffic_congestion_recorded;
CREATE INDEX idx_traffic_congestion_recorded ON traffic_readings (congestion_level, recorded_at DESC);

DROP INDEX IF EXISTS idx_incidents_reported_at;
CREATE INDEX idx_incidents_reported_at ON incident_reports (reported_at);

DROP INDEX IF EXISTS idx_incidents_expires_at;
CREATE INDEX idx_incidents_expires_at ON incident_reports (expires_at);
