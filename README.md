# Jewellery ERP Enterprise — Flutter Mobile SaaS Suite

Mobile-native **Royal 24K Gold** enterprise client for **Jewellery ERP** (`https://pos.hrpocket.in`), providing 1:1 SaaS workflow parity across Showroom POS, Fine 999 Vault, Supply & Production, Double-Entry Financials, GST Compliance, and Multi-Entity Governance.

---

## Gateway Configuration

| Setting | Value |
| --- | --- |
| **Web Portal** | `https://pos.hrpocket.in` |
| **Production API Base URL** | `https://pos.hrpocket.in/api/v1` (configured by default) |

---

## Quick Start

```bash
flutter pub get
flutter test
flutter run
```

---

## Enterprise SaaS Module Coverage

1. **Showroom & Patron Desk**: Live Bullion 24K Fine 999 Board, Vault & Tagged Stock, Camera Tag/QR Scanner, Counter POS Billing, POS Shifts, Old Metal Exchange, Custom Orders (`/custom-orders`), and Repairs & Custody (`/repairs`).
2. **Supply & Production**: Materials & Bullion Rate Books (`/materials`, `/rates`), Procurement & Intake with Controlled Posting Config (`/procurement`), Parties & Karigars with Protected KYC & Credit Policy (`/parties`), Karigar & Internal Job Work (`/job-work`), Refining & Melting (`/refining`), Inter-Branch Stock Transfers (`/stock-transfers`), Approval & Consignment (`/approval-memos`), Inter-Entity Trading (`/inter-entity-trades`), and Wholesale Rate Fixing (`/rate-fixing`).
3. **Financials & Ledgers**: Double-Entry Accounting (`/accounting/workspace` — Manual Balanced Journals, P&L / Balance Sheet Statements, Periods & COA, Opening Data & Annual Close), Settlements & Cashup (`/payments`), Banking & CSV Reconciliation (`/banking`), Consolidated Chain Analytics (`/chain-analytics`), and Valuation / Margin / Trial Balance / AR-AP Ageing Reports (`/reports/*`).
4. **Integrations, Tax & Governance**: Provider Integrations (`/integrations`), GST Registration & Transport (`/gst-compliance` — GSTIN Profiles, IRN E-Invoicing & E-Way Bills), GST Returns & ITC Review (`/gst-returns` — GSTR-2B Import/Reconciliation & Working Papers), Customer Messaging (`/messaging`), Company & Invoice Print Policy (`/documents/templates`, `/documents/render`), Showroom Hierarchy (`/organization`), Access Control & RBAC Roles (`/access`), and Support Grant Audit Governance (`/support-grants`).

---

## Financial & Bullion Integrity Guarantees

1. **Zero Floating-Point Drift**: All currency values (`2` decimal places, e.g. `"115400.00"`) and precious metal weights (`6` decimal places, e.g. `"14.250000"`) are transmitted as strings and computed exclusively with `Decimal`.
2. **Idempotent Financial Writes**: Every mutation attaches a cryptographic `Idempotency-Key` UUID v4 header.
3. **CSRF & Session Hardening**: Persistent `jewellery_session` + `jewellery_csrf` cookie jar with automatic `x-csrf-token` and `Origin` header compliance for `CsrfGuard`.
4. **Full 4-Step Tenant & Branch Context**: `POST /auth/login` → optional `POST /auth/mfa/login` → `GET /session` → `POST /session/context`.
