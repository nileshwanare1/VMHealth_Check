#!/usr/bin/env bash
# vm_health.sh
# Check VM health on Ubuntu by CPU, memory and root-disk utilization.
# Usage:
#   ./vm_health.sh         -> prints only the health status
#   ./vm_health.sh explain -> prints status + numeric reasons
set -euo pipefail

THRESHOLD=60    # percent

# compute CPU usage (%) over a short interval using /proc/stat
get_cpu_usage() {
  read -r _ user1 nice1 system1 idle1 iowait1 irq1 softirq1 steal1 guest1 guest_nice1 < /proc/stat
  idle_total1=$((idle1 + iowait1))
  total1=$((user1 + nice1 + system1 + idle1 + iowait1 + irq1 + softirq1 + steal1 + guest1 + guest_nice1))

  sleep 0.5

  read -r _ user2 nice2 system2 idle2 iowait2 irq2 softirq2 steal2 guest2 guest_nice2 < /proc/stat
  idle_total2=$((idle2 + iowait2))
  total2=$((user2 + nice2 + system2 + idle2 + iowait2 + irq2 + softirq2 + steal2 + guest2 + guest_nice2))

  delta_total=$((total2 - total1))
  delta_idle=$((idle_total2 - idle_total1))

  if [ "$delta_total" -le 0 ]; then
    echo "0"
    return
  fi

  cpu_usage=$(awk -v dt="$delta_total" -v di="$delta_idle" 'BEGIN { printf "%.0f", (dt - di) * 100 / dt }')
  echo "$cpu_usage"
}

# compute memory usage (%) using free
get_mem_usage() {
  # used / total (exclude swap)
  read -r mem_total mem_used _ < <(free -b | awk '/^Mem:/ {print $2, $3, $4}')
  if [ -z "$mem_total" ] || [ "$mem_total" -le 0 ]; then
    echo "0"
    return
  fi
  mem_pct=$(awk -v used="$mem_used" -v tot="$mem_total" 'BEGIN { printf "%.0f", used * 100 / tot }')
  echo "$mem_pct"
}

# compute root disk usage (%) using df
get_disk_usage() {
  disk_pct=$(df / --output=pcent | tail -1 | tr -dc '0-9')
  if [ -z "$disk_pct" ]; then
    echo "0"
    return
  fi
  echo "$disk_pct"
}

main() {
  explain=false
  if [ "${1-}" = "explain" ]; then
    explain=true
  elif [ "${1-}" = "" ]; then
    explain=false
  elif [ "${1-}" = "--help" ] || [ "${1-}" = "-h" ]; then
    cat <<EOF
Usage: $0 [explain]
  No args: prints health status (Healthy / Not Healthy)
  explain : prints health status and the numeric CPU/Memory/Disk values and reason
EOF
    exit 0
  else
    echo "Unknown argument: '$1'. Use 'explain' or no argument." >&2
    exit 2
  fi

  cpu=$(get_cpu_usage)
  mem=$(get_mem_usage)
  disk=$(get_disk_usage)

  unhealthy_reasons=()

  if [ "$cpu" -gt "$THRESHOLD" ]; then
    unhealthy_reasons+=("CPU=${cpu}% (>${THRESHOLD}%)")
  fi
  if [ "$mem" -gt "$THRESHOLD" ]; then
    unhealthy_reasons+=("MEM=${mem}% (>${THRESHOLD}%)")
  fi
  if [ "$disk" -gt "$THRESHOLD" ]; then
    unhealthy_reasons+=("DISK=${disk}% (>${THRESHOLD}%)")
  fi

  if [ "${#unhealthy_reasons[@]}" -eq 0 ]; then
    status="Healthy"
    code=0
  else
    status="Not Healthy"
    code=1
  fi

  echo "VM Health: $status"

  if $explain; then
    echo "Details:"
    echo "  CPU usage:    ${cpu}%"
    echo "  Memory usage: ${mem}%"
    echo "  Disk usage:   ${disk}%"
    if [ "${#unhealthy_reasons[@]}" -eq 0 ]; then
      echo "Reason: All metrics are at or below ${THRESHOLD}%."
    else
      echo "Reason: The following metric(s) exceed ${THRESHOLD}%:"
      for r in "${unhealthy_reasons[@]}"; do
        echo "  - $r"
      done
    fi
  fi

  exit $code
}

main "${1-}"
