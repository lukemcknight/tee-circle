# `revenuecat-webhook-v1`

Configure the RevenueCat webhook URL to this function and set its Authorization
header to the exact value stored in the server-only
`REVENUECAT_WEBHOOK_AUTHORIZATION` secret. `REVENUECAT_APP_ID` must also be set.

Only `NON_RENEWING_PURCHASE` for `com.teecircle.app.trip_unlock_2999` is
handled. Other authenticated event types are acknowledged without changing data.
Transaction uniqueness and the service-role-only claim RPC make webhook retries
idempotent. One pending intent is allowed per user/product. Delayed webhooks may
repair an expired or cancelled intent only when RevenueCat's verified purchase
timestamp falls inside that intent's original window; the most recently opened
matching intent wins deterministically.
