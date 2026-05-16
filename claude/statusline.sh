#!/bin/bash
input=$(cat)

# Get workspace directory from session data
WORKSPACE=$(echo "$input" | jq -r '.workspace.current_dir // empty')

# Model info
MODEL=$(echo "$input" | jq -r '.model.display_name // empty')

# Context window usage
CONTEXT_USED=$(echo "$input" | jq -r '.context_window.used_percentage // empty')

# Git branch
GIT_BRANCH=""
if [ -n "$WORKSPACE" ] && command -v git >/dev/null 2>&1; then
  GIT_BRANCH=$(git -C "$WORKSPACE" rev-parse --abbrev-ref HEAD 2>/dev/null)
fi

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

# Claude Code Max quota window (5h rolling) — requires `ccusage` installed
QUOTA=""
if command -v ccusage >/dev/null 2>&1; then
  CC_BLOCK=$(ccusage blocks --active --json 2>/dev/null | jq -r '.blocks[0] // empty' 2>/dev/null)
  if [ -n "$CC_BLOCK" ] && [ "$CC_BLOCK" != "null" ]; then
    PCT=$(echo "$CC_BLOCK" | jq -r '.tokenLimitStatus.percentUsed // empty')
    END=$(echo "$CC_BLOCK" | jq -r '.endTime // empty')
    if [ -n "$PCT" ] && [ -n "$END" ]; then
      # Normalize percent (0-1 fraction or 0-100)
      PCT_INT=$(echo "$PCT" | awk '{if ($1+0 <= 1) print int($1*100); else print int($1)}')
      # Convert ISO endTime (UTC) → local HH:MM via epoch
      END_CLEAN=$(echo "$END" | sed -E 's/\.[0-9]+Z?$//;s/Z$//')
      EPOCH=$(TZ=UTC date -j -f "%Y-%m-%dT%H:%M:%S" "$END_CLEAN" "+%s" 2>/dev/null)
      if [ -n "$EPOCH" ]; then
        RESET=$(date -r "$EPOCH" "+%H:%M" 2>/dev/null)
        if [ -n "$RESET" ]; then
          QUOTA="quota:${PCT_INT}% · resets ${RESET}"
        fi
      fi
    fi
  fi
fi

# Extract issue key from branch (e.g. "int-274")
ISSUE_KEY=""
if [ -n "$GIT_BRANCH" ]; then
  ISSUE_KEY=$(echo "$GIT_BRANCH" | grep -oE 'int-[0-9]+' | head -1 | tr '[:lower:]' '[:upper:]')
fi

# Line 1: Model | Ctx% | Quota | Issue key
LINE1=""
if [ -n "$MODEL" ]; then
  LINE1="$MODEL"
fi
if [ -n "$CONTEXT_USED" ]; then
  LINE1="${LINE1:+$LINE1 | }Ctx:${CONTEXT_USED}%"
fi
if [ -n "$QUOTA" ]; then
  LINE1="${LINE1:+$LINE1 | }$QUOTA"
fi
if [ -n "$ISSUE_KEY" ]; then
  LINE1="${LINE1:+$LINE1 | }$ISSUE_KEY"
fi

# Line 2: Env | Server status | DB
LINE2=""
if [ -n "$APP_ENV" ]; then
  LINE2="env:${APP_ENV}"
fi
if [ -n "$SERVER_STATUS" ]; then
  LINE2="${LINE2:+$LINE2 | }$SERVER_STATUS"
fi
if [ -n "$DB_STATUS" ]; then
  LINE2="${LINE2:+$LINE2 | }$DB_STATUS"
fi

# Line 3: Branch slug (e.g. "shayshalem/fix/int-274-prevent-removing-foo" → "prevent-removing-foo")
LINE3=""
if [ -n "$GIT_BRANCH" ]; then
  # Strip everything up to and including the issue key (int-123-)
  SLUG=$(echo "$GIT_BRANCH" | sed -E 's|^.*/int-[0-9]+-||')
  if [ "$SLUG" = "$GIT_BRANCH" ]; then
    # No issue key found — fallback: last path segment
    SLUG=$(echo "$GIT_BRANCH" | rev | cut -d/ -f1 | rev)
  fi
  LINE3="$SLUG"
fi

if [ -n "$LINE1" ]; then
  echo "$LINE1"
fi

if [ -n "$LINE2" ]; then
  echo -e "$LINE2"
fi

if [ -n "$LINE3" ]; then
  echo "$LINE3"
fi
