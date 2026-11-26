-- P01 draft: remove direct anon/authenticated access to audited tables.
-- USER REPORTS THIS SCRIPT RAN SUCCESSFULLY on the live project.
-- User has provided read-only post-check output: RLS remains enabled, policy
-- query returned no rows, and anon/authenticated grants are absent while
-- service_role grants remain. User screenshot confirms normal telemetry writes
-- continue after hardening; user also reports the app reads normally. Explicit
-- anon REST denial remains untested.
-- This script changes privileges/policies only; it does not delete or alter rows.
-- The backend must use SUPABASE_SERVICE_ROLE_KEY (configured first in backend
-- key selection). This draft intentionally leaves service_role and postgres ACLs
-- unchanged. The current repo source scan found no direct Supabase client usage
-- in Flutter lib/ or firmware src/; user confirms no app/client accesses Supabase directly.

BEGIN;

-- The audit found these permissive policies on public.weather_logs.
DROP POLICY IF EXISTS "Allow anonymous insert" ON public.weather_logs;
DROP POLICY IF EXISTS "Allow anonymous select" ON public.weather_logs;

-- Remove table-level privileges, including DELETE/TRUNCATE and other privileges
-- that RLS does not filter. RLS remains enabled; service_role is not modified.
REVOKE ALL PRIVILEGES
ON TABLE public.devices, public.weather_logs
FROM anon, authenticated;

-- Column-level ACLs are independent of table-level grants; revoke them explicitly.
REVOKE SELECT (device_id, name, mac, temp_max, temp_min, humi_max, wind_max, rain_max, auto_warning, buzzer),
       INSERT (device_id, name, mac, temp_max, temp_min, humi_max, wind_max, rain_max, auto_warning, buzzer),
       UPDATE (device_id, name, mac, temp_max, temp_min, humi_max, wind_max, rain_max, auto_warning, buzzer),
       REFERENCES (device_id, name, mac, temp_max, temp_min, humi_max, wind_max, rain_max, auto_warning, buzzer)
ON TABLE public.devices
FROM anon, authenticated;

REVOKE SELECT (id, created_at, device_id, temperature, humidity, rain_rate, wind_speed),
       INSERT (id, created_at, device_id, temperature, humidity, rain_rate, wind_speed),
       UPDATE (id, created_at, device_id, temperature, humidity, rain_rate, wind_speed),
       REFERENCES (id, created_at, device_id, temperature, humidity, rain_rate, wind_speed)
ON TABLE public.weather_logs
FROM anon, authenticated;

COMMIT;

-- After the reported application:
-- 1. Run the read-only post-check and confirm anon/authenticated have no table- or
--    column-level privileges on these two tables and no weather_logs policies.
-- 2. Confirm backend read/write still works using its service-role credential.
-- 3. Confirm anonymous direct REST access is denied. Do not restore the broad
--    grants/policies as an application rollback; correct the backend credential
--    or implement a narrowly scoped, reviewed access policy instead.
