# macvlan-router

`macvlan` is one of many networking modes/drivers in Docker. It assigns a unique MAC address to each container and allows for specific IP addresses of the host network on the virtual interface of the container.

However, by default the container can not ping and connect to the default network namespace (used by the host). Therefore, the **container is only reachable from outside devices** and \***\*not** the container host\*\* itself!
You can find more information here:

- <https://docs.docker.com/engine/network/drivers/macvlan/>
- <https://dockerlabs.collabnix.com/beginners/macvlan-010.html>

This small container helps to manage routing for `macvlan` interfaces from and to the container host by collecting relevant information using the `docker.sock` and managing the bridge interface and IP routing information.

## Disclaimer

**This container needs to use `host networking` and the `NET_ADMIN` capability! Therefore it has very wide privileges and can break network connectivity of the host !!!**

**Make sure to have a backup plan if you can't reach your host using the network anymore!**

## How does it work?

Before you start, you need to create the `macvlan` docker network (see #usage). This network is shared across all workloads wanting to use the feature.

This container does the following things:

- it connects to the provided `docker.sock` to determine relevant information about that network
- it ensures the bridge interface on the host
- it binds a bridge IP address to that interface
- it continuously checks the Docker socket for containers attached to the network and adds the IP to the route table

On exit, it optionally removes the network bridge again to restore the original state.

## Usage

First you need to create the `macvlan` docker network manually. The following snippet tries to determine the active interface and subnet itself:

```sh
# Replace 'bridge0' with the name of your bridge interface (e.g., 'macvlan0').
BRIDGE_INTERFACE=<your-bridge-interface>

# determine relevant information of your primary interface
PARENT_INTERFACE=$(ip route show default | awk '{print $5}')
GATEWAY=$(ip route show default | awk '{print $3}')
SUBNET=$(ip route show | grep ${PARENT_INTERFACE} | grep -v default | awk '{print $1}')

docker network create macvlan --driver macvlan -o parent=${PARENT_INTERFACE} --subnet ${SUBNET} --gateway ${GATEWAY}
```

Now you can start the container using the provided `compose.yaml` file:

```sh
docker compose up -d
```

Now you should see a new interface appear on the host named `macvlan@eth0` (or similar) and should be able to reach attached containers just fine.

| Environment Variable            | Description                                                                                                                                | Default                          | Required |
| ------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------ | -------------------------------- | -------- |
| `MACVLAN_DOCKER_NETWORK`        | name of the Docker network in `macvlan` mode                                                                                               | \<unset\>                        | yes      |
| `MACVLAN_BRIDGE_IP`             | one free IP in the macvlan subnet for bridging purposes                                                                                    | \<unset\>                        | yes      |
| `MACVLAN_BRIDGE_INTERFACE_NAME` | name of the bridge interface                                                                                                               | same as `MACVLAN_DOCKER_NETWORK` | no       |
| `ADDITIONAL_ROUTES`             | space-separated list of additional routes on the bridge (can contain VIPs)                                                                 | ""                               | no       |
| `CLEANUP_ON_EXIT`               | controls if the bridge is removed when the container exits. Setting this to `true` may disrupt ongoing services during container restarts. | false                            | no       |
| `TZ`                            | timezone used by the container                                                                                                             | UTC                              | no       |
| `DEBUG`                         | enable debug output                                                                                                                        | false                            | no       |
