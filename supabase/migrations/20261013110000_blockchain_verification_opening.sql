-- 9D: narrow technical projections only. No table grants, DML or backfill.
CREATE FUNCTION public.lookup_public_certificate_v2(p_credential_code text, p_environment text)
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
      'commitment','0x'||encode(a.commitment,'hex'),'state',o.state,
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
REVOKE ALL ON FUNCTION public.lookup_public_certificate_v2(text,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.lookup_public_certificate_v2(text,text) TO service_role;

CREATE FUNCTION public.authorize_certificate_opening(p_certificate uuid,p_actor uuid,p_environment text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE result jsonb;
BEGIN
  IF p_environment IS NULL OR length(p_environment) NOT BETWEEN 1 AND 128 THEN
    RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='invalid_input';
  END IF;
  SELECT jsonb_build_object('protocol_version',d.protocol_version,'credential_code',c.credential_code,
    'issuer_id','0x'||encode(b.issuer_id,'hex'),'document_sha256','0x'||encode(a.document_sha256,'hex'),
    'salt','0x'||encode(a.salt,'hex'),'chain_id',d.chain_id::text,
    'contract_address','0x'||encode(d.contract_address,'hex')) INTO result
  FROM public.certificates c
  JOIN public.certificate_issuance_operations op ON op.id=c.issuance_operation_id
  JOIN certichain_private.certificate_anchors a ON a.certificate_id=c.id AND a.issuance_operation_id=op.id
    AND a.institution_id=c.institution_id AND a.credential_code_snapshot::text=c.credential_code
  JOIN certichain_private.blockchain_issuers b ON b.id=a.issuer_binding_id
    AND b.institution_id=c.institution_id AND b.deployment_id=a.deployment_id
  JOIN certichain_private.blockchain_deployments d ON d.id=a.deployment_id AND d.environment_id=p_environment
  WHERE c.id=p_certificate AND op.status='completed'
    AND op.certificate_id=c.id AND op.target_certificate_id=c.id
    AND op.institution_id=c.institution_id AND op.holder_id=c.holder_id AND op.actor_id=c.issued_by
    AND c.document_hash ~ '^[0-9a-f]{64}$' AND c.document_hash=op.stored_hash AND c.document_hash=op.pdf_hash
    AND c.document_path=c.institution_id::text||'/'||c.id::text||'.pdf'
    AND a.document_sha256=decode(c.document_hash,'hex')
    AND a.certificate_key=extensions.digest(convert_to('certichain:certificate-key:v1','UTF8')||decode('00','hex')||uuid_send(a.credential_code_snapshot),'sha256')
    AND a.commitment=extensions.digest(convert_to('certichain:document-commitment:v1','UTF8')||decode('00','hex')||a.certificate_key||b.issuer_id||a.document_sha256||a.salt,'sha256')
    AND EXISTS(SELECT 1 FROM auth.users u WHERE u.id=p_actor AND u.deleted_at IS NULL
      AND NOT coalesce(u.is_anonymous,false) AND (u.banned_until IS NULL OR u.banned_until<=clock_timestamp()))
    AND (c.holder_id=p_actor OR EXISTS(SELECT 1 FROM public.institution_members m
      JOIN public.institutions i ON i.id=m.institution_id
      WHERE m.institution_id=c.institution_id AND m.user_id=p_actor
        AND m.role IN ('owner','admin','issuer') AND i.verification_status='verified'))
  ORDER BY d.enabled DESC,a.created_at DESC LIMIT 1;
  RETURN result; -- foreign/missing/incoherent/no anchor share NULL
END $$;
REVOKE ALL ON FUNCTION public.authorize_certificate_opening(uuid,uuid,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.authorize_certificate_opening(uuid,uuid,text) TO service_role;
