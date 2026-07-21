# `delete-account-v1`

Authenticated full account deletion. The caller's JWT is verified, then
`finalize_account_deletion_v1()` runs as the user: it re-checks ownership
blockers (active owned trips fail closed with `account_deletion_blocked`),
erases the user's owned finished trips and every personal artifact, and
detaches their contributions from surviving groups (seats released,
scores/invites/purchase intents reattributed to the trip owner). Only after
the data pass succeeds does the service-role Auth Admin API delete the
`auth.users` row — SQL cannot.

If auth deletion fails after the data pass, the endpoint returns retryable
`auth_deletion_incomplete`; replaying the request is safe (the data pass
finds nothing left to do).
