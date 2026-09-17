# tastetrace

Two sites, deployed as two Vercel projects (team `bcil`):

| Folder | What it is | Vercel project | Domain |
| --- | --- | --- | --- |
| `landing/` | Static waitlist landing page (`index.html`, no build step) | `tastetrace-landing` | tastetrace.app, www.tastetrace.app |
| `app/` | The TasteTrace application: React (Vite) client + Express API + Postgres (Drizzle) | `tastetrace-app` | app.tastetrace.app |

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

- `DATABASE_URL` – Postgres connection string (Neon)
- `SESSION_SECRET` – secret for signing session cookies
- `WAITLIST_ORIGINS` – optional, comma-separated origins allowed to post to
  `/api/waitlist` (defaults to the tastetrace.app landing origins)

On Vercel the client is built into `public/` and served from the CDN, and
`index.ts` exports the Express app, which runs as a single function handling
`/api/*` (see `app/vercel.json`). `npm run build && npm start` still produces a
self-contained Node server in `dist/` for any other host.

## landing/

Open `landing/index.html` directly, or serve the folder with any static server.
