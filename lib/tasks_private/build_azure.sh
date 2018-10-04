#!/bin/bash

## This script assumes that you've registered the various services you need beforehand,
## and that you've run 'az login' to establish your credentials already.

tags="owner=cfme creator=$USER specs=true";
passwd="Smartvm12345"
location1="eastus"
location2="westus"
script_dir=$(dirname $BASH_SOURCE)

## Start with the resource groups

misc_group1="miq-misc-eastus"
misc_group2="miq-misc-westus"
network_group1="miq-networking-eastus"
network_group2="miq-networking-westus"
storage_group1="miq-storage-eastus"
storage_group2="miq-storage-westus"
vm_group1="miq-vms-eastus"
vm_group2="miq-vms-westus"

## Delete everything first, in this order
eval "az group delete -n ${vm_group1} -y"
eval "az group delete -n ${vm_group2} -y"
eval "az group delete -n ${storage_group1} -y"
eval "az group delete -n ${storage_group2} -y"
eval "az group delete -n ${network_group1} -y"
eval "az group delete -n ${network_group2} -y"
eval "az group delete -n ${misc_group1} -y"
eval "az group delete -n ${misc_group2} -y"

## Recreate the resource groups

eval "az group create -n ${misc_group1} -l ${location1} --tags ${tags}";
eval "az group create -n ${misc_group2} -l ${location2} --tags ${tags}";
eval "az group create -n ${network_group1} -l ${location1} --tags ${tags}";
eval "az group create -n ${network_group2} -l ${location2} --tags ${tags}";
eval "az group create -n ${storage_group1} -l ${location1} --tags ${tags}";
eval "az group create -n ${storage_group2} -l ${location2} --tags ${tags}";
eval "az group create -n ${vm_group1} -l ${location1} --tags ${tags}";
eval "az group create -n ${vm_group2} -l ${location2} --tags ${tags}";

## Build unmanaged storage accounts

storage1="miqunmanagedeastus"
storage2="miqunmanagedwestus"
diagnostics1="miqdiagnosticseastus"
diagnostics2="miqdiagnosticswestus"

eval "az storage account create -n ${storage1} -g ${storage_group1} -l ${location1} --tags ${tags}"
eval "az storage account create -n ${storage2} -g ${storage_group2} -l ${location2} --tags ${tags}"
eval "az storage account create -n ${diagnostics1} -g ${storage_group1} -l ${location1} --tags ${tags}"
eval "az storage account create -n ${diagnostics2} -g ${storage_group2} -l ${location2} --tags ${tags}"

## Build virtual networks, one per region. All NIC/IP should be attached to one of these networks.

vnet1="miq-vnet-eastus"
vnet2="miq-vnet-westus"
subnet="default"

eval "az network vnet create \
        --name ${vnet1} \
        --resource-group ${network_group1} \
        --location ${location1} \
        --address-prefixes 10.0.0.0/16 \
        --subnet-name ${subnet} \
        --tags ${tags}"

eval "az network vnet create \
        --name ${vnet2} \
        --resource-group ${network_group2} \
        --location ${location2} \
        --address-prefixes 10.0.0.0/16 \
        --subnet-name ${subnet} \
        --tags ${tags}"

## Build Public IP addresses. All Public IPs should be in one of the two networking resource groups.
publicip_east1="miq-publicip-eastus1"
publicip_east2="miq-publicip-eastus2"
publicip_east3="miq-publicip-eastus3"
publicip_east4="miq-publicip-eastus4"
publicip_east5="miq-publicip-eastus5"
publicip_east6="miq-publicip-eastus6"
publicip_east7="miq-publicip-eastus7"

eval "az network public-ip create -n ${publicip_east1} -g ${network_group1} -l ${location1} --tags ${tags}"
eval "az network public-ip create -n ${publicip_east2} -g ${network_group1} -l ${location1} --tags ${tags}"
eval "az network public-ip create -n ${publicip_east3} -g ${network_group1} -l ${location1} --tags ${tags}"
eval "az network public-ip create -n ${publicip_east4} -g ${network_group1} -l ${location1} --tags ${tags}"
eval "az network public-ip create -n ${publicip_east5} -g ${network_group1} -l ${location1} --tags ${tags}"
eval "az network public-ip create -n ${publicip_east6} -g ${network_group1} -l ${location1} --tags ${tags}"
eval "az network public-ip create -n ${publicip_east7} -g ${network_group1} -l ${location1} --tags ${tags}"

publicip_west1="miq-publicip-westus1"
publicip_west2="miq-publicip-westus2"
publicip_west3="miq-publicip-westus3"
publicip_west4="miq-publicip-westus4"
publicip_west5="miq-publicip-westus5"
publicip_west6="miq-publicip-westus6"
publicip_west7="miq-publicip-westus7"

eval "az network public-ip create -n ${publicip_west1} -g ${network_group2} -l ${location2} --tags ${tags}"
eval "az network public-ip create -n ${publicip_west2} -g ${network_group2} -l ${location2} --tags ${tags}"
eval "az network public-ip create -n ${publicip_west3} -g ${network_group2} -l ${location2} --tags ${tags}"
eval "az network public-ip create -n ${publicip_west4} -g ${network_group2} -l ${location2} --tags ${tags}"
eval "az network public-ip create -n ${publicip_west5} -g ${network_group2} -l ${location2} --tags ${tags}"
eval "az network public-ip create -n ${publicip_west6} -g ${network_group2} -l ${location2} --tags ${tags}"
eval "az network public-ip create -n ${publicip_west7} -g ${network_group2} -l ${location2} --tags ${tags}"

# Build network security groups

nsg_east1="miq-nsg-eastus1"
nsg_east2="miq-nsg-eastus2"
nsg_east3="miq-nsg-eastus3"

eval "az network nsg create -n ${nsg_east1} -g ${network_group1} -l ${location1} --tags ${tags}"
eval "az network nsg create -n ${nsg_east2} -g ${network_group1} -l ${location1} --tags ${tags}"
eval "az network nsg create -n ${nsg_east3} -g ${network_group1} -l ${location1} --tags ${tags}"

nsg_west1="miq-nsg-westus1"
nsg_west2="miq-nsg-westus2"
nsg_west3="miq-nsg-westus3"

eval "az network nsg create -n ${nsg_west1} -g ${network_group2} -l ${location2} --tags ${tags}"
eval "az network nsg create -n ${nsg_west2} -g ${network_group2} -l ${location2} --tags ${tags}"
eval "az network nsg create -n ${nsg_west3} -g ${network_group2} -l ${location2} --tags ${tags}"

## Add some rules to some of the security groups

nsg_rule1="inbound1"
nsg_rule2="inbound2"
nsg_rule3="inbound3"
nsg_rule4="inbound4"
nsg_rule5="inbound5"
nsg_rule6="inbound6"

eval "az network nsg rule create -n ${nsg_rule1} --nsg-name ${nsg_east1} \
        -g ${network_group1} --direction Inbound \
        --destination-port-range 22 --priority 1000 --protocol Tcp"

eval "az network nsg rule create -n ${nsg_rule2} --nsg-name ${nsg_east1} \
        -g ${network_group1} --direction Inbound --priority 100 \
        --destination-port-range 80 --protocol Tcp --source-port-range 80"

eval "az network nsg rule create -n ${nsg_rule3} --nsg-name ${nsg_east1} \
        -g ${network_group1} --direction Inbound --priority 120 \
        --destination-port-range 443 --protocol Tcp --source-port-range 443"

eval "az network nsg rule create -n ${nsg_rule4} --nsg-name ${nsg_west1} \
        -g ${network_group2} --direction Inbound \
        --destination-port-range 22 --priority 1000 --protocol Tcp"

eval "az network nsg rule create -n ${nsg_rule5} --nsg-name ${nsg_west1} \
        -g ${network_group2} --direction Inbound --priority 100 \
        --destination-port-range 80 --protocol Tcp --source-port-range 80"

eval "az network nsg rule create -n ${nsg_rule6} --nsg-name ${nsg_west1} \
        -g ${network_group2} --direction Inbound --priority 120 \
        --destination-port-range 443 --protocol Tcp --source-port-range 443"

## Build NICs. All NICs should be in one of the two networking resource groups.

nic_east1="miq-nic-eastus1"
nic_east2="miq-nic-eastus2"
nic_east3="miq-nic-eastus3"
nic_east4="miq-nic-eastus4"
nic_east5="miq-nic-eastus5"
nic_east6="miq-nic-eastus6"
nic_east7="miq-nic-eastus7"

eval "az network nic create -n ${nic_east1} -g ${network_group1} -l ${location1} \
       --public-ip-address ${publicip_east1} --vnet-name ${vnet1} \
       --subnet ${subnet} --network-security-group ${nsg_east1} --tags ${tags}"

eval "az network nic create -n ${nic_east2} -g ${network_group1} -l ${location1} \
       --public-ip-address ${publicip_east2} --vnet-name ${vnet1} \
       --subnet ${subnet} --tags ${tags}"

eval "az network nic create -n ${nic_east3} -g ${network_group1} -l ${location1} \
       --public-ip-address ${publicip_east3} --vnet-name ${vnet1} \
       --subnet ${subnet} --network-security-group ${nsg_east3} --tags ${tags}"

eval "az network nic create -n ${nic_east4} -g ${network_group1} -l ${location1} \
       --public-ip-address ${publicip_east4} --vnet-name ${vnet1} \
       --subnet ${subnet} --tags ${tags}"

eval "az network nic create -n ${nic_east5} -g ${network_group1} -l ${location1} \
       --public-ip-address ${publicip_east5} --vnet-name ${vnet1} \
       --subnet ${subnet} --tags ${tags}"

eval "az network nic create -n ${nic_east6} -g ${network_group1} -l ${location1} \
       --public-ip-address ${publicip_east6} --vnet-name ${vnet1} \
       --subnet ${subnet} --tags ${tags}"

eval "az network nic create -n ${nic_east7} -g ${network_group1} -l ${location1} \
       --public-ip-address ${publicip_east7} --vnet-name ${vnet1} \
       --subnet ${subnet} --tags ${tags}"

nic_west1="miq-nic-westus1"
nic_west2="miq-nic-westus2"
nic_west3="miq-nic-westus3"
nic_west4="miq-nic-westus4"
nic_west5="miq-nic-westus5"
nic_west6="miq-nic-westus6"
nic_west7="miq-nic-westus7"

eval "az network nic create -n ${nic_west1} -g ${network_group2} -l ${location2} \
       --public-ip-address ${publicip_west1} --vnet-name ${vnet2} \
       --subnet ${subnet} --network-security-group ${nsg_west1} --tags ${tags}"

eval "az network nic create -n ${nic_west2} -g ${network_group2} -l ${location2} \
       --public-ip-address ${publicip_west2} --vnet-name ${vnet2} \
       --subnet ${subnet} --tags ${tags}"

eval "az network nic create -n ${nic_west3} -g ${network_group2} -l ${location2} \
       --public-ip-address ${publicip_west3} --vnet-name ${vnet2} \
       --subnet ${subnet} --network-security-group ${nsg_west3} --tags ${tags}"

eval "az network nic create -n ${nic_west4} -g ${network_group2} -l ${location2} \
       --public-ip-address ${publicip_west4} --vnet-name ${vnet2} \
       --subnet ${subnet} --tags ${tags}"

eval "az network nic create -n ${nic_west5} -g ${network_group2} -l ${location2} \
       --public-ip-address ${publicip_west5} --vnet-name ${vnet2} \
       --subnet ${subnet} --tags ${tags}"

eval "az network nic create -n ${nic_west6} -g ${network_group2} -l ${location2} \
       --public-ip-address ${publicip_west6} --vnet-name ${vnet2} \
       --subnet ${subnet} --tags ${tags}"

eval "az network nic create -n ${nic_west7} -g ${network_group2} -l ${location2} \
       --public-ip-address ${publicip_west7} --vnet-name ${vnet2} \
       --subnet ${subnet} --tags ${tags}"

## Build two route tables and one route for each

route1="miq-route-eastus1"
route2="miq-route-westus1"
route_table1="miq-route-table-eastus1"
route_table2="miq-route-table-westus1"

eval "az network route-table create -n ${route_table1} -g ${network_group1} --tags ${tags}"
eval "az network route-table create -n ${route_table2} -g ${network_group2} --tags ${tags}"

eval "az network route-table route create -n ${route1} -g ${network_group1} \
        --route-table-name ${route_table1} --next-hop-type VnetLocal --address-prefix 10.0.0.0/16"

eval "az network route-table route create -n ${route2} -g ${network_group2} \
        --route-table-name ${route_table2} --next-hop-type VnetLocal --address-prefix 10.0.0.0/16"

## Build managed disks

disk_east1="miq-managed-disk-eastus1"
disk_west1="miq-managed-disk-westus1"

data_disk_east1="miq-data-disk-eastus1"
data_disk_east2="miq-data-disk-eastus2"
data_disk_west1="miq-data-disk-westus1"
data_disk_west2="miq-data-disk-westus2"

eval "az disk create -n ${disk_east1} -g ${storage_group1} -l ${location1} \
       --size-gb 16 --sku Standard_LRS --tags ${tags}"

eval "az disk create -n ${disk_west1} -g ${storage_group2} -l ${location2} \
       --size-gb 16 --sku Standard_LRS --tags ${tags}"

eval "az disk create -n ${data_disk_east1} -g ${storage_group1} -l ${location1} --sku Standard_LRS -z 1 --tags ${tags}"
eval "az disk create -n ${data_disk_east2} -g ${storage_group1} -l ${location1} --sku Standard_LRS -z 1 --tags ${tags}"
eval "az disk create -n ${data_disk_west1} -g ${storage_group2} -l ${location2} --sku Standard_LRS -z 1 --tags ${tags}"
eval "az disk create -n ${data_disk_west2} -g ${storage_group2} -l ${location2} --sku Standard_LRS -z 1 --tags ${tags}"

## We have to do this first since it is in a different resource group

nic_east_id1="$(az network nic show -n ${nic_east1} -g ${network_group1} --query id)"
nic_east_id2="$(az network nic show -n ${nic_east2} -g ${network_group1} --query id)"
nic_east_id3="$(az network nic show -n ${nic_east3} -g ${network_group1} --query id)"
nic_east_id4="$(az network nic show -n ${nic_east4} -g ${network_group1} --query id)"
nic_east_id5="$(az network nic show -n ${nic_east5} -g ${network_group1} --query id)"
nic_east_id6="$(az network nic show -n ${nic_east6} -g ${network_group1} --query id)"
nic_east_id7="$(az network nic show -n ${nic_east7} -g ${network_group1} --query id)"

nic_west_id1="$(az network nic show -n ${nic_west1} -g ${network_group2} --query id)"
nic_west_id2="$(az network nic show -n ${nic_west2} -g ${network_group2} --query id)"
nic_west_id3="$(az network nic show -n ${nic_west3} -g ${network_group2} --query id)"
nic_west_id4="$(az network nic show -n ${nic_west4} -g ${network_group2} --query id)"
nic_west_id5="$(az network nic show -n ${nic_west5} -g ${network_group2} --query id)"
nic_west_id6="$(az network nic show -n ${nic_west6} -g ${network_group2} --query id)"
nic_west_id7="$(az network nic show -n ${nic_west7} -g ${network_group2} --query id)"

storage_east_id="$(az storage account show -n ${storage1} -g ${storage_group1} --query id)"
storage_west_id="$(az storage account show -n ${storage2} -g ${storage_group2} --query id)"

## Unmanaged VMs

vm_east1="miq-vm-ubuntu1-eastus"
vm_east2="miq-vm-centos1-eastus"
vm_west1="miq-vm-ubuntu2-westus"
vm_west2="miq-vm-centos2-westus"

eval "az vm create -n ${vm_east1} -g ${vm_group1} -l ${location1} \
       --admin-username ${USER} --admin-password ${passwd} \
       --image UbuntuLTS --size Standard_B1s --tags ${tags} \
       --use-unmanaged-disk --nics ${nic_east_id1} --storage-account ${storage_east_id} \
       --os-disk-name miq-vm-ubuntu-disk1 --boot-diagnostics-storage ${diagnostics1}"

eval "az vm create -n ${vm_west1} -g ${vm_group2} -l ${location2} \
       --admin-username ${USER} --admin-password ${passwd} \
       --image UbuntuLTS --size Basic_A0 --tags ${tags} \
       --use-unmanaged-disk --nics ${nic_west_id1} --storage-account ${storage_west_id} \
       --os-disk-name miq-vm-ubuntu-disk2 --boot-diagnostics-storage ${diagnostics2}"

eval "az vm create -n ${vm_east2} -g ${vm_group1} -l ${location1} \
       --admin-username ${USER} --admin-password Smartvm12345 \
       --image CentOS --size Standard_B1s --tags ${tags} \
       --use-unmanaged-disk --nics ${nic_east_id2} --storage-account ${storage_east_id} \
       --os-disk-name miq-vm-centos-disk1 --boot-diagnostics-storage ${diagnostics1}"

eval "az vm create -n ${vm_west2} -g ${vm_group2} -l ${location2} \
       --admin-username ${USER} --admin-password Smartvm12345 \
       --image CentOS --size Basic_A0 --tags ${tags} \
       --use-unmanaged-disk --nics ${nic_west_id2} --storage-account ${storage_west_id} \
       --os-disk-name miq-vm-centos-disk2 --boot-diagnostics-storage ${diagnostics2}"

## Managed

data_disk_east_id1="$(az disk show -n ${data_disk_east1} -g ${storage_group1} --query id)"
data_disk_east_id2="$(az disk show -n ${data_disk_east2} -g ${storage_group1} --query id)"
data_disk_west_id1="$(az disk show -n ${data_disk_west1} -g ${storage_group2} --query id)"
data_disk_west_id2="$(az disk show -n ${data_disk_west2} -g ${storage_group2} --query id)"

# We have to break our naming conventions for Windows a bit because of naming restrictions

vm_sles1="miq-vm-sles1-eastus"
vm_sles2="miq-vm-sles2-westus"
vm_windows1="miq-vm-win-east"
vm_windows2="miq-vm-win-west"

eval "az vm create -n ${vm_sles1} -g ${vm_group1} -l ${location1} \
       --admin-username ${USER} --admin-password ${passwd} \
       --image SLES --size Standard_A0 --tags ${tags} --nics ${nic_east_id4} \
       --os-disk-name miq-vm-sles1-disk --boot-diagnostics-storage ${diagnostics1} \
       --attach-data-disks ${data_disk_east_id1}"

eval "az vm create -n ${vm_sles2} -g ${vm_group2} -l ${location2} \
       --admin-username ${USER} --admin-password ${passwd} \
       --image SLES --size Standard_A0 --tags ${tags} --nics ${nic_west_id4} \
       --os-disk-name miq-vm-sles2-disk --boot-diagnostics-storage ${diagnostics2} \
       --attach-data-disks ${data_disk_west_id1}"

eval "az vm create -n ${vm_windows1} -g ${vm_group1} -l ${location1} \
       --admin-username ${USER} --admin-password ${passwd} \
       --image MicrosoftWindowsServer:WindowsServer:2012-R2-Datacenter:latest \
       --size Basic_A0 --tags ${tags} --nics ${nic_east_id5} \
       --boot-diagnostics-storage ${diagnostics1} \
       --os-disk-name miq-os-win2k12-1-disk"

eval "az vm create -n ${vm_windows2} -g ${vm_group2} -l ${location2} \
       --admin-username ${USER} --admin-password ${passwd} \
       --image MicrosoftWindowsServer:WindowsServer:2012-R2-Datacenter:latest \
       --size Basic_A0 --tags ${tags} --nics ${nic_west_id5} \
       --boot-diagnostics-storage ${diagnostics2} \
       --os-disk-name miq-os-win2k12-2-disk"

## These VMs are deliberately set in a resource group with a different location

vm_rhel1="miq-vm-rhel1-mismatch"
vm_rhel2="miq-vm-rhel2-mismatch"

eval "az vm create -n ${vm_rhel1} -g ${vm_group1} -l ${location2} \
       --admin-username ${USER} --admin-password ${passwd} \
       --image RHEL --size Basic_A0 --tags ${tags} --nics ${nic_west_id3} \
       --boot-diagnostics-storage ${diagnostics2} \
       --os-disk-name miq-os-disk-rhel1 --attach-data-disks ${data_disk_west_id2}"

eval "az vm create -n ${vm_rhel2} -g ${vm_group2} -l ${location1} \
       --admin-username ${USER} --admin-password ${passwd} \
       --image RHEL --size Basic_A0 --tags ${tags} --nics ${nic_east_id3} \
       --boot-diagnostics-storage miqdiagnosticseastus \
       --os-disk-name miq-os-disk-rhel2 --attach-data-disks ${data_disk_east_id2}"

## VMs used for capture

vm_general1="miq-linux-gen-east"
vm_image1="miq-linux-img-east"

eval "az vm create -n ${vm_general1} -g ${vm_group1} -l ${location1} \
       --nics ${nic_east_id6} --os-disk-name miq-linuximg-disk \
       --authentication-type ssh --ssh-key-value ~/.ssh/id_rsa.pub \
       --image UbuntuLTS --size Basic_A0 --tags ${tags}"

## Generalize the VM and create an image.

linux_ip="$(az vm list-ip-addresses -n ${vm_general1} -g ${vm_group1} --query [0].virtualMachine.network.publicIpAddresses[0].ipAddress -o tsv)"

ssh -o "StrictHostKeyChecking=no" ${linux_ip} << EOF
  sudo waagent -deprovision+user -force;
  exit
EOF

eval "az vm deallocate -n ${vm_general1} -g ${vm_group1}"
eval "az vm generalize -n ${vm_general1} -g ${vm_group1}"
eval "az image create -n ${vm_image1} -g ${vm_group1} --source ${vm_general1}"

## Create a VM from our custom image

eval "az vm create -n miq-vm-from-image-eastus1 -g ${vm_group1} -l ${location1} \
      --admin-username ${USER} --admin-password ${passwd} --tags ${tags} \
      --image ${vm_image1} --nics ${nic_east_id7} --os-disk-name miq-os-disk-image1"

## Upload a couple orchestration templates (deployments).

deployment1="miq-template-eastus"
deployment2="miq-template-westus"
template_file_east="${script_dir}/../../spec/fixtures/orchestration_templates/deployment_east.json"
parameter_file_east="${script_dir}/../../spec/fixtures/orchestration_templates/parameters_east.json"
template_file_west="${script_dir}/../../spec/fixtures/orchestration_templates/deployment_west.json"
parameter_file_west="${script_dir}/../../spec/fixtures/orchestration_templates/parameters_west.json"

eval "az group deployment create \
        --name ${deployment1} \
        --resource-group ${misc_group1} \
        --template-file ${template_file_east} \
        --parameters ${parameter_file_east}"

eval "az group deployment create \
        --name ${deployment2} \
        --resource-group ${misc_group2} \
        --template-file ${template_file_west} \
        --parameters ${parameter_file_west}"
        
## Deallocate all the VMs to avoid incurring charges

eval "az vm deallocate --ids $(az vm list -g ${vm_group1} --query '[].id' -o tsv)"
eval "az vm deallocate --ids $(az vm list -g ${vm_group2} --query '[].id' -o tsv)"
