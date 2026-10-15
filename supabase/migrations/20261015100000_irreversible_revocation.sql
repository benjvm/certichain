-- 10A. No backfill, Storage mutation, public projection or new anchors.
ALTER TABLE public.certificates ADD CONSTRAINT revocation_certificate_institution UNIQUE(id,institution_id);
CREATE TABLE certichain_private.certificate_revocations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  certificate_id uuid NOT NULL UNIQUE REFERENCES public.certificates ON DELETE RESTRICT,
  institution_id uuid NOT NULL REFERENCES public.institutions ON DELETE RESTRICT,
  requested_by uuid NOT NULL REFERENCES public.profiles ON DELETE RESTRICT,
  requested_role public.institution_role NOT NULL CHECK (requested_role IN ('owner','admin')),
  reason text NOT NULL CHECK (char_length(reason) BETWEEN 1 AND 500),
  revoked_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(id,certificate_id,institution_id),
  FOREIGN KEY(certificate_id,institution_id) REFERENCES public.certificates(id,institution_id) ON DELETE RESTRICT
);
-- Aliases retain every accepted key, including keys used after logical revocation.
CREATE TABLE certichain_private.certificate_revocation_keys (
  institution_id uuid NOT NULL REFERENCES public.institutions ON DELETE RESTRICT,
  idempotency_key uuid NOT NULL,
  certificate_id uuid NOT NULL REFERENCES public.certificates ON DELETE RESTRICT,
  request_id uuid,
  fingerprint bytea NOT NULL CHECK (octet_length(fingerprint)=32),
  actor_id uuid NOT NULL REFERENCES public.profiles ON DELETE RESTRICT,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  PRIMARY KEY(institution_id,idempotency_key),
  FOREIGN KEY(certificate_id,institution_id) REFERENCES public.certificates(id,institution_id) ON DELETE RESTRICT,
  FOREIGN KEY(request_id,certificate_id,institution_id)
    REFERENCES certichain_private.certificate_revocations(id,certificate_id,institution_id) ON DELETE RESTRICT
);
CREATE FUNCTION certichain_private.revocation_immutable() RETURNS trigger
LANGUAGE plpgsql SET search_path='' AS $$
BEGIN
  RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='revocation_history_protected';
END $$;
DO $$ DECLARE t text; BEGIN
  FOREACH t IN ARRAY ARRAY['certificate_revocations','certificate_revocation_keys'] LOOP
    EXECUTE format('ALTER TABLE certichain_private.%I ENABLE ROW LEVEL SECURITY',t);
    EXECUTE format('REVOKE ALL ON certichain_private.%I FROM PUBLIC,anon,authenticated,service_role',t);
    EXECUTE format('CREATE TRIGGER revocation_immutable BEFORE UPDATE OR DELETE OR TRUNCATE ON certichain_private.%I FOR EACH STATEMENT EXECUTE FUNCTION certichain_private.revocation_immutable()',t);
  END LOOP;
END $$;

-- Caller holds the institutional parent lock, shared with administration/issuance.
CREATE FUNCTION certichain_private.authorize_revocation(p_institution uuid,p_actor uuid)
RETURNS void LANGUAGE plpgsql SET search_path='' AS $$
BEGIN
  IF NOT EXISTS(SELECT 1 FROM public.institutions i
    JOIN public.institution_members m ON m.institution_id=i.id
    JOIN auth.users u ON u.id=m.user_id
    WHERE i.id=p_institution AND i.verification_status IN ('verified','suspended')
      AND m.user_id=p_actor AND m.role IN ('owner','admin')
      AND u.deleted_at IS NULL AND NOT coalesce(u.is_anonymous,false)
      AND (u.banned_until IS NULL OR u.banned_until<=clock_timestamp())) THEN
    RAISE EXCEPTION USING ERRCODE='PT404',MESSAGE='revocation_unavailable';
  END IF;
END $$;

-- Earlier platform bypass never overrides irreversible state/identity, even on legacy rows.
CREATE FUNCTION certichain_private.protect_revoked_certificate() RETURNS trigger
LANGUAGE plpgsql SET search_path='' AS $$
BEGIN
  IF TG_OP='DELETE' THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='certificate_history_protected';
  END IF;
  IF OLD.status='revoked' AND NEW IS DISTINCT FROM OLD THEN
    RAISE EXCEPTION 'Institution administrators may only revoke certificates';
  END IF;
  IF ROW(NEW.id,NEW.institution_id,NEW.holder_id,NEW.issued_by,NEW.credential_code)
    IS DISTINCT FROM ROW(OLD.id,OLD.institution_id,OLD.holder_id,OLD.issued_by,OLD.credential_code) THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='certificate_identity_immutable';
  END IF;
  IF OLD.status='active' AND NEW.status='revoked' THEN NEW.revoked_at:=now(); END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER certificates_00_revocation_guard BEFORE UPDATE OR DELETE ON public.certificates
FOR EACH ROW EXECUTE FUNCTION certichain_private.protect_revoked_certificate();

-- A cancellation is only possible before any durable signature. Public enum stays unchanged.
ALTER TABLE certichain_private.blockchain_operations DROP CONSTRAINT blockchain_operations_state_check;
ALTER TABLE certichain_private.blockchain_operations ADD CONSTRAINT blockchain_operations_state_check
  CHECK (state IN ('requested','prepared','submitted','included','confirmed','reorged','blocked','failed','divergence','cancelled'));

CREATE FUNCTION public.request_certificate_revocation(p_actor uuid,p_certificate uuid,p_key uuid,p_reason text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE c public.certificates; r certichain_private.certificate_revocations;
  k certichain_private.certificate_revocation_keys; a certichain_private.certificate_anchors;
  op certichain_private.blockchain_operations; canonical text; fingerprint bytea; created boolean:=false;
BEGIN
  -- Normalize in SQL as well as the HTTP boundary; SQL owns the canonical fingerprint.
  canonical:=btrim(replace(replace(normalize(p_reason,NFC),E'\r\n',E'\n'),E'\r',E'\n'),E' \t\n');
  IF p_key IS NULL OR canonical IS NULL OR char_length(canonical) NOT BETWEEN 1 AND 500
    OR canonical ~ '[\x01-\x08\x0B\x0C\x0E-\x1F\x7F]' THEN
    RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='invalid_input';
  END IF;
  SELECT * INTO c FROM public.certificates WHERE id=p_certificate;
  PERFORM 1 FROM public.institutions WHERE id=c.institution_id FOR UPDATE;
  PERFORM certichain_private.authorize_revocation(c.institution_id,p_actor);
  PERFORM 1 FROM public.certificate_issuance_operations WHERE id=c.issuance_operation_id FOR SHARE;
  SELECT * INTO c FROM public.certificates WHERE id=p_certificate FOR UPDATE;
  IF c.id IS NULL THEN RAISE EXCEPTION USING ERRCODE='PT404',MESSAGE='revocation_unavailable'; END IF;
  fingerprint:=extensions.digest(convert_to('certichain:revocation-request:v1','UTF8')||decode('00','hex')
    ||uuid_send(c.id)||convert_to(canonical,'UTF8'),'sha256');
  SELECT * INTO k FROM certichain_private.certificate_revocation_keys
    WHERE institution_id=c.institution_id AND idempotency_key=p_key;
  IF k.idempotency_key IS NOT NULL THEN
    IF k.fingerprint<>fingerprint OR k.certificate_id<>c.id THEN
      RAISE EXCEPTION USING ERRCODE='23505',MESSAGE='idempotency_conflict';
    END IF;
    RETURN public.certificate_revocation_progress(p_actor,c.id)||jsonb_build_object('created',false);
  END IF;
  SELECT * INTO r FROM certichain_private.certificate_revocations WHERE certificate_id=c.id;
  IF c.status='active' THEN
    INSERT INTO certichain_private.certificate_revocations(certificate_id,institution_id,requested_by,requested_role,reason)
      SELECT c.id,c.institution_id,p_actor,m.role,canonical FROM public.institution_members m
      WHERE m.institution_id=c.institution_id AND m.user_id=p_actor RETURNING * INTO r;
    UPDATE public.certificates SET status='revoked',revoked_at=r.revoked_at WHERE id=c.id;
    created:=true;
  END IF;
    -- Enumerate ALL deployments, even disabled ones. No new salts or anchors.
    FOR a IN SELECT * FROM certichain_private.certificate_anchors WHERE certificate_id=c.id ORDER BY deployment_id,id LOOP
      PERFORM 1 FROM certichain_private.blockchain_issuers WHERE id=a.issuer_binding_id FOR UPDATE;
      PERFORM 1 FROM certichain_private.certificate_anchors WHERE id=a.id FOR UPDATE;
      SELECT * INTO op FROM certichain_private.blockchain_operations WHERE anchor_id=a.id AND kind='issue' FOR UPDATE;
      IF NOT EXISTS(SELECT 1 FROM certichain_private.blockchain_transaction_attempts WHERE operation_id=op.id) THEN
        UPDATE certichain_private.blockchain_operations SET state='cancelled',lease_token=NULL,lease_until=NULL,
          generation=generation+1,updated_at=clock_timestamp() WHERE id=op.id AND state<>'cancelled';
        -- Unpersisted signatures cannot broadcast under persist-before-broadcast/CAS.
        UPDATE certichain_private.blockchain_signer_nonces SET active_operation_id=NULL,reserved_nonce=NULL
          WHERE active_operation_id=op.id;
      ELSE
        INSERT INTO certichain_private.blockchain_operations(anchor_id,issuer_binding_id,deployment_id,kind,
          requested_by,authorized_by,idempotency_key,payload_digest)
          VALUES(a.id,a.issuer_binding_id,a.deployment_id,'revoke',p_actor,p_actor,gen_random_uuid(),
            extensions.digest(decode('b75c7dc6','hex')||a.certificate_key,'sha256'))
          ON CONFLICT (anchor_id,kind) WHERE anchor_id IS NOT NULL DO NOTHING;
      END IF;
    END LOOP;
  -- Historical revoked rows keep their original date and NULL request; no fabricated audit.
  INSERT INTO certichain_private.certificate_revocation_keys(institution_id,idempotency_key,certificate_id,request_id,fingerprint,actor_id)
    VALUES(c.institution_id,p_key,c.id,r.id,fingerprint,p_actor);
  RETURN public.certificate_revocation_progress(p_actor,c.id)||jsonb_build_object('created',created);
END $$;

CREATE FUNCTION public.certificate_revocation_progress(p_actor uuid,p_certificate uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE c public.certificates; r certichain_private.certificate_revocations; sync jsonb;
BEGIN
  SELECT * INTO c FROM public.certificates WHERE id=p_certificate;
  PERFORM 1 FROM public.institutions WHERE id=c.institution_id FOR UPDATE;
  PERFORM certichain_private.authorize_revocation(c.institution_id,p_actor);
  SELECT * INTO c FROM public.certificates WHERE id=p_certificate FOR SHARE;
  SELECT * INTO r FROM certichain_private.certificate_revocations WHERE certificate_id=c.id;
  SELECT coalesce(jsonb_agg(jsonb_build_object('operation_id',o.id,'status',o.state) ORDER BY o.id),'[]') INTO sync
    FROM certichain_private.blockchain_operations o JOIN certichain_private.certificate_anchors a ON a.id=o.anchor_id
    WHERE a.certificate_id=c.id AND o.kind='revoke';
  RETURN jsonb_build_object('certificate_id',c.id,'request_id',r.id,'status',c.status,'revoked_at',c.revoked_at,
    'reason',r.reason,'synchronization',sync);
END $$;

REVOKE ALL ON FUNCTION certichain_private.revocation_immutable(),certichain_private.authorize_revocation(uuid,uuid),
  certichain_private.protect_revoked_certificate() FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.request_certificate_revocation(uuid,uuid,uuid,text),
  public.certificate_revocation_progress(uuid,uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.request_certificate_revocation(uuid,uuid,uuid,text),
  public.certificate_revocation_progress(uuid,uuid) TO service_role;

CREATE FUNCTION public.reauthorize_certificate_revocation(p_actor uuid,p_operation uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE op certichain_private.blockchain_operations; cid uuid;
BEGIN
  op:=certichain_private.blockchain_lock(p_operation);
  IF op.kind<>'revoke' THEN RAISE EXCEPTION USING ERRCODE='PT404',MESSAGE='revocation_unavailable'; END IF;
  SELECT certificate_id INTO cid FROM certichain_private.certificate_anchors WHERE id=op.anchor_id;
  PERFORM public.blockchain_reauthorize(p_actor,p_operation);
  RETURN public.certificate_revocation_progress(p_actor,cid);
END $$;
REVOKE ALL ON FUNCTION public.reauthorize_certificate_revocation(uuid,uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.reauthorize_certificate_revocation(uuid,uuid) TO service_role;

-- 10C: revoke has independent authorization. Existing ledger/fences remain authoritative.
CREATE OR REPLACE FUNCTION certichain_private.blockchain_authorize(o certichain_private.blockchain_operations) RETURNS void LANGUAGE plpgsql SET search_path='' AS $$
DECLARE b certichain_private.blockchain_issuers; a certichain_private.certificate_anchors;
BEGIN
  SELECT * INTO b FROM certichain_private.blockchain_issuers WHERE id=o.issuer_binding_id;
  IF o.state IN ('blocked','failed','divergence','cancelled') THEN RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='authorization_denied'; END IF;
  IF NOT EXISTS(SELECT 1 FROM certichain_private.blockchain_deployments WHERE id=o.deployment_id AND enabled AND NOT writes_stopped) THEN
    RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='authorization_denied'; END IF;
  IF o.kind='set_issuer' THEN
    IF NOT EXISTS(SELECT 1 FROM public.profiles WHERE id=o.authorized_by AND role='platform_admin') OR o.config_version<>b.config_version THEN RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='authorization_denied'; END IF;
  ELSE
    SELECT * INTO a FROM certichain_private.certificate_anchors WHERE id=o.anchor_id;
    IF o.kind='revoke' THEN
      BEGIN
        PERFORM certichain_private.authorize_revocation(b.institution_id,o.authorized_by);
      EXCEPTION WHEN SQLSTATE 'PT404' THEN
        RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='authorization_denied';
      END;
      IF NOT b.desired_can_revoke OR NOT b.observed_can_revoke OR b.sync_state<>'synced' OR b.signer<>b.observed_signer
        OR (NOT EXISTS(SELECT 1 FROM public.certificates c JOIN certichain_private.certificate_revocations r ON r.certificate_id=c.id
          WHERE c.id=a.certificate_id AND c.status='revoked' AND r.revoked_at=c.revoked_at AND r.institution_id=b.institution_id)
        AND NOT EXISTS(SELECT 1 FROM public.certificates c JOIN certichain_private.certificate_revocation_keys k ON k.certificate_id=c.id AND k.institution_id=c.institution_id
          WHERE c.id=a.certificate_id AND c.status='revoked')) THEN
        RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='authorization_denied';
      END IF;
      RETURN;
    END IF;
    PERFORM public.blockchain_anchor_snapshot(o.authorized_by,a.certificate_id,(SELECT environment_id FROM certichain_private.blockchain_deployments WHERE id=o.deployment_id));
    IF o.kind<>'issue' THEN RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='authorization_denied'; END IF;
  END IF;
END $$;

CREATE OR REPLACE FUNCTION public.blockchain_reauthorize(p_actor uuid,p_operation uuid) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE o certichain_private.blockchain_operations; inst uuid; role text;
BEGIN
  o:=certichain_private.blockchain_lock(p_operation);
  SELECT institution_id INTO inst FROM certichain_private.blockchain_issuers WHERE id=o.issuer_binding_id;
  IF o.kind='set_issuer' THEN
    IF NOT EXISTS(SELECT 1 FROM public.profiles WHERE id=p_actor AND profiles.role='platform_admin') THEN RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='authorization_denied'; END IF;
    role:='platform_admin';
  ELSE
    IF o.kind='revoke' THEN PERFORM certichain_private.authorize_revocation(inst,p_actor);
    ELSE PERFORM certichain_private.authorize_issuance(inst,p_actor); END IF;
    SELECT m.role::text INTO role FROM public.institution_members m WHERE institution_id=inst AND user_id=p_actor;
    IF o.kind NOT IN ('issue','revoke') THEN RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='authorization_denied'; END IF;
  END IF;
  IF o.state NOT IN ('blocked','failed') OR o.lease_until>clock_timestamp() OR jsonb_array_length(o.authorizations)>=64 THEN RAISE EXCEPTION USING ERRCODE='PT409',MESSAGE='busy'; END IF;
  -- Reconciliation has to visit every signed attempt after the block/failure.
  IF EXISTS(SELECT 1 FROM certichain_private.blockchain_transaction_attempts WHERE operation_id=o.id AND (observed_at IS NULL OR observed_at<o.updated_at)) THEN RAISE EXCEPTION USING ERRCODE='PT409',MESSAGE='busy'; END IF;
  UPDATE certichain_private.blockchain_operations SET authorized_by=p_actor,authorizations=authorizations||jsonb_build_array(jsonb_build_object('actor',p_actor,'role',role,'at',clock_timestamp())),state='requested',last_error=NULL,next_attempt_at=clock_timestamp(),updated_at=clock_timestamp() WHERE id=o.id;
  PERFORM certichain_private.blockchain_authorize((SELECT x FROM certichain_private.blockchain_operations x WHERE id=o.id));
  RETURN jsonb_build_object('operation_id',o.id,'status','requested');
END $$;

CREATE OR REPLACE FUNCTION public.blockchain_store_prepared(p_operation uuid,p_token uuid,p_generation bigint,p_tx jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE o certichain_private.blockchain_operations; prev certichain_private.blockchain_transaction_attempts; n certichain_private.blockchain_signer_nonces; data bytea; v_signer bytea; count_attempts integer;
BEGIN
  o:=certichain_private.blockchain_fence(p_operation,p_token,p_generation); PERFORM certichain_private.blockchain_authorize(o);
  IF jsonb_typeof(p_tx)<>'object' OR (SELECT count(*) FROM jsonb_object_keys(p_tx))<>9 OR
    NOT p_tx ?& ARRAY['hash','raw','signer','nonce','data','digest','gas','fee','tip'] OR
    p_tx->>'hash' !~ '^0x[0-9a-f]{64}$' OR p_tx->>'raw' !~ '^0x02[0-9a-f]+$' OR p_tx->>'signer' !~ '^0x[0-9a-f]{40}$' OR
    p_tx->>'digest' !~ '^0x[0-9a-f]{64}$' OR p_tx->>'data' !~ '^0x[0-9a-f]+$' OR
    p_tx->>'nonce' !~ '^[0-9]{1,78}$' OR p_tx->>'gas' !~ '^[0-9]{1,78}$' OR p_tx->>'fee' !~ '^[0-9]{1,78}$' OR p_tx->>'tip' !~ '^[0-9]{1,78}$' THEN
    RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='invalid_input'; END IF;
  data:=decode(substr(p_tx->>'data',3),'hex'); v_signer:=decode(substr(p_tx->>'signer',3),'hex');
  IF extensions.digest(data,'sha256')<>o.payload_digest OR decode(substr(p_tx->>'digest',3),'hex')<>o.payload_digest OR
    (o.kind IN ('issue','revoke') AND v_signer<>(SELECT signer FROM certichain_private.blockchain_issuers WHERE id=o.issuer_binding_id)) THEN
    RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='invalid_input'; END IF;
  SELECT * INTO n FROM certichain_private.blockchain_signer_nonces WHERE deployment_id=o.deployment_id AND signer=v_signer FOR UPDATE;
  IF n.active_operation_id IS DISTINCT FROM o.id OR n.reserved_nonce IS DISTINCT FROM (p_tx->>'nonce')::numeric THEN RAISE EXCEPTION USING ERRCODE='PT409',MESSAGE='nonce_conflict'; END IF;
  SELECT count(*) INTO count_attempts FROM certichain_private.blockchain_transaction_attempts WHERE operation_id=o.id;
  SELECT * INTO prev FROM certichain_private.blockchain_transaction_attempts WHERE operation_id=o.id ORDER BY attempt_number DESC LIMIT 1 FOR UPDATE;
  IF count_attempts>255 OR (SELECT count(*) FROM certichain_private.blockchain_transaction_attempts WHERE operation_id=o.id AND signer=v_signer AND nonce=(p_tx->>'nonce')::numeric)>3 OR
    (prev.id IS NOT NULL AND (prev.signer<>v_signer OR prev.nonce<>(p_tx->>'nonce')::numeric) AND (prev.receipt_status IS DISTINCT FROM 0 OR prev.state<>'reverted' OR jsonb_array_length(o.authorizations)=0 OR (prev.signer=v_signer AND (p_tx->>'nonce')::numeric<=prev.nonce))) OR
    (prev.id IS NOT NULL AND prev.signer=v_signer AND prev.nonce=(p_tx->>'nonce')::numeric AND (prev.calldata<>data OR
    (p_tx->>'fee')::numeric<ceil(prev.max_fee_per_gas*1.2) OR (p_tx->>'tip')::numeric<ceil(prev.max_priority_fee_per_gas*1.2)
    OR prev.created_at>clock_timestamp()-interval '5 minutes')) THEN RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='invalid_input'; END IF;
  -- Server-side hard cap in addition to the configured, tighter worker budget.
  IF (p_tx->>'gas')::numeric*(p_tx->>'fee')::numeric>100000000000000000 THEN RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='invalid_input'; END IF;
  INSERT INTO certichain_private.blockchain_transaction_attempts(operation_id,deployment_id,attempt_number,signer,nonce,transaction_hash,raw_signed_tx,calldata,calldata_digest,gas_limit,max_fee_per_gas,max_priority_fee_per_gas,authorized_by,replaces_attempt_id)
    VALUES(o.id,o.deployment_id,count_attempts,v_signer,(p_tx->>'nonce')::numeric,decode(substr(p_tx->>'hash',3),'hex'),decode(substr(p_tx->>'raw',3),'hex'),data,o.payload_digest,(p_tx->>'gas')::numeric,(p_tx->>'fee')::numeric,(p_tx->>'tip')::numeric,o.authorized_by,CASE WHEN prev.signer=v_signer AND prev.nonce=(p_tx->>'nonce')::numeric THEN prev.id ELSE NULL END);
  IF prev.id IS NOT NULL AND prev.signer=v_signer AND prev.nonce=(p_tx->>'nonce')::numeric THEN
    UPDATE certichain_private.blockchain_transaction_attempts SET state='replaced' WHERE id=prev.id;
  END IF;
  UPDATE certichain_private.blockchain_operations SET state='prepared',last_error=NULL WHERE id=o.id;
  RETURN certichain_private.blockchain_job(o.id);
EXCEPTION WHEN check_violation OR not_null_violation OR foreign_key_violation OR numeric_value_out_of_range THEN
  -- Constraint DETAIL can contain the full signed capability. Rethrow a closed
  -- error after the subtransaction rollback, without that private row detail.
  RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='invalid_input';
END $$;

CREATE OR REPLACE FUNCTION public.blockchain_recover_attempt(p_operation uuid,p_token uuid,p_generation bigint,p_tx jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE o certichain_private.blockchain_operations; t certichain_private.blockchain_transaction_attempts; v_signer bytea;
BEGIN
  o:=certichain_private.blockchain_fence(p_operation,p_token,p_generation);
  IF o.kind NOT IN ('issue','revoke') OR p_tx->>'hash' !~ '^0x[0-9a-f]{64}$' OR p_tx->>'signer' !~ '^0x[0-9a-f]{40}$' OR
    extensions.digest(decode(substr(p_tx->>'data',3),'hex'),'sha256')<>o.payload_digest OR
    EXISTS(SELECT 1 FROM certichain_private.blockchain_transaction_attempts WHERE operation_id=o.id) THEN RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='incompatible_evidence'; END IF;
  v_signer:=decode(substr(p_tx->>'signer',3),'hex');
  INSERT INTO certichain_private.blockchain_transaction_attempts(operation_id,deployment_id,attempt_number,signer,nonce,transaction_hash,raw_signed_tx,calldata,calldata_digest,gas_limit,max_fee_per_gas,max_priority_fee_per_gas,authorized_by)
    VALUES(o.id,o.deployment_id,0,v_signer,(p_tx->>'nonce')::numeric,decode(substr(p_tx->>'hash',3),'hex'),decode(substr(p_tx->>'raw',3),'hex'),decode(substr(p_tx->>'data',3),'hex'),o.payload_digest,(p_tx->>'gas')::numeric,(p_tx->>'fee')::numeric,(p_tx->>'tip')::numeric,o.authorized_by) RETURNING * INTO t;
  INSERT INTO certichain_private.blockchain_signer_nonces(deployment_id,signer,next_nonce,active_operation_id,reserved_nonce,generation)
    -- Recover evidence without treating missing nonce history as permission to
    -- skip unknown consumptions. A missing ledger starts at zero, as at signing.
    VALUES(o.deployment_id,v_signer,0,CASE WHEN t.nonce=0 THEN o.id ELSE NULL END,CASE WHEN t.nonce=0 THEN 0 ELSE NULL END,p_generation) ON CONFLICT DO NOTHING;
  UPDATE certichain_private.blockchain_signer_nonces SET active_operation_id=o.id,reserved_nonce=t.nonce,generation=p_generation
    WHERE deployment_id=o.deployment_id AND signer=v_signer AND active_operation_id IS NULL AND next_nonce=t.nonce;
  UPDATE certichain_private.blockchain_operations SET state='prepared' WHERE id=o.id;
  RETURN certichain_private.blockchain_job(o.id);
END $$;

CREATE OR REPLACE FUNCTION certichain_private.blockchain_job(p_operation uuid) RETURNS jsonb LANGUAGE sql SET search_path='' AS $$
  SELECT jsonb_build_object('sql_revoked', EXISTS(SELECT 1 FROM public.certificates c WHERE c.id=a.certificate_id AND c.status='revoked'),
    'revocation_expected',EXISTS(SELECT 1 FROM certichain_private.blockchain_operations r WHERE r.anchor_id=a.id AND r.kind='revoke'),
    'operation',to_jsonb(o)||jsonb_build_object('generation',o.generation::text,'confirmations',o.confirmations::text,'event_cursor',o.event_cursor::text,'head_number',o.head_number::text,'finalized_number',o.finalized_number::text,'config_version',o.config_version::text),
    'binding',to_jsonb(b)||jsonb_build_object('observed_block',b.observed_block::text,'config_version',b.config_version::text),
    'deployment',to_jsonb(d)||jsonb_build_object('chain_id',d.chain_id::text,'deployment_block',d.deployment_block::text),'anchor',to_jsonb(a),
    'attempts',coalesce((SELECT jsonb_agg(to_jsonb(t)||jsonb_build_object('nonce',t.nonce::text,'gas_limit',t.gas_limit::text,'max_fee_per_gas',t.max_fee_per_gas::text,'max_priority_fee_per_gas',t.max_priority_fee_per_gas::text,'block_number',t.block_number::text,'transaction_index',t.transaction_index::text,'validated_log_index',t.validated_log_index::text) ORDER BY t.attempt_number) FROM certichain_private.blockchain_transaction_attempts t WHERE t.operation_id=o.id),'[]'))
  FROM certichain_private.blockchain_operations o JOIN certichain_private.blockchain_issuers b ON b.id=o.issuer_binding_id
  JOIN certichain_private.blockchain_deployments d ON d.id=o.deployment_id LEFT JOIN certichain_private.certificate_anchors a ON a.id=o.anchor_id WHERE o.id=p_operation
$$;

CREATE OR REPLACE FUNCTION public.blockchain_queue(p_limit integer DEFAULT 10) RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path='' AS $$
  SELECT coalesce(jsonb_agg(id),'[]') FROM (SELECT id FROM certichain_private.blockchain_operations
    WHERE state<>'cancelled' AND next_attempt_at<=clock_timestamp() AND (lease_until IS NULL OR lease_until<=clock_timestamp())
    AND (state NOT IN ('failed','divergence','blocked') OR EXISTS (SELECT 1 FROM certichain_private.blockchain_transaction_attempts t WHERE t.operation_id=blockchain_operations.id AND raw_signed_tx IS NOT NULL))
    ORDER BY next_attempt_at LIMIT greatest(0,least(p_limit,10))) q
$$;

CREATE OR REPLACE FUNCTION public.blockchain_claim(p_operation uuid) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE o certichain_private.blockchain_operations;
BEGIN
  o:=certichain_private.blockchain_lock(p_operation);
  IF o.state='cancelled' THEN RAISE EXCEPTION USING ERRCODE='PT409',MESSAGE='busy'; END IF;
  IF o.lease_until>clock_timestamp() OR o.next_attempt_at>clock_timestamp() THEN RAISE EXCEPTION USING ERRCODE='PT409',MESSAGE='busy'; END IF;
  UPDATE certichain_private.blockchain_operations SET lease_token=gen_random_uuid(),lease_until=clock_timestamp()+interval '120 seconds',generation=generation+1 WHERE id=o.id;
  RETURN certichain_private.blockchain_job(o.id);
END $$;
