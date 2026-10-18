-- 10B: the shared lock helper reports a missing operation as 22023. At this
-- private HTTP boundary absence must be indistinguishable from denied access.
-- Keep the existing parent-first locks and all reauthorization guards intact.
CREATE OR REPLACE FUNCTION public.reauthorize_certificate_revocation(p_actor uuid,p_operation uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE op certichain_private.blockchain_operations; cid uuid;
BEGIN
  BEGIN
    op:=certichain_private.blockchain_lock(p_operation);
  EXCEPTION WHEN invalid_parameter_value THEN
    RAISE EXCEPTION USING ERRCODE='PT404',MESSAGE='revocation_unavailable';
  END;
  IF op.kind IS DISTINCT FROM 'revoke' THEN
    RAISE EXCEPTION USING ERRCODE='PT404',MESSAGE='revocation_unavailable';
  END IF;
  SELECT certificate_id INTO cid FROM certichain_private.certificate_anchors WHERE id=op.anchor_id;
  PERFORM public.blockchain_reauthorize(p_actor,p_operation);
  RETURN public.certificate_revocation_progress(p_actor,cid);
END $$;
REVOKE ALL ON FUNCTION public.reauthorize_certificate_revocation(uuid,uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.reauthorize_certificate_revocation(uuid,uuid) TO service_role;
