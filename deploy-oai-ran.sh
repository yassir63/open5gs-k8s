#!/bin/bash

# Function to print in color for better visibility
print_header() {
    echo -e "\n\e[1;34m############################### $1 ###############################\e[0m"
}

print_success() {
    echo -e "\e[1;32m$1\e[0m"
}

print_error() {
    echo -e "\e[1;31mERROR: $1\e[0m"
}

print_warning() {
    echo -e "\e[1;31mINFO: $1\e[0m"
}

print_subheader() {
    echo -e "\e[1;36m--- $1 ---\e[0m"
}

# Set the namespace for Open5GS
NAMESPACE="open5gs"
TIMEOUT_DURATION=10  # Set the timeout duration in seconds

print_warning "Before deploying OAI RAN, please check the oai-ran/prepare-demo-oai.sh file and adjust it to your deployment environment."

print_header "Preparing cluster for RAN deployment"
print_subheader "Checking if namespace '$NAMESPACE' exists"
kubectl get namespace $NAMESPACE 2>/dev/null || {
    print_error "Namespace '$NAMESPACE' not found. Creating it now..."
    kubectl create namespace $NAMESPACE
    print_success "Namespace '$NAMESPACE' created."
}

# Function to wait for a pod to be ready based on its label
wait_for_pod_ready() {
    local label_key=$1
    local label_value=$2
    echo "Waiting for pod with label $label_key=$label_value to be ready in namespace $NAMESPACE..."

    while [ "$(kubectl get pods -n "$NAMESPACE" -l="$label_key=$label_value" -o jsonpath='{.items[*].status.containerStatuses[0].ready}')" != "true" ]; do
        sleep 5
        echo "Still waiting for pod $label_value to be ready..."
    done
    print_success "Pod $label_value is now ready."
}

# Function to wait for a pod to be running based on its label
wait_for_pod_running() {
    local label_key=$1
    local label_value=$2
    echo "Waiting for pod with label $label_key=$label_value to be running in namespace $NAMESPACE..."

    # Check if the pod exists
    pod_count=$(kubectl get pods -n "$NAMESPACE" -l "$label_key=$label_value" --no-headers | wc -l)
    
    if [ "$pod_count" -eq 0 ]; then
        print_error "No pods found with label $label_key=$label_value in namespace $NAMESPACE."
        return 1
    fi

    # Wait for the pod to be in Running state
    while : ; do
        # Get the pod status
        pod_status=$(kubectl get pods -n "$NAMESPACE" -l "$label_key=$label_value" -o jsonpath='{.items[*].status.phase}')
        
        # Check if the pod is in 'Running' state
        if [[ "$pod_status" =~ "Running" ]]; then
            print_success "Pod $label_value is now running."
            break
        else
            echo "Pod $label_value is not running yet. Waiting..."
            sleep 5
        fi
    done
}


print_subheader "Checking if subscribers have been added"
output=$(timeout $TIMEOUT_DURATION python3 mongo-tools/check-subscribers.py)

# Check if the Python script completed successfully or timed out
if [ $? -eq 124 ]; then
    echo "ERROR: The check-subscribers script timed out after ${TIMEOUT_DURATION} seconds."
    echo "Please verify the connection to MongoDB or troubleshoot the script in mongo-tools/check-subscribers.py."
    exit 1
elif echo "$output" | grep -q "No subscribers found"; then
    echo "There are no subscribers. Please add subscribers before deploying the RAN."
    exit 1
else
    echo "$output"  # Print the list of subscribers if found
fi

print_header "Preparing OAI RAN files (RAN Deployment [1/4])"
cd oai-ran
chmod +x ./prepare-demo-oai.sh
./prepare-demo-oai.sh -a

print_header "Deploying the OAI gNodeB (RAN Deployment [2/4])"
./demo-oai.sh start-gnb
sleep 5
print_success "OAI gNodeB deployed successfully."

print_header "Deploying OAI NR-UE (RAN Deployment [3/4])"
./demo-oai.sh start-nr-ue
print_success "OAI NR-UE deployed successfully."

print_header "Deploying OAI NR-UE2 (RAN Deployment [4/4])"
./demo-oai.sh start-nr-ue2
print_success "OAI NR-UE2 deployed successfully."

# Final message for the user
print_header "Deployment Complete"
echo -e "\e[1;33mOAI RAN deployment is complete and ready to use.\e[0m"
cd ..