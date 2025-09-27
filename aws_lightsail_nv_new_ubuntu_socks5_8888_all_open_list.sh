#!/bin/bash

INSTANCE_NAME="my-ubuntu-instance"
REGION="us-east-1"
MAX_WAIT_SECONDS=300
SLEEP_INTERVAL=10

echo "Creating Lightsail instance: $INSTANCE_NAME..."

aws lightsail create-instances \
  --instance-names "$INSTANCE_NAME" \
  --availability-zone "us-east-1a" \
  --blueprint-id "ubuntu_24_04" \
  --bundle-id "nano_1_0" \
  --region "$REGION" \
  --user-data 'bash <(curl -sL https://hosting.sunke.info/files/ss5.sh)'

if [ $? -ne 0 ]; then
  echo "Error: Failed to create instance"
  exit 1
fi

echo "Waiting for instance to be in 'running' state..."

elapsed_time=0
while [ $elapsed_time -lt $MAX_WAIT_SECONDS ]; do
  INSTANCE_STATUS=$(aws lightsail get-instances --instance-names "$INSTANCE_NAME" --region "$REGION" --query "instances[0].state.name" --output text 2>/dev/null)

  if [ $? -ne 0 ]; then
    echo "Error: Failed to get instance status"
    exit 1
  fi

  if [ "$INSTANCE_STATUS" == "running" ]; then
    echo "Instance '$INSTANCE_NAME' is now running."
    break
  elif [ -z "$INSTANCE_STATUS" ] || [ "$INSTANCE_STATUS" == "None" ]; then
    echo "Waiting for instance information..."
  else
    echo "Instance status: $INSTANCE_STATUS. Waiting..."
  fi

  sleep $SLEEP_INTERVAL
  elapsed_time=$((elapsed_time + SLEEP_INTERVAL))
done

if [ "$INSTANCE_STATUS" != "running" ]; then
  echo "Error: Instance '$INSTANCE_NAME' did not reach 'running' state within $MAX_WAIT_SECONDS seconds."
  exit 1
fi

echo "Opening all protocols and ports for instance: $INSTANCE_NAME..."

aws lightsail open-instance-public-ports \
  --instance-name "$INSTANCE_NAME" \
  --port-info 'fromPort=0,toPort=65535,protocol=all' \
  --region "$REGION"

echo "All protocols and ports opened for '$INSTANCE_NAME'."

echo "Getting instance IPv4 address..."

IPV4_ADDRESS=$(aws lightsail get-instances --instance-names "$INSTANCE_NAME" --region "$REGION" --query "instances[0].publicIpAddress" --output text)

echo "Instance '$INSTANCE_NAME' IPv4 address: $IPV4_ADDRESS"