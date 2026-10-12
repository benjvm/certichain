-- 9C. No backfill, certificate/status mutation, or Storage DML.
ALTER TABLE public.certificates ADD CONSTRAINT anchor_certificate_identity
  UNIQUE (id, institution_id, issuance_operation_id);
ALTER TABLE public.certificate_issuance_operations ADD CONSTRAINT anchor_publication_identity
  UNIQUE (id, institution_id, certificate_id);

CREATE TABLE certichain_private.blockchain_deployments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), environment_id text NOT NULL,
  network text NOT NULL CHECK (network IN ('anvil','sepolia')),
  chain_id bigint NOT NULL CHECK (chain_id IN (31337,11155111)),
  contract_address bytea NOT NULL CHECK (octet_length(contract_address)=20),
  protocol_version integer NOT NULL CHECK (protocol_version=1),
  genesis_hash bytea NOT NULL CHECK (octet_length(genesis_hash)=32),
  runtime_code_hash bytea NOT NULL CHECK (octet_length(runtime_code_hash)=32),
  deployment_block bigint NOT NULL CHECK (deployment_block>0),
  deployment_hash bytea NOT NULL CHECK (octet_length(deployment_hash)=32),
  enabled boolean NOT NULL DEFAULT false,
  confirmations_required integer NOT NULL CHECK (confirmations_required IN (1,12)),
  writes_stopped boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  CHECK ((network='anvil' AND chain_id=31337 AND confirmations_required=1)
    OR (network='sepolia' AND chain_id=11155111 AND confirmations_required=12)),
  UNIQUE (environment_id,chain_id,contract_address)
);
CREATE UNIQUE INDEX blockchain_enabled_environment ON certichain_private.blockchain_deployments(environment_id) WHERE enabled;
CREATE TABLE certichain_private.blockchain_issuers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  deployment_id uuid NOT NULL REFERENCES certichain_private.blockchain_deployments ON DELETE RESTRICT,
  institution_id uuid NOT NULL REFERENCES public.institutions ON DELETE RESTRICT,
  issuer_id bytea NOT NULL CHECK (octet_length(issuer_id)=32 AND issuer_id<>decode(repeat('00',32),'hex')),
  signer bytea NOT NULL CHECK (octet_length(signer)=20),
  desired_can_issue boolean NOT NULL, desired_can_revoke boolean NOT NULL,
  observed_signer bytea CHECK (octet_length(observed_signer)=20),
  observed_can_issue boolean, observed_can_revoke boolean,
  observed_block bigint, observed_hash bytea CHECK (octet_length(observed_hash)=32),
  config_version bigint NOT NULL DEFAULT 1 CHECK (config_version>0),
  sync_state text NOT NULL DEFAULT 'pending' CHECK (sync_state IN ('pending','synced','divergence')),
  UNIQUE (deployment_id,institution_id), UNIQUE (deployment_id,issuer_id),
  UNIQUE (id,institution_id,deployment_id), UNIQUE (id,deployment_id)
);
CREATE TABLE certichain_private.certificate_anchors (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), certificate_id uuid NOT NULL,
  issuance_operation_id uuid NOT NULL, institution_id uuid NOT NULL,
  deployment_id uuid NOT NULL, issuer_binding_id uuid NOT NULL,
  credential_code_snapshot uuid NOT NULL,
  certificate_key bytea NOT NULL CHECK (octet_length(certificate_key)=32),
  document_sha256 bytea NOT NULL CHECK (octet_length(document_sha256)=32),
  salt bytea NOT NULL CHECK (octet_length(salt)=32),
  commitment bytea NOT NULL CHECK (octet_length(commitment)=32),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  FOREIGN KEY (certificate_id,institution_id,issuance_operation_id) REFERENCES public.certificates(id,institution_id,issuance_operation_id) ON DELETE RESTRICT,
  FOREIGN KEY (issuance_operation_id,institution_id,certificate_id) REFERENCES public.certificate_issuance_operations(id,institution_id,certificate_id) ON DELETE RESTRICT,
  FOREIGN KEY (issuer_binding_id,institution_id,deployment_id) REFERENCES certichain_private.blockchain_issuers(id,institution_id,deployment_id) ON DELETE RESTRICT,
  UNIQUE (certificate_id,deployment_id), UNIQUE (deployment_id,certificate_key),
  UNIQUE (id,issuer_binding_id,deployment_id)
);
CREATE TABLE certichain_private.blockchain_operations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), anchor_id uuid,
  issuer_binding_id uuid NOT NULL, deployment_id uuid NOT NULL,
  kind text NOT NULL CHECK (kind IN ('issue','revoke','set_issuer')),
  requested_by uuid NOT NULL REFERENCES public.profiles ON DELETE RESTRICT,
  authorized_by uuid NOT NULL REFERENCES public.profiles ON DELETE RESTRICT,
  idempotency_key uuid NOT NULL,
  payload_digest bytea NOT NULL CHECK (octet_length(payload_digest)=32),
  target_signer bytea CHECK (octet_length(target_signer)=20),
  target_can_issue boolean, target_can_revoke boolean, config_version bigint,
  state text NOT NULL DEFAULT 'requested' CHECK (state IN ('requested','prepared','submitted','included','confirmed','reorged','blocked','failed','divergence')),
  lease_token uuid, lease_until timestamptz, generation bigint NOT NULL DEFAULT 0,
  next_attempt_at timestamptz NOT NULL DEFAULT clock_timestamp(), retry_count integer NOT NULL DEFAULT 0,
  event_cursor bigint, last_error text CHECK (last_error IN ('authorization_denied','rpc_unavailable','rpc_timeout','insufficient_funds','nonce_conflict','transaction_reverted','deployment_mismatch','incompatible_evidence','reorg','divergence','opening_unavailable','busy')),
  canonical_attempt_id uuid, confirmations bigint NOT NULL DEFAULT 0 CHECK (confirmations>=0),
  finality text NOT NULL DEFAULT 'unknown' CHECK (finality IN ('unknown','not_applicable','finalized')),
  checked_at timestamptz, head_number bigint, head_hash bytea CHECK (octet_length(head_hash)=32),
  finalized_number bigint, finalized_hash bytea CHECK (octet_length(finalized_hash)=32),
  authorizations jsonb NOT NULL DEFAULT '[]' CHECK (jsonb_typeof(authorizations)='array' AND jsonb_array_length(authorizations)<=64),
  closed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(), updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  FOREIGN KEY (issuer_binding_id,deployment_id) REFERENCES certichain_private.blockchain_issuers(id,deployment_id) ON DELETE RESTRICT,
  FOREIGN KEY (anchor_id,issuer_binding_id,deployment_id) REFERENCES certichain_private.certificate_anchors(id,issuer_binding_id,deployment_id) ON DELETE RESTRICT,
  CHECK ((lease_token IS NULL)=(lease_until IS NULL)),
  CHECK ((kind IN ('issue','revoke') AND anchor_id IS NOT NULL AND config_version IS NULL AND target_signer IS NULL)
    OR (kind='set_issuer' AND anchor_id IS NULL AND config_version IS NOT NULL AND target_signer IS NOT NULL AND target_can_issue IS NOT NULL AND target_can_revoke IS NOT NULL)),
  CHECK (state NOT IN ('included','confirmed') OR canonical_attempt_id IS NOT NULL),
  CHECK (finality<>'finalized' OR (state='confirmed' AND finalized_number IS NOT NULL AND finalized_hash IS NOT NULL)),
  UNIQUE (issuer_binding_id,kind,idempotency_key), UNIQUE (id,deployment_id), UNIQUE (id,issuer_binding_id)
);
CREATE UNIQUE INDEX blockchain_one_anchor_kind ON certichain_private.blockchain_operations(anchor_id,kind) WHERE anchor_id IS NOT NULL;
CREATE UNIQUE INDEX blockchain_one_config ON certichain_private.blockchain_operations(issuer_binding_id,config_version) WHERE kind='set_issuer';
CREATE INDEX blockchain_queue ON certichain_private.blockchain_operations(state,next_attempt_at);
CREATE INDEX blockchain_leases ON certichain_private.blockchain_operations(lease_until);
CREATE TABLE certichain_private.blockchain_transaction_attempts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), operation_id uuid NOT NULL, deployment_id uuid NOT NULL,
  attempt_number integer NOT NULL CHECK (attempt_number BETWEEN 0 AND 255),
  signer bytea NOT NULL CHECK (octet_length(signer)=20), nonce numeric(78,0) NOT NULL CHECK (nonce>=0),
  transaction_hash bytea NOT NULL CHECK (octet_length(transaction_hash)=32),
  raw_signed_tx bytea CHECK (octet_length(raw_signed_tx) BETWEEN 64 AND 2048),
  calldata bytea NOT NULL CHECK (octet_length(calldata) IN (36,100,132)),
  calldata_digest bytea NOT NULL CHECK (octet_length(calldata_digest)=32),
  gas_limit numeric(78,0) NOT NULL CHECK (gas_limit>0 AND gas_limit<=1000000),
  max_fee_per_gas numeric(78,0) NOT NULL CHECK (max_fee_per_gas>0),
  max_priority_fee_per_gas numeric(78,0) NOT NULL CHECK (max_priority_fee_per_gas>0 AND max_priority_fee_per_gas<=max_fee_per_gas),
  authorized_by uuid NOT NULL REFERENCES public.profiles ON DELETE RESTRICT,
  replaces_attempt_id uuid,
  state text NOT NULL DEFAULT 'prepared' CHECK (state IN ('prepared','submitted','pending','included','reverted','replaced','orphaned','unknown')),
  submitted_at timestamptz, receipt_status integer CHECK (receipt_status IN (0,1)),
  block_number bigint, block_hash bytea CHECK (octet_length(block_hash)=32), transaction_index bigint, validated_log_index bigint,
  observed_at timestamptz, created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  receipt_observations jsonb NOT NULL DEFAULT '[]' CHECK (jsonb_typeof(receipt_observations)='array' AND jsonb_array_length(receipt_observations)<=64),
  FOREIGN KEY (operation_id,deployment_id) REFERENCES certichain_private.blockchain_operations(id,deployment_id) ON DELETE RESTRICT,
  UNIQUE (operation_id,attempt_number), UNIQUE (deployment_id,transaction_hash), UNIQUE (id,operation_id),
  FOREIGN KEY (replaces_attempt_id,operation_id) REFERENCES certichain_private.blockchain_transaction_attempts(id,operation_id) ON DELETE RESTRICT
);
ALTER TABLE certichain_private.blockchain_operations ADD CONSTRAINT blockchain_canonical_attempt_fk FOREIGN KEY(canonical_attempt_id,id)
  REFERENCES certichain_private.blockchain_transaction_attempts(id,operation_id) ON DELETE RESTRICT;
CREATE INDEX blockchain_attempt_nonce ON certichain_private.blockchain_transaction_attempts(deployment_id,signer,nonce);
CREATE TABLE certichain_private.blockchain_signer_nonces (
  deployment_id uuid NOT NULL REFERENCES certichain_private.blockchain_deployments ON DELETE RESTRICT,
  signer bytea NOT NULL CHECK (octet_length(signer)=20), next_nonce numeric(78,0) NOT NULL CHECK (next_nonce>=0),
  active_operation_id uuid, reserved_nonce numeric(78,0), generation bigint NOT NULL,
  PRIMARY KEY (deployment_id,signer),
  FOREIGN KEY(active_operation_id,deployment_id) REFERENCES certichain_private.blockchain_operations(id,deployment_id) ON DELETE RESTRICT,
  CHECK ((active_operation_id IS NULL)=(reserved_nonce IS NULL))
);

-- Immutable identities and append-only bounded audit/evidence, including postgres.
CREATE FUNCTION certichain_private.blockchain_guard() RETURNS trigger LANGUAGE plpgsql SET search_path='' AS $$
DECLARE mutable text[];
BEGIN
  IF TG_OP='DELETE' THEN RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='blockchain_history_protected'; END IF;
  mutable := CASE TG_TABLE_NAME
    WHEN 'blockchain_deployments' THEN ARRAY['enabled','writes_stopped']
    WHEN 'blockchain_issuers' THEN ARRAY['signer','desired_can_issue','desired_can_revoke','observed_signer','observed_can_issue','observed_can_revoke','observed_block','observed_hash','config_version','sync_state']
    WHEN 'certificate_anchors' THEN ARRAY[]::text[]
    WHEN 'blockchain_operations' THEN ARRAY['authorized_by','state','lease_token','lease_until','generation','next_attempt_at','retry_count','event_cursor','last_error','canonical_attempt_id','confirmations','finality','checked_at','head_number','head_hash','finalized_number','finalized_hash','authorizations','closed_at','updated_at']
    WHEN 'blockchain_transaction_attempts' THEN ARRAY['raw_signed_tx','state','submitted_at','receipt_status','block_number','block_hash','transaction_index','validated_log_index','observed_at','receipt_observations']
    ELSE ARRAY['next_nonce','active_operation_id','reserved_nonce','generation'] END;
  IF (to_jsonb(NEW)-mutable) IS DISTINCT FROM (to_jsonb(OLD)-mutable) THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='blockchain_identity_immutable';
  END IF;
  IF TG_TABLE_NAME='blockchain_transaction_attempts' THEN
    IF OLD.raw_signed_tx IS NOT NULL AND NEW.raw_signed_tx IS NOT NULL AND NEW.raw_signed_tx<>OLD.raw_signed_tx THEN
      RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='signed_bytes_immutable'; END IF;
    IF coalesce((SELECT jsonb_agg(v ORDER BY ord) FROM jsonb_array_elements(NEW.receipt_observations) WITH ORDINALITY AS x(v,ord) WHERE ord<=jsonb_array_length(OLD.receipt_observations)),'[]') IS DISTINCT FROM OLD.receipt_observations THEN RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='receipt_history_immutable'; END IF;
    IF (OLD.raw_signed_tx IS NULL AND NEW.raw_signed_tx IS NOT NULL) OR (OLD.raw_signed_tx IS NOT NULL AND NEW.raw_signed_tx IS NULL AND NOT EXISTS(
      SELECT 1 FROM certichain_private.blockchain_operations o WHERE o.id=OLD.operation_id AND o.closed_at<clock_timestamp()-interval '7 days'
      AND (o.finality='finalized' OR (o.state='confirmed' AND o.finality='not_applicable')))) THEN RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='raw_retention_protected'; END IF;
  ELSIF TG_TABLE_NAME='blockchain_operations' THEN
    IF coalesce((SELECT jsonb_agg(v ORDER BY ord) FROM jsonb_array_elements(NEW.authorizations) WITH ORDINALITY AS x(v,ord) WHERE ord<=jsonb_array_length(OLD.authorizations)),'[]') IS DISTINCT FROM OLD.authorizations OR (NEW.authorized_by<>OLD.authorized_by AND jsonb_array_length(NEW.authorizations)<=jsonb_array_length(OLD.authorizations)) THEN
      RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='authorization_history_immutable'; END IF;
    IF NEW.state IN ('included','confirmed') AND NOT EXISTS(SELECT 1 FROM certichain_private.blockchain_transaction_attempts t WHERE t.id=NEW.canonical_attempt_id AND t.operation_id=NEW.id AND t.receipt_status=1 AND t.validated_log_index IS NOT NULL AND t.state='included') THEN
      RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='compatible_receipt_required'; END IF;
    IF NEW.finality='finalized' AND (SELECT network FROM certichain_private.blockchain_deployments WHERE id=NEW.deployment_id)<>'sepolia' THEN RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='finality_policy'; END IF;
  END IF;
  RETURN NEW;
END $$;
DO $$ DECLARE t text; BEGIN
  FOREACH t IN ARRAY ARRAY['blockchain_deployments','blockchain_issuers','certificate_anchors','blockchain_operations','blockchain_transaction_attempts','blockchain_signer_nonces'] LOOP
    EXECUTE format('ALTER TABLE certichain_private.%I ENABLE ROW LEVEL SECURITY',t);
    EXECUTE format('REVOKE ALL ON certichain_private.%I FROM PUBLIC,anon,authenticated,service_role',t);
    EXECUTE format('CREATE TRIGGER blockchain_immutable BEFORE UPDATE OR DELETE ON certichain_private.%I FOR EACH ROW EXECUTE FUNCTION certichain_private.blockchain_guard()',t);
  END LOOP;
END $$;
REVOKE ALL ON FUNCTION certichain_private.blockchain_guard() FROM PUBLIC,anon,authenticated,service_role;

-- Snapshot reads and commit share the same authorization/coherence checks.
CREATE FUNCTION public.blockchain_anchor_snapshot(p_actor uuid,p_certificate uuid,p_environment text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE c public.certificates; b certichain_private.blockchain_issuers; d certichain_private.blockchain_deployments;
BEGIN
  SELECT * INTO c FROM public.certificates WHERE id=p_certificate;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='PT404',MESSAGE='publication_unavailable'; END IF;
  PERFORM 1 FROM public.institutions WHERE id=c.institution_id FOR UPDATE;
  PERFORM certichain_private.authorize_issuance(c.institution_id,p_actor);
  PERFORM 1 FROM public.certificate_issuance_operations WHERE id=c.issuance_operation_id FOR SHARE;
  SELECT * INTO c FROM public.certificates WHERE id=p_certificate FOR SHARE;
  IF c.status<>'active' OR (c.expires_at IS NOT NULL AND c.expires_at<=clock_timestamp()) OR
    NOT EXISTS(SELECT 1 FROM public.certificate_issuance_operations o WHERE o.id=c.issuance_operation_id AND o.status='completed'
      AND o.certificate_id=c.id AND o.target_certificate_id=c.id AND o.institution_id=c.institution_id
      AND o.actor_id=c.issued_by AND o.holder_id=c.holder_id AND o.pdf_hash=c.document_hash AND o.stored_hash=c.document_hash)
    OR c.document_path IS DISTINCT FROM c.institution_id::text||'/'||c.id::text||'.pdf'
    OR c.credential_code !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' THEN
    RAISE EXCEPTION USING ERRCODE='PT404',MESSAGE='publication_unavailable'; END IF;
  SELECT * INTO d FROM certichain_private.blockchain_deployments WHERE environment_id=p_environment AND enabled AND NOT writes_stopped FOR SHARE;
  SELECT * INTO b FROM certichain_private.blockchain_issuers WHERE deployment_id=d.id AND institution_id=c.institution_id FOR UPDATE;
  IF b.id IS NULL OR b.sync_state<>'synced' OR NOT b.desired_can_issue OR NOT b.observed_can_issue OR b.signer<>b.observed_signer THEN
    RAISE EXCEPTION USING ERRCODE='PT503',MESSAGE='temporary_failure'; END IF;
  RETURN jsonb_build_object('certificate_id',c.id,'issuance_operation_id',c.issuance_operation_id,'institution_id',c.institution_id,
    'code',c.credential_code,'hash',c.document_hash,'path',c.document_path,'binding_id',b.id,'deployment_id',d.id,'I','0x'||encode(b.issuer_id,'hex'));
END $$;

CREATE FUNCTION public.blockchain_request_anchor(p_actor uuid,p_certificate uuid,p_environment text,p_key uuid,p_snapshot jsonb,p_salt text,p_k text,p_c text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE s jsonb; a certichain_private.certificate_anchors; o certichain_private.blockchain_operations; k bytea; c bytea; h bytea; salt bytea; i bytea;
BEGIN
  s:=public.blockchain_anchor_snapshot(p_actor,p_certificate,p_environment);
  IF s IS DISTINCT FROM p_snapshot THEN RAISE EXCEPTION USING ERRCODE='PT409',MESSAGE='busy'; END IF;
  SELECT * INTO o FROM certichain_private.blockchain_operations WHERE issuer_binding_id=(s->>'binding_id')::uuid AND kind='issue' AND idempotency_key=p_key;
  IF FOUND THEN
    IF NOT EXISTS(SELECT 1 FROM certichain_private.certificate_anchors WHERE id=o.anchor_id AND certificate_id=p_certificate) THEN
      RAISE EXCEPTION USING ERRCODE='23505',MESSAGE='idempotency_conflict'; END IF;
    PERFORM 1 FROM certichain_private.certificate_anchors WHERE id=o.anchor_id FOR UPDATE;
    SELECT * INTO o FROM certichain_private.blockchain_operations WHERE id=o.id FOR UPDATE;
    RETURN jsonb_build_object('operation_id',o.id,'status',o.state,'created',false);
  END IF;
  SELECT * INTO a FROM certichain_private.certificate_anchors WHERE certificate_id=p_certificate AND deployment_id=(s->>'deployment_id')::uuid FOR UPDATE;
  IF FOUND THEN
    SELECT * INTO o FROM certichain_private.blockchain_operations WHERE anchor_id=a.id AND kind='issue' FOR UPDATE;
    RETURN jsonb_build_object('operation_id',o.id,'status',o.state,'created',false);
  END IF;
  IF p_key IS NULL OR p_salt !~ '^0x[0-9a-f]{64}$' OR p_k !~ '^0x[0-9a-f]{64}$' OR p_c !~ '^0x[0-9a-f]{64}$' THEN
    RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='invalid_input'; END IF;
  salt:=decode(substr(p_salt,3),'hex'); i:=decode(substr(s->>'I',3),'hex'); h:=decode(s->>'hash','hex');
  k:=extensions.digest(convert_to('certichain:certificate-key:v1','UTF8')||decode('00','hex')||uuid_send((s->>'code')::uuid),'sha256');
  c:=extensions.digest(convert_to('certichain:document-commitment:v1','UTF8')||decode('00','hex')||k||i||h||salt,'sha256');
  IF k<>decode(substr(p_k,3),'hex') OR c<>decode(substr(p_c,3),'hex') THEN RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='invalid_input'; END IF;
  INSERT INTO certichain_private.certificate_anchors(certificate_id,issuance_operation_id,institution_id,deployment_id,issuer_binding_id,credential_code_snapshot,certificate_key,document_sha256,salt,commitment)
    VALUES(p_certificate,(s->>'issuance_operation_id')::uuid,(s->>'institution_id')::uuid,(s->>'deployment_id')::uuid,(s->>'binding_id')::uuid,(s->>'code')::uuid,k,h,salt,c) RETURNING * INTO a;
  INSERT INTO certichain_private.blockchain_operations(anchor_id,issuer_binding_id,deployment_id,kind,requested_by,authorized_by,idempotency_key,payload_digest)
    VALUES(a.id,a.issuer_binding_id,a.deployment_id,'issue',p_actor,p_actor,p_key,extensions.digest(decode('f8362009','hex')||k||c||i,'sha256')) RETURNING * INTO o;
  RETURN jsonb_build_object('operation_id',o.id,'status',o.state,'created',true);
END $$;

CREATE FUNCTION public.blockchain_progress(p_actor uuid,p_operation uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE o certichain_private.blockchain_operations; inst uuid;
BEGIN
  SELECT op.* INTO o FROM certichain_private.blockchain_operations op WHERE op.id=p_operation;
  SELECT institution_id INTO inst FROM certichain_private.blockchain_issuers WHERE id=o.issuer_binding_id;
  PERFORM 1 FROM public.institutions WHERE id=inst FOR UPDATE;
  PERFORM certichain_private.authorize_issuance(inst,p_actor);
  IF o.id IS NULL OR o.kind<>'issue' THEN RAISE EXCEPTION USING ERRCODE='PT404',MESSAGE='publication_unavailable'; END IF;
  RETURN jsonb_build_object('operation_id',o.id,'status',o.state);
END $$;

-- Technical snapshots never pass through client DTOs. Decimal quantities are strings.
CREATE FUNCTION certichain_private.blockchain_job(p_operation uuid) RETURNS jsonb LANGUAGE sql SET search_path='' AS $$
  SELECT jsonb_build_object('operation',to_jsonb(o)||jsonb_build_object('generation',o.generation::text,'confirmations',o.confirmations::text,'event_cursor',o.event_cursor::text,'head_number',o.head_number::text,'finalized_number',o.finalized_number::text,'config_version',o.config_version::text),
    'binding',to_jsonb(b)||jsonb_build_object('observed_block',b.observed_block::text,'config_version',b.config_version::text),
    'deployment',to_jsonb(d)||jsonb_build_object('chain_id',d.chain_id::text,'deployment_block',d.deployment_block::text),'anchor',to_jsonb(a),
    'attempts',coalesce((SELECT jsonb_agg(to_jsonb(t)||jsonb_build_object('nonce',t.nonce::text,'gas_limit',t.gas_limit::text,'max_fee_per_gas',t.max_fee_per_gas::text,'max_priority_fee_per_gas',t.max_priority_fee_per_gas::text,'block_number',t.block_number::text,'transaction_index',t.transaction_index::text,'validated_log_index',t.validated_log_index::text) ORDER BY t.attempt_number) FROM certichain_private.blockchain_transaction_attempts t WHERE t.operation_id=o.id),'[]'))
  FROM certichain_private.blockchain_operations o JOIN certichain_private.blockchain_issuers b ON b.id=o.issuer_binding_id
  JOIN certichain_private.blockchain_deployments d ON d.id=o.deployment_id LEFT JOIN certichain_private.certificate_anchors a ON a.id=o.anchor_id WHERE o.id=p_operation
$$;
CREATE FUNCTION public.blockchain_queue(p_limit integer DEFAULT 10) RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path='' AS $$
  SELECT coalesce(jsonb_agg(id),'[]') FROM (SELECT id FROM certichain_private.blockchain_operations
    WHERE next_attempt_at<=clock_timestamp() AND (lease_until IS NULL OR lease_until<=clock_timestamp())
    AND (state NOT IN ('failed','divergence','blocked') OR EXISTS (SELECT 1 FROM certichain_private.blockchain_transaction_attempts t WHERE t.operation_id=blockchain_operations.id AND raw_signed_tx IS NOT NULL))
    ORDER BY next_attempt_at LIMIT greatest(0,least(p_limit,10))) q
$$;
CREATE FUNCTION certichain_private.blockchain_lock(p_operation uuid) RETURNS certichain_private.blockchain_operations LANGUAGE plpgsql SET search_path='' AS $$
DECLARE o certichain_private.blockchain_operations; inst uuid;
BEGIN
  SELECT b.institution_id INTO inst FROM certichain_private.blockchain_operations x JOIN certichain_private.blockchain_issuers b ON b.id=x.issuer_binding_id WHERE x.id=p_operation;
  PERFORM 1 FROM public.institutions WHERE id=inst FOR UPDATE;
  PERFORM 1 FROM public.certificate_issuance_operations WHERE id=(SELECT a.issuance_operation_id FROM certichain_private.certificate_anchors a JOIN certichain_private.blockchain_operations x ON x.anchor_id=a.id WHERE x.id=p_operation) FOR SHARE;
  PERFORM 1 FROM public.certificates WHERE id=(SELECT a.certificate_id FROM certichain_private.certificate_anchors a JOIN certichain_private.blockchain_operations x ON x.anchor_id=a.id WHERE x.id=p_operation) FOR SHARE;
  PERFORM 1 FROM certichain_private.blockchain_issuers WHERE id=(SELECT issuer_binding_id FROM certichain_private.blockchain_operations WHERE id=p_operation) FOR UPDATE;
  PERFORM 1 FROM certichain_private.certificate_anchors WHERE id=(SELECT anchor_id FROM certichain_private.blockchain_operations WHERE id=p_operation) FOR UPDATE;
  SELECT * INTO o FROM certichain_private.blockchain_operations WHERE id=p_operation FOR UPDATE;
  IF o.id IS NULL THEN RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='invalid_input'; END IF;
  RETURN o;
END $$;
CREATE FUNCTION public.blockchain_claim(p_operation uuid) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE o certichain_private.blockchain_operations;
BEGIN
  o:=certichain_private.blockchain_lock(p_operation);
  IF o.lease_until>clock_timestamp() OR o.next_attempt_at>clock_timestamp() THEN RAISE EXCEPTION USING ERRCODE='PT409',MESSAGE='busy'; END IF;
  UPDATE certichain_private.blockchain_operations SET lease_token=gen_random_uuid(),lease_until=clock_timestamp()+interval '120 seconds',generation=generation+1 WHERE id=o.id;
  RETURN certichain_private.blockchain_job(o.id);
END $$;
CREATE FUNCTION certichain_private.blockchain_fence(p_operation uuid,p_token uuid,p_generation bigint) RETURNS certichain_private.blockchain_operations LANGUAGE plpgsql SET search_path='' AS $$
DECLARE o certichain_private.blockchain_operations;
BEGIN
  o:=certichain_private.blockchain_lock(p_operation);
  IF p_token IS NULL OR o.lease_token IS DISTINCT FROM p_token OR o.generation<>p_generation OR o.lease_until<=clock_timestamp() THEN
    RAISE EXCEPTION USING ERRCODE='PT409',MESSAGE='busy'; END IF;
  RETURN o;
END $$;
CREATE FUNCTION certichain_private.blockchain_authorize(o certichain_private.blockchain_operations) RETURNS void LANGUAGE plpgsql SET search_path='' AS $$
DECLARE b certichain_private.blockchain_issuers; a certichain_private.certificate_anchors;
BEGIN
  SELECT * INTO b FROM certichain_private.blockchain_issuers WHERE id=o.issuer_binding_id;
  IF o.state IN ('blocked','failed','divergence') THEN RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='authorization_denied'; END IF;
  IF NOT EXISTS(SELECT 1 FROM certichain_private.blockchain_deployments WHERE id=o.deployment_id AND enabled AND NOT writes_stopped) THEN
    RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='authorization_denied'; END IF;
  IF o.kind='set_issuer' THEN
    IF NOT EXISTS(SELECT 1 FROM public.profiles WHERE id=o.authorized_by AND role='platform_admin') OR o.config_version<>b.config_version THEN RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='authorization_denied'; END IF;
  ELSE
    SELECT * INTO a FROM certichain_private.certificate_anchors WHERE id=o.anchor_id;
    PERFORM public.blockchain_anchor_snapshot(o.authorized_by,a.certificate_id,(SELECT environment_id FROM certichain_private.blockchain_deployments WHERE id=o.deployment_id));
    IF o.kind<>'issue' THEN RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='authorization_denied'; END IF;
  END IF;
END $$;
CREATE FUNCTION public.blockchain_authorize_job(p_operation uuid,p_token uuid,p_generation bigint) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE o certichain_private.blockchain_operations;
BEGIN
  o:=certichain_private.blockchain_fence(p_operation,p_token,p_generation);
  PERFORM certichain_private.blockchain_authorize(o);
  RETURN certichain_private.blockchain_job(o.id);
END $$;
CREATE FUNCTION public.blockchain_reserve_nonce(p_operation uuid,p_token uuid,p_generation bigint,p_signer text,p_latest text,p_pending text)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE o certichain_private.blockchain_operations; n certichain_private.blockchain_signer_nonces; v_signer bytea;
BEGIN
  o:=certichain_private.blockchain_fence(p_operation,p_token,p_generation); PERFORM certichain_private.blockchain_authorize(o);
  IF p_signer !~ '^0x[0-9a-f]{40}$' OR p_latest !~ '^[0-9]{1,78}$' OR p_pending !~ '^[0-9]{1,78}$' THEN RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='invalid_input'; END IF;
  v_signer:=decode(substr(p_signer,3),'hex');
  INSERT INTO certichain_private.blockchain_signer_nonces(deployment_id,signer,next_nonce,generation) VALUES(o.deployment_id,v_signer,0,p_generation) ON CONFLICT DO NOTHING;
  SELECT * INTO n FROM certichain_private.blockchain_signer_nonces WHERE deployment_id=o.deployment_id AND signer=v_signer FOR UPDATE;
  IF n.active_operation_id IS NOT NULL AND n.active_operation_id<>o.id THEN RAISE EXCEPTION USING ERRCODE='PT409',MESSAGE='busy'; END IF;
  IF n.active_operation_id=o.id THEN RETURN n.reserved_nonce::text; END IF;
  -- Dedicated EOA: unknown consumptions are never silently skipped, including its first use.
  IF p_latest::numeric<>n.next_nonce OR p_pending::numeric<>n.next_nonce THEN RAISE EXCEPTION USING ERRCODE='PT409',MESSAGE='nonce_conflict'; END IF;
  UPDATE certichain_private.blockchain_signer_nonces SET active_operation_id=o.id,reserved_nonce=next_nonce,generation=p_generation WHERE deployment_id=o.deployment_id AND signer=v_signer;
  RETURN n.next_nonce::text;
END $$;

CREATE FUNCTION public.blockchain_store_prepared(p_operation uuid,p_token uuid,p_generation bigint,p_tx jsonb)
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
    (o.kind='issue' AND v_signer<>(SELECT signer FROM certichain_private.blockchain_issuers WHERE id=o.issuer_binding_id)) THEN
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

-- All mutable worker actions are fenced; no RPC holds locks across external I/O.
CREATE FUNCTION public.blockchain_update_job(p_operation uuid,p_token uuid,p_generation bigint,p_action text,p_detail jsonb DEFAULT '{}')
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE o certichain_private.blockchain_operations; t certichain_private.blockchain_transaction_attempts; obs jsonb; v_state text; err text;
BEGIN
  o:=certichain_private.blockchain_fence(p_operation,p_token,p_generation);
  IF p_action='renew' THEN
    UPDATE certichain_private.blockchain_operations SET lease_until=clock_timestamp()+interval '120 seconds' WHERE id=o.id;
  ELSIF p_action='release' THEN
    UPDATE certichain_private.blockchain_operations SET lease_token=NULL,lease_until=NULL,next_attempt_at=clock_timestamp()+CASE WHEN (SELECT network FROM certichain_private.blockchain_deployments WHERE id=o.deployment_id)='anvil' THEN interval '5 seconds' ELSE interval '15 seconds' END WHERE id=o.id;
  ELSIF p_action='cursor' THEN
    UPDATE certichain_private.blockchain_operations SET event_cursor=(p_detail->>'cursor')::bigint WHERE id=o.id;
  ELSIF p_action='configuration' THEN
    IF p_detail->>'signer' !~ '^0x[0-9a-f]{40}$' OR p_detail->>'block_hash' !~ '^0x[0-9a-f]{64}$' OR jsonb_typeof(p_detail->'can_issue')<>'boolean' OR jsonb_typeof(p_detail->'can_revoke')<>'boolean' THEN RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='invalid_input'; END IF;
    UPDATE certichain_private.blockchain_issuers SET observed_signer=decode(substr(p_detail->>'signer',3),'hex'),observed_can_issue=(p_detail->>'can_issue')::boolean,
      observed_can_revoke=(p_detail->>'can_revoke')::boolean,observed_block=(p_detail->>'block_number')::bigint,observed_hash=decode(substr(p_detail->>'block_hash',3),'hex'),
      sync_state=CASE WHEN signer=decode(substr(p_detail->>'signer',3),'hex') AND desired_can_issue=(p_detail->>'can_issue')::boolean AND desired_can_revoke=(p_detail->>'can_revoke')::boolean THEN 'synced' ELSE 'pending' END WHERE id=o.issuer_binding_id;
  ELSIF p_action='incompatible' THEN
    SELECT * INTO t FROM certichain_private.blockchain_transaction_attempts WHERE operation_id=o.id AND transaction_hash=decode(substr(p_detail->>'hash',3),'hex') FOR UPDATE;
    IF t.id IS NULL OR NOT p_detail ?& ARRAY['hash','status','block_number','block_hash','transaction_index'] OR (p_detail->>'status')::integer NOT IN (0,1) OR p_detail->>'block_hash' !~ '^0x[0-9a-f]{64}$' THEN RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='invalid_input'; END IF;
    obs:=jsonb_build_object('status',(p_detail->>'status')::integer,'block_number',p_detail->>'block_number','block_hash',p_detail->>'block_hash','transaction_index',p_detail->>'transaction_index','validated_log_index',NULL,'observed_at',clock_timestamp(),'canonical',true);
    UPDATE certichain_private.blockchain_transaction_attempts SET observed_at=clock_timestamp(),receipt_observations=receipt_observations||jsonb_build_array(obs) WHERE id=t.id;
    UPDATE certichain_private.blockchain_operations SET state='divergence',last_error='incompatible_evidence',confirmations=0,finality='unknown',canonical_attempt_id=NULL WHERE id=o.id;
  ELSIF p_action='error' THEN
    err:=p_detail->>'error';
    v_state:=CASE WHEN err IN ('incompatible_evidence','divergence') THEN 'divergence'
      WHEN err IN ('authorization_denied','insufficient_funds','nonce_conflict','deployment_mismatch','opening_unavailable') THEN 'blocked'
      WHEN err='transaction_reverted' THEN 'failed' ELSE o.state END;
    UPDATE certichain_private.blockchain_operations SET state=v_state,last_error=err,retry_count=retry_count+1,
      next_attempt_at=clock_timestamp()+make_interval(secs=>least(300,15*power(2,least(retry_count,5)))::integer),lease_token=NULL,lease_until=NULL,updated_at=clock_timestamp() WHERE id=o.id;
  ELSIF p_action IN ('submitted','pending','unknown') THEN
    SELECT * INTO t FROM certichain_private.blockchain_transaction_attempts WHERE operation_id=o.id AND transaction_hash=decode(substr(p_detail->>'hash',3),'hex') FOR UPDATE;
    IF t.id IS NULL THEN RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='invalid_input'; END IF;
    UPDATE certichain_private.blockchain_transaction_attempts SET state=p_action,submitted_at=coalesce(submitted_at,clock_timestamp()),observed_at=clock_timestamp() WHERE id=t.id;
    UPDATE certichain_private.blockchain_operations SET state=CASE WHEN state IN ('prepared','requested','reorged') THEN 'submitted' ELSE state END WHERE id=o.id;
  ELSIF p_action='reorg' THEN
    SELECT * INTO t FROM certichain_private.blockchain_transaction_attempts WHERE id=o.canonical_attempt_id FOR UPDATE;
    IF t.id IS NULL THEN RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='invalid_input'; END IF;
    obs:=jsonb_build_object('status',t.receipt_status,'block_number',t.block_number::text,'block_hash','0x'||encode(t.block_hash,'hex'),'transaction_index',t.transaction_index::text,'validated_log_index',t.validated_log_index::text,'observed_at',clock_timestamp(),'canonical',false);
    UPDATE certichain_private.blockchain_transaction_attempts SET state='orphaned',receipt_observations=receipt_observations||jsonb_build_array(obs) WHERE id=t.id;
    UPDATE certichain_private.blockchain_operations SET state=CASE WHEN finality='finalized' THEN 'divergence' ELSE 'reorged' END,
      last_error='reorg',confirmations=0,finality='unknown',canonical_attempt_id=NULL WHERE id=o.id;
    IF o.finality='finalized' THEN UPDATE certichain_private.blockchain_deployments SET writes_stopped=true WHERE id=o.deployment_id; END IF;
    IF o.kind='set_issuer' THEN UPDATE certichain_private.blockchain_issuers SET sync_state='pending' WHERE id=o.issuer_binding_id; END IF;
    -- Reorg restores the original logical reservation; never allocates another nonce.
    UPDATE certichain_private.blockchain_signer_nonces SET active_operation_id=o.id,reserved_nonce=t.nonce,next_nonce=t.nonce,generation=p_generation WHERE deployment_id=o.deployment_id AND signer=t.signer AND (active_operation_id IS NULL OR active_operation_id=o.id);
    IF NOT FOUND THEN UPDATE certichain_private.blockchain_deployments SET writes_stopped=true WHERE id=o.deployment_id; END IF;
  ELSIF p_action='receipt' THEN
    SELECT * INTO t FROM certichain_private.blockchain_transaction_attempts WHERE operation_id=o.id AND transaction_hash=decode(substr(p_detail->>'hash',3),'hex') FOR UPDATE;
    IF t.id IS NULL OR NOT p_detail ?& ARRAY['hash','status','block_number','block_hash','transaction_index','validated_log_index','head_number','head_hash','confirmations','finality']
      OR (p_detail->>'status')::integer NOT IN (0,1) OR p_detail->>'block_hash' !~ '^0x[0-9a-f]{64}$' THEN RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='invalid_input'; END IF;
    IF p_detail->>'status'='1' AND p_detail->>'validated_log_index' IS NULL THEN RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='incompatible_evidence'; END IF;
    obs:=jsonb_build_object('status',(p_detail->>'status')::integer,'block_number',p_detail->>'block_number','block_hash',p_detail->>'block_hash','transaction_index',p_detail->>'transaction_index','validated_log_index',p_detail->>'validated_log_index','observed_at',clock_timestamp(),'canonical',true);
    UPDATE certichain_private.blockchain_transaction_attempts SET state=CASE WHEN p_detail->>'status'='1' THEN 'included' ELSE 'reverted' END,
      receipt_status=(p_detail->>'status')::integer,block_number=(p_detail->>'block_number')::bigint,block_hash=decode(substr(p_detail->>'block_hash',3),'hex'),
      transaction_index=(p_detail->>'transaction_index')::bigint,validated_log_index=(p_detail->>'validated_log_index')::bigint,observed_at=clock_timestamp(),
      receipt_observations=CASE WHEN block_hash IS DISTINCT FROM decode(substr(p_detail->>'block_hash',3),'hex') OR state='orphaned' THEN receipt_observations||jsonb_build_array(obs) ELSE receipt_observations END WHERE id=t.id;
    v_state:=CASE WHEN p_detail->>'status'='0' THEN 'failed' WHEN (p_detail->>'confirmations')::bigint>=(SELECT confirmations_required FROM certichain_private.blockchain_deployments WHERE id=o.deployment_id) THEN 'confirmed' ELSE 'included' END;
    IF p_detail->>'finality'='finalized' AND (SELECT network FROM certichain_private.blockchain_deployments WHERE id=o.deployment_id)<>'sepolia' THEN RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='invalid_input'; END IF;
    UPDATE certichain_private.blockchain_operations SET state=v_state,canonical_attempt_id=t.id,confirmations=(p_detail->>'confirmations')::bigint,
      finality=p_detail->>'finality',checked_at=clock_timestamp(),head_number=(p_detail->>'head_number')::bigint,head_hash=decode(substr(p_detail->>'head_hash',3),'hex'),
      finalized_number=(p_detail->>'finalized_number')::bigint,finalized_hash=decode(substr(p_detail->>'finalized_hash',3),'hex'),
      last_error=CASE WHEN v_state='failed' THEN 'transaction_reverted' ELSE NULL END,retry_count=0,
      closed_at=CASE WHEN p_detail->>'finality'='finalized' THEN coalesce(closed_at,clock_timestamp()) ELSE closed_at END WHERE id=o.id;
    IF v_state IN ('confirmed','failed') THEN
      UPDATE certichain_private.blockchain_signer_nonces SET active_operation_id=NULL,reserved_nonce=NULL,next_nonce=t.nonce+1 WHERE deployment_id=o.deployment_id AND signer=t.signer AND active_operation_id=o.id;
    END IF;
    IF o.kind='set_issuer' AND v_state='confirmed' THEN
      UPDATE certichain_private.blockchain_issuers SET observed_signer=o.target_signer,observed_can_issue=o.target_can_issue,observed_can_revoke=o.target_can_revoke,
        observed_block=(p_detail->>'block_number')::bigint,observed_hash=decode(substr(p_detail->>'block_hash',3),'hex'),sync_state=CASE WHEN config_version=o.config_version THEN 'synced' ELSE 'pending' END WHERE id=o.issuer_binding_id;
    END IF;
  ELSE RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='invalid_input'; END IF;
  RETURN certichain_private.blockchain_job(o.id);
END $$;

CREATE FUNCTION public.blockchain_reauthorize(p_actor uuid,p_operation uuid) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE o certichain_private.blockchain_operations; inst uuid; role text;
BEGIN
  o:=certichain_private.blockchain_lock(p_operation);
  SELECT institution_id INTO inst FROM certichain_private.blockchain_issuers WHERE id=o.issuer_binding_id;
  IF o.kind='set_issuer' THEN
    IF NOT EXISTS(SELECT 1 FROM public.profiles WHERE id=p_actor AND profiles.role='platform_admin') THEN RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='authorization_denied'; END IF;
    role:='platform_admin';
  ELSE
    PERFORM certichain_private.authorize_issuance(inst,p_actor);
    SELECT m.role::text INTO role FROM public.institution_members m WHERE institution_id=inst AND user_id=p_actor;
    IF o.kind<>'issue' THEN RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='authorization_denied'; END IF;
  END IF;
  IF o.state NOT IN ('blocked','failed') OR o.lease_until>clock_timestamp() OR jsonb_array_length(o.authorizations)>=64 THEN RAISE EXCEPTION USING ERRCODE='PT409',MESSAGE='busy'; END IF;
  -- Reconciliation has to visit every signed attempt after the block/failure.
  IF EXISTS(SELECT 1 FROM certichain_private.blockchain_transaction_attempts WHERE operation_id=o.id AND (observed_at IS NULL OR observed_at<o.updated_at)) THEN RAISE EXCEPTION USING ERRCODE='PT409',MESSAGE='busy'; END IF;
  UPDATE certichain_private.blockchain_operations SET authorized_by=p_actor,authorizations=authorizations||jsonb_build_array(jsonb_build_object('actor',p_actor,'role',role,'at',clock_timestamp())),state='requested',last_error=NULL,next_attempt_at=clock_timestamp(),updated_at=clock_timestamp() WHERE id=o.id;
  PERFORM certichain_private.blockchain_authorize((SELECT x FROM certichain_private.blockchain_operations x WHERE id=o.id));
  RETURN jsonb_build_object('operation_id',o.id,'status','requested');
END $$;

-- Trusted operator tools. Configuration snapshots are separate durable operations.
CREATE FUNCTION public.blockchain_register_deployment(p_manifest jsonb) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE id uuid;
BEGIN
  IF p_manifest->>'synthetic' IS DISTINCT FROM 'false' OR p_manifest->>'environmentId' IS NULL THEN RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='deployment_mismatch'; END IF;
  INSERT INTO certichain_private.blockchain_deployments(environment_id,network,chain_id,contract_address,protocol_version,genesis_hash,runtime_code_hash,deployment_block,deployment_hash,enabled,confirmations_required)
    VALUES(p_manifest->>'environmentId',p_manifest->>'network',(p_manifest->>'chainId')::bigint,decode(substr(p_manifest->>'contractAddress',3),'hex'),(p_manifest->>'protocolVersion')::integer,decode(substr(p_manifest->>'genesisHash',3),'hex'),decode(substr(p_manifest->>'runtimeCodeHash',3),'hex'),(p_manifest->'deploymentBlock'->>'number')::bigint,decode(substr(p_manifest->'deploymentBlock'->>'hash',3),'hex'),true,CASE WHEN p_manifest->>'network'='anvil' THEN 1 ELSE 12 END) RETURNING blockchain_deployments.id INTO id;
  RETURN id;
END $$;
CREATE FUNCTION public.blockchain_configure_issuer(p_actor uuid,p_deployment uuid,p_institution uuid,p_i text,p_signer text,p_issue boolean,p_revoke boolean,p_payload text,p_key uuid)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE b certichain_private.blockchain_issuers; id uuid; prior certichain_private.blockchain_operations; expected bytea;
BEGIN
  PERFORM 1 FROM public.institutions WHERE institutions.id=p_institution FOR UPDATE;
  IF NOT EXISTS(SELECT 1 FROM public.profiles WHERE profiles.id=p_actor AND role='platform_admin') THEN RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='authorization_denied'; END IF;
  IF p_i !~ '^0x[0-9a-f]{64}$' OR p_signer !~ '^0x[0-9a-f]{40}$' OR p_payload !~ '^0x[0-9a-f]{64}$' THEN RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='invalid_input'; END IF;
  expected:=extensions.digest(decode('161575ee'||substr(p_i,3)||repeat('00',12)||substr(p_signer,3)||repeat('00',31)||CASE WHEN p_issue THEN '01' ELSE '00' END||repeat('00',31)||CASE WHEN p_revoke THEN '01' ELSE '00' END,'hex'),'sha256');
  IF expected<>decode(substr(p_payload,3),'hex') THEN RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='invalid_input'; END IF;
  SELECT * INTO b FROM certichain_private.blockchain_issuers WHERE deployment_id=p_deployment AND institution_id=p_institution FOR UPDATE;
  SELECT * INTO prior FROM certichain_private.blockchain_operations WHERE issuer_binding_id=b.id AND kind='set_issuer' AND idempotency_key=p_key;
  IF prior.id IS NOT NULL THEN
    IF prior.payload_digest<>expected OR b.issuer_id<>decode(substr(p_i,3),'hex') THEN RAISE EXCEPTION USING ERRCODE='PT409',MESSAGE='idempotency_conflict'; END IF;
    RETURN prior.id;
  END IF;
  IF b.id IS NULL THEN
    INSERT INTO certichain_private.blockchain_issuers(deployment_id,institution_id,issuer_id,signer,desired_can_issue,desired_can_revoke)
      VALUES(p_deployment,p_institution,decode(substr(p_i,3),'hex'),decode(substr(p_signer,3),'hex'),p_issue,p_revoke) RETURNING * INTO b;
  ELSE
    IF b.issuer_id<>decode(substr(p_i,3),'hex') THEN RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='blockchain_identity_immutable'; END IF;
    IF ROW(b.signer,b.desired_can_issue,b.desired_can_revoke) IS DISTINCT FROM ROW(decode(substr(p_signer,3),'hex'),p_issue,p_revoke)
      OR (b.sync_state<>'synced' AND EXISTS(SELECT 1 FROM certichain_private.blockchain_operations WHERE issuer_binding_id=b.id AND kind='set_issuer' AND config_version=b.config_version AND state='confirmed')) THEN
      UPDATE certichain_private.blockchain_issuers SET signer=decode(substr(p_signer,3),'hex'),desired_can_issue=p_issue,desired_can_revoke=p_revoke,config_version=config_version+1,sync_state='pending' WHERE blockchain_issuers.id=b.id RETURNING * INTO b;
    END IF;
  END IF;
  INSERT INTO certichain_private.blockchain_operations(issuer_binding_id,deployment_id,kind,requested_by,authorized_by,idempotency_key,payload_digest,target_signer,target_can_issue,target_can_revoke,config_version)
    VALUES(b.id,b.deployment_id,'set_issuer',p_actor,p_actor,p_key,decode(substr(p_payload,3),'hex'),b.signer,p_issue,p_revoke,b.config_version)
    ON CONFLICT (issuer_binding_id,config_version) WHERE kind='set_issuer' DO NOTHING RETURNING blockchain_operations.id INTO id;
  RETURN coalesce(id,(SELECT o.id FROM certichain_private.blockchain_operations o WHERE issuer_binding_id=b.id AND config_version=b.config_version AND kind='set_issuer'));
END $$;
CREATE FUNCTION public.blockchain_close_local(p_operation uuid) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE o certichain_private.blockchain_operations;
BEGIN
  o:=certichain_private.blockchain_lock(p_operation);
  IF o.state<>'confirmed' OR (SELECT network FROM certichain_private.blockchain_deployments WHERE id=o.deployment_id)<>'anvil' THEN RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='invalid_input'; END IF;
  UPDATE certichain_private.blockchain_operations SET closed_at=coalesce(closed_at,clock_timestamp()) WHERE id=o.id;
END $$;
CREATE FUNCTION public.blockchain_purge_raw() RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE count_rows bigint;
BEGIN
  UPDATE certichain_private.blockchain_transaction_attempts t SET raw_signed_tx=NULL FROM certichain_private.blockchain_operations o
    WHERE t.operation_id=o.id AND t.raw_signed_tx IS NOT NULL AND o.closed_at<clock_timestamp()-interval '7 days'
    AND (o.finality='finalized' OR (o.finality='not_applicable' AND o.state='confirmed'));
  GET DIAGNOSTICS count_rows=ROW_COUNT; RETURN count_rows;
END $$;

REVOKE ALL ON FUNCTION certichain_private.blockchain_job(uuid),certichain_private.blockchain_lock(uuid),certichain_private.blockchain_fence(uuid,uuid,bigint),certichain_private.blockchain_authorize(certichain_private.blockchain_operations) FROM PUBLIC,anon,authenticated,service_role;
-- Import only an already observed compatible issue. This does not sign or send.
CREATE FUNCTION public.blockchain_recover_attempt(p_operation uuid,p_token uuid,p_generation bigint,p_tx jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE o certichain_private.blockchain_operations; t certichain_private.blockchain_transaction_attempts; v_signer bytea;
BEGIN
  o:=certichain_private.blockchain_fence(p_operation,p_token,p_generation);
  IF o.kind<>'issue' OR p_tx->>'hash' !~ '^0x[0-9a-f]{64}$' OR p_tx->>'signer' !~ '^0x[0-9a-f]{40}$' OR
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
DO $$ DECLARE f record; BEGIN
  FOR f IN SELECT p.oid::regprocedure AS signature FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname LIKE 'blockchain_%' LOOP
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC,anon,authenticated,service_role',f.signature);
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO service_role',f.signature);
  END LOOP;
END $$;
