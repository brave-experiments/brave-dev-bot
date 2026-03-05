#!/bin/bash
# Display a human-readable summary of brave-bot scheduled tasks
# Parses sync-schedules.sh to show what runs when

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCHEDULE_FILE="$SCRIPT_DIR/sync-schedules.sh"

if [ ! -f "$SCHEDULE_FILE" ]; then
  echo "Error: sync-schedules.sh not found at $SCHEDULE_FILE" >&2
  exit 1
fi

# Colors (disable if not a terminal)
if [ -t 1 ]; then
  BOLD='\033[1m'
  DIM='\033[2m'
  CYAN='\033[36m'
  GREEN='\033[32m'
  RESET='\033[0m'
else
  BOLD='' DIM='' CYAN='' GREEN='' RESET=''
fi

cron_to_human() {
  local min="$1" hour="$2" dom="$3" mon="$4" dow="$5"

  local freq_part=""
  local time_part=""

  # Determine frequency
  if [[ "$dom" != "*" && "$mon" == "*" ]]; then
    freq_part="Monthly (${dom}st)"
  elif [[ "$min" == *","* && "$hour" == "*" ]]; then
    local count
    count=$(echo "$min" | tr ',' '\n' | wc -l | tr -d ' ')
    local interval=$((60 / count))
    freq_part="Every ${interval} min"
  elif [[ "$min" == "*/"* ]]; then
    freq_part="Every ${min#*/} min"
  elif [[ "$hour" == "*/"* ]]; then
    freq_part="Every ${hour#*/}h"
  else
    freq_part="Daily"
  fi

  # Determine times
  if [[ "$hour" != "*" && "$hour" != "*/"* ]]; then
    local times=""
    # Handle comma-separated minutes (shouldn't happen with hours set, but be safe)
    local first_min
    first_min=$(echo "$min" | cut -d',' -f1)
    for h in $(echo "$hour" | tr ',' ' '); do
      times="${times:+$times, }$(printf '%02d:%02d' "$h" "$first_min")"
    done
    time_part="at $times"
  elif [[ "$min" == *","* && "$hour" == "*" ]]; then
    local first_min
    first_min=$(echo "$min" | cut -d',' -f1)
    time_part="at :$(printf '%02d' "$first_min") past each hour"
  fi

  echo "${freq_part}${time_part:+ $time_part}"
}

echo -e "${BOLD}Brave Bot Scheduled Tasks${RESET}"
echo -e "${DIM}Source: scripts/sync-schedules.sh${RESET}"
echo ""

in_cron=false
comment=""
gate=""

while IFS= read -r line; do
  # Detect start/end of cron block
  if [[ "$line" == *'CRON_JOBS=$(cat <<EOF'* ]]; then
    in_cron=true
    continue
  fi
  if [[ "$line" == "EOF" ]] && $in_cron; then
    break
  fi
  if ! $in_cron; then
    continue
  fi

  # Skip boilerplate lines
  if [[ "$line" =~ ^(SHELL|PATH)= ]] || [[ "$line" == *"do not edit"* ]] || [[ "$line" == *"=== brave-bot"* ]]; then
    continue
  fi

  # Collect comment lines
  if [[ "$line" =~ ^#\  ]]; then
    local_stripped="${line#\# }"
    if [[ "$local_stripped" == Gate* ]]; then
      gate="$local_stripped"
    elif [ -z "$comment" ]; then
      comment="$local_stripped"
    else
      comment="$comment | $local_stripped"
    fi
    continue
  fi

  # Skip empty lines (reset comment state)
  if [ -z "$line" ]; then
    comment=""
    gate=""
    continue
  fi

  # Parse cron line into 5 schedule fields + command
  if [[ "$line" =~ ^([0-9,*/]+)[[:space:]]+([0-9,*/]+)[[:space:]]+([0-9,*/]+)[[:space:]]+([0-9,*/]+)[[:space:]]+([0-9,*/]+)[[:space:]]+(.*) ]]; then
    cron_min="${BASH_REMATCH[1]}"
    cron_hour="${BASH_REMATCH[2]}"
    cron_dom="${BASH_REMATCH[3]}"
    cron_mon="${BASH_REMATCH[4]}"
    cron_dow="${BASH_REMATCH[5]}"
    command="${BASH_REMATCH[6]}"
  else
    comment=""
    gate=""
    continue
  fi

  # Extract the task name from the command
  task_name=""
  if [[ "$command" == *"./run.sh"* ]]; then
    # Extract iteration count: look for number after run.sh
    if [[ "$command" =~ run\.sh[[:space:]]+([0-9]+) ]]; then
      task_name="run.sh (${BASH_REMATCH[1]} iterations)"
    else
      task_name="run.sh"
    fi
  elif [[ "$command" =~ -p\ \'(/[a-z-]+) ]]; then
    task_name="${BASH_REMATCH[1]}"
  elif [[ "$command" == *"git push origin"* ]]; then
    task_name="sync repo upstream→origin"
  else
    task_name="(unknown)"
  fi

  # Convert cron schedule to human-readable
  human=$(cron_to_human "$cron_min" "$cron_hour" "$cron_dom" "$cron_mon" "$cron_dow")
  cron_expr="$cron_min $cron_hour $cron_dom $cron_mon $cron_dow"

  # Print the entry
  echo -e "  ${GREEN}$task_name${RESET}"
  echo -e "    ${CYAN}Schedule:${RESET} $human"
  echo -e "    ${CYAN}Cron:${RESET}     ${DIM}$cron_expr${RESET}"
  if [ -n "$gate" ]; then
    echo -e "    ${CYAN}Gate:${RESET}     ${DIM}${gate#Gate check *}${RESET}"
  fi
  if [ -n "$comment" ]; then
    echo -e "    ${CYAN}Note:${RESET}     ${DIM}$comment${RESET}"
  fi
  echo ""

  comment=""
  gate=""
done < "$SCHEDULE_FILE"
