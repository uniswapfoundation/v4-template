#!/bin/bash

# Script to deploy the VCOP system to Base mainnet
echo "=== Preparing to deploy VCOP system to Base mainnet ==="

# Ensure we're in the right directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.."

# Clean any pending transactions
echo "Cleaning pending transactions..."
make clean-txs

# Run the deployment with the Chain ID for Base mainnet
echo "Starting deployment to Base mainnet..."
make deploy-mainnet

echo "Deployment completed. Check the logs for any errors."
echo "If everything looks good, you can now interact with your system on Base mainnet." 