# CamoTracker App Store notifications worker

A small Cloudflare Worker that receives [App Store Server Notifications V2](https://developer.apple.com/documentation/appstoreservernotifications)
from App Store Connect — purchases, renewals, cancellations, refunds, etc. — verifies Apple's
signature, and emails a summary via [Resend](https://resend.com).

GitHub Pages (where the rest of this repo is hosted) can't run server code, so this lives in its
own small deployable project.

> **This repo is public.** Only `APP_BUNDLE_ID` and `APP_APPLE_ID` — both already publicly visible
> via the App Store listing — go in the committed `wrangler.toml`. Your notify/from email addresses
> and the Resend API key are set as Cloudflare Worker **secrets** (`wrangler secret put`), which are
> stored encrypted on Cloudflare and never appear in this repo or its git history.

## One-time setup

1. **Install dependencies**
   ```sh
   cd appstore-notifications-worker
   npm install
   ```

2. **Log in to Cloudflare**
   ```sh
   npx wrangler login
   ```

3. **Create a Resend account and API key** at https://resend.com, and verify a sending domain (or
   use their shared test domain while you're getting this working). Create an API key.

4. **Fill in `wrangler.toml`** (only the non-sensitive `[vars]` — this repo is public, so nothing
   that identifies you personally belongs in a committed file)
   - `APP_BUNDLE_ID` is already set to `com.DannyRyman.MW4CamoTracker`.
   - `APP_APPLE_ID`: the app's numeric Apple ID, found in App Store Connect under
     **App Information → General Information → Apple ID**. Only needed to verify *production*
     notifications — sandbox testing works without it. This is already public (it's in every
     App Store URL for the app), so it's fine as a plain var.

5. **Set the rest as secrets** — these never get written to any file, so they never end up in
   git history on this public repo:
   ```sh
   npx wrangler secret put RESEND_API_KEY
   npx wrangler secret put NOTIFY_EMAIL       # where alerts get sent
   npx wrangler secret put NOTIFY_FROM_EMAIL  # the "from" address (must be on a domain verified
                                               # in Resend, or onboarding@resend.dev for testing)
   ```

6. **Deploy**
   ```sh
   npm run deploy
   ```
   Wrangler prints the deployed URL, e.g. `https://camotracker-appstore-notifications.<your-subdomain>.workers.dev`.

## Wire it up in App Store Connect

Go to **App Store Connect → your app → App Information → App Store Server Notifications**, choose
**Version 2**, and set:

- **Production Server URL**: `https://<your-worker-url>/production`
- **Sandbox Server URL**: `https://<your-worker-url>/sandbox`

(The worker uses separate paths for each so it always knows which environment it's verifying
against, instead of trusting an unverified field in the payload to decide.)

## Test it

- In App Store Connect, use the **Send Test Notification** button next to each URL — a `TEST`
  notification should arrive by email within a few seconds.
- Watch live logs while testing:
  ```sh
  npx wrangler tail
  ```
- `GET /health` returns `ok` if you just want to confirm the worker is deployed and reachable.

Once real traffic flows, you'll get an email for every subscription/purchase lifecycle event Apple
sends — `SUBSCRIBED`, `DID_RENEW`, `DID_FAIL_TO_RENEW`, `EXPIRED`, `REFUND`, `REVOKE`, `PRICE_INCREASE`,
etc. See Apple's [`notificationType`](https://developer.apple.com/documentation/appstoreservernotifications/notificationtype)
docs for the full list.

## How verification works

Every notification arrives as a signed JWT (`signedPayload`). The worker uses Apple's own
[`@apple/app-store-server-library`](https://github.com/apple/app-store-server-library-node) to:

1. Fetch Apple's Root CA (G3) certificate (cached for a day).
2. Verify the notification's certificate chain back to that root and check its signature.
3. Decode the notification, then separately verify-and-decode the embedded transaction and
   renewal info (each is its own signed JWT).

Only after all of that succeeds does it send an email — forged or tampered payloads are rejected
with a 4xx before anything is emailed. Online revocation (OCSP) checking is intentionally left off
since Apple's signing certs are effectively never revoked, and it would make every request depend
on a third-party responder being reachable.

## Implementation note

`@apple/app-store-server-library` pulls in `jsrsasign`, which does work at module-evaluation time
that the Workers runtime only permits inside a request handler. Importing the library statically
at the top of the file crashes the worker on startup. `src/index.ts` works around this with a
`import('@apple/app-store-server-library')` performed lazily from inside `fetch()` instead — don't
change that back to a static import.

## Local development

```sh
npm run dev       # wrangler dev, simulates the worker locally
npm run typecheck # tsc --noEmit
```

Local dev can verify the request pipeline (routing, JSON parsing, error handling), but actually
verifying a signature end-to-end requires reaching `www.apple.com` to fetch the root cert and a
real signed payload from Apple — easiest to test after deploying, via **Send Test Notification** in
App Store Connect.
