# tastetrace

Two sites, deployed as two services in one Railway project. Each service
builds from its own root directory and redeploys on pushes to `main`.

| Folder | What it is | Railway service | Domain |
| --- | --- | --- | --- |
| `landing/` | Static waitlist landing page (`index.html`, no build step) | `landing` | https://tastetrace.up.railway.app (later tastetrace.app) |
| `app/` | The TasteTrace application: React (Vite) client + Express API + Postgres (Drizzle) | `tastetrace` | https://tastetrace-app.up.railway.app (later app.tastetrace.app) |

The sites run on their Railway domains for now. The custom domains are already
attached to the services in Railway and start working once their DNS records
are added; at that point change `WAITLIST_URL` in `landing/index.html` to
`https://app.tastetrace.app/api/waitlist`.

The landing page's waitlist form posts to the app's `/api/waitlist`, which
stores signups in the `waitlist_signups` table.

## app/

```sh
cd app
npm install
npm run dev        # http://localhost:5000 (set PORT to change)
npm run db:push    # apply shared/schema.ts to the database
```

Environment variables:

- `DATABASE_URL` – Postgres connection string (on Railway: `${{Postgres.DATABASE_URL}}`)
- `SESSION_SECRET` – secret for signing session cookies
- `WAITLIST_ORIGINS` – optional, comma-separated origins allowed to post to
  `/api/waitlist` (defaults to the landing page's Railway and tastetrace.app origins)

Railway builds with `npm run build` and runs `npm start`: a single Node server
that serves the API and the built client on `PORT`.

## landing/

Open `landing/index.html` directly, or serve the folder with any static server.
