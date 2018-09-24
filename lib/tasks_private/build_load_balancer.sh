#!/bin/bash

tags="owner=cfme creator=$USER specs=true";
group="miq-networking-eastus"
vnet="miq-vnet-lb"
pubip="miq-publicip-lb"
lb="miq-lb"
location="eastus"
frontend="miq-frontend-pool"
backend="miq-backend-pool"
probe="miq-lb-health-probe"
lb_rule="miq-lb-rule"
subnet="miq-subnet-eastus"
nsg="miq-nsg-lb-eastus"
nsg_rule="miq-nsg-rule-eastus"
nic1="miq-nic1-lb"
nic2="miq-nic2-lb"
av_set="miq-availability-set-lb-eastus"
passwd="Smartvm12345"
vm1="miq-vm1-lb-eastus"
vm2="miq-vm2-lb-eastus"

eval "az group create -n ${group} -l eastus --tags ${tags}";

eval "az network public-ip create \
        --name ${pubip} \
        --resource-group ${group} \
        --location ${location} \
        --tags ${tags}"

eval "az network lb create \
        --name ${lb} \
        --resource-group ${group} \
        --public-ip-address ${pubip} \
        --frontend-ip-name ${frontend} \
        --backend-pool-name ${backend} \
        --tags ${tags}"

eval "az network lb probe create \
        --name ${probe} \
        --resource-group ${group} \
        --lb-name ${lb} \
        --protocol tcp \
        --port 80"

eval "az network lb rule create \
        --name ${lb_rule} \
        --resource-group ${group} \
        --lb-name ${lb} \
        --protocol tcp \
        --frontend-port 80 \
        --backend-port 80 \
        --frontend-ip-name ${frontend} \
        --backend-pool-name ${backend} \
        --probe-name ${probe}"

eval "az network vnet create \
        --name ${vnet} \
        --resource-group ${group} \
        --location ${location} \
        --subnet-name ${subnet} \
        --tags ${tags}"

eval "az network nsg create \
        --name ${nsg} \
        --resource-group ${group} \
        --tags ${tags}"

eval "az network nsg rule create \
        --name ${nsg_rule} \
        --resource-group ${group} \
        --nsg-name ${nsg} \
        --protocol tcp \
        --direction inbound \
        --source-address-prefix '*' \
        --source-port-range '*' \
        --destination-address-prefix '*' \
        --destination-port-range 80 \
        --access allow \
        --priority 200"

eval "az network nic create \
        --name ${nic1} \
        --resource-group ${group} \
        --vnet-name ${vnet} \
        --subnet ${subnet} \
        --network-security-group ${nsg} \
        --lb-name ${lb} \
        --lb-address-pools ${backend}"

eval "az network nic create \
        --name ${nic2} \
        --resource-group ${group} \
        --vnet-name ${vnet} \
        --subnet ${subnet} \
        --network-security-group ${nsg} \
        --lb-name ${lb} \
        --lb-address-pools ${backend}"

eval "az vm availability-set create \
        --name ${av_set} \
        --resource-group ${group}"

## Note: cannot use "basic" sizes for load balancers.

eval "az vm create \
        --name ${vm1} \
        --resource-group ${group} \
        --availability-set ${av_set} \
        --nics ${nic1} \
        --image UbuntuLTS \
        --location ${location} \
        --admin-username ${USER} \
        --admin-password ${passwd} \
        --size Standard_A0 \
        --os-disk-name miq-vm-lb-disk1 \
        --tags ${tags}"

eval "az vm create \
        --name ${vm2} \
        --resource-group ${group} \
        --availability-set ${av_set} \
        --nics ${nic2} \
        --image UbuntuLTS \
        --location ${location} \
        --admin-username ${USER} \
        --admin-password ${passwd} \
        --size Standard_A0 \
        --os-disk-name miq-vm-lb-disk2 \
        --tags ${tags}"
