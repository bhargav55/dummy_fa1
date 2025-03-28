#!/bin/bash

# Check if both arguments are provided
if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <private_key> <public_key>"
    exit 1
fi

PRIVATE_KEY=$1
PUBLIC_KEY=$2

# Task 1: Remove .aptos directory
echo "Removing .aptos directory..."
rm -rf .aptos

# Task 2: Initialize aptos with private key
echo "Initializing aptos..."
aptos init --network testnet --private-key "$PRIVATE_KEY" --assume-yes

# Task 3: Create and fund resource account
echo "Creating and funding resource account..."
aptos move run --function-id '0x1::resource_account::create_resource_account_and_fund' \
    --args "string:warpgate" "hex:$PUBLIC_KEY" 'u64:10000000' --assume-yes

# Task 4: Derive resource account address
echo "Deriving resource account address..."
RESOURCE_ACCOUNT=$(aptos account derive-resource-account-address --address "$PUBLIC_KEY" \
    --seed warpgate --seed-encoding utf8 | grep -o '"Result": "[^"]*"' | cut -d'"' -f4)

echo "Resource Account: $RESOURCE_ACCOUNT"

# Update move.toml
echo "Updating move.toml..."
sed -i.bak -e "s|^dev = .*|dev = \"$PUBLIC_KEY\"|" \
    -e "s|^default_admin = .*|default_admin = \"$PUBLIC_KEY\"|" \
    -e "s|^mmfee = .*|mmfee = \"$PUBLIC_KEY\"|" \
    -e "s|^warpgate = .*|warpgate = \"0x$RESOURCE_ACCOUNT\"|" move.toml

# Update .aptos/config.yaml
echo "Updating .aptos/config.yaml..."
sed -i.bak "s|^    account: .*|    account: \"0x$RESOURCE_ACCOUNT\"|" .aptos/config.yaml

# Publish move package
echo "Publishing move package..."
aptos move publish --assume-yes

echo "Setup completed successfully!"
