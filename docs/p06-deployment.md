# P06 deployment: config and command operations

## Before deployment

1. Review and apply [`p06-operations-migration.sql`](p06-operations-migration.sql) (or [`p06-operations-rename-migration.sql`](p06-operations-rename-migration.sql) if upgrading from `p06_*` names) in the Supabase SQL editor with a database administrator account. This creates `station_state`, `device_operations`, and four transactional RPC functions. No live migration is performed by the repository build.
2. Keep `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` configured on the backend. The service role key must stay server-side. A missing migration makes operation endpoints return 503; the backend does not silently reset the desired version.
3. If a previous P06 backend already wrote `data/operation-ledger.json`, preserve it and reconcile its desired version/config with the station before cutover. The new DB starts at version 0 and cannot infer an existing NVS version; do not discard that file or enable writes until reconciled.
4. Set `DEVICE_DEPLOYMENTS` so each station is bound to its current firmware deployment ID. Deploy the P06 firmware before using the new operation endpoints.
5. Start one backend instance, verify `GET /api/devices/{id}/state`, then test a config update and a command. Confirm the operation progresses from `queued`/`published` to `applied` and the ACK topic is subscribed before publishing.
6. Restart the backend and verify the operation and desired/reported versions remain. Then test a disconnected broker, reconnect, a lost device ACK, and a device reboot after a side-effect command.

## Runtime behavior

- PostgreSQL atomically creates the desired config and operation. `(device_id, operation_id)` prevents duplicate client requests. Workers claim due rows using `FOR UPDATE SKIP LOCKED` and a lease; broker uncertainty remains retryable with the same ID.
- A published operation is retried every 10 seconds until the device ACK arrives or its TTL expires. The device stores command IDs in NVS for at least the maximum command TTL. If all 64 ID slots are still within retention, it rejects new side-effect commands instead of evicting an active ID.
- Firmware persists a pending/applied command marker around side effects and stores up to eight ACK messages in NVS. A power cut between marker and effect yields an *unknown* result rather than claiming `applied`; exactly-once execution of a physical side effect cannot be guaranteed across that cut.
- The local JSON ledger is kept only for isolated legacy tests; deployed operation routes use Supabase RPCs. The P06 migration must be applied before the backend is deployed.

## Verification limits

Repository tests mock the database and MQTT broker. The SQL migration, ESP32 NVS power-cut behavior, and broker/device end-to-end flow still need staging verification before enabling production traffic.
