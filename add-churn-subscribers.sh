#!/bin/bash
set -euo pipefail

print_header() {
    echo -e "\n\e[1;34m############################### $1 ###############################\e[0m"
}

print_success() {
    echo -e "\e[1;32m$1\e[0m"
}

COUNT="${1:-100}"
IMSI_PREFIX="${IMSI_PREFIX:-0010100001}"
START_SUFFIX="${START_SUFFIX:-0}"

print_header "Generating ${COUNT} UERANSIM churn subscribers"
python3 mongo-tools/generate-ueransim-churn-data.py \
  --count "$COUNT" \
  --imsi-prefix "$IMSI_PREFIX" \
  --start-suffix "$START_SUFFIX"

print_header "Adding generated subscribers to Open5GS"
python3 mongo-tools/add-subscribers.py
print_success "Generated and added ${COUNT} churn subscribers."
