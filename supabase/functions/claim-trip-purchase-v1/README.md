# `claim-trip-purchase-v1`

Authenticated purchase claim used by the native app. It requires these
server-only Supabase Edge Function secrets:

- `REVENUECAT_V2_SECRET_API_KEY`, with RevenueCat v2
  `customer_information:purchases:read` and
  `project_configuration:products:read` permissions.
- `REVENUECAT_PROJECT_ID`
- `REVENUECAT_APP_ID`

The function never accepts a RevenueCat secret or user identity from the client.
It verifies the App Store transaction, Supabase UUID, RevenueCat app, store
product identifier, and consumable product type before calling the
service-role-only `verify_trip_purchase_v1` RPC. The verified purchase
environment and purchase timestamp are persisted. Sandbox receipts are eligible
only while the server's TestFlight flag is explicitly enabled.
