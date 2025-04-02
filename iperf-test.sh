#!/bin/bash

# Script to Ping a Target Address from UERANSIM UE Pods in the Open5GS Namespace

NAMESPACE="open5gs"
PING_ADDRESS="www.google.ca"

# Function to print in color
print_header() {
    echo -e "\n\e[1;34m############################### $1 ###############################\e[0m"
}

print_success() {
    echo -e "\e[1;32m$1\e[0m"
}

print_error() {
    echo -e "\e[1;31mERROR: $1\e[0m"
}

# Function to print script usage
usage() {
    echo "Usage: $0"
    echo "This script pings $PING_ADDRESS from all pods containing 'ueransim-ue' in the '$NAMESPACE' namespace."
}

# Retrieve the list of UE pods
print_header "Checking for UERANSIM UE Pods in Namespace '$NAMESPACE'"
PODS=$(kubectl get pods -n $NAMESPACE | grep "ueransim-ue" | awk '{print $1}')

if [ -z "$PODS" ]; then
    print_error "No pods found containing 'ueransim-ue' in namespace: $NAMESPACE"
    exit 1
fi
UPF1_POD=$(kubectl get pods -n $NAMESPACE | grep "open5gs-upf1" | awk '{print $1}')
UPF2_POD=$(kubectl get pods -n $NAMESPACE | grep "open5gs-upf2" | awk '{print $1}')

print_success "Found the following UE Pods $PODS and UPF Pods:"
echo $PODS $UPF1_POD $UPF2_POD

print_header "Initiating Ping Test and installing iperf3"
echo "Pinging $PING_ADDRESS from each UE pod..."

# For each UPF pod, possibly install iperf3 and run 2 occurrences with server mode on 2 ports, default 5201 and 5202
POD=$UPF1_POD; CONTAINER=$(kubectl get pod $POD -n $NAMESPACE -o jsonpath='{.spec.containers[0].name}')

kubectl exec $POD -n $NAMESPACE -c $CONTAINER -- apt update > /dev/null 2>&1
kubectl exec $POD -n $NAMESPACE -c $CONTAINER -- apt install -y net-tools iperf3 > /dev/null 2>&1

if kubectl exec $POD -n $NAMESPACE -c $CONTAINER -- netstat -tuln | grep -q '5201'; then
    print_success "Pod $POD: iperf3 is already listening on port 5201"
else
    echo "Pod $POD: run iperf3, server mode with port 5201"
    kubectl exec $POD -n $NAMESPACE -c $CONTAINER -- nohup iperf3 -B 10.41.0.1 -p 5201 -s & > /dev/null 2>&1
fi
if kubectl exec $POD -n $NAMESPACE -c $CONTAINER -- netstat -tuln | grep -q '5202'; then
    print_success "Pod $POD: iperf3 is already listening on port 5202"
else
    echo "Pod $POD: run iperf3, server mode, port 5202"
    kubectl exec $POD -n $NAMESPACE -c $CONTAINER -- nohup iperf3 -B 10.41.0.1 -p 5202 -s & > /dev/null 2>&1
fi
POD=$UPF2_POD; CONTAINER=$(kubectl get pod $POD -n $NAMESPACE -o jsonpath='{.spec.containers[0].name}')
kubectl exec $POD -n $NAMESPACE -c $CONTAINER -- apt update > /dev/null 2>&1
kubectl exec $POD -n $NAMESPACE -c $CONTAINER -- apt install -y net-tools iperf3 > /dev/null 2>&1
if kubectl exec $POD -n $NAMESPACE -c $CONTAINER -- netstat -tuln | grep -q '5201'; then
    print_success "Pod $POD: iperf3 is already listening on port 5201"
else
    echo "Pod $POD: run iperf3, server mode with port 5201"
    kubectl exec $POD -n $NAMESPACE -c $CONTAINER -- nohup iperf3 -B 10.42.0.1 -p 5201 -s & > /dev/null 2>&1
fi
if kubectl exec $POD -n $NAMESPACE -c $CONTAINER -- netstat -tuln | grep -q '5202'; then
    print_success "Pod $POD: iperf3 is already listening on port 5202"
else
    echo "Pod $POD: run iperf3, server mode, port 5202"
    kubectl exec $POD -n $NAMESPACE -c $CONTAINER -- nohup iperf3 -B 10.42.0.1 -p 5202 -s & > /dev/null 2>&1
fi

# Arrays to store ping results
SUCCESSFUL_PODS=()
FAILED_PODS=()

# Loop through each UE pod, possibly install iperf3 and ping
for POD in $PODS; do
    CONTAINER=$(kubectl get pod $POD -n $NAMESPACE -o jsonpath='{.spec.containers[0].name}')
    echo "Possibly install iperf3 then Ping from pod: $POD, container: $CONTAINER"

    # Install iperf3
    kubectl exec $POD -n $NAMESPACE -c $CONTAINER -- apt update > /dev/null 2>&1
    kubectl exec $POD -n $NAMESPACE -c $CONTAINER -- apt install -y iperf3 > /dev/null 2>&1

    IP_TUN=$(kubectl exec $POD -n $NAMESPACE -c $CONTAINER -- ip -4 addr show uesimtun0 | grep inet | awk '{ print $2 }' | cut -d/ -f1)
    echo "You can now run:"
    echo "kubectl exec $POD -n $NAMESPACE -c $CONTAINER -- iperf3 -B $IP_TUN -c 10.[41/42].0.1 -p [5201/5202] -t 0"

    # Perform ping and check result
    if kubectl exec $POD -n $NAMESPACE -c $CONTAINER -- ping -I uesimtun0 -c 5 $PING_ADDRESS > /dev/null 2>&1; then
        print_success "$POD: Ping successful"
        SUCCESSFUL_PODS+=("$POD")
    else
        print_error "$POD: Ping failed"
        FAILED_PODS+=("$POD")
    fi
done

# Display summary of ping results
print_header "Ping Test Summary"
if [ ${#SUCCESSFUL_PODS[@]} -gt 0 ]; then
    echo -e "\e[1;32mSuccessful Pods:\e[0m"
    for POD in "${SUCCESSFUL_PODS[@]}"; do
        echo "  - $POD"
    done
else
    print_error "No pods were successful."
fi

if [ ${#FAILED_PODS[@]} -gt 0 ]; then
    echo -e "\e[1;31mFailed Pods:\e[0m"
    for POD in "${FAILED_PODS[@]}"; do
        echo "  - $POD"
    done
else
    print_success "All pods were successful."
fi
