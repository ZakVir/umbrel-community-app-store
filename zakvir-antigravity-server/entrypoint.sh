#!/bin/bash
set -euo pipefail

# Umbrel entrypoint for Antigravity Server
# - Ensures data directories exist and are writable
# - Sets up egress firewall (only Antigravity model APIs)
# - Ensures language_server binary is present (downloads via agy-server update if missing)
# - Then execs agy-server serve with Umbrel-friendly defaults

AGY_HOME="${AGY_HOME:-/data/agy-home}"
AGY_WORKSPACE_ROOT="${AGY_WORKSPACE_ROOT:-/data/workspace}"
AGY_LANGUAGE_SERVER="${AGY_LANGUAGE_SERVER:-$AGY_HOME/language_server}"
AGY_PORT="${AGY_PORT:-8765}"
AGY_BIND="${AGY_BIND:-0.0.0.0}"
AGY_DISABLE_AUTH="${AGY_DISABLE_AUTH:-false}"

echo "[entrypoint] AGY_HOME=$AGY_HOME"
echo "[entrypoint] AGY_WORKSPACE_ROOT=$AGY_WORKSPACE_ROOT"
echo "[entrypoint] AGY_LANGUAGE_SERVER=$AGY_LANGUAGE_SERVER"
echo "[entrypoint] AGY_DISABLE_AUTH=$AGY_DISABLE_AUTH"

mkdir -p "$AGY_HOME" "$AGY_WORKSPACE_ROOT" "/home/agy/.gemini"

# Setup egress firewall (restrict outside connections to only model APIs)
# Run as early as possible, before any network activity
if [ -x /usr/local/bin/egress.sh ]; then
  echo "[entrypoint] Setting up egress firewall..."
  /usr/local/bin/egress.sh 2>&1 || echo "[entrypoint] egress setup failed (continuing)"
else
  echo "[entrypoint] egress.sh not found, skipping firewall"
fi

# Ensure permissions for 1000:1000 (already chowned in image, but volume mounts may be root on first run)
# Only chown if we are root (not 1000) - but Umbrel runs as 1000, so skip if not needed
if [ "$(id -u)" = "0" ]; then
  chown -R 1000:1000 "$AGY_HOME" "$AGY_WORKSPACE_ROOT" "/home/agy/.gemini" 2>/dev/null || true
  # drop privileges if we started as root
  exec su -p agy -c "exec $0 $*"
fi

# If language_server missing, try to download it (requires egress to storage.googleapis.com)
if [ ! -x "$AGY_LANGUAGE_SERVER" ]; then
  echo "[entrypoint] language_server not found at $AGY_LANGUAGE_SERVER, attempting to download..."
  export AGY_LANGUAGE_SERVER
  export AGY_HOME
  if /usr/local/bin/agy-server update --yes 2>&1; then
    echo "[entrypoint] language_server downloaded successfully"
  else
    echo "[entrypoint] WARNING: automatic download failed. The server will attempt to start anyway and may fail."
    echo "[entrypoint] You can manually run: docker exec <container> agy-server update --yes"
  fi
  if [ ! -x "$AGY_LANGUAGE_SERVER" ]; then
    for alt in "$AGY_HOME/language_server" "/opt/agy-server/language_server" "/home/agy/.agy-remote/language_server"; do
      if [ -x "$alt" ]; then
        echo "[entrypoint] Found language_server at $alt, using it"
        export AGY_LANGUAGE_SERVER="$alt"
        break
      fi
    done
  fi
fi

if [ -x "$AGY_LANGUAGE_SERVER" ]; then
  echo "[entrypoint] language_server: $(ls -lh "$AGY_LANGUAGE_SERVER" | awk '{print $9, $5}')"
else
  echo "[entrypoint] WARNING: language_server still not found - agy-server will error with instructions"
fi

# Handle AGY_TRUSTED_PROXIES
if [ -z "${AGY_TRUSTED_PROXIES:-}" ] && [ -n "${APP_TRUSTED_PROXIES:-}" ]; then
  export AGY_TRUSTED_PROXIES="$APP_TRUSTED_PROXIES"
fi

# Auth handling
if [ "$AGY_DISABLE_AUTH" = "1" ] || [ "$AGY_DISABLE_AUTH" = "true" ]; then
  echo "[entrypoint] Authentication DISABLED (AGY_DISABLE_AUTH=$AGY_DISABLE_AUTH) - open access"
  unset AGY_PASSWORD
else
  if [ -n "${AGY_PASSWORD:-}" ]; then
    echo "[entrypoint] AGY_PASSWORD is set (len=${#AGY_PASSWORD}) - will create credentials if needed"
  else
    echo "[entrypoint] AGY_PASSWORD not set - agy-server will generate a random password on first run"
  fi
fi

# Ensure AGY_HOME config directory exists
mkdir -p "$AGY_HOME"

# If egress was enabled, ensure language_server can still talk to model APIs (already allowed)
# Note: storage.googleapis.com is allowed for initial download, but after that we could block it
# For now we keep it allowed for updates; to fully lock down, set AGY_EGRESS_ALLOW_HOSTS without storage

echo "[entrypoint] Starting: agy-server $* --port $AGY_PORT --bind $AGY_BIND --workspace-root $AGY_WORKSPACE_ROOT --language-server $AGY_LANGUAGE_SERVER --disable-auth=$AGY_DISABLE_AUTH"
if [ "$1" = "serve" ] || [ "$1" = "" ]; then
  # Pass disable-auth via env only; agy-server checks AGY_DISABLE_AUTH
  exec /usr/local/bin/agy-server serve --port "$AGY_PORT" --bind "$AGY_BIND" --workspace-root "$AGY_WORKSPACE_ROOT" --language-server "$AGY_LANGUAGE_SERVER"
else
  exec /usr/local/bin/agy-server "$@"
fi
