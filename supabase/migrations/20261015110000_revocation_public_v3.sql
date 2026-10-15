-- Explicit v3 snapshot, one statement/eligibility shared literally with v2. No private reason/actor.
CREATE FUNCTION public.lookup_public_certificate_v3(p_credential_code text, p_environment text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE result jsonb; checked timestamptz := clock_timestamp();
BEGIN
  IF p_credential_code IS NULL OR length(p_credential_code) <> 36
    OR p_credential_code !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    OR p_environment IS NULL OR length(p_environment) NOT BETWEEN 1 AND 128 THEN
    RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='invalid_input';
  END IF;
  -- One SQL statement/snapshot; eligibility is literal to the existing 8C helper.
  SELECT jsonb_build_object('registry', jsonb_build_object(
    'schema_version','1','result',certichain_private.public_verification_result(
      c.status='revoked',c.expires_at,i.verification_status='verified',checked),
    'credential_code',c.credential_code,'title',c.title,'issuer',jsonb_build_object('name',i.name),
    'issued_at',c.issued_at,'expires_at',c.expires_at,'checked_at',checked,
    'verification_source','certichain_registry'),
    'revocation',jsonb_build_object('revoked_at',c.revoked_at,'expected',rv.id IS NOT NULL,
      'state',rv.state,'transaction_hash',CASE WHEN rt.id IS NULL THEN NULL ELSE '0x'||encode(rt.transaction_hash,'hex') END,
      'signer',CASE WHEN rt.id IS NULL THEN NULL ELSE '0x'||encode(rt.signer,'hex') END,
      'previous',CASE WHEN rt.receipt_status=1 AND rt.validated_log_index IS NOT NULL THEN jsonb_build_object(
        'transaction_hash','0x'||encode(rt.transaction_hash,'hex'),'block_number',rt.block_number::text,
        'block_hash','0x'||encode(rt.block_hash,'hex'),'checked_at',rt.observed_at) ELSE NULL END),
    'anchor', CASE WHEN a.id IS NULL THEN NULL ELSE jsonb_build_object(
      'deployment',jsonb_build_object('environment_id',d.environment_id,'network',d.network,
        'chain_id',d.chain_id::text,'contract_address','0x'||encode(d.contract_address,'hex'),
        'protocol_version',d.protocol_version,'runtime_code_hash','0x'||encode(d.runtime_code_hash,'hex'),
        'genesis_hash','0x'||encode(d.genesis_hash,'hex'),'deployment_block',d.deployment_block::text,
        'deployment_hash','0x'||encode(d.deployment_hash,'hex')),
      'certificate_key','0x'||encode(a.certificate_key,'hex'),'issuer_id','0x'||encode(b.issuer_id,'hex'),
      'commitment','0x'||encode(a.commitment,'hex'),'state',CASE WHEN o.state='cancelled' THEN 'blocked' ELSE o.state END,
      'transaction_hash',CASE WHEN t.id IS NULL THEN NULL ELSE '0x'||encode(t.transaction_hash,'hex') END,
      'signer',CASE WHEN t.id IS NULL THEN NULL ELSE '0x'||encode(t.signer,'hex') END,
      'last_evidence',prior.evidence) END)
  INTO result
  FROM public.certificates c
  JOIN public.certificate_issuance_operations op ON op.id=c.issuance_operation_id
  JOIN public.institutions i ON i.id=c.institution_id
  LEFT JOIN LATERAL (SELECT x.* FROM certichain_private.certificate_anchors x
    JOIN certichain_private.blockchain_deployments dep ON dep.id=x.deployment_id
    WHERE x.certificate_id=c.id AND dep.environment_id=p_environment
    ORDER BY dep.enabled DESC,x.created_at DESC LIMIT 1) a ON a.issuance_operation_id=op.id AND a.institution_id=c.institution_id
    AND a.credential_code_snapshot::text=c.credential_code
  LEFT JOIN certichain_private.blockchain_deployments d ON d.id=a.deployment_id
  LEFT JOIN certichain_private.blockchain_issuers b ON b.id=a.issuer_binding_id
    AND b.deployment_id=d.id AND b.institution_id=c.institution_id
  LEFT JOIN certichain_private.blockchain_operations o ON o.anchor_id=a.id AND o.kind='issue'
    AND o.issuer_binding_id=b.id AND o.deployment_id=d.id
  LEFT JOIN LATERAL (SELECT x.* FROM certichain_private.blockchain_transaction_attempts x
    WHERE x.operation_id=o.id AND x.deployment_id=d.id
    ORDER BY (x.id=o.canonical_attempt_id) DESC NULLS LAST,x.attempt_number DESC LIMIT 1) t ON true
  LEFT JOIN LATERAL (
    SELECT jsonb_build_object('state',CASE WHEN x.state='orphaned' OR o.state='reorged' THEN 'reorged'
        WHEN o.canonical_attempt_id=x.id AND x.state='included' AND o.confirmations>=d.confirmations_required THEN 'confirmed' ELSE 'included' END,
      'finality',CASE WHEN o.canonical_attempt_id=x.id AND x.state='included' THEN o.finality ELSE 'unknown' END,
      'chain_id',d.chain_id::text,'contract_address','0x'||encode(d.contract_address,'hex'),
      'protocol_version',d.protocol_version,'certificate_key','0x'||encode(a.certificate_key,'hex'),
      'issuer_id','0x'||encode(b.issuer_id,'hex'),'commitment','0x'||encode(a.commitment,'hex'),
      'revoked',false,'transaction_hash','0x'||encode(x.transaction_hash,'hex'),
      'block_number',v->>'block_number','block_hash',v->>'block_hash',
      'confirmations',CASE WHEN o.canonical_attempt_id=x.id AND x.state='included' THEN o.confirmations::text ELSE '0' END,
      'checked_at',CASE WHEN o.canonical_attempt_id=x.id AND x.state='included' THEN coalesce(to_jsonb(o.checked_at),v->'observed_at')
        ELSE v->'observed_at' END,'source','persisted_receipt') evidence
    FROM certichain_private.blockchain_transaction_attempts x
    CROSS JOIN LATERAL jsonb_array_elements(x.receipt_observations) WITH ORDINALITY r(v,n)
    WHERE x.operation_id=o.id AND x.deployment_id=d.id AND v->>'status'='1'
      AND v->>'validated_log_index' IS NOT NULL AND v->>'canonical'='true'
    ORDER BY (x.id=o.canonical_attempt_id) DESC NULLS LAST,x.attempt_number DESC,n DESC LIMIT 1
  ) prior ON true
  LEFT JOIN certichain_private.blockchain_operations rv ON rv.anchor_id=a.id AND rv.kind='revoke'
  LEFT JOIN LATERAL (SELECT x.* FROM certichain_private.blockchain_transaction_attempts x WHERE x.operation_id=rv.id
    ORDER BY (x.id=rv.canonical_attempt_id) DESC NULLS LAST,x.attempt_number DESC LIMIT 1) rt ON true
  WHERE c.credential_code=lower(p_credential_code) AND op.status='completed'
    AND op.certificate_id=c.id AND op.target_certificate_id=c.id
    AND op.institution_id=c.institution_id AND op.holder_id=c.holder_id AND op.actor_id=c.issued_by
    AND c.document_hash ~ '^[0-9a-f]{64}$' AND c.document_hash=op.stored_hash AND c.document_hash=op.pdf_hash
    AND c.document_path=c.institution_id::text||'/'||c.id::text||'.pdf';
  RETURN coalesce(result,jsonb_build_object('registry',jsonb_build_object('schema_version','1','result','not_found'),'anchor',NULL,'revocation',NULL));
END $$;
REVOKE ALL ON FUNCTION public.lookup_public_certificate_v3(text,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.lookup_public_certificate_v3(text,text) TO service_role;

-- Map private cancellation into the existing closed v2 technical snapshot.
CREATE OR REPLACE FUNCTION public.lookup_public_certificate_v2(p_credential_code text, p_environment text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE result jsonb; checked timestamptz := clock_timestamp();
BEGIN
  IF p_credential_code IS NULL OR length(p_credential_code) <> 36
    OR p_credential_code !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    OR p_environment IS NULL OR length(p_environment) NOT BETWEEN 1 AND 128 THEN
    RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='invalid_input';
  END IF;
  -- One SQL statement/snapshot; eligibility is literal to the existing 8C helper.
  SELECT jsonb_build_object('registry', jsonb_build_object(
    'schema_version','1','result',certichain_private.public_verification_result(
      c.status='revoked',c.expires_at,i.verification_status='verified',checked),
    'credential_code',c.credential_code,'title',c.title,'issuer',jsonb_build_object('name',i.name),
    'issued_at',c.issued_at,'expires_at',c.expires_at,'checked_at',checked,
    'verification_source','certichain_registry'),
    'anchor', CASE WHEN a.id IS NULL THEN NULL ELSE jsonb_build_object(
      'deployment',jsonb_build_object('environment_id',d.environment_id,'network',d.network,
        'chain_id',d.chain_id::text,'contract_address','0x'||encode(d.contract_address,'hex'),
        'protocol_version',d.protocol_version,'runtime_code_hash','0x'||encode(d.runtime_code_hash,'hex'),
        'genesis_hash','0x'||encode(d.genesis_hash,'hex'),'deployment_block',d.deployment_block::text,
        'deployment_hash','0x'||encode(d.deployment_hash,'hex')),
      'certificate_key','0x'||encode(a.certificate_key,'hex'),'issuer_id','0x'||encode(b.issuer_id,'hex'),
      'commitment','0x'||encode(a.commitment,'hex'),'state',CASE WHEN o.state='cancelled' THEN 'blocked' ELSE o.state END,
      'transaction_hash',CASE WHEN t.id IS NULL THEN NULL ELSE '0x'||encode(t.transaction_hash,'hex') END,
      'signer',CASE WHEN t.id IS NULL THEN NULL ELSE '0x'||encode(t.signer,'hex') END,
      'last_evidence',prior.evidence) END)
  INTO result
  FROM public.certificates c
  JOIN public.certificate_issuance_operations op ON op.id=c.issuance_operation_id
  JOIN public.institutions i ON i.id=c.institution_id
  LEFT JOIN LATERAL (SELECT x.* FROM certichain_private.certificate_anchors x
    JOIN certichain_private.blockchain_deployments dep ON dep.id=x.deployment_id
    WHERE x.certificate_id=c.id AND dep.environment_id=p_environment
    ORDER BY dep.enabled DESC,x.created_at DESC LIMIT 1) a ON a.issuance_operation_id=op.id AND a.institution_id=c.institution_id
    AND a.credential_code_snapshot::text=c.credential_code
  LEFT JOIN certichain_private.blockchain_deployments d ON d.id=a.deployment_id
  LEFT JOIN certichain_private.blockchain_issuers b ON b.id=a.issuer_binding_id
    AND b.deployment_id=d.id AND b.institution_id=c.institution_id
  LEFT JOIN certichain_private.blockchain_operations o ON o.anchor_id=a.id AND o.kind='issue'
    AND o.issuer_binding_id=b.id AND o.deployment_id=d.id
  LEFT JOIN LATERAL (SELECT x.* FROM certichain_private.blockchain_transaction_attempts x
    WHERE x.operation_id=o.id AND x.deployment_id=d.id
    ORDER BY (x.id=o.canonical_attempt_id) DESC NULLS LAST,x.attempt_number DESC LIMIT 1) t ON true
  LEFT JOIN LATERAL (
    SELECT jsonb_build_object('state',CASE WHEN x.state='orphaned' OR o.state='reorged' THEN 'reorged'
        WHEN o.canonical_attempt_id=x.id AND x.state='included' AND o.confirmations>=d.confirmations_required THEN 'confirmed' ELSE 'included' END,
      'finality',CASE WHEN o.canonical_attempt_id=x.id AND x.state='included' THEN o.finality ELSE 'unknown' END,
      'chain_id',d.chain_id::text,'contract_address','0x'||encode(d.contract_address,'hex'),
      'protocol_version',d.protocol_version,'certificate_key','0x'||encode(a.certificate_key,'hex'),
      'issuer_id','0x'||encode(b.issuer_id,'hex'),'commitment','0x'||encode(a.commitment,'hex'),
      'revoked',false,'transaction_hash','0x'||encode(x.transaction_hash,'hex'),
      'block_number',v->>'block_number','block_hash',v->>'block_hash',
      'confirmations',CASE WHEN o.canonical_attempt_id=x.id AND x.state='included' THEN o.confirmations::text ELSE '0' END,
      'checked_at',CASE WHEN o.canonical_attempt_id=x.id AND x.state='included' THEN coalesce(to_jsonb(o.checked_at),v->'observed_at')
        ELSE v->'observed_at' END,'source','persisted_receipt') evidence
    FROM certichain_private.blockchain_transaction_attempts x
    CROSS JOIN LATERAL jsonb_array_elements(x.receipt_observations) WITH ORDINALITY r(v,n)
    WHERE x.operation_id=o.id AND x.deployment_id=d.id AND v->>'status'='1'
      AND v->>'validated_log_index' IS NOT NULL AND v->>'canonical'='true'
    ORDER BY (x.id=o.canonical_attempt_id) DESC NULLS LAST,x.attempt_number DESC,n DESC LIMIT 1
  ) prior ON true
  WHERE c.credential_code=lower(p_credential_code) AND op.status='completed'
    AND op.certificate_id=c.id AND op.target_certificate_id=c.id
    AND op.institution_id=c.institution_id AND op.holder_id=c.holder_id AND op.actor_id=c.issued_by
    AND c.document_hash ~ '^[0-9a-f]{64}$' AND c.document_hash=op.stored_hash AND c.document_hash=op.pdf_hash
    AND c.document_path=c.institution_id::text||'/'||c.id::text||'.pdf';
  RETURN coalesce(result,jsonb_build_object('registry',jsonb_build_object('schema_version','1','result','not_found'),'anchor',NULL));
END $$;
