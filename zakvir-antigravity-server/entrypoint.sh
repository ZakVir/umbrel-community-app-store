#!/bin/bash
set -euo pipefail

# Umbrel entrypoint for Antigravity Server
# - Ensures data directories exist and are writable
# - Ensures language_server binary is present (downloads via agy-server update if missing)
# - Then execs agy-server serve with Umbrel-friendly defaults

AGY_HOME="${AGY_HOME:-/data/agy-home}"
AGY_WORKSPACE_ROOT="${AGY_WORKSPACE_ROOT:-/data/workspace}"
AGY_LANGUAGE_SERVER="${AGY_LANGUAGE_SERVER:-$AGY_HOME/language_server}"
AGY_PORT="${AGY_PORT:-8765}"
AGY_BIND="${AGY_BIND:-0.0.0.0}"

echo "[entrypoint] AGY_HOME=$AGY_HOME"
echo "[entrypoint] AGY_WORKSPACE_ROOT=$AGY_WORKSPACE_ROOT"
echo "[entrypoint] AGY_LANGUAGE_SERVER=$AGY_LANGUAGE_SERVER"

mkdir -p "$AGY_HOME" "$AGY_WORKSPACE_ROOT" "/home/agy/.gemini"
# Ensure permissions for 1000:1000 (already chowned in image, but volume mounts may be root on first run)
# Only chown if we are root (not 1000) - but Umbrel runs as 1000, so skip if not needed
if [ "$(id -u)" = "0" ]; then
  chown -R 1000:1000 "$AGY_HOME" "$AGY_WORKSPACE_ROOT" "/home/agy/.gemini" 2>/dev/null || true
  # drop privileges if we started as root
  exec su -p agy -c "exec $0 $*"
fi

# If language_server missing, try to download it
if [ ! -x "$AGY_LANGUAGE_SERVER" ]; then
  echo "[entrypoint] language_server not found at $AGY_LANGUAGE_SERVER, attempting to download..."
  # Set a temporary language server path for update command
  export AGY_LANGUAGE_SERVER
  export AGY_HOME
  # Try updater - it will fetch from Google storage
  if /usr/local/bin/agy-server update --yes 2>&1; then
    echo "[entrypoint] language_server downloaded successfully"
  else
    echo "[entrypoint] WARNING: automatic download failed. The server will attempt to start anyway and may fail."
    echo "[entrypoint] You can manually run: docker exec <container> agy-server update --yes"
    # Don't exit - let agy-server report the error with hints
  fi
  # Verify again
  if [ ! -x "$AGY_LANGUAGE_SERVER" ]; then
    # Check alternative locations the binary might have been installed to
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

# Handle AGY_TRUSTED_PROXIES - Umbrel sets DEVICE_DOMAIN_NAME etc via exports, but we default to common Umbrel network
if [ -z "${AGY_TRUSTED_PROXIES:-}" ] && [ -n "${APP_TRUSTED_PROXIES:-}" ]; then
  export AGY_TRUSTED_PROXIES="$APP_TRUSTED_PROXIES"
fi

# If AGY_PASSWORD is provided via env (from APP_PASSWORD), it will be used to seed credentials on first run
if [ -n "${AGY_PASSWORD:-}" ]; then
  echo "[entrypoint] AGY_PASSWORD is set (len=${#AGY_PASSWORD}) - will create credentials if needed"
else
  echo "[entrypoint] AGY_PASSWORD not set - agy-server will generate a random password on first run"
fi

# Ensure AGY_HOME config directory exists
mkdir -p "$AGY_HOME"

echo "[entrypoint] Starting: agy-server $* --port $AGY_PORT --bind $AGY_BIND"
# Exec agy-server with passed args (default CMD is "serve")
# Umbrel compose passes no extra args, entrypoint CMD is serve, so this becomes "agy-server serve"
if [ "$1" = "serve" ] || [ "$1" = "" ]; then
  exec /usr/local/bin/agy-server serve --port "$AGY_PORT" --bind "$AGY_BIND" --workspace-root "$AGY_WORKSPACE_ROOT" --language-server "$AGY_LANGUAGE_SERVER"
else
  exec /usr/local/bin/agy-server "$@"
fi
