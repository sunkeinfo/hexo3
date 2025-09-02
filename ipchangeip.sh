#!/bin/bash

# ==============================================================================
# AWS Elastic IP Association Script
#
# Description: This script associates a specific Elastic IP with an EC2 instance
#              for a short duration (10 seconds) and then disassociates it.
#
# Usage: Can be executed directly from a machine with AWS CLI configured,
#        or called remotely via curl:
#        curl -sSL "URL_TO_THIS_RAW_SCRIPT" | bash
#
# ==============================================================================

# --- Configuration Variables ---
# Target Elastic IP address
EIP="3.149.176.94"
# Target EC2 Instance ID
INSTANCE_ID="i-094ccfdca8be8c80f"
# Target AWS Region
REGION="us-east-2"

# --- Script Logic ---

# Function to print a formatted message
log_message() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

log_message "Starting Elastic IP management script in region $REGION..."
log_message "=========================================================="

# 1. Get the Allocation ID for the public IP
log_message "Finding Allocation ID for IP ${EIP}..."
ALLOCATION_ID=$(aws ec2 describe-addresses --region $REGION --public-ips $EIP --query "Addresses[0].AllocationId" --output text)

# Check if the Allocation ID was found successfully
if [ -z "$ALLOCATION_ID" ]; then
  log_message "Error: Could not find Allocation ID for IP ${EIP} in region $REGION."
  log_message "Please check if the IP is correct and belongs to your account in this region."
  exit 1
fi
log_message "Successfully found Allocation ID: $ALLOCATION_ID"

# 2. Associate the Elastic IP with the EC2 instance
log_message "Associating IP ${EIP} with instance ${INSTANCE_ID}..."
ASSOCIATE_OUTPUT=$(aws ec2 associate-address --region $REGION --instance-id $INSTANCE_ID --allocation-id $ALLOCATION_ID --output json)

# Check if the association command was successful before proceeding
if [ $? -ne 0 ]; then
    log_message "Error: Failed to associate the Elastic IP. Aborting."
    exit 1
fi

# Extract the new Association ID from the JSON output
ASSOCIATION_ID=$(echo $ASSOCIATE_OUTPUT | grep -o 'eipassoc-[a-zA-Z0-9]*')
log_message "Association command submitted. The new Association ID is: $ASSOCIATION_ID"

# 3. Wait for 10 seconds
log_message "Waiting for 10 seconds..."
sleep 10

# 4. Disassociate the Elastic IP from the instance
log_message "Disassociating IP ${EIP} (Association ID: $ASSOCIATION_ID)..."
aws ec2 disassociate-address --region $REGION --association-id $ASSOCIATION_ID

if [ $? -eq 0 ]; then
    log_message "Successfully disassociated the Elastic IP."
else
    log_message "Warning: The disassociation command failed. Please check the instance state manually."
fi

log_message "=========================================================="
log_message "Script finished."
