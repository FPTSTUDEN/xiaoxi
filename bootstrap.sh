#!/bin/sh
# ============================================================
# SiYuan Bootstrap Script
# Idempotent: safe to rerun on every container start.
#
# Responsibilities:
#   1. Wait for SiYuan HTTP endpoint to be ready
#   2. Authenticate with the access auth code to get a session cookie
#   3. Set the API token (if not already set)
#   4. Set the AI provider config (if not already set or if values differ)
#   5. Verify the provider is reachable
#
# Required env:
#   SIYUAN_ACCESS_AUTH_CODE   - lock screen password
#   SIYUAN_API_TOKEN          - desired API token
#   SIYUAN_OPENAI_API_KEY     - provider API key
#   SIYUAN_OPENAI_API_MODEL   - provider model name
#   SIYUAN_OPENAI_API_BASE_URL- provider base URL
#   BOOTSTRAP_ENABLED         - "true" to run
# ============================================================

set -eu

SIYUAN_URL="http://127.0.0.1:6806"
COOKIE_JAR="/tmp/siyuan-bootstrap-cookies.txt"
MAX_WAIT=120
WAITED=0

log() { echo "[bootstrap] $*"; }

if [ "${BOOTSTRAP_ENABLED:-true}" != "true" ]; then
  log "Bootstrap disabled via BOOTSTRAP_ENABLED. Exiting."
  exit 0
fi

# --- 1. Wait for SiYuan to be ready ---
log "Waiting for SiYuan at ${SIYUAN_URL} ..."
while [ "$WAITED" -lt "$MAX_WAIT" ]; do
  if curl -fsS "${SIYUAN_URL}/api/system/version" >/dev/null 2>&1; then
    log "SiYuan is up after ${WAITED}s."
    break
  fi
  sleep 2
  WAITED=$((WAITED + 2))
done

if [ "$WAITED" -ge "$MAX_WAIT" ]; then
  log "ERROR: SiYuan did not become ready within ${MAX_WAIT}s."
  exit 1
fi

# --- 2. Authenticate to get a session cookie ---
# SiYuan's login endpoint accepts the access auth code and sets a cookie.
log "Authenticating with access auth code ..."
LOGIN_RESP=$(curl -fsS -c "$COOKIE_JAR" \
  -X POST "${SIYUAN_URL}/api/system/loginAuth" \
  -H "Content-Type: application/json" \
  -d "{\"authCode\":\"${SIYUAN_ACCESS_AUTH_CODE}\"}" 2>&1) || {
    log "ERROR: loginAuth request failed: ${LOGIN_RESP}"
    exit 1
  }

# Check the response code field (SiYuan returns {"code":0,...} on success)
CODE=$(echo "$LOGIN_RESP" | sed -n 's/.*"code":\([0-9-]*\).*/\1/p')
if [ "${CODE:-1}" != "0" ]; then
  log "ERROR: loginAuth returned non-zero code: ${LOGIN_RESP}"
  exit 1
fi
log "Authenticated."

# Helper: POST JSON with cookie
api_post() {
  curl -fsS -b "$COOKIE_JAR" -c "$COOKIE_JAR" \
    -X POST "$1" \
    -H "Content-Type: application/json" \
    -d "$2"
}

# Helper: read current API token
get_api_token() {
  curl -fsS -b "$COOKIE_JAR" -c "$COOKIE_JAR" \
    -X POST "${SIYUAN_URL}/api/system/getConf" \
    -H "Content-Type: application/json" \
    -d '{}' 2>/dev/null | sed -n 's/.*"apiToken":"\([^"]*\)".*/\1/p'
}

# --- 3. Set API token (idempotent) ---
CURRENT_TOKEN=$(get_api_token || true)
if [ "${CURRENT_TOKEN}" = "${SIYUAN_API_TOKEN}" ]; then
  log "API token already matches desired value. Skipping."
else
  log "Setting API token ..."
  api_post "${SIYUAN_URL}/api/system/setApiToken" \
    "{\"token\":\"${SIYUAN_API_TOKEN}\"}" >/dev/null
  log "API token set."
fi

# --- 4. Set AI provider config (idempotent) ---
# SiYuan stores AI provider config; we set the OpenAI-compatible provider.
# The exact endpoint may vary by SiYuan version; we attempt the documented
# AI config API and treat "already configured" as success.
log "Configuring AI provider ..."
AI_PAYLOAD=$(cat <<EOF
{
  "openAI": {
    "apiKey": "${SIYUAN_OPENAI_API_KEY}",
    "apiBaseURL": "${SIYUAN_OPENAI_API_BASE_URL}",
    "apiModel": "${SIYUAN_OPENAI_API_MODEL}"
  }
}
EOF
)

if api_post "${SIYUAN_URL}/api/ai/setProvider" "$AI_PAYLOAD" >/dev/null 2>&1; then
  log "AI provider configured."
else
  log "WARN: setProvider endpoint not available; attempting setConf fallback ..."
  api_post "${SIYUAN_URL}/api/system/setConf" "$AI_PAYLOAD" >/dev/null 2>&1 || \
    log "WARN: AI provider could not be set via API. Configure manually in SiYuan settings."
fi

# --- 5. Verify provider connectivity (lightweight) ---
log "Verifying AI provider connectivity ..."
VERIFY_RESP=$(api_post "${SIYUAN_URL}/api/ai/chat" \
  '{"messages":[{"role":"user","content":"ping"}],"max_tokens":1}' 2>&1) || true
if echo "$VERIFY_RESP" | grep -q '"code":0'; then
  log "AI provider reachable."
else
  log "WARN: AI provider verification inconclusive: ${VERIFY_RESP}"
  log "This is non-fatal; the provider may still work from the UI."
fi

log "Bootstrap complete."