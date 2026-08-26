#!/bin/bash
# Umbrel exports for zakvir-antigravity-server
# Derive stable secrets and device-specific values

# Export workspace and home paths for templating if needed
export APP_ANTIGRAVITY_SERVER_DATA_DIR="${EXPORTS_APP_DATA_DIR}/data"
export APP_ANTIGRAVITY_SERVER_AGY_HOME="${EXPORTS_APP_DATA_DIR}/data/agy-home"
export APP_ANTIGRAVITY_SERVER_WORKSPACE="${EXPORTS_APP_DATA_DIR}/data/workspace"

# Trusted proxies: allow Umbrel's Docker network (10.21.0.0/16) plus localhost
# Users can override via AGY_TRUSTED_PROXIES env if needed
export APP_TRUSTED_PROXIES="10.21.0.0/16,127.0.0.1/32,::1/128"

# App password is already provided as APP_PASSWORD by Umbrel (deterministic per install)
# We expose it as AGY_PASSWORD for the entrypoint; compose will map it
# No extra derive_entropy needed unless we add DB or JWT secrets in future
# Example for future: export APP_ANTIGRAVITY_SERVER_JWT_SECRET="$(derive_entropy "${app_entropy_identifier}-jwt-secret")"
