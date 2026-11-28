-- Operation ledger: apply in the Supabase SQL editor before deploying the backend.
-- Only the backend service_role may access these tables and functions.
CREATE TABLE IF NOT EXISTS public.station_state (
  device_id text PRIMARY KEY REFERENCES public.devices(device_id) ON DELETE RESTRICT,
  desired_version integer NOT NULL DEFAULT 0 CHECK (desired_version >= 0),
  desired_config jsonb NOT NULL DEFAULT '{"temp_max":38,"temp_min":10,"humi_max":90,"wind_max":15,"rain_max":30,"auto_warning":true,"buzzer":true}'::jsonb,
  reported_version integer NOT NULL DEFAULT 0 CHECK (reported_version >= 0),
  reported_config jsonb,
  last_ack_at timestamptz
);
CREATE TABLE IF NOT EXISTS public.device_operations (
  device_id text NOT NULL REFERENCES public.devices(device_id) ON DELETE RESTRICT,
  operation_id text NOT NULL,
  kind text NOT NULL CHECK (kind IN ('config','command')),
  status text NOT NULL DEFAULT 'queued' CHECK (status IN ('queued','published','accepted','persisted','applied','failed','expired')),
  desired_version integer,
  payload jsonb NOT NULL,
  snapshot jsonb,
  expected_version integer,
  deployment_id text,
  expires_at timestamptz NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  broker_acked_at timestamptz,
  device_acked_at timestamptz,
  ack_boot_id text,
  error_code text,
  error_message text,
  attempts integer NOT NULL DEFAULT 0,
  next_attempt_at timestamptz NOT NULL DEFAULT now(),
  lease_until timestamptz,
  PRIMARY KEY (device_id, operation_id)
);
CREATE INDEX IF NOT EXISTS device_operations_outbox_due ON public.device_operations(next_attempt_at)
  WHERE status IN ('queued','published');
CREATE INDEX IF NOT EXISTS device_operations_recent ON public.device_operations(device_id, created_at DESC);
ALTER TABLE public.station_state ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.device_operations ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.station_state, public.device_operations FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE ON public.station_state, public.device_operations TO service_role;

CREATE OR REPLACE FUNCTION public.create_device_operation(
  p_device text, p_kind text, p_payload jsonb, p_request text,
  p_expected integer, p_expires timestamptz, p_deployment text
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE st public.station_state%ROWTYPE; old_op public.device_operations%ROWTYPE;
  new_op public.device_operations%ROWTYPE; merged jsonb; op_id text;
BEGIN
  IF p_kind NOT IN ('command','config') OR p_payload IS NULL OR jsonb_typeof(p_payload) <> 'object'
     OR p_expires <= now() OR p_device IS NULL OR p_device = '' THEN
    RAISE EXCEPTION 'invalid_operation' USING ERRCODE = '22023';
  END IF;
  INSERT INTO public.station_state(device_id) VALUES (p_device) ON CONFLICT DO NOTHING;
  SELECT * INTO st FROM public.station_state WHERE device_id = p_device FOR UPDATE;
  op_id := coalesce(nullif(trim(p_request), ''), p_kind || '-' || gen_random_uuid()::text);
  SELECT * INTO old_op FROM public.device_operations
    WHERE device_id = p_device AND operation_id = op_id;
  IF FOUND THEN
    IF old_op.kind <> p_kind OR old_op.payload <> p_payload
      OR old_op.expected_version IS DISTINCT FROM p_expected THEN
      RAISE EXCEPTION 'request_id_conflict' USING ERRCODE = '23505';
    END IF;
    RETURN jsonb_build_object('operation', to_jsonb(old_op), 'duplicate', true);
  END IF;
  IF p_kind = 'config' THEN
    IF p_expected IS NOT NULL AND p_expected <> st.desired_version THEN
      RAISE EXCEPTION 'version_conflict:%', st.desired_version USING ERRCODE = '40001';
    END IF;
    merged := st.desired_config || p_payload;
    IF (merged->>'temp_min')::numeric >= (merged->>'temp_max')::numeric
      OR (merged->>'temp_min')::numeric < -40 OR (merged->>'temp_max')::numeric > 80
      OR (merged->>'humi_max')::numeric NOT BETWEEN 0 AND 100
      OR (merged->>'wind_max')::numeric NOT BETWEEN 0 AND 100
      OR (merged->>'rain_max')::numeric NOT BETWEEN 0 AND 500 THEN
      RAISE EXCEPTION 'invalid_config' USING ERRCODE = '22023';
    END IF;
    UPDATE public.station_state SET desired_version = st.desired_version + 1,
      desired_config = merged WHERE device_id = p_device;
  END IF;
  INSERT INTO public.device_operations(device_id, operation_id, kind, desired_version, payload,
    snapshot, expected_version, deployment_id, expires_at)
  VALUES (p_device, op_id, p_kind,
    CASE WHEN p_kind = 'config' THEN st.desired_version + 1 END,
    p_payload, CASE WHEN p_kind = 'config' THEN merged END,
    p_expected, p_deployment, p_expires)
  RETURNING * INTO new_op;
  RETURN jsonb_build_object('operation', to_jsonb(new_op), 'duplicate', false);
END $$;

CREATE OR REPLACE FUNCTION public.claim_device_operations(p_limit integer DEFAULT 20)
RETURNS SETOF public.device_operations LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  UPDATE public.device_operations SET status = 'expired', updated_at = now()
    WHERE status IN ('queued','published','accepted','persisted') AND expires_at <= now();
  RETURN QUERY
    WITH due AS (
      SELECT device_id, operation_id FROM public.device_operations
      WHERE status IN ('queued','published') AND expires_at > now() AND next_attempt_at <= now()
        AND (lease_until IS NULL OR lease_until <= now())
      ORDER BY created_at FOR UPDATE SKIP LOCKED LIMIT LEAST(greatest(p_limit, 1), 100)
    )
    UPDATE public.device_operations op SET lease_until = now() + interval '30 seconds',
      attempts = attempts + 1, updated_at = now()
    FROM due WHERE op.device_id = due.device_id AND op.operation_id = due.operation_id
    RETURNING op.*;
END $$;

CREATE OR REPLACE FUNCTION public.publish_device_operation_result(p_device text, p_operation text, p_published boolean)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  UPDATE public.device_operations SET
    status = CASE WHEN p_published AND status = 'queued' THEN 'published' ELSE status END,
    broker_acked_at = CASE WHEN p_published THEN now() ELSE broker_acked_at END,
    next_attempt_at = now() + CASE WHEN p_published THEN interval '10 seconds' ELSE interval '5 seconds' END,
    lease_until = NULL, updated_at = now(),
    error_code = CASE WHEN p_published THEN NULL ELSE 'broker_publish_unknown' END
  WHERE device_id = p_device AND operation_id = p_operation AND status IN ('queued','published');
END $$;

CREATE OR REPLACE FUNCTION public.apply_device_operation_ack(p_device text, p_ack jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE op public.device_operations%ROWTYPE; result_status text;
BEGIN
  SELECT * INTO op FROM public.device_operations
    WHERE device_id = p_device AND operation_id = p_ack->>'request_id' FOR UPDATE;
  IF NOT FOUND OR op.status IN ('applied','failed') THEN RETURN NULL; END IF;
  IF p_ack->>'device_id' IS DISTINCT FROM p_device OR p_ack->>'kind' IS DISTINCT FROM op.kind
     OR (op.deployment_id IS NOT NULL AND p_ack->>'deployment_id' IS DISTINCT FROM op.deployment_id)
     OR (op.kind = 'config' AND (p_ack->>'version')::integer IS DISTINCT FROM op.desired_version) THEN
    RETURN NULL;
  END IF;
  result_status := CASE WHEN p_ack->>'status' = 'rejected' THEN 'failed' ELSE p_ack->>'status' END;
  IF result_status NOT IN ('accepted','persisted','applied','failed') THEN RETURN NULL; END IF;
  UPDATE public.device_operations SET status = result_status, device_acked_at = now(),
    ack_boot_id = p_ack->>'boot_id', updated_at = now(), lease_until = NULL,
    error_code = CASE WHEN result_status = 'failed' THEN coalesce(p_ack->>'error_code', 'device_failed') END,
    error_message = CASE WHEN result_status = 'failed' THEN p_ack->>'error_message' END
    WHERE device_id = p_device AND operation_id = op.operation_id;
  IF op.kind = 'config' AND result_status IN ('persisted','applied') THEN
    UPDATE public.station_state SET reported_version = op.desired_version,
      reported_config = op.snapshot, last_ack_at = now()
      WHERE device_id = p_device AND reported_version <= op.desired_version;
  END IF;
  RETURN jsonb_build_object('operation_id', op.operation_id, 'status', result_status);
END $$;
REVOKE ALL ON FUNCTION public.create_device_operation(text,text,jsonb,text,integer,timestamptz,text),
  public.claim_device_operations(integer), public.publish_device_operation_result(text,text,boolean),
  public.apply_device_operation_ack(text,jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.create_device_operation(text,text,jsonb,text,integer,timestamptz,text),
  public.claim_device_operations(integer), public.publish_device_operation_result(text,text,boolean),
  public.apply_device_operation_ack(text,jsonb) TO service_role;

NOTIFY pgrst, 'reload schema';
