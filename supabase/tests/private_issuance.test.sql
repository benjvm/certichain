BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SET LOCAL search_path = public, extensions;
SELECT * FROM no_plan();

INSERT INTO auth.users (id, raw_user_meta_data) VALUES
    ('7a000000-0000-4000-8000-000000000001', '{"full_name":"Synthetic Issuer"}'),
    ('7a000000-0000-4000-8000-000000000002', '{"full_name":"Synthetic Holder"}');
INSERT INTO public.institutions (id, name, slug, verification_status) VALUES
    ('7a000000-0000-4000-8000-000000000011', 'Synthetic One', 'phase7a-one', 'verified'),
    ('7a000000-0000-4000-8000-000000000012', 'Synthetic Two', 'phase7a-two', 'verified');
INSERT INTO public.institution_members (institution_id, user_id, role) VALUES
    ('7a000000-0000-4000-8000-000000000011', '7a000000-0000-4000-8000-000000000001', 'owner'),
    ('7a000000-0000-4000-8000-000000000012', '7a000000-0000-4000-8000-000000000001', 'owner');

-- Historical formats, including absent documents, remain readable and revocable.
INSERT INTO public.certificates (id, holder_id, institution_id, issued_by, title, credential_code,
    document_path, document_hash) VALUES
    ('7a000000-0000-4000-8000-000000000021', '7a000000-0000-4000-8000-000000000002',
     '7a000000-0000-4000-8000-000000000011', '7a000000-0000-4000-8000-000000000001',
     'Historical no PDF', 'phase7a-historical-null', NULL, NULL),
    ('7a000000-0000-4000-8000-000000000022', '7a000000-0000-4000-8000-000000000002',
     '7a000000-0000-4000-8000-000000000011', '7a000000-0000-4000-8000-000000000001',
     'Historical unknown hash', 'phase7a-historical-unknown', 'legacy/object', 'legacy-hash');
SELECT is((SELECT count(*) FROM public.certificates WHERE issuance_operation_id IS NULL),
    2::bigint, 'Historical rows survive with no issuance operation');
SELECT lives_ok($sql$ UPDATE public.certificates SET status = 'revoked'
    WHERE credential_code IN ('phase7a-historical-null', 'phase7a-historical-unknown') $sql$,
    'Future trusted revocation can update old rows irrespective of PDF/hash format');
SELECT is((SELECT count(*) FROM public.certificates WHERE status = 'revoked'
    AND issuance_operation_id IS NULL), 2::bigint, 'Historical values remain unchanged');

INSERT INTO public.certificate_issuance_operations
    (id, institution_id, actor_id, holder_id, idempotency_key, request_fingerprint,
     pdf_hash, target_certificate_id) VALUES
    ('7a000000-0000-4000-8000-000000000031', '7a000000-0000-4000-8000-000000000011',
     '7a000000-0000-4000-8000-000000000001', '7a000000-0000-4000-8000-000000000002',
     '7a000000-0000-4000-8000-000000000041', repeat('a',64), repeat('b',64),
     '7a000000-0000-4000-8000-000000000051');
SELECT is((SELECT status FROM public.certificate_issuance_operations
    WHERE id = '7a000000-0000-4000-8000-000000000031'), 'reserved',
    'Operation starts reserved');
SELECT throws_ok($sql$ INSERT INTO public.certificate_issuance_operations
    (institution_id, actor_id, holder_id, idempotency_key, request_fingerprint, pdf_hash)
    VALUES ('7a000000-0000-4000-8000-000000000011', '7a000000-0000-4000-8000-000000000001',
    '7a000000-0000-4000-8000-000000000002', '7a000000-0000-4000-8000-000000000041',
    repeat('c',64), repeat('b',64)) $sql$, '23505', NULL,
    'Same institutional key cannot create a second operation with different content');
SELECT lives_ok($sql$ INSERT INTO public.certificate_issuance_operations
    (institution_id, actor_id, holder_id, idempotency_key, request_fingerprint, pdf_hash)
    VALUES ('7a000000-0000-4000-8000-000000000012', '7a000000-0000-4000-8000-000000000001',
    '7a000000-0000-4000-8000-000000000002', '7a000000-0000-4000-8000-000000000041',
    repeat('c',64), repeat('b',64)) $sql$, 'Same key is scoped to institution');
SELECT lives_ok($sql$ INSERT INTO public.certificate_issuance_operations
    (institution_id, actor_id, holder_id, idempotency_key, request_fingerprint, pdf_hash)
    VALUES ('7a000000-0000-4000-8000-000000000011', '7a000000-0000-4000-8000-000000000001',
    '7a000000-0000-4000-8000-000000000002', '7a000000-0000-4000-8000-000000000042',
    repeat('a',64), repeat('b',64)) $sql$, 'Different key may have identical content');
SELECT throws_ok($sql$ INSERT INTO public.certificate_issuance_operations
    (institution_id, actor_id, holder_id, idempotency_key, request_fingerprint, pdf_hash)
    VALUES ('7a000000-0000-4000-8000-000000000011', '7a000000-0000-4000-8000-000000000001',
    '7a000000-0000-4000-8000-000000000002', gen_random_uuid(), repeat('A',64), repeat('b',64))
    $sql$, '23514', NULL, 'Request fingerprint requires lowercase hex');
SELECT throws_ok($sql$ INSERT INTO public.certificate_issuance_operations
    (institution_id, actor_id, holder_id, idempotency_key, request_fingerprint, pdf_hash)
    VALUES ('7a000000-0000-4000-8000-000000000011', '7a000000-0000-4000-8000-000000000001',
    '7a000000-0000-4000-8000-000000000002', gen_random_uuid(), repeat('a',64), repeat('b',63))
    $sql$, '23514', NULL, 'PDF hash requires exactly 64 hex characters');
SELECT throws_ok($sql$ UPDATE public.certificate_issuance_operations
    SET status = 'completed' WHERE id = '7a000000-0000-4000-8000-000000000031' $sql$,
    '23514', NULL, 'Cannot finish without stored hash and certificate');
SELECT lives_ok($sql$ UPDATE public.certificate_issuance_operations
    SET status = 'uploading' WHERE id = '7a000000-0000-4000-8000-000000000031' $sql$,
    'Upload state can be persisted');
SELECT throws_ok($sql$ UPDATE public.certificate_issuance_operations
    SET request_fingerprint = repeat('c',64)
    WHERE id = '7a000000-0000-4000-8000-000000000031' $sql$,
    '23514', NULL, 'Reservation fingerprint cannot change after creation');
SELECT lives_ok($sql$ UPDATE public.certificate_issuance_operations
    SET status = 'cleanup_pending' WHERE id = '7a000000-0000-4000-8000-000000000031' $sql$,
    'Cleanup state can be persisted');
SELECT throws_ok($sql$ UPDATE public.certificate_issuance_operations
    SET status = 'finalizing', stored_hash = repeat('C',64)
    WHERE id = '7a000000-0000-4000-8000-000000000031' $sql$,
    '23514', NULL, 'Stored bytes hash requires lowercase hex');
SELECT lives_ok($sql$ UPDATE public.certificate_issuance_operations
    SET status = 'finalizing', stored_hash = repeat('b',64)
    WHERE id = '7a000000-0000-4000-8000-000000000031' $sql$,
    'Finalizing stores verified final bytes hash');
SELECT throws_ok($sql$ INSERT INTO public.certificates
    (id, holder_id, institution_id, issued_by, title, credential_code,
     document_path, document_hash, issuance_operation_id)
    VALUES ('7a000000-0000-4000-8000-000000000051',
    '7a000000-0000-4000-8000-000000000001', '7a000000-0000-4000-8000-000000000011',
    '7a000000-0000-4000-8000-000000000001', 'Wrong holder', 'phase7a-wrong-holder',
    '7a000000-0000-4000-8000-000000000011/7a000000-0000-4000-8000-000000000051.pdf',
    repeat('b',64), '7a000000-0000-4000-8000-000000000031') $sql$,
    '23503', NULL, 'Certificate holder must match its operation');
SELECT throws_ok($sql$ INSERT INTO public.certificates
    (id, holder_id, institution_id, issued_by, title, credential_code,
     document_path, document_hash, issuance_operation_id)
    VALUES ('7a000000-0000-4000-8000-000000000051',
    '7a000000-0000-4000-8000-000000000002', '7a000000-0000-4000-8000-000000000011',
    '7a000000-0000-4000-8000-000000000001', 'Bad path', 'phase7a-bad-path',
    'other/path.pdf', repeat('b',64), '7a000000-0000-4000-8000-000000000031') $sql$,
    '23514', NULL, 'Linked certificate requires opaque canonical path');
SELECT throws_ok($sql$ INSERT INTO public.certificates
    (id, holder_id, institution_id, issued_by, title, credential_code,
     document_path, document_hash, issuance_operation_id)
    VALUES ('7a000000-0000-4000-8000-000000000051',
    '7a000000-0000-4000-8000-000000000002', '7a000000-0000-4000-8000-000000000011',
    '7a000000-0000-4000-8000-000000000001', 'Bad hash', 'phase7a-bad-hash',
    '7a000000-0000-4000-8000-000000000011/7a000000-0000-4000-8000-000000000051.pdf',
    repeat('B',64), '7a000000-0000-4000-8000-000000000031') $sql$,
    '23514', NULL, 'Linked certificate hash requires lowercase hex');
SELECT lives_ok($sql$ INSERT INTO public.certificates
    (id, holder_id, institution_id, issued_by, title, credential_code,
     document_path, document_hash, issuance_operation_id)
    VALUES ('7a000000-0000-4000-8000-000000000051',
    '7a000000-0000-4000-8000-000000000002', '7a000000-0000-4000-8000-000000000011',
    '7a000000-0000-4000-8000-000000000001', 'Valid linked', 'phase7a-linked',
    '7a000000-0000-4000-8000-000000000011/7a000000-0000-4000-8000-000000000051.pdf',
    repeat('b',64), '7a000000-0000-4000-8000-000000000031') $sql$,
    'Verified operation can link exactly its certificate, actor, institution and hash');
SELECT lives_ok($sql$ UPDATE public.certificate_issuance_operations
    SET status = 'completed', certificate_id = target_certificate_id
    WHERE id = '7a000000-0000-4000-8000-000000000031' $sql$,
    'Operation can complete after certificate exists');
SELECT throws_ok($sql$ UPDATE public.certificate_issuance_operations
    SET certificate_id = NULL WHERE id = '7a000000-0000-4000-8000-000000000031' $sql$,
    '23514', NULL, 'Completed operation cannot lose result');
SELECT is((SELECT count(*) FROM public.certificates WHERE issuance_operation_id =
    '7a000000-0000-4000-8000-000000000031'), 1::bigint,
    'Operation has one resulting certificate');
SELECT throws_ok($sql$ UPDATE public.certificates SET title = 'Altered'
    WHERE id = '7a000000-0000-4000-8000-000000000051' $sql$,
    '23514', NULL, 'Published certificate metadata is immutable');
SELECT throws_ok($sql$ UPDATE public.certificate_issuance_operations SET status = 'failed'
    WHERE id = '7a000000-0000-4000-8000-000000000031' $sql$,
    '23514', NULL, 'Completed result is immutable');

SELECT ok((SELECT relrowsecurity FROM pg_class WHERE oid =
    'public.certificate_issuance_operations'::regclass), 'Operations have RLS');
SELECT is((SELECT count(*) FROM pg_policy WHERE polrelid =
    'public.certificate_issuance_operations'::regclass), 0::bigint,
    'No API policy exposes operations');
SELECT ok(NOT has_table_privilege('anon', 'public.certificate_issuance_operations', 'SELECT')
    AND NOT has_table_privilege('authenticated', 'public.certificate_issuance_operations', 'SELECT')
    AND NOT has_table_privilege('authenticated', 'public.certificate_issuance_operations', 'INSERT')
    AND NOT has_table_privilege('authenticated', 'public.certificate_issuance_operations', 'UPDATE')
    AND NOT has_table_privilege('authenticated', 'public.certificate_issuance_operations', 'DELETE'),
    'API roles lack operation grants');
SELECT ok(NOT has_table_privilege('authenticated', 'public.certificate_issuance_operations', 'TRUNCATE')
    AND NOT has_table_privilege('anon', 'public.certificate_issuance_operations', 'TRUNCATE'),
    'API roles cannot truncate operation history');
SELECT ok(NOT has_function_privilege('anon',
    'certichain_private.protect_issuance_operation_update()', 'EXECUTE')
    AND NOT has_function_privilege('authenticated',
    'certichain_private.protect_issuance_operation_update()', 'EXECUTE')
    AND NOT has_function_privilege('service_role',
    'certichain_private.protect_issuance_operation_update()', 'EXECUTE')
    AND NOT has_function_privilege('authenticated',
    'certichain_private.protect_issued_certificate_update()', 'EXECUTE'),
    'New trigger functions have no direct API execution grant');
SELECT set_config('request.jwt.claim.sub', '7a000000-0000-4000-8000-000000000001', true);
SET LOCAL ROLE authenticated;
SELECT throws_ok($sql$ SELECT * FROM public.certificate_issuance_operations $sql$,
    '42501', NULL, 'Authenticated issuer cannot read operation details');
SELECT throws_ok($sql$ INSERT INTO public.certificate_issuance_operations
    (institution_id, actor_id, holder_id, idempotency_key, request_fingerprint, pdf_hash)
    VALUES ('7a000000-0000-4000-8000-000000000011', auth.uid(),
    '7a000000-0000-4000-8000-000000000002', gen_random_uuid(), repeat('a',64), repeat('b',64))
    $sql$, '42501', NULL, 'Authenticated issuer cannot reserve operation');
SELECT throws_ok($sql$ UPDATE public.certificate_issuance_operations SET status = 'failed' $sql$,
    '42501', NULL, 'Authenticated issuer cannot alter operation');
SELECT throws_ok($sql$ INSERT INTO public.certificates
    (holder_id, institution_id, issued_by, title, credential_code)
    VALUES ('7a000000-0000-4000-8000-000000000002',
    '7a000000-0000-4000-8000-000000000011', auth.uid(), 'Direct', 'phase7a-direct')
    $sql$, '42501', NULL, 'Authenticated issuer still cannot insert certificates');
RESET ROLE;
SET LOCAL ROLE anon;
SELECT throws_ok($sql$ SELECT * FROM public.certificate_issuance_operations $sql$,
    '42501', NULL, 'Anon cannot read operations');
SELECT throws_ok($sql$ DELETE FROM public.certificate_issuance_operations $sql$,
    '42501', NULL, 'Anon cannot delete operations');
SELECT throws_ok($sql$ INSERT INTO public.certificates
    (holder_id, institution_id, issued_by, title, credential_code)
    VALUES ('7a000000-0000-4000-8000-000000000002',
    '7a000000-0000-4000-8000-000000000011',
    '7a000000-0000-4000-8000-000000000001', 'Direct', 'phase7a-anon')
    $sql$, '42501', NULL, 'Anon still cannot insert certificates');
RESET ROLE;

SELECT is((SELECT file_size_limit FROM storage.buckets WHERE id = 'certificates'),
    8388608::bigint, 'Bucket enforces exactly 8 MiB');
SELECT ok((SELECT NOT public AND allowed_mime_types = ARRAY['application/pdf']::text[]
    FROM storage.buckets WHERE id = 'certificates'), 'Bucket is private and PDF only');
SELECT is((SELECT count(*) FROM pg_policies WHERE schemaname = 'storage'
    AND tablename = 'objects' AND policyname LIKE 'certificates_objects_no_client_%'
    AND permissive = 'RESTRICTIVE' AND roles @> ARRAY['anon','authenticated']::name[]),
    4::bigint, 'Four restrictive object policies cover both API roles');
SELECT * FROM finish();
ROLLBACK;
