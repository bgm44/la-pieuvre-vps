-- Base pour le cockpit La Pieuvre
CREATE DATABASE cockpit;

-- Base pour le projet Touriz
CREATE DATABASE touriz;

-- App user (password set via COCKPIT_DB_PASSWORD env or default)
CREATE USER app WITH PASSWORD 'changeme';

GRANT ALL PRIVILEGES ON DATABASE cockpit TO app;
GRANT ALL PRIVILEGES ON DATABASE touriz TO app;
