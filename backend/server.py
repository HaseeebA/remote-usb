import asyncio
import websockets
from websockets.server import WebSocketServerProtocol
import json
import logging
from typing import Dict, Set

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

class USBShareServer:
    def __init__(self):
        self.hosts: Dict[str, Dict] = {}  # key -> {websocket, ip, port}
        self.clients: Dict[str, Set[WebSocketServerProtocol]] = {}

    async def register_host(self, websocket: WebSocketServerProtocol, key: str):
        # Get client address
        client_address = websocket.remote_address
        host_ip = client_address[0]
        
        if key in self.hosts:
            old_host = self.hosts[key]['websocket']
            await old_host.close()
            
        self.hosts[key] = {
            'websocket': websocket,
            'ip': host_ip,
            'port': None  # Will be set when host sends port info
        }
        self.clients[key] = set()
        
        logger.info(f"Host registered with key: {key} at {host_ip}")
        await websocket.send(json.dumps({
            'type': 'registration_success',
            'message': 'Successfully registered as host'
        }))

    async def register_client(self, websocket: WebSocketServerProtocol, key: str):
        if key in self.hosts:
            self.clients[key].add(websocket)
            host_info = self.hosts[key]
            # Send host connection info to client
            await websocket.send(json.dumps({
                'type': 'host_info',
                'host_ip': host_info['ip'],
                'host_port': host_info['port']
            }))
            logger.info(f"Client connected to host with key: {key}")
            return True
        
        await websocket.send(json.dumps({
            'type': 'error',
            'message': 'Invalid connection key'
        }))
        return False

    async def handle_connection(self, websocket: WebSocketServerProtocol):
        try:
            async for message in websocket:
                try:
                    data = json.loads(message)
                    message_type = data.get('type', '')
                    logger.info(f"Received message: {message_type}")
                    
                    if message_type == 'host_connect':
                        await self.register_host(websocket, data['key'])
                    
                    elif message_type == 'host_port_update':
                        # Update host's TCP port
                        key = next(k for k, v in self.hosts.items() 
                                 if v['websocket'] == websocket)
                        port = data.get('port')
                        logger.info(f"Updating host {key} TCP port to: {port}")
                        self.hosts[key]['port'] = port
                        
                        # Notify any already connected clients
                        for client in self.clients.get(key, set()):
                            await client.send(json.dumps({
                                'type': 'host_info',
                                'host_ip': self.hosts[key]['ip'],
                                'host_port': port
                            }))
                    
                    elif message_type == 'client_connect':
                        await self.register_client(websocket, data['key'])

                except json.JSONDecodeError:
                    logger.error(f"Invalid JSON received: {message}")
                except Exception as e:
                    logger.error(f"Error processing message: {e}")
                    logger.exception(e)
                    
        except websockets.exceptions.ConnectionClosed:
            logger.info("Connection closed normally")
        finally:
            # Clean up connections
            for key, host in list(self.hosts.items()):
                if host['websocket'] == websocket:
                    del self.hosts[key]
                    if key in self.clients:
                        for client in self.clients[key]:
                            await client.send(json.dumps({'type': 'host_disconnected'}))
                        del self.clients[key]
                    break
            
            for key, client_set in self.clients.items():
                if websocket in client_set:
                    client_set.remove(websocket)

async def main():
    server = USBShareServer()
    # Listen on all interfaces (0.0.0.0) to allow external connections
    async with websockets.serve(
        server.handle_connection,
        "0.0.0.0",  # Changed from 127.0.0.1 to accept all connections
        8765,
        # Add ping/pong settings to keep connection alive
        ping_interval=20,
        ping_timeout=20
    ):
        logger.info("Server started on ws://0.0.0.0:8765")
        await asyncio.Future()

if __name__ == "__main__":
    asyncio.run(main())
