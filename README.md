# Jewellery ERP - Flutter app

Native Flutter client for the shared NestJS API described in
`MOBILE_APP_DEVELOPER_HANDOFF_REPORT.md`.

## Run it

```bash
flutter create . --project-name jewellery_erp --org com.yourcompany   # generates android/ and ios/
flutter pub get
flutter run
```

Set the server on the login screen (tap the address at the bottom):
- Android emulator: `http://10.0.2.2:3000/api/v1` (default)
- iOS simulator: `http://localhost:3000/api/v1`
- Real phone: `http://<your-laptop-wifi-ip>:3000/api/v1`

### Platform setup (after `flutter create .`)

**Android** - `android/app/src/main/AndroidManifest.xml`, inside `<manifest>`:
```xml
<uses-permission android:name="android.permission.INTERNET"/>
<uses-permission android:name="android.permission.CAMERA"/>
```
and on `<application>` for local HTTP testing only: `android:usesCleartextTraffic="true"`.
Set `minSdkVersion 23` in `android/app/build.gradle`.

**iOS** - `ios/Runner/Info.plist`:
```xml
<key>NSCameraUsageDescription</key>
<string>The camera scans barcodes on jewellery tags.</string>
```
For local HTTP testing add an `NSAppTransportSecurity` exception (remove for production).

## Structure

```
lib/
  main.dart                  app root + auth gate
  core/
    theme.dart               palette + type (Fraunces / Manrope)
    api.dart                 Dio + persistent cookie jar, envelope unwrapping, error mapping
    app_state.dart           login -> MFA -> showroom -> ready
    rates.dart               live bullion board (60 s refresh)
    format.dart              string-only INR / gram formatting
    widgets.dart             Panel, StatusPill, skeletons, gem mark...
  features/
    auth/                    login, 2FA, showroom picker
    home/                    rate plate, today strip, quick actions
    inventory/               barcode scanner, stock lookup
    billing/                 POS cart, payments, idempotent checkout, receipt
    customers/               list, search, create, picker
    more/                    old gold, counter shift, records viewer, account
```

## Rules from the API guide, and where they live

| Rule | Implementation |
| --- | --- |
| No float/double for weights or money | Values stay strings; `format.dart` is string-only; `Decimal` for the old-gold preview |
| `Idempotency-Key` on billing POST | `BillingController` - new UUID whenever the bill changes, reused on retry |
| Envelope `{data, meta}` / `{error}` | `ApiClient._send` |
| Session cookie persistence | `PersistCookieJar` |
| Pessimistic barcode lock | `addArticle` calls `POST /inventory/articles/:id/reserve` |
| Tenant/branch context | `AppState.selectContext` |

## Confirm with the backend team

The guide gives full payloads for login, session, rates, barcode lookup, quick-bill and
purchase vouchers. These were **assumed** and should be checked against
`packages/contracts/src/index.ts`:

1. **Client-guard header** - `ApiClient.clientHeaders` sends `X-Client: mobile`. Replace with whatever the CSRF / API-client guard expects.
2. **`GET /inventory` (no barcode)** list shape, **`GET /parties`** list shape, and whether they paginate (the app filters customers locally).
3. **`POST /parties`** body fields: `name`, `phone`, `pan`, `gstin`.
4. **Shift bodies**: `openingCash` / `closingCash`, and the `GET /pos-shifts/current` response (404 treated as "no shift").
5. **Old-metal voucher** `payoutMode: "CASH"` value, and the response id field (`voucherId` or `id`).
6. **Payment modes** beyond `CASH` and `UPI` (`CARD`, `BANK_TRANSFER` are guesses).
7. **A bill-total preview endpoint.** The app deliberately does no billing maths, so the cashier types payment amounts and sees the server's totals only after "Create invoice". A preview endpoint would let the app show the amount due before payment.
8. **A release endpoint** for reserved pieces removed from a bill.
9. Approval memos, job work, procurement, rate fixing and the two reports use a generic read-only viewer (`records_screen.dart`) until their response shapes are final.

Not built yet because the backend isn't ready: PDF/thermal printing, WhatsApp share, push notifications.
