-- Local trusted SQL walkthrough. Always rolls back; never run as a user RPC.
\set ON_ERROR_STOP on
\if :{?admin_id}
\else
    \echo 'Required: admin_id'
    \quit 3
\endif
\if :{?confirm_admin_id}
\else
    \echo 'Required: confirm_admin_id'
    \quit 3
\endif
\if :{?expected_admin_count}
\else
    \echo 'Required: expected_admin_count'
    \quit 3
\endif
\if :{?owner_id}
\else
    \echo 'Required: owner_id'
    \quit 3
\endif
\if :{?member_id}
\else
    \echo 'Required: member_id'
    \quit 3
\endif

BEGIN;
SELECT certichain_private.grant_platform_admin(
    :'admin_id'::uuid, :'confirm_admin_id'::uuid, :'expected_admin_count'::integer
) AS bootstrap_result;
SELECT set_config('request.jwt.claim.sub', :'admin_id', true);
SELECT set_config('request.jwt.claims', jsonb_build_object('sub', :'admin_id', 'role', 'authenticated')::text, true);
SET LOCAL ROLE authenticated;
SELECT public.create_institution('Local institutional walkthrough', 'local-walkthrough-' || gen_random_uuid()::text,
    :'owner_id'::uuid) AS institution_id \gset
SELECT id, verification_status FROM public.institutions WHERE id = :'institution_id'::uuid;
SELECT role, count(*) FROM public.institution_members WHERE institution_id = :'institution_id'::uuid GROUP BY role;
SELECT public.set_institution_status(:'institution_id'::uuid, 'verified');
SELECT id, verification_status FROM public.institutions WHERE id = :'institution_id'::uuid;
RESET ROLE;

SELECT set_config('request.jwt.claim.sub', :'owner_id', true);
SELECT set_config('request.jwt.claims', jsonb_build_object('sub', :'owner_id', 'role', 'authenticated')::text, true);
SET LOCAL ROLE authenticated;
SELECT public.set_institution_member(:'institution_id'::uuid, :'member_id'::uuid, 'issuer');
SELECT role, count(*) FROM public.institution_members WHERE institution_id = :'institution_id'::uuid GROUP BY role;
SELECT public.set_institution_member(:'institution_id'::uuid, :'member_id'::uuid, 'admin');
SELECT role, count(*) FROM public.institution_members WHERE institution_id = :'institution_id'::uuid GROUP BY role;
RESET ROLE;

SELECT set_config('request.jwt.claim.sub', :'admin_id', true);
SELECT set_config('request.jwt.claims', jsonb_build_object('sub', :'admin_id', 'role', 'authenticated')::text, true);
SET LOCAL ROLE authenticated;
SELECT public.set_institution_status(:'institution_id'::uuid, 'suspended');
SELECT id, verification_status FROM public.institutions WHERE id = :'institution_id'::uuid;
RESET ROLE;
SET CONSTRAINTS ALL IMMEDIATE;
ROLLBACK;
\echo 'Walkthrough completed; all changes rolled back. No certificates were written.'
