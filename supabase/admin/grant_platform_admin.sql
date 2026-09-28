-- Run only through trusted psql as postgres. No target or credentials in Git.
\set ON_ERROR_STOP on
\if :{?target_id}
\else
    \echo 'Required: target_id'
    \quit 3
\endif
\if :{?confirm_target_id}
\else
    \echo 'Required: confirm_target_id (independently reviewed)'
    \quit 3
\endif
\if :{?expected_admin_count}
\else
    \echo 'Required: expected_admin_count (0 only for initial bootstrap)'
    \quit 3
\endif

BEGIN;
SELECT certichain_private.grant_platform_admin(
    :'target_id'::uuid, :'confirm_target_id'::uuid, :'expected_admin_count'::integer
) AS result, :'target_id'::uuid AS confirmed_target;
COMMIT;
