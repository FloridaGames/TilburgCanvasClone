# Deploying Canvas LMS to Klutch — TilburgCanvasClone

Step-by-step deployment guide for `FloridaGames/TilburgCanvasClone` on Klutch project `69e87aeb99200fe6f42c72ed`. Database: **Klutch Postgres**.

> Reference: https://docs.klutch.sh/guides/open-source-software/canvas-lms/

---

## 0. What's in this kit

```
canvas-deploy/
├── Dockerfile                  # Clones canvas-lms stable, installs deps, compiles assets
├── entrypoint.sh               # Waits for DB/Redis, runs migrations, starts Puma
├── config/
│   ├── database.yml            # Postgres adapter (env-driven)
│   ├── redis.yml               # Redis cache (env-driven)
│   ├── outgoing_mail.yml       # SMTP (env-driven, optional)
│   └── domain.yml              # CANVAS_DOMAIN wiring
├── .env.example                # Every env var documented
├── docker-compose.yml          # LOCAL ONLY — test before pushing
├── .gitignore
└── README-DEPLOY.md            # this file
```

---

## 1. Commit to GitHub

```bash
git clone git@github.com:FloridaGames/TilburgCanvasClone.git
cd TilburgCanvasClone
# Copy every file from this kit into the repo root
cp -r /path/to/canvas-deploy/. .
git add .
git commit -m "Add Klutch Canvas LMS deployment kit"
git push origin main
```

## 2. Klutch Postgres add-on

1. Open Klutch project `69e87aeb99200fe6f42c72ed`.
2. **Add-ons → Add → Postgres** → choose size (start with smallest, upsize later).
3. After provisioning, open the add-on → **Connection details**. Copy:
   - Host → `DATABASE_HOST`
   - Port → `DATABASE_PORT` (usually `5432`)
   - Database → `DATABASE_NAME`
   - User → `DATABASE_USER`
   - Password → `DATABASE_PASSWORD`

## 3. Klutch Redis add-on

1. **Add-ons → Add → Redis**.
2. Copy the connection URL (`redis://:password@host:6379`) → `REDIS_URL`.

## 4. Generate secrets locally

```bash
echo "SECRET_KEY_BASE=$(openssl rand -hex 64)"
echo "ENCRYPTION_KEY=$(openssl rand -hex 32)"
```

Save these — you'll paste them in step 6. **Don't lose `ENCRYPTION_KEY`** — it encrypts password columns; rotating it makes existing data unreadable.

## 5. Create the Klutch app

1. **New App → Docker** → connect GitHub → select `FloridaGames/TilburgCanvasClone` → branch `main`.
2. **Build**: Dockerfile path = `Dockerfile` (root).
3. **Networking**:
   - Protocol: HTTP
   - Internal port: **3000**
   - Attach the auto-generated `*.klutch.sh` domain (note this — it goes into `CANVAS_DOMAIN`).
4. **Volumes**: add a 100 GB volume mounted at `/app/public/assets`.
5. **Resources**: at minimum 2 vCPU / 4 GB RAM for the migration. Can scale down after first boot.

## 6. Set environment variables

In the Klutch app **Environment** panel, paste from `.env.example`:

| Key | Value |
|---|---|
| `CANVAS_DOMAIN` | The `*.klutch.sh` hostname from step 5 (no protocol) |
| `DATABASE_HOST` / `_PORT` / `_NAME` / `_USER` / `_PASSWORD` | From step 2 |
| `REDIS_URL` | From step 3 |
| `SECRET_KEY_BASE` | From step 4 |
| `ENCRYPTION_KEY` | From step 4 |
| `RAILS_ENV` | `production` |
| `RAILS_LOG_TO_STDOUT` | `true` |
| `RAILS_SERVE_STATIC_FILES` | `true` |
| SMTP_* | optional |

## 7. Deploy & wait

Click **Deploy**. Tail logs. First boot:
- ~5 min: dependency install (cached on subsequent builds)
- ~10 min: asset compilation
- **20–40 min**: `db:initial_setup` — creates ~600 tables and seeds defaults

You'll see `[entrypoint] Starting Canvas: bundle exec puma ...` when it's ready.

## 8. Create root admin

Visit `https://<your>.klutch.sh`. Canvas's first-run wizard prompts you to create the root admin account. Done — you have a working Canvas LMS.

## 9. Enable LTI 1.3

1. In Canvas: **Admin → Developer Keys → +Key → LTI Key**.
2. Switch to the Lovable companion app (this project's preview URL).
3. Go to **/keys** → generate an RSA keypair → copy JWKS JSON.
4. Go to **/config** → fill tool URL + redirect URIs → copy the LTI 1.3 JSON config.
5. Paste the config into Canvas's Developer Key form. Save.
6. **Developer Keys → ON** for the new key.
7. Copy the **Client ID** Canvas shows you — that's what your tool will use to authenticate.

## 10. Test a launch

Use the helper app's **/decode** route to inspect launch tokens, **/simulate** to construct OIDC login init URLs, and **/jwks** to validate your tool's JWKS endpoint.

---

## Troubleshooting

- **Migration hangs**: check Postgres add-on is in the same Klutch region as the app. Increase Postgres CPU/RAM during initial setup.
- **`redis-cli: command not found`**: rebuild the image — `redis-tools` is in the apt install list.
- **Assets 404**: ensure `RAILS_SERVE_STATIC_FILES=true` and the volume is mounted at `/app/public/assets`.
- **502 from Klutch**: app is still compiling assets — check logs for `Compiling assets...`.
- **Login loop**: `CANVAS_DOMAIN` must exactly match the public hostname (no `https://`, no trailing slash).
