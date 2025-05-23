#!/usr/bin/env sh

if [[ "${DEBUG}" == "true" || "${DEBUG}" == "1" ]]; then
  set -x
fi

MACVLAN_DOCKER_NETWORK=${MACVLAN_DOCKER_NETWORK:?"MACVLAN_DOCKER_NETWORK is required"}
MACVLAN_BRIDGE_IP=${MACVLAN_BRIDGE_IP:?"MACVLAN_BRIDGE_IP is required"}
MACVLAN_BRIDGE_INTERFACE_NAME=${MACVLAN_BRIDGE_INTERFACE_NAME:-$MACVLAN_DOCKER_NETWORK}

ADDITIONAL_ROUTES=${ADDITIONAL_ROUTES:-""}
CLEANUP_ON_EXIT=${CLEANUP_ON_EXIT:-"false"}

SUBNET=$(docker network inspect ${MACVLAN_DOCKER_NETWORK} | jq -r '.[].IPAM.Config[].Subnet')
GATEWAY=$(docker network inspect ${MACVLAN_DOCKER_NETWORK} | jq -r '.[].IPAM.Config[].Gateway')
PARENT_INTERFACE=$(docker network inspect ${MACVLAN_DOCKER_NETWORK} | jq -r '.[].Options.parent')

######## functions

function log {
  echo "$@"
}

function debug {
  [[ "${DEBUG}" == "true" || "${DEBUG}" == "1" ]] && log "$@"
}

function ip_route_add {
  IP=$(echo ${1} | cut -d'/' -f1)
  ip route show dev ${MACVLAN_BRIDGE_INTERFACE_NAME} | grep -E "^${IP}(/[0-9]+|\s)" >/dev/null || (
      log "[$(date)] Adding route for ${IP} ..."
      ip route add ${IP} dev ${MACVLAN_BRIDGE_INTERFACE_NAME}
    )
}

function cleanup {
  log "[$(date)] Cleaning up..."
  ip link del ${MACVLAN_BRIDGE_INTERFACE_NAME}
}

function trap_exit {
  log "[$(date)] Exiting..."
  [[ "${CLEANUP_ON_EXIT}" == "true" || "${CLEANUP_ON_EXIT}" == "1" ]] && cleanup
  exit 0
}
trap trap_exit SIGHUP SIGINT SIGTERM

######## routing config

log "[$(date)] Creating bridge interface: ${MACVLAN_BRIDGE_INTERFACE_NAME} ..."
ip link show ${MACVLAN_BRIDGE_INTERFACE_NAME} 2>/dev/null || ip link add ${MACVLAN_BRIDGE_INTERFACE_NAME} link ${PARENT_INTERFACE} type macvlan mode bridge

log "[$(date)] Adding IP to bridge interface: ${MACVLAN_BRIDGE_IP} ..."
ip addr show ${MACVLAN_BRIDGE_INTERFACE_NAME} | grep ${MACVLAN_BRIDGE_IP} || ip addr add ${MACVLAN_BRIDGE_IP} dev ${MACVLAN_BRIDGE_INTERFACE_NAME}

log "[$(date)] Bringing interface up: ${MACVLAN_BRIDGE_INTERFACE_NAME} ..."
ip link show ${MACVLAN_BRIDGE_INTERFACE_NAME} | grep "state UP" || ip link set ${MACVLAN_BRIDGE_INTERFACE_NAME} up

while [ true ]; do
  debug "[$(date)] Checking for docker network members..."
  CONTAINER_IPS=$(docker network inspect ${MACVLAN_DOCKER_NETWORK} | jq -r '.[].Containers | to_entries[].value.IPv4Address')

  for IP in ${CONTAINER_IPS}; do ip_route_add ${IP}; done
  for IP in ${ADDITIONAL_ROUTES}; do ip_route_add ${IP}; done

  ip route show dev ${MACVLAN_BRIDGE_INTERFACE_NAME} | grep -v kernel
  sleep ${INTERVAL:-5}
done
