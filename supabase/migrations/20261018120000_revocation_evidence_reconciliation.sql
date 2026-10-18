-- 10C. Preserve identities, historical receipts, authorization and the existing nonce ledger.
-- No backfill, certificate mutation, new grants or alternate ledger.
CREATE OR REPLACE FUNCTION public.blockchain_update_job(p_operation uuid,p_token uuid,p_generation bigint,p_action text,p_detail jsonb DEFAULT '{}')
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
      canonical_attempt_id=CASE WHEN v_state='divergence' THEN NULL ELSE canonical_attempt_id END,
      confirmations=CASE WHEN v_state='divergence' THEN 0 ELSE confirmations END,
      finality=CASE WHEN v_state='divergence' THEN 'unknown' ELSE finality END,
      next_attempt_at=clock_timestamp()+make_interval(secs=>least(300,15*power(2,least(retry_count,5)))::integer),lease_token=NULL,lease_until=NULL,updated_at=clock_timestamp() WHERE id=o.id;
  ELSIF p_action='reconciled' THEN
    -- Revalidated consumed receipts must remain eligible for subsequent explicit
    -- recovery without replaying their old failed operation transition.
    UPDATE certichain_private.blockchain_transaction_attempts SET observed_at=clock_timestamp()
      WHERE operation_id=o.id AND transaction_hash=decode(substr(p_detail->>'hash',3),'hex');
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='invalid_input'; END IF;
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

