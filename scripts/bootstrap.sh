#!/bin/sh
set -e

SIYUAN_URL="${SIYUAN_INTERNAL_URL}"
CONF_FILE="/siyuan-conf/conf.json"
OPENAI_ENDPOINT="${AZURE_OPENAI_ENDPOINT}"
OPENAI_KEY="${AZURE_OPENAI_API_KEY}"
OPENAI_DEPLOYMENT="${AZURE_OPENAI_DEPLOYMENT}"
OPENAI_BASE_URL="${OPENAI_ENDPOINT%/}/openai/v1"

echo "=== SiYuan Bootstrap Setup Job Started ==="
echo "Waiting for SiYuan at ${SIYUAN_URL}..."

# 1. Wait for readiness
MAX_RETRIES=30
RETRY_DELAY=10
for i in $(seq 1 $MAX_RETRIES); do
  if curl -s -o /dev/null -w "%{http_code}" "${SIYUAN_URL}/api/system/version" | grep -q "200"; then
    echo "SiYuan is ready."
    break
  fi
  echo "Attempt ${i}/${MAX_RETRIES}: not ready, sleeping ${RETRY_DELAY}s..."
  sleep "${RETRY_DELAY}"
  if [ "${i}" -eq "${MAX_RETRIES}" ]; then
    echo "Error: SiYuan did not become ready."
    exit 1
  fi
done

# 2. Safely retrieve the API Token from the read-only mounted conf.json
echo "Retrieving API Token from ${CONF_FILE}..."

if [ ! -f "${CONF_FILE}" ]; then
  echo "Error: conf.json not found at ${CONF_FILE}."
  echo "Check the volume mount subPath and that the workspace has initialized."
  exit 1
fi

# Ensure jq is available (the alpine image needs it installed)
if ! command -v jq >/dev/null 2>&1; then
  echo "Installing jq..."
  apk add --no-cache jq >/dev/null 2>&1
fi

# The API token lives under the top-level "api" key, with the actual value in "token"[citation:2][citation:12]
API_TOKEN=$(jq -r '.api.token // empty' "${CONF_FILE}")

if [ -z "${API_TOKEN}" ]; then
  echo "Error: Could not extract 'api.token' from conf.json."
  echo "The workspace may not have finished its first-boot initialization yet."
  exit 1
fi

echo "API Token retrieved successfully."

# 3. Configure AI provider using the current SiYuan settings schema
echo "Configuring AI provider..."
AI_CONFIG=$(jq -n \
  --arg api_key "${OPENAI_KEY}" \
  --arg base_url "${OPENAI_BASE_URL}" \
  --arg model "${OPENAI_DEPLOYMENT}" \
  '{
    k: "ai",
    v: {
      providers: [{
        enabled: true,
        apiKey: $api_key,
        baseURL: $base_url,
        requestTimeout: 120,
        models: [{
          enabled: true,
          name: $model,
          displayName: $model
        }]
      }],
      editing: {
        maxHistoryMessages: 7,
        temperature: 1.0,
        maxCompletionTokens: 4096
      },
      agent: {
        temperature: 1.0,
        maxCompletionTokens: 4096
      }
    }
  }')

AI_RESPONSE=$(curl -sS -X POST "${SIYUAN_URL}/api/setting/setAI" \
  -H "Authorization: Token ${API_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "${AI_CONFIG}")

if echo "${AI_RESPONSE}" | grep -q '"code":0'; then
  echo "AI provider configured successfully."
  # log AI response with sensitive info fields removed
  SAFE_AI_RESPONSE=$(echo "${AI_RESPONSE}" | jq 'del(.data.providers[].apiKey)')
  echo "AI Response: ${SAFE_AI_RESPONSE}"
else
  echo "Error: Failed to set AI config: ${AI_RESPONSE}"
  exit 1
fi

echo "=== Bootstrap Job Completed ==="