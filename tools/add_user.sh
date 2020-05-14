#!/bin/bash

# This script adds a user to the Azure dev environment using their userid.
# By default, it will create a resource group in the east US region with
# the same name as the userid, scope the user to that resource group,
# and the credentials will be good for two years.

# The password will only be displayed once, so be sure to save it somewhere.

# Usage:
#
#   add_user.sh some_user [eastus 12345]
#

username=$1
region="${2:-eastus}"
subscription_id="${3:-$AZURE_SUBSCRIPTION_ID}"

if [ -z "$username" ]; then
  echo "You must specify a username argument. This should match the user's ID."
  exit
fi

# Explicitly set the subscription ID.
if [ -z "$subscription_id" ]; then
  echo "Unable to continue. Please specify the subscription ID, or set the AZURE_SUBSCRIPTION_ID env variable."
  exit
else
  echo "Setting account using subscription ${subscription_id}"
  eval "az account set -s ${subscription_id}"
fi

echo -e "Creating Azure credentials using the following arguments:\n \
  username: ${username}\n \
  region: ${region}\n \
  subscription_id: ${subscription_id}"

# Create the resource group.
eval "az group create -n ${username} -l ${region}"

# Finally, create the credentials
eval "az ad sp create-for-rbac \
  --name ${username} \
  --role contributor \
  --scopes /subscriptions/${subscription_id}/resourceGroups/${username} \
  --years 2"
