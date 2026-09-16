-- Runs once, on first container start against an empty data directory
-- (Postgres's docker-entrypoint-initdb.d convention). Re-running this
-- file by hand is safe too -- IF NOT EXISTS makes it idempotent.
CREATE EXTENSION IF NOT EXISTS vector;
