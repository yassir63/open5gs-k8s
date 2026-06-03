#!/bin/bash
set -euo pipefail

NAMESPACE="${NAMESPACE:-open5gs}"
STATEFULSET="${STATEFULSET:-ueransim-ue-churn}"
COUNTS="10 25 50"
SETTLE_SECONDS=60
BETWEEN_SECONDS=30

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

for count in $COUNTS; do
  echo
  echo "==== $(timestamp) scaling to ${count} UEs ===="
  kubectl scale "statefulset/${STATEFULSET}" -n "$NAMESPACE" --replicas="$count"
  wait_for_count "$count"
  wait_for_ready "$count"
  echo "==== $(timestamp) holding ${count} UEs for ${SETTLE_SECONDS}s ===="
  sleep "$SETTLE_SECONDS"

  echo "==== $(timestamp) scaling down to 0 UEs ===="
  kubectl scale "statefulset/${STATEFULSET}" -n "$NAMESPACE" --replicas=0
  wait_for_count 0
  echo "==== $(timestamp) detached all UEs; waiting ${BETWEEN_SECONDS}s ===="
  sleep "$BETWEEN_SECONDS"
done

echo "UERANSIM AMF churn run finished at $(timestamp)"
