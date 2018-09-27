#!/bin/bash

# Recreate the load balancing environment for Azure development and testing

## Variables

tags="owner=cfme creator=$USER specs=true";
passwd="Smartvm12345"

network_group1="miq-networking-eastus"
network_group2="miq-networking-westus"

vm_group1="miq-vms-eastus"
vm_group2="miq-vms-westus"

vnet1="miq-vnet-lb-eastus"
vnet2="miq-vnet-lb-westus"

pubip1="miq-publicip-lb-eastus"
pubip2="miq-publicip-lb-westus"

lb1="miq-lb-eastus"
lb2="miq-lb-westus"
lb3="miq-lb-eastus2"

location1="eastus"
location2="westus"

frontend1="miq-frontend-pool1"
frontend2="miq-frontend-pool2"

backend1="miq-backend-pool1"
backend2="miq-backend-pool2"

probe1="miq-lb-health-probe1"
probe2="miq-lb-health-probe2"

lb_rule1="miq-lb-rule1"
lb_rule2="miq-lb-rule2"

subnet1="miq-subnet-eastus"
subnet2="miq-subnet-westus"

nsg1="miq-nsg-lb-eastus"
nsg2="miq-nsg-lb-westus"

nsg_rule1="miq-nsg-rule-eastus"
nsg_rule2="miq-nsg-rule-westus"

nic1="miq-nic1-lb-eastus"
nic2="miq-nic2-lb-eastus"
nic3="miq-nic3-lb-westus"
nic4="miq-nic4-lb-westus"

av_set1="miq-availability-set-lb-eastus"
av_set2="miq-availability-set-lb-westus"

vm1="miq-vm1-lb-eastus"
vm2="miq-vm2-lb-eastus"
vm3="miq-vm1-lb-westus"
vm4="miq-vm2-lb-westus"

## Resource Groups

eval "az group create -n ${network_group1} -l ${location1} --tags ${tags}";
eval "az group create -n ${network_group2} -l ${location2} --tags ${tags}";
eval "az group create -n ${vm_group1} -l ${location1} --tags ${tags}";
eval "az group create -n ${vm_group2} -l ${location2} --tags ${tags}";

## Public IPs

eval "az network public-ip create \
        --name ${pubip1} \
        --resource-group ${network_group1} \
        --location ${location1} \
        --tags ${tags}"

eval "az network public-ip create \
        --name ${pubip2} \
        --resource-group ${network_group2} \
        --location ${location2} \
        --tags ${tags}"

## Load Balancers

eval "az network lb create \
        --name ${lb1} \
        --resource-group ${network_group1} \
        --public-ip-address ${pubip1} \
        --frontend-ip-name ${frontend1} \
        --backend-pool-name ${backend1} \
        --tags ${tags}"

eval "az network lb create \
        --name ${lb2} \
        --resource-group ${network_group2} \
        --public-ip-address ${pubip2} \
        --frontend-ip-name ${frontend2} \
        --backend-pool-name ${backend2} \
        --tags ${tags}"

eval "az network lb create -n ${lb3} -g ${$network_group1}"

## Load Balancer Probes

eval "az network lb probe create \
        --name ${probe1} \
        --resource-group ${network_group1} \
        --lb-name ${lb1} \
        --protocol Http \
        --port 80 \
        --interval 15 \
        --path /"

eval "az network lb probe create \
        --name ${probe2} \
        --resource-group ${network_group2} \
        --lb-name ${lb2} \
        --protocol Http \
        --port 80 \
        --interval 15 \
        --path /"

## Load Balancer Rules

eval "az network lb rule create \
        --name ${lb_rule1} \
        --resource-group ${network_group1} \
        --lb-name ${lb1} \
        --protocol tcp \
        --frontend-port 80 \
        --backend-port 80 \
        --frontend-ip-name ${frontend1} \
        --backend-pool-name ${backend1} \
        --probe-name ${probe1}"

eval "az network lb rule create \
        --name ${lb_rule2} \
        --resource-group ${network_group2} \
        --lb-name ${lb2} \
        --protocol tcp \
        --frontend-port 80 \
        --backend-port 80 \
        --frontend-ip-name ${frontend2} \
        --backend-pool-name ${backend2} \
        --probe-name ${probe2}"

## Virtual Networks

eval "az network vnet create \
        --name ${vnet1} \
        --resource-group ${network_group1} \
        --location ${location1} \
        --subnet-name ${subnet1} \
        --tags ${tags}"

eval "az network vnet create \
        --name ${vnet2} \
        --resource-group ${network_group2} \
        --location ${location2} \
        --subnet-name ${subnet2} \
        --tags ${tags}"

## Network Security Groups

eval "az network nsg create \
        --name ${nsg1} \
        --resource-group ${network_group1} \
        --tags ${tags}"

eval "az network nsg create \
        --name ${nsg2} \
        --resource-group ${network_group2} \
        --tags ${tags}"

## Network Security Group Rules

eval "az network nsg rule create \
        --name ${nsg_rule1} \
        --resource-group ${network_group1} \
        --nsg-name ${nsg1} \
        --protocol tcp \
        --direction inbound \
        --source-address-prefix '*' \
        --source-port-range '*' \
        --destination-address-prefix '*' \
        --destination-port-range 80 \
        --access allow \
        --priority 200"

eval "az network nsg rule create \
        --name ${nsg_rule2} \
        --resource-group ${network_group2} \
        --nsg-name ${nsg2} \
        --protocol tcp \
        --direction inbound \
        --source-address-prefix '*' \
        --source-port-range '*' \
        --destination-address-prefix '*' \
        --destination-port-range 80 \
        --access allow \
        --priority 200"

## NICs

eval "az network nic create \
        --name ${nic1} \
        --resource-group ${network_group1} \
        --vnet-name ${vnet1} \
        --subnet ${subnet1} \
        --network-security-group ${nsg1} \
        --lb-name ${lb1} \
        --lb-address-pools ${backend1}"

eval "az network nic create \
        --name ${nic2} \
        --resource-group ${network_group1} \
        --vnet-name ${vnet1} \
        --subnet ${subnet1} \
        --network-security-group ${nsg1} \
        --lb-name ${lb1} \
        --lb-address-pools ${backend1}"

eval "az network nic create \
        --name ${nic3} \
        --resource-group ${network_group2} \
        --vnet-name ${vnet2} \
        --subnet ${subnet2} \
        --network-security-group ${nsg2} \
        --lb-name ${lb2} \
        --lb-address-pools ${backend2}"

eval "az network nic create \
        --name ${nic4} \
        --resource-group ${network_group2} \
        --vnet-name ${vnet2} \
        --subnet ${subnet2} \
        --network-security-group ${nsg2} \
        --lb-name ${lb2} \
        --lb-address-pools ${backend2}"

## Availability Set

eval "az vm availability-set create \
        --name ${av_set1} \
        --resource-group ${vm_group1} \
        --location ${location1}"

eval "az vm availability-set create \
        --name ${av_set2} \
        --resource-group ${vm_group2} \
        --location ${location2}"

## Virtual Machines

## Note: cannot use "basic" sizes for load balancing VMs.

nic_id1="$(az network nic show -n ${nic1} -g ${network_group1} --query id)"
nic_id2="$(az network nic show -n ${nic2} -g ${network_group1} --query id)"
nic_id3="$(az network nic show -n ${nic3} -g ${network_group2} --query id)"
nic_id4="$(az network nic show -n ${nic4} -g ${network_group2} --query id)"

eval "az vm create \
        --name ${vm1} \
        --resource-group ${vm_group1} \
        --availability-set ${av_set1} \
        --nics ${nic_id1} \
        --image UbuntuLTS \
        --location ${location1} \
        --admin-username ${USER} \
        --admin-password ${passwd} \
        --size Standard_A0 \
        --os-disk-name miq-vm-lb-disk1 \
        --tags ${tags}"

eval "az vm create \
        --name ${vm2} \
        --resource-group ${vm_group1} \
        --availability-set ${av_set1} \
        --nics ${nic_id2} \
        --image UbuntuLTS \
        --location ${location1} \
        --admin-username ${USER} \
        --admin-password ${passwd} \
        --size Standard_A0 \
        --os-disk-name miq-vm-lb-disk2 \
        --tags ${tags}"

eval "az vm create \
        --name ${vm3} \
        --resource-group ${vm_group2} \
        --availability-set ${av_set2} \
        --nics ${nic_id3} \
        --image UbuntuLTS \
        --location ${location2} \
        --admin-username ${USER} \
        --admin-password ${passwd} \
        --size Standard_A0 \
        --os-disk-name miq-vm-lb-disk3 \
        --tags ${tags}"

eval "az vm create \
        --name ${vm4} \
        --resource-group ${vm_group2} \
        --availability-set ${av_set2} \
        --nics ${nic_id4} \
        --image UbuntuLTS \
        --location ${location2} \
        --admin-username ${USER} \
        --admin-password ${passwd} \
        --size Standard_A0 \
        --os-disk-name miq-vm-lb-disk4 \
        --tags ${tags}"
