#!/bin/bash
set -euo pipefail

print_header() {
    echo -e "\n\e[1;34m############################### $1 ###############################\e[0m"
}

print_success() {
    echo -e "\e[1;32m$1\e[0m"
}

NAMESPACE="${NAMESPACE:-open5gs}"

print_header "Removing scalable UERANSIM churn UEs"
kubectl delete --wait=true -k ueransim/ueransim-ue-churn -n "$NAMESPACE" || true
print_success "UERANSIM churn UEs removed."

print_header "Removing UERANSIM gNB"
kubectl delete --wait=true -k ueransim/ueransim-gnb -n "$NAMESPACE" || true
print_success "UERANSIM gNB removed."
