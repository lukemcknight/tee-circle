// Status mapping for the delete-account-v1 edge command. Kept separate from
// the handler so the contract is unit-testable without Deno.serve.

export function accountDeletionStatusFor(code: string): number {
  if (code === "unauthenticated") return 401;
  if (code === "forbidden") return 403;
  if (code === "account_deletion_blocked") return 409;
  if (code === "native_writes_disabled") return 503;
  return 400;
}
