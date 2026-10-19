-- Run once by the official postgres image on the first boot of the volume
-- (against POSTGRES_DB=nde, as the nde user — a superuser inside the container).
--
-- pg_trgm: trigram index used by the configuration search.
CREATE EXTENSION IF NOT EXISTS pg_trgm;
