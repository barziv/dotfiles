#!/bin/bash
input=$(cat)

# Get workspace directory from session data
WORKSPACE=$(echo "$input" | jq -r '.workspace.current_dir // empty')

API_PORT=""
UI_PORT=""
MONGO_URI=""
APP_ENV=""

if [ -n "$WORKSPACE" ]; then
  # Read environment profile
  if [ -f "$WORKSPACE/momentum-api/.env.profile" ]; then
    APP_ENV=$(grep -m1 '^APP_ENV=' "$WORKSPACE/momentum-api/.env.profile" | cut -d= -f2 | tr -d '[:space:]')
  fi

  # Determine which .env file the app loads (mirrors env-loader.ts logic)
  if [ -n "$APP_ENV" ]; then
    API_ENV_FILE="$WORKSPACE/momentum-api/.env.${APP_ENV}"
  else
    API_ENV_FILE="$WORKSPACE/momentum-api/.env"
  fi

  # Read API port and Mongo URI from the active env file
  if [ -f "$API_ENV_FILE" ]; then
    API_PORT=$(grep -m1 '^PORT=' "$API_ENV_FILE" | cut -d= -f2)
    MONGO_URI=$(grep -m1 '^MONGO_URI=' "$API_ENV_FILE" | cut -d= -f2-)
  fi

  # Read UI port from momentum-ui/.env
  if [ -f "$WORKSPACE/momentum-ui/.env" ]; then
    UI_PORT=$(grep -m1 '^VITE_PORT=' "$WORKSPACE/momentum-ui/.env" | cut -d= -f2)
  fi
fi

# MongoDB environment & connectivity
DB_STATUS=""
if [ -n "$MONGO_URI" ]; then
  # Detect environment from URI
  if echo "$MONGO_URI" | grep -q 'intera-prod'; then
    DB_ENV="PROD"
  elif echo "$MONGO_URI" | grep -q 'intera-staging'; then
    DB_ENV="staging"
  else
    DB_ENV="dev"
  fi

  # Extract host from mongodb+srv:// URI
  DB_HOST=$(echo "$MONGO_URI" | sed -E 's|^mongodb(\+srv)?://[^@]+@([^/]+).*|\2|')

  # Check DNS resolution (fast, <1s timeout)
  RED='\033[0;31m'
  RESET='\033[0m'
  if host "$DB_HOST" >/dev/null 2>&1; then
    if [ "$DB_ENV" = "PROD" ]; then
      DB_STATUS="${RED}DB:PROD${RESET}"
    else
      DB_STATUS="DB:${DB_ENV}"
    fi
  else
    if [ "$DB_ENV" = "PROD" ]; then
      DB_STATUS="${RED}DB:PROD DNS-FAIL${RESET}"
    else
      DB_STATUS="DB:${DB_ENV} DNS-FAIL"
    fi
  fi
fi

# Build server status string
SERVER_STATUS=""

if [ -n "$UI_PORT" ]; then
  if nc -z localhost "$UI_PORT" 2>/dev/null; then
    SERVER_STATUS="UI:${UI_PORT} up"
  else
    SERVER_STATUS="UI:${UI_PORT} down"
  fi
fi

if [ -n "$API_PORT" ]; then
  if nc -z localhost "$API_PORT" 2>/dev/null; then
    SERVER_STATUS="${SERVER_STATUS:+$SERVER_STATUS | }API:${API_PORT} up"
  else
    SERVER_STATUS="${SERVER_STATUS:+$SERVER_STATUS | }API:${API_PORT} down"
  fi
fi

# Output: Env | Server status | DB
LINE=""
if [ -n "$APP_ENV" ]; then
  LINE="env:${APP_ENV}"
fi
if [ -n "$SERVER_STATUS" ]; then
  LINE="${LINE:+$LINE | }$SERVER_STATUS"
fi
if [ -n "$DB_STATUS" ]; then
  LINE="${LINE:+$LINE | }$DB_STATUS"
fi

if [ -n "$LINE" ]; then
  echo -e "$LINE"
fi
