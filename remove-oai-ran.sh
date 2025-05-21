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

print_subheader() {
    echo -e "\e[1;36m--- $1 ---\e[0m"
}

# Set the namespace for Open5GS
NAMESPACE="open5gs"

# Delete the OAI UE
#print_header "Removing OAI NR-UE (RAN Deployment [1/5])"
#cd oai-ran
#./demo-oai.sh stop-nr-ue
#print_success "OAI NR-UE removed."

# Delete the OAI UE 2
#print_header "Removing OAI NR-UE2 (RAN Deployment [2/5])"
#cd oai-ran
#./demo-oai.sh stop-nr-ue2
#print_success "OAI NR-UE2 removed."

# Delete the OAI gNodeB
print_header "Removing OAI gNodeB (RAN Deployment [1/3])"
./demo-oai.sh stop-gnb
print_success "OAI gNodeB removed."

# Delete the OAI FlexRIC
print_header "Removing OAI FlexRIC (RAN Deployment [2/3])"
./demo-oai.sh stop-flexric
print_success "OAI FlexRIC removed."

# Delete leftover files
print_header "Removing leftover OAI RAN files (RAN Deployment [3/3])"
rm -rf oai-cn5g-fed/ oai5g-rru/ configure-demo-oai.sh demo-oai.sh
cd ..
print_success "Leftover OAI RAN files removed."

# Final message for the user
print_header "Cleanup Complete"
echo -e "\e[1;33mAll RAN components have been removed successfully.\e[0m"
echo "The namespace '$NAMESPACE' is still available. You may delete it manually if no other resources are needed in this namespace."