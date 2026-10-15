#!/bin/sh
input=$(cat)

# --- model ---
model=$(echo "$input" | jq -r '.model.display_name // ""')
effort=$(echo "$input" | jq -r '.effort.level // ""')

# --- folder ---
dir=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // ""')
dir_name=$(basename "$dir")

# --- git branch ---
branch=""
if [ -d "${dir}/.git" ] || git -C "$dir" rev-parse --git-dir > /dev/null 2>&1; then
  branch=$(git -C "$dir" symbolic-ref --short HEAD 2>/dev/null || git -C "$dir" rev-parse --short HEAD 2>/dev/null)
fi

# --- usage stats (5h / 7d) from cache ---
# Cache format:
# Line 1: five_hour.utilization (integer %)
# Line 2: seven_day.utilization (integer %)
# Line 3: five_hour.resets_at (raw ISO string, e.g. 2026-02-26T12:59:59.997656+00:00)
# Line 4: seven_day.resets_at (raw ISO string)
CACHE_FILE="/tmp/.claude_usage_cache"
CACHE_TTL=60  # seconds
five_h=""
seven_d=""
five_h_reset=""
seven_d_reset=""

fetch_usage() {
  token=$(jq -r '.claudeAiOauth.accessToken // empty' ~/.claude/.credentials.json 2>/dev/null)
  [ -z "$token" ] && return

  usage_json=$(curl -s -m 3 \
    -H "accept: application/json" \
    -H "anthropic-beta: oauth-2025-04-20" \
    -H "authorization: Bearer $token" \
    -H "user-agent: claude-code/2.1.11" \
    "https://api.anthropic.com/oauth/usage")
  [ -z "$usage_json" ] && return

  five_h_raw=$(printf '%s' "$usage_json" | jq -r '.five_hour.utilization // empty')
  seven_d_raw=$(printf '%s' "$usage_json" | jq -r '.seven_day.utilization // empty')
  five_h_reset=$(printf '%s' "$usage_json" | jq -r '.five_hour.resets_at // ""')
  seven_d_reset=$(printf '%s' "$usage_json" | jq -r '.seven_day.resets_at // ""')

  if [ -n "$five_h_raw" ] && [ -n "$seven_d_raw" ]; then
    printf '%.0f\n%.0f\n%s\n%s\n' "$five_h_raw" "$seven_d_raw" "$five_h_reset" "$seven_d_reset" > "$CACHE_FILE"
  fi
}

if [ -f "$CACHE_FILE" ]; then
  five_h=$(sed -n '1p' "$CACHE_FILE")
  seven_d=$(sed -n '2p' "$CACHE_FILE")
  five_h_reset=$(sed -n '3p' "$CACHE_FILE")
  seven_d_reset=$(sed -n '4p' "$CACHE_FILE")
  cache_age=$(( $(date +%s) - $(stat -c %Y "$CACHE_FILE") ))
fi

if [ ! -f "$CACHE_FILE" ] || [ "$cache_age" -ge "$CACHE_TTL" ]; then
  # Bump mtime so concurrent renders don't all start a fetch
  [ -f "$CACHE_FILE" ] && touch "$CACHE_FILE"
  ( fetch_usage ) > /dev/null 2>&1 &
fi

# --- compute_delta: given a raw ISO timestamp, returns human-readable time until reset ---
compute_delta() {
  clean=$(echo "$1" | sed 's/\+[0-9][0-9]:[0-9][0-9]$//' | sed 's/Z$//' | tr 'T' ' ')
  reset_epoch=$(TZ=UTC date -d "$clean" "+%s" 2>/dev/null)
  if [ -z "$reset_epoch" ]; then return; fi
  now_epoch=$(date -u "+%s")
  diff=$(( reset_epoch - now_epoch ))
  if [ "$diff" -le 0 ]; then echo "now"; return; fi
  days=$(( diff / 86400 ))
  hours=$(( (diff % 86400) / 3600 ))
  minutes=$(( (diff % 3600) / 60 ))
  if [ "$days" -gt 0 ]; then
    echo "${days}d ${hours}h"
  elif [ "$hours" -gt 0 ]; then
    echo "${hours}h ${minutes}m"
  else
    echo "${minutes}m"
  fi
}

# --- context window ---
used=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
ctx_str=""
ctx_tokens_str=""
if [ -n "$used" ]; then
  used_int=$(printf "%.0f" "$used")
  ctx_str="${used_int}%"
  ctx_used=$(echo "$input" | jq -r '(.context_window.current_usage.cache_read_input_tokens + .context_window.current_usage.cache_creation_input_tokens + .context_window.current_usage.input_tokens + .context_window.current_usage.output_tokens) // empty' 2>/dev/null)
  ctx_total=$(echo "$input" | jq -r '.context_window.context_window_size // empty' 2>/dev/null)
  if [ -n "$ctx_used" ] && [ -n "$ctx_total" ]; then
    ctx_used_k=$(( ctx_used / 1000 ))
    ctx_total_k=$(( ctx_total / 1000 ))
    ctx_tokens_str="${ctx_used_k}k/${ctx_total_k}k"
  fi
fi

# --- colors (Nord palette) ---
C_MODEL='\033[38;2;208;135;112m'   # nord12 #D08770 - model name
C_EFFORT='\033[38;2;235;203;139m'  # nord13 #EBCB8B - effort level
C_DIR='\033[38;2;136;192;208m'     # nord8  #88C0D0 - directory name
C_BRANCH='\033[38;2;180;142;173m'  # nord15 #B48EAD - git branch
C_USAGE='\033[38;2;129;161;193m'   # nord9  #81A1C1 - 5h/7d usage values
C_DELTA='\033[38;2;94;129;172m'    # nord10 #5E81AC - 5h/7d reset time deltas
C_CTX='\033[38;2;216;222;233m'     # nord4  #D8DEE9 - ctx percentage value
C_CTX_TOK='\033[38;2;236;239;244m' # nord6  #ECEFF4 - ctx token count label
C_SEP='\033[38;2;76;86;106m'       # nord3  #4C566A - separators and pipes
C_RESET='\033[0m'

# --- assemble output ---
SEP="${C_SEP} • ${C_RESET}"

printf "${C_MODEL}\033[1m%s\033[22m${C_RESET}" "$model"
if [ -n "$effort" ]; then
  printf "%b" "$SEP"
  printf "${C_EFFORT}%s${C_RESET}" "$effort"
fi
printf "${C_SEP} | ${C_RESET}"
printf "\033[1m${C_DIR}%s\033[22m${C_RESET}" "$dir_name"
if [ -n "$branch" ]; then
  printf "%b" "$SEP"
  printf "\033[1m${C_BRANCH}%s\033[22m${C_RESET}" "$branch"
fi
printf "${C_SEP} | ${C_RESET}"
if [ -n "$five_h" ]; then
  printf "${C_USAGE}5h %s%%${C_RESET}" "$five_h"
  if [ -n "$five_h_reset" ]; then
    delta=$(compute_delta "$five_h_reset")
    [ -n "$delta" ] && printf " ${C_DELTA}(%s)${C_RESET}" "$delta"
  fi
fi
if [ -n "$seven_d" ]; then
  [ -n "$five_h" ] && printf "%b" "$SEP"
  printf "${C_USAGE}7d %s%%${C_RESET}" "$seven_d"
  if [ -n "$seven_d_reset" ]; then
    delta=$(compute_delta "$seven_d_reset")
    [ -n "$delta" ] && printf " ${C_DELTA}(%s)${C_RESET}" "$delta"
  fi
fi
if [ -n "$ctx_str" ]; then
  printf "${C_SEP} | ${C_RESET}"
  printf "${C_CTX}ctx %s${C_RESET}" "$ctx_str"
  [ -n "$ctx_tokens_str" ] && printf " ${C_CTX_TOK}(%s)${C_RESET}" "$ctx_tokens_str"
fi
