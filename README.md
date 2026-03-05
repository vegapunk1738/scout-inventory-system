# scout-inventory-system

## License

This project is licensed under the PolyForm Noncommercial License.
Commercial use is **not permitted**.
See the LICENSE file for details.

## Getting Started

### 1. Flutter Web

Make sure Flutter is installed:

```bash
flutter doctor
```

You should see:

```
[✓] Chrome - develop for the web
```

Inside the `scout_stock` folder, run the app:

```bash
flutter run -d chrome
```

### 2. Backend (API) — Cloudflare Workers + D1 + Hono + Bun

The API runs on **Cloudflare Workers** using **Hono**.
Data is stored in **Cloudflare D1 (SQLite)**.
Schema changes are managed with **Drizzle** (generate SQL migrations) + **Wrangler** (apply migrations).

---

## Dev vs Prod Databases

We use **two D1 databases**:

| Environment | Database Name | Usage |
|---|---|---|
| **Dev** | `scout-stock-db-dev` | Local development via `bun dev` (connects remotely) |
| **Prod** | `scout-stock-db` | Production, deployed via Cloudflare Git integration |

Both are configured in `api/wrangler.jsonc`. The prod DB lives under `[env.prod]`.
In code, both use the same binding name: `DB`.

---

## Prerequisites

Install [Bun](https://bun.sh), then:

```bash
cd api
bun install
bunx wrangler login
```

### Create D1 databases (one-time)

```bash
bunx wrangler d1 create scout-stock-db-dev
bunx wrangler d1 create scout-stock-db
```

Paste the returned `database_id` values into `api/wrangler.jsonc`:

- Dev ID → top-level `d1_databases` array
- Prod ID → `env.prod.d1_databases` array

---

## Local Development

```bash
bun dev
```

This runs `wrangler dev --remote`, which starts a local server connected to the **remote dev database** (`scout-stock-db-dev`).

---

## Database Migrations (Drizzle + Wrangler)

1. Edit your schema in `api/src/db/schema.ts`

2. Generate migration SQL:

```bash
bun run db:generate
```

This creates SQL files in `api/drizzle/`. Commit these files.

3. Apply migrations:

```bash
# Dev
bun run migrate:dev

# Prod
bun run migrate:prod
```

Always run migrations before deploying code that depends on them.

---

## Deployment

### CI/CD (automatic)

Production deploys are handled by **Cloudflare Git integration**:

- Push to `main` → auto builds and deploys to prod
- Build command: installs deps, generates migrations, applies prod migrations
- Deploy command: `npx wrangler deploy --env prod`
- Root directory: `/api`

Non-production branch builds are disabled.

### Manual deploy (if needed)

```bash
# Prod
bun run release:prod
```

This runs: generate migrations → apply prod migrations → deploy with `--env prod`.

---

## Scripts Reference

| Script | Command | Purpose |
|---|---|---|
| `bun dev` | `wrangler dev --remote` | Local dev server using remote dev DB |
| `bun run db:generate` | `bunx drizzle-kit generate` | Generate migration SQL from schema |
| `bun run migrate:dev` | `wrangler d1 migrations apply scout-stock-db-dev --remote` | Apply migrations to dev DB |
| `bun run migrate:prod` | `wrangler d1 migrations apply scout-stock-db --remote --env prod` | Apply migrations to prod DB |
| `bun run deploy:prod` | `wrangler deploy --env prod` | Deploy worker to prod |
| `bun run release:prod` | generate + migrate + deploy prod | Full prod release |

---

## wrangler.jsonc Structure

```jsonc
{
  // Default (dev)
  "d1_databases": [
    { "binding": "DB", "database_name": "scout-stock-db-dev", "database_id": "..." }
  ],

  // Production
  "env": {
    "prod": {
      "name": "scout-stock-api-prod",
      "d1_databases": [
        { "binding": "DB", "database_name": "scout-stock-db", "database_id": "..." }
      ]
    }
  }
}
```

Same `DB` binding in code — the environment flag determines which database is used.