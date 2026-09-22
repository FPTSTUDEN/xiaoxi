#!/bin/sh
set -e

SIYUAN_URL="${SIYUAN_INTERNAL_URL}"
AUTH_CODE="${SIYUAN_ACCESS_AUTH_CODE}"
OPENAI_ENDPOINT="${AZURE_OPENAI_ENDPOINT}"
OPENAI_KEY="${AZURE_OPENAI_API_KEY}"
OPENAI_DEPLOYMENT="${AZURE_OPENAI_DEPLOYMENT}"

echo "=== SiYuan Setup Job Started ==="
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

# 2. Login to get session cookie
echo "Logging in..."
COOKIE_JAR="/tmp/siyuan_cookies.txt"
LOGIN_RESPONSE=$(curl -s -c "${COOKIE_JAR}" -X POST "${SIYUAN_URL}/api/system/loginAuth" \
  -H "Content-Type: application/json" \
  -d "{\"authCode\": \"${AUTH_CODE}\"}")

if echo "${LOGIN_RESPONSE}" | grep -q '"code":0'; then
  echo "Login successful."
else
  echo "Login failed: ${LOGIN_RESPONSE}"
  exit 1
fi

# 3. Configure AI provider
echo "Configuring AI provider..."
AI_CONFIG=$(cat <<JSONEOF
{
  "provider": "OpenAI",
  "openAI": {
    "apiKey": "${OPENAI_KEY}",
    "apiModel": "${OPENAI_DEPLOYMENT}",
    "apiBaseURL": "${OPENAI_ENDPOINT}",
    "apiTimeout": 60,
    "apiMaxTokens": 4096,
    "apiTemperature": 1.0,
    "apiMaxContexts": 7
  }
}
JSONEOF
)

AI_RESPONSE=$(curl -s -b "${COOKIE_JAR}" -X POST "${SIYUAN_URL}/api/setting/setAI" \
  -H "Content-Type: application/json" \
  -d "${AI_CONFIG}")

if echo "${AI_RESPONSE}" | grep -q '"code":0'; then
  echo "AI provider configured successfully."
else
  echo "Warning: Failed to set AI config: ${AI_RESPONSE}"
fi

echo "=== Bootstrap Job Completed ==="