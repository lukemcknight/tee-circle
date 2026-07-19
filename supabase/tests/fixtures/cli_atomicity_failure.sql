-- This relation and the migration-history row must both roll back. The
-- deliberate exception verifies Supabase CLI keeps a wrapper-free migration
-- and its appended ledger insert in one implicit transaction.
create table public.cli_atomicity_must_rollback (id bigint primary key);

do $$
begin
  raise exception using
    errcode = 'P0001',
    message = 'intentional_cli_atomicity_test_failure';
end
$$;
