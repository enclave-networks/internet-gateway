#!/bin/bash

set -euo pipefail

source ".env"

EXISTING_BRIDGE=$(docker network ls | grep $DOCKER_BRIDGE_NAME || echo "")

if [ -z "$EXISTING_BRIDGE" ] ; then

    docker network create \
        --driver bridge \
        --attachable \
        --opt "com.docker.network.bridge.name"="$DOCKER_BRIDGE_NAME" \
        --opt "com.docker.network.bridge.enable_ip_masquerade"="false" \
        $DOCKER_BRIDGE_NAME

else

  echo "docker bridge network $DOCKER_BRIDGE_NAME for this stack already exists, nothing to do."

fi

BRIDGE_NETWORK=$(docker inspect $DOCKER_BRIDGE_NAME | jq -r ".[0].IPAM.Config[0].Subnet")

HOST_IP=$(hostname -I | awk '{print $1}')

EXISTING_IPTABLES_ENTRY=$(iptables -t nat -S POSTROUTING | grep -F -- "-A POSTROUTING -s $BRIDGE_NETWORK ! -o $DOCKER_BRIDGE_NAME" || echo "")

if [ ! "$EXISTING_IPTABLES_ENTRY" ] ; then

    echo "Adding iptables rule to allow the bridge network to snat to the Internet"

    # add an iptables rule to allow the bridge network to snat to the Internet
    iptables -t nat -A POSTROUTING -s $BRIDGE_NETWORK ! -o $DOCKER_BRIDGE_NAME -j SNAT --to-source $HOST_IP

else

  echo "iptables snat rule $BRIDGE_NETWORK for this stack already exists, nothing to do."

fi

# persist the iptables rules so the snat rule survives a host reboot. This runs
# even when the rule already existed so hosts deployed before iptables-persistent
# was installed pick up persistence on the next run of this script.
if command -v netfilter-persistent >/dev/null 2>&1; then

    echo "Saving iptables rules to /etc/iptables so the snat rule persists across reboot"

    netfilter-persistent save

else

  echo "Warning: netfilter-persistent not found, the snat rule will NOT survive a host reboot. Install it with: apt install -y iptables-persistent"

fi