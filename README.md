# Jewellery ERP Enterprise — Flutter Mobile App

Enterprise showroom & vault mobile client for **Jewellery ERP** (`https://pos.hrpocket.in`), aligned with the **Mobile App Developer Handoff & API Integration Guide (v1.0.0)** and `@jewellery-erp/contracts`.

---

## Live Portal & Demo Credentials

| Setting | Value |
| --- | --- |
| **Web Portal** | `https://pos.hrpocket.in/login` |
| **Production API Base URL** | `https://pos.hrpocket.in/api/v1` (configured by default) |
| **Store / Tenant** | `Kalyan Jewellers` |
| **Login Email** | `owner@kalyan.com` |
| **Password** | `Kalyan@2026Pass` |

> Tip: Tap **Kalyan Store Fill** on the mobile Sign-In screen to pre-populate the demo showroom credentials in one tap, or tap the gateway badge in the top-right to switch between `pos.hrpocket.in`, Android Emulator (`10.0.2.2:3000`), iOS Simulator (`localhost:3000`), or a custom LAN server.

---

## Quick Start

```bash
flutter pub get
flutter test
flutter run
```

---

## Architecture & Module Map

```text
lib/
  main.dart                           Bootstraps cookies, gateway URL & session gate
  core/
    build.dart                        Production API URL (pos.hrpocket.in) & server presets
    theme.dart                        Obsidian, 24K Gold & Royal Teal design system (Fraunces + Plus Jakarta Sans + JetBrains Mono)
    api.dart                          Dio + CookieJar, CSRF double-submit (x-csrf-token + Origin), envelope unwrapping & call timing
    app_state.dart                    4-step auth gate: login -> TOTP/recovery MFA -> showroom context -> shell
    showrooms.dart                    Parses scopes[] & legalEntities[] multi-branch context payloads
    models.dart                       Dual-shape Article, MetalRate, MaterialLotItem, StockLocationItem & Party models
    rates.dart                        Live Bullion Spot Board (/rates + /materials RateBook) & /pricing/calculate-metal estimator
    format.dart                       IEEE-754-free string/Decimal INR (lakhs/crores) & 6-dp gram formatters
    widgets.dart                      LuxuryHeroCard, Panel, WeightBreakdownBar, PillTabs, StatusPill, MetricTile
  features/
    auth/
      login_screen.dart               Enterprise login, TOTP + recovery-code MFA, 1-tap Kalyan demo fill, gateway switcher
      context_screen.dart             Tenant / Legal Entity / Showroom Branch working context selector
    home/
      home_screen.dart                Showroom executive dashboard, 1g/10g bullion board, price quote sheet & live KPIs
    inventory/
      scanner_page.dart               Camera HUID / QR / Code-128 tag scanner with torch & manual tag fallback
      inventory_screen.dart           Tagged pieces, bullion lots, vault locations, weight breakdown & Receive Piece sheet
    billing/
      billing_controller.dart         Counter POS cart, 15m tag reservation + release, Decimal GST preview, Old Gold credit & split pay
      billing_screen.dart             Counter POS checkout, digital GST invoice receipt & live Sales Register (/sales)
    customers/
      customers_screen.dart           Parties & CRM (Customers, Karigars, Suppliers), E.164 normalization, GSTIN & PAN/Aadhaar KYC vault
    more/
      more_screen.dart                Enterprise Operations hub, TOTP 2FA enrollment sheet & session security
      old_gold_screen.dart            Old Gold / Silver appraisal (6-dp Fine 999 math), voucher issue & register (/old-metal)
      shift_screen.dart               POS cash drawer open / reconcile / close & shift history (/pos-shifts)
      operations_screens.dart         Approval Memos (Jangad), Rate Fixing & Advances, Karigar Job Work & Procurement (/procurement)
      reports_screen.dart             Stock Valuation, Gross Margin, Trial Balance, AR/AP Ageing & Settlements (/payments)
    debug/
      api_inspector.dart              Live HTTP latency, status code & JSON payload inspector + /health/live ping
```

---

## Financial & Bullion Integrity Guarantees

1. **Zero Floating-Point Drift**: All currency values (`2` decimal places, e.g. `"115400.00"`) and precious metal weights (`6` decimal places, e.g. `"14.250000"`) are transmitted as strings and computed exclusively with `Decimal`.
2. **Idempotent Financial Writes**: POS billing, Old Gold purchase vouchers, shift open/close, stock inward/reservations, Jangad memos, rate locks, and Karigar bullion issues attach a cryptographic `Idempotency-Key` UUID v4 header.
3. **CSRF & Session Hardening**: Persistent `jewellery_session` + `jewellery_csrf` cookie jar with automatic `x-csrf-token` and `Origin` header compliance for `CsrfGuard`.
4. **Full 4-Step Tenant & Branch Context**: `POST /auth/login` → `POST /auth/mfa/login` (6-digit TOTP or recovery code) → `GET /session` → `POST /session/context`.
