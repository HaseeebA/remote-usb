# Remote USB Connect

A desktop application that enables sharing USB devices between computers over the network through a client-server architecture.

## Overview

Remote USB Connect allows you to use USB devices plugged into one computer (host) on another computer (client) remotely. The connection is facilitated through a cloud relay server for seamless connectivity between peers.

## Features

- Connect and use USB devices remotely between two computers
- Cloud relay server for reliable peer-to-peer connections
- Simple user interface for device sharing and connection management
- Secure socket-based communication
- Cross-platform support (Windows)

## How It Works

1. Host computer connects to the relay server and shares selected USB devices
2. Client computer connects to the relay server
3. Relay server facilitates the connection between host and client
4. Client can now use the shared USB devices as if they were connected locally

## Requirements

- Windows operating system
- Active internet connection
- USB devices to share
- Relay server credentials (provided during setup)

## Getting Started

1. Download and install the application
2. Launch the application
3. Choose to run as host or client
4. Follow the on-screen instructions to connect

## Security

All connections are encrypted and authenticated through the relay server. Only authorized peers can connect to shared devices.