# Rooster Trader v2

Complete paperless poultry trading platform — Flutter mobile app + Supabase backend.

## Supabase Project
- **Project ID:** `kgntismpoaxzkokuvrcl`
- **URL:** `https://kgntismpoaxzkokuvrcl.supabase.co`

## Running the app

```bash
flutter pub get
flutter run \
  --dart-define=SUPABASE_URL=https://kgntismpoaxzkokuvrcl.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=<your-anon-key>
```

Get the anon key from: Supabase Dashboard → Project Settings → API → anon public key

## Architecture

```
lib/
  core/           — config, models, providers, router, theme
  features/
    auth/         — login, auth gate
    trader_admin/ — dashboard, orders, dispatch, approvals,
                    invoices, ledger, retailers, agents,
                    rates, shifts, crates, analytics, settings
    delivery_agent/ — home, shift open/close, batch pickup,
                      deliveries, expenses
    retailer/     — (separate Flutter project: rooster_retailer)
  data/
    repositories/ — one per domain
    services/     — PDF, WhatsApp, location
```

## Roles
| Role | App | Access |
|------|-----|--------|
| super_admin | Trader app | Everything |
| trader_admin | Trader app | Full trader features |
| trader_staff | Trader app | Orders, dispatch, retailers, ledger |
| delivery_staff | Trader app (agent flow) | Shift, deliveries, expenses |
| retailer_user | Retailer app (separate) | Orders, invoices, ledger |

## Database
22 tables · 23 functions · 12 triggers · 40+ indexes · Full RLS
See `supabase/schema.sql` for complete migration.

## Build Status
- [x] Database schema — complete
- [x] Core (config, models, providers, router, theme)
- [x] Auth (login screen, auth gate, role routing)
- [x] Dashboard (trader admin)
- [x] Data repositories (orders, delivery, shift, approval, ledger, rate)
- [ ] Orders module — in progress
- [ ] Dispatch module — in progress
- [ ] Agent flow — in progress
- [ ] Approvals + invoices — in progress
- [ ] Ledger — in progress
- [ ] Rates screen — in progress
