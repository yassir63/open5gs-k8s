#!/bin/bash
set -euo pipefail

NAMESPACE="${NAMESPACE:-open5gs}"
STATEFULSET="${STATEFULSET:-ueransim-ue-churn}"
COUNTS="10 25 50"
SETTLE_SECONDS=60
BETWEEN_SECONDS=30
MAPPER_NAMESPACE="${MAPPER_NAMESPACE:-$NAMESPACE}"
MAPPER_SERVICE="${MAPPER_SERVICE:-ue-mapper-api}"
MAPPER_LOCAL_PORT="${MAPPER_LOCAL_PORT:-18081}"
REQUIRE_MAPPER_REGISTRATION="${REQUIRE_MAPPER_REGISTRATION:-true}"
MAPPER_WAIT_SECONDS="${MAPPER_WAIT_SECONDS:-180}"
MAPPER_PF_PID=""
BASELINE_MAPPER_COUNT=0
GRACEFUL_DEREGISTRATION="${GRACEFUL_DEREGISTRATION:-true}"

usage() {
  cat <<EOF
Usage: $0 [options]

Scale UERANSIM UEs up/down to stress AMF attach/detach and the UE mapper.
This script does not generate user-plane traffic.

Options:
  --counts "10 25 50"       Space-separated UE counts to test.
  --settle-seconds 60       Wait after scaling up before detaching.
  --between-seconds 30      Wait after scaling down before next wave.
  -h, --help                Show this help.

Example:
  $0 --counts "10 25 50 100" --settle-seconds 90
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --counts)
      COUNTS="$2"
      shift 2
      ;;
    --settle-seconds)
      SETTLE_SECONDS="$2"
      shift 2
      ;;
    --between-seconds)
      BETWEEN_SECONDS="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

timestamp() {
  date -Is
}

pod_count() {
  kubectl get pods -n "$NAMESPACE" -l app=ueransim,component=ue,profile=churn --no-headers 2>/dev/null | wc -l | tr -d ' '
}

ready_count() {
  kubectl get pods -n "$NAMESPACE" -l app=ueransim,component=ue,profile=churn \
    -o jsonpath='{range .items[*]}{range .status.containerStatuses[*]}{.ready}{"\n"}{end}{end}' 2>/dev/null \
    | grep -c '^true$' || true
}

mapper_inventory_count() {
  python3 - "$MAPPER_LOCAL_PORT" <<'PY'
import json
import sys
import urllib.request

port = int(sys.argv[1])
with urllib.request.urlopen(
    f"http://127.0.0.1:{port}/inventory/ues?limit=10000",
    timeout=10,
) as response:
    payload = json.load(response)
print(int(payload["count"]))
PY
}

start_mapper_port_forward() {
  if [ "$REQUIRE_MAPPER_REGISTRATION" != "true" ]; then
    return 0
  fi

  kubectl port-forward -n "$MAPPER_NAMESPACE" "svc/$MAPPER_SERVICE" \
    "${MAPPER_LOCAL_PORT}:80" > /tmp/ueransim-churn-mapper-port-forward.log 2>&1 &
  MAPPER_PF_PID=$!
  sleep 3
  if ! kill -0 "$MAPPER_PF_PID" >/dev/null 2>&1; then
    cat /tmp/ueransim-churn-mapper-port-forward.log >&2 || true
    echo "UE mapper port-forward failed" >&2
    return 1
  fi
  BASELINE_MAPPER_COUNT="$(mapper_inventory_count)"
  echo "Baseline UE mapper inventory count: ${BASELINE_MAPPER_COUNT}"
}

stop_mapper_port_forward() {
  if [ -n "$MAPPER_PF_PID" ]; then
    kill "$MAPPER_PF_PID" >/dev/null 2>&1 || true
    wait "$MAPPER_PF_PID" >/dev/null 2>&1 || true
  fi
}

wait_for_mapper_count() {
  local expected="$1"
  local comparison="$2"
  local deadline=$((SECONDS + MAPPER_WAIT_SECONDS))
  while [ "$SECONDS" -lt "$deadline" ]; do
    local mapped
    mapped="$(mapper_inventory_count 2>/dev/null || echo -1)"
    if [ "$comparison" = "at-least" ] && [ "$mapped" -ge "$expected" ]; then
      echo "UE mapper inventory count: ${mapped} (expected at least ${expected})"
      return 0
    fi
    if [ "$comparison" = "at-most" ] && [ "$mapped" -le "$expected" ] && [ "$mapped" -ge 0 ]; then
      echo "UE mapper inventory count: ${mapped} (expected at most ${expected})"
      return 0
    fi
    echo "Waiting for UE mapper inventory: ${mapped}/${expected} (${comparison})"
    sleep 5
  done
  echo "Timed out waiting for UE mapper inventory count ${comparison} ${expected}" >&2
  return 1
}

graceful_deregister_ues() {
  if [ "$GRACEFUL_DEREGISTRATION" != "true" ]; then
    echo "Graceful UE deregistration disabled; scaling pods down directly."
    return 0
  fi

  local pods
  pods="$(kubectl get pods -n "$NAMESPACE" \
    -l app=ueransim,component=ue,profile=churn \
    -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}')"

  if [ -z "$pods" ]; then
    return 0
  fi

  echo "Triggering parallel NAS deregistration for active UEs..."
  local pids=()
  local pod
  for pod in $pods; do
    (
      kubectl exec -n "$NAMESPACE" "$pod" -- /bin/bash -c '
        set -e
        CLI="/ueransim/nr-cli"
        if [ ! -x "$CLI" ]; then
          CLI="$(command -v nr-cli)"
        fi
        NODE="$("$CLI" --dump | awk "/^imsi-/ { print \$1; exit }")"
        if [ -z "$NODE" ]; then
          echo "No active UERANSIM UE node found" >&2
          exit 1
        fi
        echo "Deregistering $NODE with disable-5g"
        "$CLI" "$NODE" --exec "deregister disable-5g"
      '
    ) &
    pids+=("$!")
  done

  local failed=0
  local pid
  for pid in "${pids[@]}"; do
    if ! wait "$pid"; then
      failed=1
    fi
  done
  if [ "$failed" -ne 0 ]; then
    echo "At least one UERANSIM UE failed graceful deregistration" >&2
    return 1
  fi
}

wait_for_count() {
  local expected="$1"
  local deadline=$((SECONDS + 300))
  while [ "$SECONDS" -lt "$deadline" ]; do
    local pods
    pods="$(pod_count)"
    if [ "$pods" -eq "$expected" ]; then
      return 0
    fi
    echo "Waiting for pod count ${pods}/${expected}"
    sleep 2
  done
  echo "Timed out waiting for pod count ${expected}" >&2
  return 1
}

wait_for_ready() {
  local expected="$1"
  local deadline=$((SECONDS + 300))
  while [ "$SECONDS" -lt "$deadline" ]; do
    local ready
    ready="$(ready_count)"
    if [ "$ready" -ge "$expected" ]; then
      echo "Ready UE pods: ${ready}/${expected}"
      return 0
    fi
    echo "Waiting for ready UE pods: ${ready}/${expected}"
    sleep 5
  done
  echo "Timed out waiting for ${expected} ready UE pods" >&2
  return 1
}

echo "UERANSIM AMF churn run started at $(timestamp)"
echo "namespace=${NAMESPACE} statefulset=${STATEFULSET} counts=${COUNTS}"
trap stop_mapper_port_forward EXIT
start_mapper_port_forward

for count in $COUNTS; do
  echo
  echo "==== $(timestamp) scaling to ${count} UEs ===="
  kubectl scale "statefulset/${STATEFULSET}" -n "$NAMESPACE" --replicas="$count"
  wait_for_count "$count"
  wait_for_ready "$count"
  if [ "$REQUIRE_MAPPER_REGISTRATION" = "true" ]; then
    wait_for_mapper_count "$((BASELINE_MAPPER_COUNT + count))" "at-least"
  fi
  echo "==== $(timestamp) holding ${count} UEs for ${SETTLE_SECONDS}s ===="
  sleep "$SETTLE_SECONDS"

  echo "==== $(timestamp) gracefully deregistering ${count} UEs ===="
  graceful_deregister_ues
  if [ "$REQUIRE_MAPPER_REGISTRATION" = "true" ]; then
    wait_for_mapper_count "$BASELINE_MAPPER_COUNT" "at-most"
  fi
  echo "==== $(timestamp) scaling down to 0 UE pods ===="
  kubectl scale "statefulset/${STATEFULSET}" -n "$NAMESPACE" --replicas=0
  wait_for_count 0
  echo "==== $(timestamp) detached all UEs; waiting ${BETWEEN_SECONDS}s ===="
  sleep "$BETWEEN_SECONDS"
done

echo "UERANSIM AMF churn run finished at $(timestamp)"
