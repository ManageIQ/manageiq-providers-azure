#!/bin/bash

# Assumes that you've registered the various services you need beforehand,
# and that you've run 'az login' to establish your credentials already.

tags="owner=cfme creator=$USER specs=true";

# Delete everything first
#eval "az group delete -n miq-testrg-vms-eastus -y"
#eval "az group delete -n miq-testrg-vms-westus -y"
#eval "az group delete -n miq-testrg-storage-eastus -y"
#eval "az group delete -n miq-testrg-storage-westus -y"
#eval "az group delete -n miq-testrg-networking-eastus -y"
#eval "az group delete -n miq-testrg-networking-westus -y"
#eval "az group delete -n miq-testrg-misc-eastus -y"
#eval "az group delete -n miq-testrg-misc-westus -y"

# Start with the resource groups

eval "az group create -n miq-testrg-misc-eastus -l eastus --tags ${tags}";
eval "az group create -n miq-testrg-misc-westus -l westus --tags ${tags}";
eval "az group create -n miq-testrg-networking-eastus -l eastus --tags ${tags}";
eval "az group create -n miq-testrg-networking-westus -l westus --tags ${tags}";
eval "az group create -n miq-testrg-storage-eastus -l eastus --tags ${tags}";
eval "az group create -n miq-testrg-storage-westus -l westus --tags ${tags}";
eval "az group create -n miq-testrg-vms-eastus -l eastus --tags ${tags}";
eval "az group create -n miq-testrg-vms-westus -l westus --tags ${tags}";

# Build unmanaged storage accounts

eval "az storage account create -n miqunmanagedeastus -g miq-testrg-storage-eastus -l eastus --tags ${tags}"
eval "az storage account create -n miqunmanagedwestus -g miq-testrg-storage-westus -l westus --tags ${tags}"
eval "az storage account create -n miqdiagnosticseastus -g miq-testrg-storage-eastus -l eastus --tags ${tags}"
eval "az storage account create -n miqdiagnosticswestus -g miq-testrg-storage-westus -l westus --tags ${tags}"

# Build two virtual networks, one per region. All NIC's (and thus IP's)
# should be attached to one of these two networks.

eval "az network vnet create -n miq-virtual-network-eastus -g miq-testrg-networking-eastus \
        -l eastus --address-prefixes 192.168.0.0/24 --subnet-name default --tags ${tags}"

eval "az network vnet create -n miq-virtual-network-westus -g miq-testrg-networking-westus \
        -l westus --address-prefixes 192.168.0.0/24 --subnet-name default --tags ${tags}"

# Build Public IP addresses. All Public IP's should be in one of the two networking resource groups.

eval "az network public-ip create -n miq-publicip-eastus1 -g miq-testrg-networking-eastus -l eastus --tags ${tags}"
eval "az network public-ip create -n miq-publicip-eastus2 -g miq-testrg-networking-eastus -l eastus --tags ${tags}"
eval "az network public-ip create -n miq-publicip-eastus3 -g miq-testrg-networking-eastus -l eastus --tags ${tags}"

eval "az network public-ip create -n miq-publicip-westus1 -g miq-testrg-networking-westus -l westus --tags ${tags}"
eval "az network public-ip create -n miq-publicip-westus2 -g miq-testrg-networking-westus -l westus --tags ${tags}"
eval "az network public-ip create -n miq-publicip-westus3 -g miq-testrg-networking-westus -l westus --tags ${tags}"

# Build network security groups
eval "az network nsg create -n miq-nsg-eastus1 -g miq-testrg-networking-eastus -l eastus --tags ${tags}"
eval "az network nsg create -n miq-nsg-eastus2 -g miq-testrg-networking-eastus -l eastus --tags ${tags}"
eval "az network nsg create -n miq-nsg-eastus3 -g miq-testrg-networking-eastus -l eastus --tags ${tags}"
eval "az network nsg create -n miq-nsg-westus1 -g miq-testrg-networking-westus -l westus --tags ${tags}"
eval "az network nsg create -n miq-nsg-westus2 -g miq-testrg-networking-westus -l westus --tags ${tags}"
eval "az network nsg create -n miq-nsg-westus3 -g miq-testrg-networking-westus -l westus --tags ${tags}"

# Build NIC's. All NIC's should be in one of the two networking resource groups.

eval "az network nic create -n miq-nic-eastus1 -g miq-testrg-networking-eastus -l eastus \
       --public-ip-address miq-publicip-eastus1 --vnet-name miq-virtual-network-eastus \
       --subnet default --network-security-group miq-nsg-eastus1 --tags ${tags}"

eval "az network nic create -n miq-nic-eastus2 -g miq-testrg-networking-eastus -l eastus \
       --public-ip-address miq-publicip-eastus2 --vnet-name miq-virtual-network-eastus \
       --subnet default --tags ${tags}"

eval "az network nic create -n miq-nic-eastus3 -g miq-testrg-networking-eastus -l eastus \
       --public-ip-address miq-publicip-eastus3 --vnet-name miq-virtual-network-eastus \
       --subnet default --network-security-group miq-nsg-eastus3 --tags ${tags}"

eval "az network nic create -n miq-nic-westus1 -g miq-testrg-networking-westus -l westus \
       --public-ip-address miq-publicip-westus1 --vnet-name miq-virtual-network-westus \
       --subnet default --network-security-group miq-nsg-westus1 --tags ${tags}"

eval "az network nic create -n miq-nic-westus2 -g miq-testrg-networking-westus -l westus \
       --public-ip-address miq-publicip-westus2 --vnet-name miq-virtual-network-westus \
       --subnet default --tags ${tags}"

eval "az network nic create -n miq-nic-westus3 -g miq-testrg-networking-westus -l westus \
       --public-ip-address miq-publicip-westus3 --vnet-name miq-virtual-network-westus \
       --subnet default --network-security-group miq-nsg-westus3 --tags ${tags}"

# Build two availability sets

eval "az vm availability-set create -n miq-availability-set-eastus -g miq-testrg-vms-eastus -l eastus --tags ${tags}"
eval "az vm availability-set create -n miq-availability-set-westus -g miq-testrg-vms-westus -l westus --tags ${tags}"

# Build managed disks

eval "az disk create -n miq-managed-disk-eastus -g miq-testrg-storage-eastus -l eastus \
       --size-gb 16 --sku Standard_LRS --tags ${tags}"

eval "az disk create -n miq-managed-disk-westus -g miq-testrg-storage-westus -l westus \
       --size-gb 16 --sku Standard_LRS --tags ${tags}"

eval "az disk create -n data-disk1-eastus -g miq-testrg-storage-eastus -l eastus --sku Standard_LRS -z 1 --tags ${tags}"
eval "az disk create -n data-disk1-westus -g miq-testrg-storage-westus -l westus --sku Standard_LRS -z 1 --tags ${tags}"

# Have to do this since it's in a different resource group
nic_eastus1="$(az network nic show -n miq-nic-eastus1 -g miq-testrg-networking-eastus --query id)"
nic_eastus2="$(az network nic show -n miq-nic-eastus2 -g miq-testrg-networking-eastus --query id)"
nic_eastus3="$(az network nic show -n miq-nic-eastus3 -g miq-testrg-networking-eastus --query id)"
nic_westus1="$(az network nic show -n miq-nic-westus1 -g miq-testrg-networking-westus --query id)"
nic_westus2="$(az network nic show -n miq-nic-westus2 -g miq-testrg-networking-westus --query id)"
nic_westus3="$(az network nic show -n miq-nic-westus3 -g miq-testrg-networking-westus --query id)"

storage_eastus="$(az storage account show -n miqunmanagedeastus -g miq-testrg-storage-eastus --query id)"
storage_westus="$(az storage account show -n miqunmanagedwestus -g miq-testrg-storage-westus --query id)"

eval "az vm create -n miq-vm-ubuntu1-eastus -g miq-testrg-vms-eastus -l eastus \
       --admin-username ${USER} --admin-password Smartvm12345 \
       --image UbuntuLTS --size Standard_B1s --tags ${tags} \
       --use-unmanaged-disk --nics ${nic_eastus1} --storage-account ${storage_eastus} \
       --os-disk-name miq-vm-ubuntu1-disk --boot-diagnostics-storage miqdiagnosticseastus"

eval "az vm create -n miq-vm-ubuntu2-westus -g miq-testrg-vms-westus -l westus \
       --admin-username ${USER} --admin-password Smartvm12345 \
       --image UbuntuLTS --size Basic_A0 --tags ${tags} \
       --use-unmanaged-disk --nics ${nic_westus1} --storage-account ${storage_westus} \
       --os-disk-name miq-vm-ubuntu2-disk --boot-diagnostics-storage miqdiagnosticswestus"

eval "az vm create -n miq-vm-centos1-eastus -g miq-testrg-vms-eastus -l eastus \
       --admin-username ${USER} --admin-password Smartvm12345 \
       --image CentOS --size Standard_B1s --tags ${tags} \
       --use-unmanaged-disk --nics ${nic_eastus2} --storage-account ${storage_eastus} \
       --os-disk-name miq-vm-centos1-disk --boot-diagnostics-storage miqdiagnosticseastus"

eval "az vm create -n miq-vm-centos2-westus -g miq-testrg-vms-westus -l westus \
       --admin-username ${USER} --admin-password Smartvm12345 \
       --image CentOS --size Basic_A0 --tags ${tags} \
       --use-unmanaged-disk --nics ${nic_westus2} --storage-account ${storage_westus} \
       --os-disk-name miq-vm-centos2-disk --boot-diagnostics-storage miqdiagnosticswestus"

data_disk1_eastus="$(az disk show -n data-disk1-eastus -g miq-testrg-storage-eastus --query id)"
data_disk1_westus="$(az disk show -n data-disk1-westus -g miq-testrg-storage-westus --query id)"

# These VM's are deliberately set in a resource group with a different location
eval "az vm create -n miq-vm-rhel1-mismatch -g miq-testrg-vms-eastus -l westus \
       --admin-username ${USER} --admin-password Smartvm12345 \
       --image RHEL --size Basic_A0 --tags ${tags} --nics ${nic_westus3} \
       --boot-diagnostics-storage miqdiagnosticswestus \
       --os-disk-name miq-os-disk-rhel1 --attach-data-disks ${data_disk1_westus}"

eval "az vm create -n miq-vm-rhel2-mismatch -g miq-testrg-vms-westus -l eastus \
       --admin-username ${USER} --admin-password Smartvm12345 \
       --image RHEL --size Basic_A0 --tags ${tags} --nics ${nic_eastus3} \
       --boot-diagnostics-storage miqdiagnosticseastus \
       --os-disk-name miq-os-disk-rhel2 --attach-data-disks ${data_disk1_eastus}"
