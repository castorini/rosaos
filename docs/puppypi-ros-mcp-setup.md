# PuppyPi ROS MCP Setup

This guide captures the working HiWonder PuppyPi setup as of May 2026:
Mac laptop + iPhone hotspot + PuppyPi in ROS 2 mode + laptop-side ROS MCP.

Official docs: https://wiki.hiwonder.com/projects/PuppyPi/en/latest/

## What Runs Where

- PuppyPi runs ROS 2, rosbridge, rosapi, camera, and `puppy_control`.
- The laptop runs `ros-mcp-server`, exposed to rosaOS as `dog` at
  `http://localhost:9090/mcp`.
- rosaOS talks to the laptop MCP server; the laptop MCP server talks to
  PuppyPi rosbridge at `<robot-host>:9090`.

On the working iPhone hotspot setup, PuppyPi was reachable from the Mac as
`raspberrypi.local`. The hotspot may not expose a normal scan-able IPv4 subnet;
on one carrier the Mac showed `192.0.0.2/32` with IPv6/NAT64. In that case,
prefer `raspberrypi.local` over trying to discover an IPv4 address.

## One-Time Laptop Setup

Install RealVNC Viewer. Homebrew works:

```bash
brew install --cask realvnc-connect
```

Install ROS MCP into the rosaOS virtualenv:

```bash
cd /Users/lily/dev/rosaos
git submodule update --init --recursive
uv pip install -p scripts/reachy_mini_env/bin/python -e server/ros-mcp-server
```

## Connect PuppyPi To The Hotspot

See official docs [here](https://wiki.hiwonder.com/projects/PuppyPi/en/latest/docs/3.Remote_Tool_Installation_Connection.html#remote-tool-installation-and-docker-entry-method).

1. Power on the PuppyPi.
2. Press key `1` on the PuppyPi to make it create its own Wi-Fi access point.
3. Connect the Mac to the PuppyPi access point. The access point's name starts with HW- and the password is `hiwonder`.
4. Open VNC Viewer on the Mac and connect to the PuppyPi access-point IP shown
   by the PuppyPi app or docs. Common credentials are:

```text
IP: 192.168.149.1
username: pi
password: raspberrypi
```

5. Start the phone hotspot.
6. In the PuppyPi desktop/app UI, connect the PuppyPi to the phone hotspot.
   VNC will disconnect when the robot leaves AP mode.
7. Switch the Mac to the same phone hotspot.
8. VNC into the PuppyPi again.

If the app shows an IPv4 address, use it in VNC Viewer. If it does not show an
IP but the robot is visible by hostname, use:

```text
vnc://raspberrypi.local
```

If macOS resolves only IPv6, bracket the IPv6 address:

```text
vnc://[2605:...]
```

## Start ROS 2 On PuppyPi

In the PuppyPi UI, use the tool/gear icon to switch the system to ROS 2 mode.
The ROS 1 Noetic terminal may show `/opt/ros/noetic`, `ROS_MASTER_URI`, and no
`ros2`; that is the wrong mode for this setup.

Open four PuppyPi terminals over VNC and leave all of them running.

Terminal 1, Puppy control:

```bash
source /opt/ros/humble/setup.bash
ros2 launch puppy_control puppy_control.launch.py
```

Terminal 2, camera/peripherals:

```bash
source /opt/ros/humble/setup.bash
ros2 launch peripherals usb_cam.launch.py
```

Terminal 3, rosbridge:

```bash
source /opt/ros/humble/setup.bash
ros2 launch rosbridge_server rosbridge_websocket_launch.xml
```

Terminal 4, rosapi:

```bash
source /opt/ros/humble/setup.bash
ros2 run rosapi rosapi_node
```

## Verify From The Laptop

From the Mac:

```bash
nc -vz raspberrypi.local 5900
nc -vz raspberrypi.local 9090
```

Port `5900` is VNC. Port `9090` is rosbridge.

Start the laptop-side dog MCP:

```bash
cd /Users/lily/dev/rosaos
DOG_ROSBRIDGE_IP=raspberrypi.local ./scripts/start_dog_mcp.sh
```

The defaults are:

- PuppyPi rosbridge: `${DOG_ROSBRIDGE_IP}:9090`
- Laptop MCP server: `http://localhost:9090/mcp`
- Camera topic: `/image_raw`

Override as needed:

```bash
DOG_ROSBRIDGE_IP=<host-or-ip> DOG_MCP_PORT=9090 ./scripts/start_dog_mcp.sh
```

## Smoke Test

With `start_dog_mcp.sh` running, verify MCP can see the live ROS 2 graph:

```bash
scripts/reachy_mini_env/bin/python - <<'PY'
import asyncio
from fastmcp import Client

async def main():
    async with Client("http://127.0.0.1:9090/mcp") as client:
        topics = await client.call_tool("get_topics", {})
        services = await client.call_tool("get_services", {})
        print("topic_count", topics.data.get("topic_count"))
        print("service_count", services.data.get("service_count"))
        print("/puppy_control/velocity_move" in topics.data.get("topics", []))
        print("/image_raw" in topics.data.get("topics", []))
        print("/puppy_control/go_home" in services.data.get("services", []))

asyncio.run(main())
PY
```

Expected working values from May 31, 2026:

- `topic_count`: `31`
- `service_count`: `67`
- `/puppy_control/velocity_move`: present
- `/image_raw`: present
- `/puppy_control/go_home`: present

Safe command test:

```bash
scripts/reachy_mini_env/bin/python - <<'PY'
import asyncio
from fastmcp import Client

async def main():
    async with Client("http://127.0.0.1:9090/mcp") as client:
        print(await client.call_tool("call_service", {
            "service_name": "/puppy_control/set_running",
            "service_type": "std_srvs/srv/SetBool",
            "request": {"data": True},
            "timeout": 5,
        }))
        print(await client.call_tool("call_service", {
            "service_name": "/puppy_control/go_home",
            "service_type": "std_srvs/srv/Empty",
            "request": {},
            "timeout": 5,
        }))

asyncio.run(main())
PY
```

The dog should visibly settle or reset posture.

## ROS 2 Surface Used By rosaOS

The `dog` driver prompt is configured for the ROS 2 PuppyPi graph observed on
May 31, 2026.

Important topics:

- `/cmd_vel` with `geometry_msgs/msg/Twist`
- `/image_raw` with `sensor_msgs/msg/Image`
- `/puppy_control/velocity_move` with `puppy_control_msgs/msg/Velocity`
- `/puppy_control/velocity` with `puppy_control_msgs/msg/Velocity`

Important services:

- `/puppy_control/go_home` with `std_srvs/srv/Empty`
- `/puppy_control/set_running` with `std_srvs/srv/SetBool`
- `/puppy_control/runActionGroup` with
  `puppy_control_msgs/srv/SetRunActionName`
