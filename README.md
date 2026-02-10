# scout-inventory-system

## License

This project is licensed under the PolyForm Noncommercial License.
Commercial use is **not permitted**.

See the LICENSE file for details.


## Getting Started

### 1. Flutter Web

Make sure Flutter is installed

```bash
flutter doctor
```

You should see:

```
[✓] Chrome - develop for the web
```

Inside ```scout_stock``` folder, run the app normally:

```bash
flutter run -d chrome
```

### 2. Backend (API) Setup — Cloudflare Workers + D1 + Hono + Bun

The API runs on **Cloudflare Workers** using **Hono**.
Data is stored in **Cloudflare D1 (SQLite)**.
Schema changes are managed with **Drizzle** (generate SQL migrations) + **Wrangler** (apply migrations).

### Dev vs Prod databases

We use **two D1 databases**:

- **DEV:** `scout-stock-db-dev`
  - configured in `api/wrangler.json` (includes the dev `database_id`)
  - safe for testing

- **PROD:** `scout-stock-db`
  - configured as the `prod` environment in `api/wrangler.json`
  - **does NOT include the prod database_id** in git
  - **requires manual binding in the Cloudflare Dashboard** (see below)

In the Worker code, we always reference the same binding name: `DB`.

---

## Prerequisites



Install Bun (if you don’t already have it), then install API 
```
cd api
bun install
bun wrangler login
```
1) Create the D1 databases (one-time).
```
wrangler d1 create scout-stock-db-dev
wrangler d1 create scout-stock-db
✅ The dev DB ID is already stored in wrangler.json.
❌ Do not commit the prod DB ID.
```

2) IMPORTANT: Manual PROD binding in Cloudflare Dashboard (required)
```
Production deployments use the prod environment (--env prod), and the database name is scout-stock-db.
Because the prod DB ID is not stored in git, you must bind it manually in the Cloudflare Dashboard:

Cloudflare Dashboard → Workers & Pages

Open the Worker: scout-stock-api

Go to Settings → Bindings

Add a D1 Database binding:

Variable name: DB

Database: scout-stock-db

Save

⚠️ If this manual binding is missing, prod will not have a DB binding at runtime.
```

3) Local dev (uses DEV DB)
```
bun run dev
This runs wrangler dev and connects to the remote DEV database (scout-stock-db-dev) because remote: true is set in wrangler.json.
```

4) Database migrations (Drizzle + Wrangler)
```
cd api/src/db/schema.ts
Generate migration SQL (Drizzle)
bun run db:generate
This creates SQL files in:

cd api/drizzle/
Commit the migration files.

Apply migrations

DEV:
bun run migrate:dev

PROD:
bun run migrate:prod
✅ Always run migrations before deploying code that depends on them.
```

5) Deploy
```
DEV deploy:
bun run deploy:dev

PROD deploy:
bun run deploy:prod
⚠️ Never deploy prod without --env prod (the script already includes it).
```

6) One-command release (recommended)
```
These commands do:
generate migrations
apply migrations
deploy

DEV:
bun run release:dev

PROD:
bun run release:prod
```