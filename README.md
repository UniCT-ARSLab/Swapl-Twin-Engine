<h1 align="center">SWAPL – Godot Engine Integration</h1>

<p align="center">
  <strong>A real-time framework for programming drone swarms in SWAPL and monitoring their behaviour through a Godot-based digital twin.</strong>
</p>

<p align="center">
  SWAPL + Godot Engine 4 + HTTP + WebSocket
</p>

---

## Author

Developed by Enrico Sorbello, Computer Science student at the Department of Mathematics and Computer Science, University of Catania, Italy.

Supervisor: Prof. Federico Fausto Santoro — Co-supervisor: Prof. Corrado Santoro — A.Y. 2024–2025

---

## Why it exists

`SWAPL–Godot` was built to bridge the gap between swarm programming languages and 3D physics Digital Twins:

- define collective behaviours and trajectories in SWAPL
- observe the swarm moving in real time inside a physics-accurate 3D environment
- receive sensor feedback from the twin back into the logic layer
- validate swarm programs before deploying on physical hardware

The goal is not just to visualise agents, but to close the loop between logic and physics.

---

## What's included

### SWAPL side (Python)
- multi-agent runtime with parallel behaviour execution
- HTTP server for initial handshake with Godot
- WebSocket position server streaming agent coordinates at 100ms intervals
- WebSocket alert server receiving collision events from the twin

### Godot side (GDScript)
- `Connector`: manages the full communication lifecycle with SWAPL
- `DroneSpawner`: dynamically instantiates drone scenes in a √N grid
- `Drone Controller`: RigidBody3D with cascaded PID for altitude and horizontal movement
- `Proximity Sensor`: 9-ray fan over 30°

---

## Architecture

```
┌─────────────────────────┐         ┌─────────────────────────┐
│         SWAPL           │         │       Godot Engine       │
│                         │         │                         │
│  Agent Runtime          │◄───────►│  Connector              │
│  HTTP Service  :8080    │─────────│  DroneSpawner           │
│  WS Position   :9080    │────────►│  Drone Controller       │
│  WS Alert      :8081    │◄────────│  Proximity Sensor       │
└─────────────────────────┘         └─────────────────────────┘
         Logic                               Physics / Twin
```

| Channel | Port | Direction | Description |
|---------|------|-----------|-------------|
| HTTP | 8080 | Godot → SWAPL | Initial setup (`/setup`) |
| WebSocket | 9080 | SWAPL → Godot | Position updates (30ms) |
| WebSocket | 8081 | Godot → SWAPL | Collision alerts |

---

## Requirements

### SWAPL (Python)
- Python 3.10+

### Godot
- Godot Engine 4.x
- No additional plugins required

---

## Quick start

### 1. Clone and install

```bash
git clone https://github.com/your-username/swapl-godot-twin.git
cd swapl-godot-twin
```

The repository is structured as follows:

```text
swapl-godot-twin/
├── SWAPL/          # Python runtime and .swapl programs
└── DigitalTwin/    # Godot Engine project
```

Open Godot Engine and import the `DigitalTwin/` folder as an existing project.
### 2. Start Godot

Open the project in Godot Engine and press **Play** on the `world.tscn` scene. The Connector will automatically reach SWAPL, spawn the drones based on the received configuration, and start updating their positions.
### 3. Start SWAPL

```bash
cd lib
py swapl.py -p 8080 -t 10 ..\tests\test_circle.swapl
```

**Available flags:**

| Flag | Description | Example |
|------|-------------|---------|
| `-p` | HTTP port for the setup server | `-p 8080` |
| `-t` | Simulation duration in seconds (optional) | `-t 10` |

SWAPL will automatically start all three servers and wait for Godot to connect.



### 4. Shutdown

When the `-t` duration expires, SWAPL prints the session metrics to the terminal and disconnects. Godot detects the disconnection and automatically removes all drones from the scene, returning to the initial state.

---

## Operational notes

- SWAPL and Godot must run on the same machine or the same local network
- the HTTP port set with `-p` must match the one configured in `connector.gd` (`swapl_http_url`)
- if you change port 9080 or 8081, update `connector.gd` and `drone.gd` accordingly