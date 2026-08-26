# ZakVir Community App Store

Community App Store for [umbrelOS](https://umbrel.com) — currently featuring **Antigravity Server**.

Add this store to your Umbrel: `https://github.com/ZakVir/umbrel-community-app-store`

## Apps

### Antigravity Server (`zakvir-antigravity-server`) — v0.2.7

Use the Antigravity IDE from your phone via your Umbrel. One binary that serves Antigravity's web UI behind a password, with 25 mobile UX patches (New Conversation (+) button, conversation kebab menu, iOS keyboard fixes, chunked uploads) and direct connection (no Google relay required). Based on [AFSlayer/antigravity-server](https://github.com/AFSlayer/antigravity-server) (Apache-2.0).

- **Port:** 8767 (host) → 8765 (container)
- **Image:** `ghcr.io/zakvir/antigravity-server:0.2.7` (multi-arch amd64/arm64, built via GitHub Actions)
- **Data:** `${APP_DATA_DIR}/data/agy-home` (credentials/sessions/config + language_server), `${APP_DATA_DIR}/data/workspace` (projects), `${APP_DATA_DIR}/data/gemini` (OAuth token)
- **Auth:** Password is Umbrel's `APP_PASSWORD` (shown in Umbrel UI when `deterministicPassword: true`). First run auto-generates if not set; stored as PBKDF2 hash in `agy-home/credentials.json`.
- **language_server:** Auto-downloaded on first start from `storage.googleapis.com/antigravity-public` via `agy-server update --yes`. No Google binaries are redistributed in the image. Re-run `docker exec zakvir-antigravity-server_server_1 agy-server update --yes` to update.

## Install

1. In umbrelOS go to **App Store → Community App Stores → Add** and paste: `https://github.com/ZakVir/umbrel-community-app-store`
2. Find **Antigravity Server** and click **Install**
3. Open the app (port 8767). On first open, sign in to Google via Settings or copy an existing token: `scp ~/.gemini/jetski-standalone-oauth-token umbrel@umbrel.local:~/umbrel/app-data/zakvir-antigravity-server/data/gemini/`
4. Add to Home Screen for fullscreen PWA (iOS: Share → Add to Home Screen, Android: Menu → Install app).

## Development

### Build image locally

```bash
docker buildx build --platform linux/amd64,linux/arm64 \
  -f zakvir-antigravity-server/Dockerfile \
  -t ghcr.io/zakvir/antigravity-server:0.2.7 \
  --push .
# then get digest
docker buildx imagetools inspect ghcr.io/zakvir/antigravity-server:0.2.7
# update docker-compose.yml image line with @sha256:<digest>
```

### Lint

The store uses Umbrel's app linter (from https://github.com/getumbrel/umbrel-apps):

```bash
npm run lint:apps -- zakvir-antigravity-server --check-images
```

### Structure

```
umbrel-app-store.yml
zakvir-antigravity-server/
  umbrel-app.yml
  docker-compose.yml
  Dockerfile
  entrypoint.sh
  exports.sh
  data/
    agy-home/.gitkeep
    workspace/.gitkeep
    gemini/.gitkeep
```

## Credits

- Upstream: [AFSlayer/antigravity-server](https://github.com/AFSlayer/antigravity-server)
- Umbrel template: [getumbrel/umbrel-community-app-store](https://github.com/getumbrel/umbrel-community-app-store)

## License

Store template MIT; Antigravity Server upstream Apache-2.0. This package is community-maintained and not affiliated with Google or Umbrel.
