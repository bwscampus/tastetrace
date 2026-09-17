# tastetrace

Two sites, deployed as two services in one Railway project. Each service
builds from its own root directory and redeploys on pushes to `main`.

| Folder | What it is | Railway service | Domain |
| --- | --- | --- | --- |
| `landing/` | Static waitlist landing page (`index.html`, no build step) | `landing` | tastetrace.app |
| `app/` | The TasteTrace application: React (Vite) client + Express API + Postgres (Drizzle) | `tastetrace` | app.tastetrace.app |

The landing page's waitlist form posts to `https://app.tastetrace.app/api/waitlist`,
which stores signups in the `waitlist_signups` table.

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
  `/api/waitlist` (defaults to the tastetrace.app landing origins)

Railway builds with `npm run build` and runs `npm start`: a single Node server
that serves the API and the built client on `PORT`.

## landing/

Open `landing/index.html` directly, or serve the folder with any static server.
