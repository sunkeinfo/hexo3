#!/bin/bash

# This script creates a new AWS Organizations account.
# It automatically uses the part of the email address before the "@" as the account name.
#
# Usage:
#   curl -sL https://raw.githubusercontent.com/your-username/your-repo/main/create-org-account.sh | bash -s -- "your-email@example.com"
#
# Ensure you have the necessary AWS CLI permissions and have 'jq' installed.

# Check if an email address was provided as an argument
if [ -z "$1" ]; then
  echo "Error: No email address was provided."
  echo "Usage: $0 \"your-email@example.com\""
  exit 1
fi

EMAIL="$1"

# Extract the account name from the email address
ACCOUNT_NAME=$(echo "$EMAIL" | cut -d'@' -f1)

# A simple check to ensure the account name is not empty
if [ -z "$ACCOUNT_NAME" ]; then
  echo "Error: The account name could not be extracted from the email address."
  exit 1
fi

echo "Attempting to create a new AWS Organizations account..."
echo "Account Name: ${ACCOUNT_NAME}"
echo "Email: ${EMAIL}"

# Execute the AWS CLI command to create the account
# We capture all output (including errors) into the 'RESULT' variable
RESULT=$(aws organizations create-account \
    --email "${EMAIL}" \
    --account-name "${ACCOUNT_NAME}" \
    --query 'CreateAccountStatus' --output json 2>&1)

# Check the exit status of the AWS CLI command
if [ $? -eq 0 ]; then
  echo "Account creation request submitted successfully."
  
  # Check if 'jq' is installed to parse the JSON output
  if ! command -v jq &> /dev/null; then
      echo "Warning: The 'jq' command was not found, so the detailed results cannot be parsed."
      echo "Original output:"
      echo "${RESULT}"
      exit 0
  fi

  # Parse the JSON output for key information
  ACCOUNT_ID=$(echo "${RESULT}" | jq -r '.AccountId')
  ACCOUNT_STATE=$(echo "${RESULT}" | jq -r '.State')

  echo "----------------------------------------"
  echo "Account ID: ${ACCOUNT_ID}"
  echo "Account State: ${ACCOUNT_STATE}"
  echo "----------------------------------------"
  echo "An email has been sent to ${EMAIL}. Please check your inbox to complete the account setup."
else
  echo "Failed to create the AWS Organizations account."
  echo "Error message:"
  echo "${RESULT}"
  exit 1
fi
