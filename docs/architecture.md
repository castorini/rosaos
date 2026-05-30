# rosaOS architecture (OS-style)

High-level layout with operating-system analogies: kernel, process manager, processes, and device layer.

```mermaid
flowchart TB

%% =========================================================
%% STYLES
%% =========================================================

classDef entry fill:#eef6ff,stroke:#6aa5ff,stroke-width:2px,color:#1d1d1f
classDef api fill:#f8f5ff,stroke:#8b5cf6,stroke-width:2px,color:#1d1d1f
classDef datastore fill:#faf2ff,stroke:#b26bff,stroke-width:2px,color:#1d1d1f
classDef agent fill:#f3ecff,stroke:#8b5cf6,stroke-width:2px,color:#1d1d1f
classDef mcp fill:#fff4df,stroke:#e0a100,stroke-width:2px,color:#1d1d1f
classDef hardware fill:#f5f5f7,stroke:#9aa0a6,stroke-width:1.5px,color:#1d1d1f

linkStyle default stroke-width:2px

%% =========================================================
%% USER ENTRYPOINTS
%% =========================================================
subgraph OS["<span style='font-size:1.2em;font-weight:700'>rosaOS</span>"]
direction TB

subgraph USERS["USER ENTRYPOINTS"]
direction LR

R(["🤖<br/><b>Reachy Mini UI</b><br/><small>Eye Contact · Voice</small>"])

B(["💻<br/><b>Browser UI / CLI</b><br/><small>Text Chat</small>"])

end

style USERS fill:#f8fbff,stroke:#c8defc,stroke-width:2px

class R,B entry

%% =========================================================
%% KERNEL FLOW
%% =========================================================

API{{"🌐 <b>HTTP API</b><br/><small>/stt · /chat · /event</small>"}}

QUEUE(["📬 Event Queue"])

KERNEL("🧠 <b>Kernel Agent</b><br/><small>Decides · Plans · Orchestrates</small>")

PM[["⚙️ <b>Process Management MCP</b><br/><small>Spawn · Manage · List Processes</small>"]]

class API api
class QUEUE datastore
class KERNEL agent
class PM mcp

%% =========================================================
%% AGENT RUNTIME
%% =========================================================

subgraph PROC["AGENT RUNTIME"]
direction LR

P1("<b>Process 1</b><br/><small>Speak</small>")

P2("<b>Process 2</b><br/><small>Smart Home</small>")

P3("<b>Process 3</b><br/><small>Robot Navigation</small>")

%% PX["⋯"]

end

style PROC fill:#f5f9ff,stroke:#bdd7ff,stroke-width:2px

class P1,P2,P3 agent

%% =========================================================
%% MCP DRIVER LAYER
%% =========================================================

subgraph MCP["MCP DRIVER LAYER"]
direction LR

M1[["🤖 Reachy Mini MCP"]]

M2[["💡 Lamp MCP"]]

M3[["🦾 ROS MCP"]]

%% MX["⋯"]

end

style MCP fill:#fff9eb,stroke:#f0cb6b,stroke-width:2px

class M1,M2,M3 mcp

end

style OS fill:#fcfaff,stroke:#cab8ff,stroke-width:3px


%% =========================================================
%% HARDWARE
%% =========================================================

subgraph HW["HARDWARE / SYSTEMS"]
direction LR

H1[/"<div style='width:180px;text-align:center'>🤖 <b>Reachy Mini Hardware</b><br/><small>Daemon / SDK</small></div>"/]

H2[/"<div style='width:180px;text-align:center'>💡 <b>Lamp Hardware</b><br/><small>Lamp SDK</small></div>"/]

H3[/"<div style='width:180px;text-align:center'>🦾 <b>Robot Hardware</b><br/><small>ROS 2 System</small></div>"/]

%% HX["⋯"]

end

style HW fill:#fafafa,stroke:#d7d7d7,stroke-width:2px

class H1,H2,H3 hardware


%% =========================================================
%% FLOW
%% =========================================================

R -->|/stt| API
B -->|/chat| API

API --> QUEUE
QUEUE --> KERNEL
KERNEL --> PM

PM -->|dispatch| P1
PM -->|dispatch| P2
PM -->|dispatch| P3

P1 -->|MCP tool calls| M1
P2 -->|MCP tool calls| M2
P3 -->|MCP tool calls| M3

M1 -->|tool execution| H1
M2 -->|tool execution| H2
M3 -->|tool execution| H3

P1 -. /event .-> API
P2 -. /event .-> API
P3 -. /event .-> API
```

## Flow summary

| Step | What happens |
|------|----------------|
| 1 | User speaks → Reachy mic → STT loop transcribes → POST `/stt` → event queue. |
| 2 | Kernel agent consumes event (e.g. `[User said] ...`), calls `launch_process(system_prompt)` on process server. |
| 3 | Process server spawns worker subprocess; worker runs process agent with robot MCP tools. |
| 4 | Worker uses tools (e.g. `speak`, `take_picture`) → Reachy MCP server → ReachyMini → daemon/robot. |
| 5 | Worker finishes → POST `/event` to kernel with `worker_id`, `message`, `done` → kernel gets `[Worker callback]` event. |
| 6 | Kernel may launch another process (e.g. to speak to user). |

## Ports

| Port | Service | Role |
|------|---------|------|
| 8000 | Reachy Mini daemon | Robot control (external) |
| 5001 | Reachy MCP server | Device layer: robot tools + STT loop |
| 7001 | Process server (MCP) | Internal process manager |
| 8765 | Client (FastAPI) | Kernel + HTTP API (event, stt, chat, updates) |
| 6000 | vLLM (optional) | Local LLM endpoint |
