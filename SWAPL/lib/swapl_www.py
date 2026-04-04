# -----------------------------------------------------------------------------
# swapl_www.py
# -----------------------------------------------------------------------------

import http.server
import socketserver
import pathlib
import threading
import time
import re
import json
import os
import io
import sys
import asyncio
import websockets

from urllib.parse import urlparse


class MessageStats:

    def __init__(self, name, latency_label="latency"):
        self.name = name
        self.latency_label = latency_label
        self.sent = 0
        self.items_sent = 0
        self.recv = 0
        self.send_errors = 0
        self.recv_errors = 0
        self.lost = 0
        self.latency_sum = 0.0
        self.latency_count = 0
        self._last_seq_by_client = { }
        self._lock = threading.Lock()

    def record_send(self):
        with self._lock:
            self.sent += 1

    def record_items_sent(self, count):
        with self._lock:
            self.items_sent += int(count)

    def record_send_error(self):
        with self._lock:
            self.send_errors += 1

    def record_recv_error(self):
        with self._lock:
            self.recv_errors += 1

    def record_lost(self, n=1):
        with self._lock:
            self.lost += n

    def record_latency(self, value_s):
        with self._lock:
            self.latency_sum += float(value_s)
            self.latency_count += 1

    def record_recv(self, client_id=None, seq=None, sent_ts=None):
        with self._lock:
            self.recv += 1
            if client_id is not None and seq is not None:
                try:
                    seq_val = int(seq)
                    key = str(client_id)
                    last = self._last_seq_by_client.get(key)
                    if last is not None:
                        if seq_val > last + 1:
                            self.lost += (seq_val - last - 1)
                        if seq_val > last:
                            self._last_seq_by_client[key] = seq_val
                    else:
                        self._last_seq_by_client[key] = seq_val
                except Exception:
                    pass
            if sent_ts is not None:
                try:
                    ts_val = float(sent_ts)
                    if ts_val > 1e12:
                        ts_val = ts_val / 1000.0
                    now = time.time()
                    latency = now - ts_val
                    if latency >= 0:
                        self.latency_sum += latency
                        self.latency_count += 1
                except Exception:
                    pass

    def summary(self):
        with self._lock:
            avg_latency_ms = None
            if self.latency_count > 0:
                avg_latency_ms = (self.latency_sum / self.latency_count) * 1000.0
            return {
                "name": self.name,
                "sent": self.sent,
                "items_sent": self.items_sent,
                "recv": self.recv,
                "send_errors": self.send_errors,
                "recv_errors": self.recv_errors,
                "lost": self.lost,
                "latency_label": self.latency_label,
                "latency_count": self.latency_count,
                "avg_latency_ms": avg_latency_ms
            }


WS_STATS = {
    "position": MessageStats("position", latency_label="rtt"),
    "alert": MessageStats("alert", latency_label="one_way")
}


def print_ws_stats():
    print("\n--- WebSocket stats ---")
    for name, stats in WS_STATS.items():
        s = stats.summary()
        avg = "n/a" if s["avg_latency_ms"] is None else "{:.2f}".format(s["avg_latency_ms"])
        print("[{}] sent={} items_sent={} recv={} send_errors={} recv_errors={} lost={} avg_{}_ms={} (n={})".format(
            name,
            s["sent"],
            s["items_sent"],
            s["recv"],
            s["send_errors"],
            s["recv_errors"],
            s["lost"],
            s["latency_label"],
            avg,
            s["latency_count"]
        ))


class SWAPLHttpRequestHandler(http.server.SimpleHTTPRequestHandler):

    program = None

    def __init__(self, request, client_address, server):
        root_path = pathlib.Path(__file__).parent.resolve()
        self.root_path = str(root_path) + '/www/'
        os.chdir(self.root_path)
        super().__init__(request, client_address, server)

    def log_message(self, format, *args):
        pass

    def do_GET(self):
        parsed = urlparse(self.path)
        
        if parsed.path == "/agentlist":
            alist = [ ]
            for agent in SWAPLHttpRequestHandler.program.get_agents().values():
                f = agent.to_dict()
                del f['object']
                alist.append(f)
            content = json.dumps(alist)
            self.send_json(content)
        
        elif parsed.path == "/environment":
            env = SWAPLHttpRequestHandler.program.get_environment()
            content = json.dumps(env.to_dict())
            self.send_json(content)
        
        elif parsed.path == "/agent":
            agent = SWAPLHttpRequestHandler.program.get_agent(parsed.query)
            f = agent.to_dict()
            del f['object']
            content = json.dumps(f)
            self.send_json(content)
        
        # === NUOVO: Endpoint /setup per Godot ===
        elif parsed.path == "/setup":
            agents = SWAPLHttpRequestHandler.program.get_agents()
            setup_data = {
                "drone_count": len(agents),
                "agents": []
            }
            
            for i, (name, agent) in enumerate(agents.items()):
                try:
                    role = agent.get_attribute('role')
                except:
                    role = "unknown"
                
                setup_data["agents"].append({
                    "id": i,
                    "name": name,
                    "role": role
                })
            
            content = json.dumps(setup_data)
            print(f"[HTTP] /setup requested - Sending {setup_data['drone_count']} drones info")
            self.send_json(content)
        
        else:
            super().do_GET()

    def send_json(self, _json):
        enc = sys.getfilesystemencoding()
        encoded = _json.encode(enc, 'surrogateescape')
        f = io.BytesIO()
        f.write(encoded)
        f.seek(0)
        self.send_response(200)
        self.send_header("Content-type", "application/json")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Content-Length", str(len(encoded)))
        self.end_headers()
        try:
            self.copyfile(f, self.wfile)
        finally:
            f.close()



class SWAPLHttpServer(threading.Thread):

    def __init__(self, port):
        super().__init__()
        self.port = port
        self.httpd = None
        self.setDaemon(True)

    def run(self):
        Handler = SWAPLHttpRequestHandler
        socketserver.TCPServer.allow_reuse_address = True
        self.httpd = socketserver.TCPServer(("", self.port), Handler)
        self.httpd.serve_forever()

    def stop(self):
        if self.httpd is not None:
            try:
                self.httpd.shutdown()
                self.httpd.server_close()
            except Exception:
                pass



class SWAPLWebSocketAlertServer:
    
    def __init__(self, program, port=8081):
        self.program = program
        self.port = port
        self.clients = set()
        self.loop = None
        self.server = None
        self.stats = WS_STATS["alert"]
    
    async def handle_client(self, websocket):
        """Gestisce un client WebSocket connesso (droni Godot)"""
        client_addr = websocket.remote_address
        print(f"[Alert Server] Drone connected: {client_addr}")
        self.clients.add(websocket)
        
        try:
            async for message in websocket:
                await self.process_message(websocket, message)
        except websockets.exceptions.ConnectionClosed:
            print(f"[Alert Server] Drone disconnected: {client_addr}")
        finally:
            self.clients.discard(websocket)
    
    async def process_message(self, websocket, message):
        """Processa messaggi ricevuti (alert collisioni)"""
        try:
            data = json.loads(message)
            self.stats.record_recv(websocket.remote_address, data.get("seq"), data.get("ts"))
            
            if data.get('type') == 'collision_alert':
                drone_name = data.get('drone', '?')
                distance = data.get('distance', 0)
                obj_name = data.get('object', '?')
                
                print(f"COLLISION ALERT: Drone={drone_name}, Distance={distance:.2f}m, Object={obj_name}")
                
                # Passa l'alert all'agente SWAPL
                try:
                    drone_id = None
                    if isinstance(drone_name, str):
                        match = re.search(r"(\d+)$", drone_name)
                        if match:
                            drone_id = int(match.group(1))
                    if drone_id is None:
                        raise ValueError(f"Invalid drone name '{drone_name}'")

                    agent_name = "leader" if drone_id == 0 else f"dynamic-{drone_id - 1}"
                    agent = self.program.get_agent(agent_name)
                    
                    if agent and hasattr(agent.get_attribute('object'), 'on_collision_alert'):
                        agent.get_attribute('object').on_collision_alert(data)
                except (ValueError, KeyError, Exception) as e:
                    print(f"Could not forward alert to agent: {e}")
                
                # Risposta
                response = {'type': 'collision_response', 'status': 'received', 'drone': drone_name}
                try:
                    await websocket.send(json.dumps(response))
                    self.stats.record_send()
                except Exception:
                    self.stats.record_send_error()
        
        except json.JSONDecodeError:
            print(f"Invalid JSON: {message}")
            self.stats.record_recv_error()
        except Exception as e:
            print(f"Error processing message: {e}")
            self.stats.record_recv_error()
    
    async def start_server(self):
        """Avvia il server WebSocket"""
        self.server = await websockets.serve(self.handle_client, "0.0.0.0", self.port)
        print(f"WebSocket Alert Server started on port {self.port}")
        await asyncio.Future()
    
    def run(self):
        """Esegue il server in un loop asyncio"""
        self.loop = asyncio.new_event_loop()
        asyncio.set_event_loop(self.loop)
        self.loop.run_until_complete(self.start_server())



class SWAPLWebSocketPositionServer:
    
    def __init__(self, program, port=9080):
        self.program = program
        self.port = port
        self.clients = set()
        self.loop = None
        self.server = None
        self.stats = WS_STATS["position"]
        self.seq = 0
        self.use_ping_latency = True

    async def handle_incoming(self, websocket):
        """Gestisce messaggi in ingresso (ack)"""
        try:
            async for message in websocket:
                try:
                    data = json.loads(message)
                except Exception:
                    self.stats.record_recv_error()
                    continue

                if data.get("type") == "position_ack":
                    self.use_ping_latency = False
                    self.stats.record_recv(
                        websocket.remote_address,
                        data.get("seq"),
                        data.get("ts")
                    )
        except websockets.exceptions.ConnectionClosed:
            pass
        except Exception:
            self.stats.record_recv_error()
    
    async def handle_client(self, websocket):
        """Gestisce connessione da Godot Main"""
        client_addr = websocket.remote_address
        print(f"[Position Server] Godot connected: {client_addr}")
        self.clients.add(websocket)
        receiver_task = asyncio.create_task(self.handle_incoming(websocket))

        try:
            
            last_ping = time.monotonic()
            ping_interval = 1.0
            ping_timeout = 1.0
            while True:
                
                agents = self.program.get_agents()
                drones_data = []
                
                for i, (name, agent) in enumerate(agents.items()):
                    try:
                        x = agent.get_attribute('x').get()
                        y = agent.get_attribute('y').get()
                    except:
                        x = 0.0
                        y = 0.0
                    
                    drones_data.append({
                        "id": i,
                        "name": f"Drone_{i}",
                        "x": round(float(x), 2),
                        "z": round(float(y), 2) 
                    })
                
                self.seq += 1
                position_msg = {
                    "type": "position_update",
                    "seq": self.seq,
                    "ts": time.time(),
                    "drones": drones_data
                }
                
                try:
                    await websocket.send(json.dumps(position_msg))
                    self.stats.record_send()
                    self.stats.record_items_sent(len(drones_data))
                except Exception:
                    self.stats.record_send_error()
                    raise

                if self.use_ping_latency:
                    now = time.monotonic()
                    if now - last_ping >= ping_interval:
                        last_ping = now
                        try:
                            start = time.perf_counter()
                            pong_waiter = await websocket.ping()
                            await asyncio.wait_for(pong_waiter, timeout=ping_timeout)
                            self.stats.record_latency(time.perf_counter() - start)
                        except asyncio.TimeoutError:
                            self.stats.record_lost()
                        except Exception:
                            self.stats.record_send_error()

                await asyncio.sleep(0.03)  
                
        except websockets.exceptions.ConnectionClosed:
            print(f"[Position Server] Godot disconnected: {client_addr}")
        except Exception as e:
            print(f"[Position Server] Error: {e}")
        finally:
            self.clients.discard(websocket)
            if receiver_task:
                receiver_task.cancel()
                try:
                    await receiver_task
                except asyncio.CancelledError:
                    pass
    
    async def start_server(self):
        """Avvia il server WebSocket"""
        self.server = await websockets.serve(self.handle_client, "0.0.0.0", self.port)
        print(f"WebSocket Position Server started on port {self.port}")
        await asyncio.Future()
    
    def run(self):
        """Esegue il server in un loop asyncio"""
        self.loop = asyncio.new_event_loop()
        asyncio.set_event_loop(self.loop)
        self.loop.run_until_complete(self.start_server())


# -----------------------------------------------------------------------------
# Thread WebSocket per le alert
# -----------------------------------------------------------------------------
class SWAPLWebSocketAlertServerThread(threading.Thread):
    
    def __init__(self, program, port=8081):
        super().__init__()
        self.program = program
        self.port = port
        self.ws_server = None
        self.setDaemon(True)
    
    def run(self):
        self.ws_server = SWAPLWebSocketAlertServer(self.program, self.port)
        self.ws_server.run()


# -----------------------------------------------------------------------------
# Thread  WebSocket per le posizioni
# -----------------------------------------------------------------------------
class SWAPLWebSocketPositionServerThread(threading.Thread):
    
    def __init__(self, program, port=9080):
        super().__init__()
        self.program = program
        self.port = port
        self.ws_server = None
        self.setDaemon(True)
    
    def run(self):
        self.ws_server = SWAPLWebSocketPositionServer(self.program, self.port)
        self.ws_server.run()

