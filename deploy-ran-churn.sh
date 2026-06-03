#!/bin/bash
set -euo pipefail

print_header() {
    echo -e "\n\e[1;34m############################### $1 ###############################\e[0m"
}

print_success() {
    echo -e "\e[1;32m$1\e[0m"
}

NAMESPACE="${NAMESPACE:-open5gs}"
REPLICAS="${1:-0}"

print_header "Deploying UERANSIM gNB"
kubectl apply -k ueransim/ueransim-gnb -n "$NAMESPACE"
kubectl wait -n "$NAMESPACE" --for=condition=Ready pod -l app=ueransim,component=gnb --timeout=180s
print_success "UERANSIM gNB is ready."

print_header "Deploying scalable UERANSIM churn UE StatefulSet"
kubectl apply -k ueransim/ueransim-ue-churn -n "$NAMESPACE"
kubectl scale statefulset/ueransim-ue-churn -n "$NAMESPACE" --replicas="$REPLICAS"
print_success "UERANSIM churn UE StatefulSet deployed with replicas=${REPLICAS}."

cat <<EOF

Useful commands:
  kubectl scale statefulset/ueransim-ue-churn -n ${NAMESPACE} --replicas=10
  kubectl scale statefulset/ueransim-ue-churn -n ${NAMESPACE} --replicas=0
  scripts/ueransim-churn/run-churn.sh --counts "10 25 50"
EOF
