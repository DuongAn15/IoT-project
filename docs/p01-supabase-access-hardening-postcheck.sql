-- P01 post-check: read only. Run each SELECT separately in Supabase SQL Editor.
-- This file reads catalog metadata only; it does not return table rows or change ACLs.
-- Run it in the same project where the P01 hardening draft was applied.

-- 1. RLS must remain enabled on both tables.
select ns.nspname as schema_name,
       tbl.relname as table_name,
       tbl.relrowsecurity as rls_enabled,
       tbl.relforcerowsecurity as force_rls
from pg_class tbl
join pg_namespace ns on ns.oid = tbl.relnamespace
where ns.nspname = 'public'
  and tbl.relname in ('devices', 'weather_logs')
order by tbl.relname;

-- 2. Expected: no policies on these two tables after the current hardening draft.
select schemaname, tablename, policyname, roles, cmd, qual, with_check
from pg_policies
where schemaname = 'public'
  and tablename in ('devices', 'weather_logs')
order by tablename, policyname;

-- 3. Expected: no anon/authenticated table-level grants; service_role grants remain.
select table_schema, table_name, grantee, privilege_type, is_grantable
from information_schema.role_table_grants
where table_schema = 'public'
  and table_name in ('devices', 'weather_logs')
  and grantee in ('anon', 'authenticated', 'service_role')
order by table_name, grantee, privilege_type;

-- 4. Expected: no anon/authenticated column-level grants; service_role grants remain.
select table_schema,
       table_name,
       grantee,
       privilege_type,
       is_grantable,
       count(*) as column_count,
       array_agg(column_name order by column_name) as columns
from information_schema.column_privileges
where table_schema = 'public'
  and table_name in ('devices', 'weather_logs')
  and grantee in ('anon', 'authenticated', 'service_role')
group by table_schema, table_name, grantee, privilege_type, is_grantable
order by table_name, grantee, privilege_type;
