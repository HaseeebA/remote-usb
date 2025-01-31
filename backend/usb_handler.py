import win32file
import win32pipe
import win32con
import asyncio
from typing import Dict
import logging
from ctypes import *
import re
import subprocess

logger = logging.getLogger(__name__)

# Add required DLL imports
setupapi = windll.setupapi
cfgmgr32 = windll.cfgmgr32

# Constants
DIGCF_PRESENT = 0x2
DIGCF_DEVICEINTERFACE = 0x10
DICS_FLAG_GLOBAL = 0x1
DIREG_DEV = 0x1
MAX_PATH = 260
ERROR_INSUFFICIENT_BUFFER = 122

class USBDeviceHandler:
    def __init__(self):
        self.active_connections: Dict[str, object] = {}
        self._ensure_usbip_tools()

    def _ensure_usbip_tools(self):
        """Ensure USB/IP tools are installed"""
        try:
            # Check if USB/IP tools are installed
            subprocess.run(['usbip', 'version'], check=True, capture_output=True)
        except Exception:
            logger.error("USB/IP tools not found. Please install USB/IP utilities.")
            
    def list_host_devices(self):
        """List available USB devices on host"""
        try:
            result = subprocess.run(['usbip', 'list', '-l'], capture_output=True, text=True)
            devices = []
            current_device = {}
            
            for line in result.stdout.split('\n'):
                if line.startswith('busid'):
                    if current_device:
                        devices.append(current_device)
                    current_device = {'id': line.split(':')[1].strip()}
                elif ':' in line:
                    key, value = line.split(':', 1)
                    current_device[key.strip()] = value.strip()
                    
            if current_device:
                devices.append(current_device)
            return devices
        except Exception as e:
            logger.error(f"Error listing devices: {e}")
            return []

    def bind_device(self, device_id: str):
        """Bind device to USB/IP driver on host"""
        try:
            subprocess.run(['usbip', 'bind', '-b', device_id], check=True)
            return True
        except Exception as e:
            logger.error(f"Error binding device {device_id}: {e}")
            return False

    def unbind_device(self, device_id: str):
        """Unbind device from USB/IP driver"""
        try:
            subprocess.run(['usbip', 'unbind', '-b', device_id], check=True)
            return True
        except Exception as e:
            logger.error(f"Error unbinding device {device_id}: {e}")
            return False

    def get_device_path(self, device_id: str) -> str:
        """Get the actual device path from device ID"""
        try:
            # Extract VID and PID
            vid_pid_match = re.search(r'VID_([0-9A-F]{4})&PID_([0-9A-F]{4})', device_id, re.IGNORECASE)
            if not vid_pid_match:
                return device_id

            vid, pid = vid_pid_match.groups()
            
            # Try different path formats
            paths = [
                f"\\\\.\\USB#{vid}#{pid}#",  # Generic USB format
                f"\\\\.\\USBSTOR#{vid}#{pid}#",  # USB storage format
                f"\\\\.\\{device_id}",  # Direct device ID
                device_id  # Original ID as fallback
            ]
            
            for path in paths:
                try:
                    handle = win32file.CreateFile(
                        path,
                        win32con.GENERIC_READ | win32con.GENERIC_WRITE,
                        win32con.FILE_SHARE_READ | win32con.FILE_SHARE_WRITE,
                        None,
                        win32con.OPEN_EXISTING,
                        win32con.FILE_ATTRIBUTE_NORMAL | win32con.FILE_FLAG_OVERLAPPED,
                        None
                    )
                    if handle != win32file.INVALID_HANDLE_VALUE:
                        win32file.CloseHandle(handle)
                        return path
                except:
                    continue

            return device_id

        except Exception as e:
            logger.error(f"Error getting device path: {e}")
            return device_id

    def connect_to_host_device(self, device_id: str):
        """Opens a direct connection to the physical USB device"""
        try:
            logger.info(f"Attempting to connect to device: {device_id}")
            device_path = self.get_device_path(device_id)
            logger.info(f"Using device path: {device_path}")

            # Try different sharing modes
            share_modes = [
                win32con.FILE_SHARE_READ | win32con.FILE_SHARE_WRITE,
                win32con.FILE_SHARE_READ,
                0
            ]

            for share_mode in share_modes:
                try:
                    handle = win32file.CreateFile(
                        device_path,
                        win32con.GENERIC_READ | win32con.GENERIC_WRITE,
                        share_mode,
                        None,
                        win32con.OPEN_EXISTING,
                        win32con.FILE_ATTRIBUTE_NORMAL | win32con.FILE_FLAG_OVERLAPPED,
                        None
                    )
                    
                    if handle != win32file.INVALID_HANDLE_VALUE:
                        logger.info(f"Successfully connected to device: {device_id}")
                        return handle
                except Exception as e:
                    logger.debug(f"Failed to open with share mode {share_mode}: {e}")
                    continue

            raise Exception("Could not open device with any share mode")

        except Exception as e:
            logger.error(f"Error connecting to host device: {e}")
            return None

    def create_virtual_device(self, device_id: str):
        """Creates a virtual USB interface that mirrors the host device"""
        try:
            # Use simpler pipe name format to avoid potential path issues
            safe_id = device_id.replace('\\', '_').replace('&', '_')
            pipe_name = f"\\\\.\\pipe\\usb_{safe_id}"
            
            pipe_handle = win32pipe.CreateNamedPipe(
                pipe_name,
                win32pipe.PIPE_ACCESS_DUPLEX,
                win32pipe.PIPE_TYPE_BYTE | win32pipe.PIPE_READMODE_BYTE | win32pipe.PIPE_WAIT,
                1, 65536, 65536, 0, None
            )
            return pipe_handle
        except Exception as e:
            logger.error(f"Error creating virtual device: {e}")
            return None

    async def start_device_forwarding(self, device_id: str, client_id: str):
        """Start USB/IP forwarding for device"""
        try:
            if self.bind_device(device_id):
                # Store connection info
                self.active_connections[client_id] = {
                    'device_id': device_id,
                    'active': True
                }
                return True
            return False
        except Exception as e:
            logger.error(f"Error starting forwarding: {e}")
            return False

    async def _forward_traffic(self, connection):
        """Handles the actual USB traffic forwarding"""
        buffer_size = 8192
        
        while connection['active']:
            try:
                # Read from host device
                result, data = win32file.ReadFile(connection['host_handle'], buffer_size)
                if result == 0:  # Success
                    # Write to virtual device
                    win32file.WriteFile(connection['virtual_device'], data)
                
                # Check for client data
                result, data = win32file.ReadFile(connection['virtual_device'], buffer_size)
                if result == 0:
                    # Write to host device
                    win32file.WriteFile(connection['host_handle'], data)
                
                await asyncio.sleep(0.001)  # Small delay to prevent CPU overload
            except Exception as e:
                print(f"Error in traffic forwarding: {e}")
                break

    def stop_device_forwarding(self, client_id: str):
        """Stop USB/IP forwarding"""
        if client_id in self.active_connections:
            connection = self.active_connections[client_id]
            device_id = connection['device_id']
            
            if self.unbind_device(device_id):
                del self.active_connections[client_id]
                return True
        return False
