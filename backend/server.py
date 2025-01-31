import asyncio
import websockets
from websockets.server import WebSocketServerProtocol  # Updated import
import json
import logging
from typing import Dict, Set
from usb_handler import USBDeviceHandler

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

class USBShareServer:
    def __init__(self):
        # Dictionary to store connections by key
        self.hosts: Dict[str, WebSocketServerProtocol] = {}  # Updated type hint
        self.clients: Dict[str, Set[WebSocketServerProtocol]] = {}  # Updated type hint
        self.device_lists: Dict[str, list] = {}
        # Add USB handler
        self.usb_handler = USBDeviceHandler()
        self.shared_devices: Dict[str, Set[str]] = {}  # key -> set of shared device IDs

    async def register_host(self, websocket: WebSocketServerProtocol, key: str):  # Updated type hint
        # Remove any existing host with the same key
        if key in self.hosts:
            old_host = self.hosts[key]
            await old_host.close()
            await self.unregister(old_host)
            
        self.hosts[key] = websocket
        self.clients[key] = set()
        self.device_lists[key] = []
        self.shared_devices[key] = set()
        
        # Initialize device list
        devices = self.usb_handler.list_host_devices()
        self.device_lists[key] = devices
        logger.info(f"Host registered with key: {key}")
        
        # Confirm registration to host
        await websocket.send(json.dumps({
            'type': 'registration_success',
            'message': 'Successfully registered as host',
            'devices': devices
        }))

    async def register_client(self, websocket: WebSocketServerProtocol, key: str):  # Updated type hint
        if key in self.hosts:
            self.clients[key].add(websocket)
            # Send success message to client
            await websocket.send(json.dumps({
                'type': 'registration_success',
                'message': 'Successfully connected to host'
            }))
            # Send current device list if available
            if self.device_lists[key]:
                await websocket.send(json.dumps({
                    'type': 'device_list',
                    'devices': self.device_lists[key]
                }))
            logger.info(f"Client connected to host with key: {key}")
            return True
        
        await websocket.send(json.dumps({
            'type': 'error',
            'message': 'Invalid connection key'
        }))
        return False

    async def unregister(self, websocket: WebSocketServerProtocol):  # Updated type hint
        # Remove from hosts
        for key, host in list(self.hosts.items()):
            if host == websocket:
                del self.hosts[key]
                del self.device_lists[key]
                del self.shared_devices[key]
                # Notify all clients of disconnection
                for client in self.clients[key]:
                    await client.send(json.dumps({'type': 'host_disconnected'}))
                del self.clients[key]
                logger.info(f"Host unregistered: {key}")
                return

        # Remove from clients
        for key, client_set in self.clients.items():
            if websocket in client_set:
                client_set.remove(websocket)
                logger.info(f"Client unregistered from key: {key}")
                return

    async def handle_connection(self, websocket: WebSocketServerProtocol):  # Updated type hint
        try:
            async for message in websocket:
                try:
                    data = json.loads(message)
                    message_type = data.get('type', '')
                    logger.info(f"Received message: {message_type}")
                    
                    if message_type == 'host_connect':
                        await self.register_host(websocket, data['key'])
                    
                    elif message_type == 'client_connect':
                        await self.register_client(websocket, data['key'])
                    
                    elif message_type == 'device_list_update':
                        if websocket in self.hosts.values():
                            key = next(k for k, v in self.hosts.items() if v == websocket)
                            self.device_lists[key] = data['devices']
                            logger.info(f"Updated device list for {key}: {data['devices']}")
                            for client in self.clients[key]:
                                await client.send(json.dumps({
                                    'type': 'device_list',
                                    'devices': data['devices']
                                }))
                    
                    elif message_type == 'connect_device':
                        key = data['key']
                        device_id = data['device_id']
                        client_id = str(id(websocket))
                        
                        if key in self.hosts:
                            # Start device forwarding
                            success = await self.usb_handler.start_device_forwarding(
                                device_id, client_id
                            )
                            
                            response = {
                                'type': 'device_connection_status',
                                'device_id': device_id,
                                'success': success
                            }
                            await websocket.send(json.dumps(response))
                            
                            if success:
                                logger.info(f"Device {device_id} connected for client {client_id}")
                            else:
                                logger.error(f"Failed to connect device {device_id}")
                    
                    elif message_type == 'disconnect_device':
                        client_id = str(id(websocket))
                        success = self.usb_handler.stop_device_forwarding(client_id)
                        await websocket.send(json.dumps({
                            'type': 'device_disconnected',
                            'success': success
                        }))

                    elif message_type == 'share_device':
                        # Host is sharing a device
                        key = data['key']
                        device_id = data['device_id']
                        if key in self.hosts and websocket == self.hosts[key]:
                            self.shared_devices[key].add(device_id)
                            # Notify clients of newly shared device
                            for client in self.clients[key]:
                                await client.send(json.dumps({
                                    'type': 'device_available',
                                    'device_id': device_id
                                }))

                    elif message_type == 'unshare_device':
                        # Host is unsharing a device
                        key = data['key']
                        device_id = data['device_id']
                        if key in self.hosts and websocket == self.hosts[key]:
                            self.shared_devices[key].remove(device_id)
                            # Notify clients
                            for client in self.clients[key]:
                                await client.send(json.dumps({
                                    'type': 'device_unavailable',
                                    'device_id': device_id
                                }))

                except json.JSONDecodeError:
                    logger.error(f"Invalid JSON received: {message}")
                except Exception as e:
                    logger.error(f"Error processing message: {e}")
                    
        except websockets.exceptions.ConnectionClosed:
            logger.info("Connection closed normally")
        except Exception as e:
            logger.error(f"Connection error: {e}")
        finally:
            await self.unregister(websocket)

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
