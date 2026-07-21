import { accountDeletionStatusFor } from "./account-deletion-v1.ts";

function assertEquals(actual: unknown, expected: unknown): void {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error(
      `Expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`,
    );
  }
}

Deno.test("blocked deletions surface as conflicts", () => {
  assertEquals(accountDeletionStatusFor("account_deletion_blocked"), 409);
});

Deno.test("auth and flag failures keep their transport semantics", () => {
  assertEquals(accountDeletionStatusFor("unauthenticated"), 401);
  assertEquals(accountDeletionStatusFor("forbidden"), 403);
  assertEquals(accountDeletionStatusFor("native_writes_disabled"), 503);
  assertEquals(accountDeletionStatusFor("anything_else"), 400);
});
