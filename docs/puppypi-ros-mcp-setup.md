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

Usually, once the Mac and PuppyPi are both on the phone hotspot, the easiest VNC
target is just:

```text
vnc://raspberrypi.local
```

You can open it from Terminal.app with:

```bash
open vnc://raspberrypi.local
```

If the app shows an IPv4 address, that also works in VNC Viewer. If
`raspberrypi.local` does not work, use the fallback discovery commands below.

If macOS resolves only IPv6 and you want to connect by address instead of
hostname, bracket the IPv6 address:

```text
vnc://[2605:...]
```

### Fallback: Find The PuppyPi VNC Address From macOS

Use this only if `vnc://raspberrypi.local` fails. On a phone hotspot, the
PuppyPi may not get a normal IPv4 address that shows up in `arp -a`. Query mDNS
directly:

```bash
dns-sd -G v4v6 raspberrypi.local
```

This command keeps running. Wait for an `Add` line for `raspberrypi.local`,
copy the address, then press `Ctrl-C`.

If the address is IPv6, put square brackets around it in VNC Viewer or in the
macOS `open` command:

```bash
open 'vnc://[2605:b100:36b:c7f7:07fd:af6f:d175:39e6]'
```

To confirm it is really the PuppyPi VNC server:

```bash
nc -vz '2605:b100:36b:c7f7:07fd:af6f:d175:39e6' 5900
```

Expected success text includes `port 5900 [tcp/rfb] succeeded`.

If mDNS does not return anything, wake up IPv6 neighbor discovery and inspect
neighbors:

```bash
ping6 -c 2 ff02::1%en0
ndp -an
```

Look for a non-Mac neighbor on `en0`, then test likely candidates with
`nc -vz <address> 5900`. Link-local IPv6 addresses need the interface suffix,
for example `fe80::681a:47ff:feb0:1a64%en0`.

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

Important actions:

- `/puppy/move_distance`
- `/puppy/rotate_angle`
- `/puppy/move_to_pose`

Important services:

- `/puppy_control/go_home` with `std_srvs/srv/Empty`
- `/puppy_control/set_running` with `std_srvs/srv/SetBool`
- `/puppy_control/runActionGroup` with
  `puppy_control_msgs/srv/SetRunActionName`

For physical movement, use `/puppy_control/velocity`. On June 1, 2026, a live
test confirmed that publishing `puppy_control_msgs/msg/Velocity` with `x: 5.0`,
`y: 0.0`, `yaw_rate: 0.0` for 0.8 seconds, followed by an all-zero stop message,
moved the dog forward.

Hiwonder's ROS 2 docs demonstrate direct forward velocity with
`/puppy_control/velocity` and `x: 5.0`, followed by an all-zero stop message.
Avoid tiny fractional values such as `x: 0.15`; that was observed to produce
little or no translation.

For raw velocity rotation, use the same `/puppy_control/velocity` topic with
`x: 0.0`, `y: 0.0`, and a bounded `yaw_rate`, followed immediately by an
all-zero stop message. Positive `yaw_rate` should mean left / counterclockwise
and negative `yaw_rate` should mean right / clockwise, unless live testing shows
this PuppyPi image has the signs reversed.

The best calibrated raw-velocity turn so far is `yaw_rate: 0.2` for 0.03
seconds, followed by zero velocity for 0.5 seconds. It produced a cleaner turn
than lower yaw-rate commands, but it is still a large turn: roughly 135 degrees.
Use it when a cleaner pivot matters more than precise small-angle control.

For smaller turns, lower `yaw_rate` instead of relying on extremely short
durations. Testing suggests sub-30ms durations may hit a controller or gait
timing floor: `yaw_rate: 0.2` for both 0.03 seconds and 0.01 seconds produced
roughly the same 135 degree turn. Lower yaw rates can produce smaller turns, but
they arc more.

Calibration notes from June 1, 2026:

| Command | Observed result |
| --- | --- |
| `yaw_rate: 0.04` for 0.1s | Roughly 30 degrees, more arcing |
| `yaw_rate: 0.08` for 0.06s | Roughly 45 degrees, still arcing |
| `yaw_rate: 0.2` for 0.03s | Roughly 135 degrees, less arcing |
| `yaw_rate: 0.2` for 0.01s | Roughly 135 degrees, likely timing floor |
| `yaw_rate: 0.5` for 0.01s | Nearly a full rotation; avoid for small turns |

The live graph also exposed `/puppy/move_distance`, `/puppy/rotate_angle`, and
`/puppy/move_to_pose`, but a `MoveDistance` goal sent through ROS MCP timed out
and did not move the dog. Treat those actions as unverified until tested
directly on the PuppyPi.

`rosapi_node` is needed for MCP discovery tools such as `get_topics`,
`get_services`, and action listing. Direct topic publishing through rosbridge can
still work if `rosapi_node` dies, but restart `rosapi_node` before relying on
introspection.
