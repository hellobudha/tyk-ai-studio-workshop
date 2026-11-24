-- A separate database for the claims handbook's vector index (Act 5).
-- AI Studio's own data stays in the "studio" database.
CREATE DATABASE vectors;
\connect vectors
CREATE EXTENSION IF NOT EXISTS vector;
