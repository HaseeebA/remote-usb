import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'services/usb_service.dart';
import 'services/websocket_service.dart';
import 'models/usb_device.dart';
import 'dart:async';  // Add this import

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  await windowManager.setTitle('Remote USB Share');
  await windowManager.setMinimumSize(const Size(800, 600));
  
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Remote USB Share',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const ConnectionTypePage(),
    );
  }
}

class ConnectionTypePage extends StatelessWidget {
  const ConnectionTypePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Remote USB Share'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'Select Connection Type',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 40),
            ElevatedButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const HostPage()),
              ),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 50, vertical: 20),
              ),
              child: const Text('Host (Share USB Devices)'),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const ClientPage()),
              ),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 50, vertical: 20),
              ),
              child: const Text('Client (Connect to Shared Devices)'),
            ),
          ],
        ),
      ),
    );
  }
}

class HostPage extends StatefulWidget {
  const HostPage({super.key});

  @override
  State<HostPage> createState() => _HostPageState();
}

class _HostPageState extends State<HostPage> {
  final _usbService = USBService();
  final _wsService = WebSocketService();
  String connectionKey = '';
  List<USBDevice> usbDevices = [];
  StreamSubscription<dynamic>? _messageSubscription;  // Fix type declaration
  bool _disposed = false;

  void _onDeviceShareChanged(USBDevice device, bool? value) {
    setState(() {
      device.isShared = value!;
      // Send updated device list directly through TCP
      final sharedDevices = usbDevices
          .where((d) => d.isShared)
          .map((d) => d.toJson())
          .toList();
      print('Host: Sending device list update...');
      _wsService.sendDirectMessage({
        'type': 'device_list_update',
        'devices': sharedDevices,
      });
    });
  }

  Future<void> _handleDeviceRequest(String deviceId) async {
    if (!mounted) return;

    try {
      final success = await _wsService.startDeviceSharing(deviceId);
      if (!mounted) return;
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(
          success ? 'Started sharing device: $deviceId' : 'Failed to share device: $deviceId'
        )),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error sharing device: $e')),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    _generateNewKey();
    _refreshDevices();
    
    _usbService.deviceStream.listen((devices) {
      if (mounted) {
        setState(() => usbDevices = devices);
      }
    });

    _messageSubscription = _wsService.messageStream.listen((message) {
      print('Host received message: $message');
      if (!mounted) return;

      if (message['type'] == 'greeting') {
        print('Client connected: ${message['message']}');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Client connected: ${message['message']}')),
        );
      } else if (message['type'] == 'request_device') {
        _handleDeviceRequest(message['deviceId']);
      }
    });
  }

  void _refreshDevices() async {
    await _usbService.refreshDevices();
  }

  @override
  void dispose() {
    _disposed = true;
    _messageSubscription?.cancel();
    _wsService.disconnect();
    super.dispose();
  }

  void _generateNewKey() {
    // Generate a simple random key for now
    connectionKey = DateTime.now().millisecondsSinceEpoch.toString().substring(7);
    _wsService.connect(connectionKey, ConnectionMode.host);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Host - Share USB Devices'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refreshDevices,
            tooltip: 'Refresh USB Devices',
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    Text(
                      'Connection Key: $connectionKey',
                      style: const TextStyle(fontSize: 18),
                    ),
                    const SizedBox(width: 16),
                    ElevatedButton(
                      onPressed: _generateNewKey,
                      child: const Text('Generate New Key'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Available USB Devices:',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                StreamBuilder<ConnectionStatus>(
                  stream: _wsService.statusStream,
                  builder: (context, snapshot) {
                    final status = snapshot.data ?? ConnectionStatus.disconnected;
                    return Chip(
                      label: Text(status.toString().split('.').last),
                      backgroundColor: status == ConnectionStatus.connected
                          ? Colors.green[100]
                          : Colors.grey[300],
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 10),
            Expanded(
              child: ListView.builder(
                itemCount: usbDevices.length,
                itemBuilder: (context, index) {
                  final device = usbDevices[index];
                  return Card(
                    child: CheckboxListTile(
                      title: Text(device.name),
                      subtitle: Text(device.description),
                      value: device.isShared,
                      onChanged: (value) => _onDeviceShareChanged(device, value),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ClientPage extends StatefulWidget {
  const ClientPage({super.key});

  @override
  State<ClientPage> createState() => _ClientPageState();
}

class _ClientPageState extends State<ClientPage> {
  final _wsService = WebSocketService();
  final TextEditingController _keyController = TextEditingController();
  List<USBDevice> availableDevices = [];
  String? hostIP;
  int? hostPort;
  bool directlyConnected = false;

  @override
  void initState() {
    super.initState();
    _wsService.messageStream.listen((message) {
      print('Client received message type: ${message['type']}');
      if (message['type'] == 'host_info') {
        setState(() {
          hostIP = message['host_ip'];
          hostPort = message['host_port'];
        });
        // Attempt direct connection
        if (hostIP != null && hostPort != null) {
          _wsService.connectToHost(hostIP!, hostPort!).then((_) {
            setState(() => directlyConnected = true);
            _wsService.disconnect(); // Disconnect from WebSocket server
          });
        }
      } else if (message['type'] == 'device_list_update') {
        print('Received updated device list');
        setState(() {
          availableDevices = (message['devices'] as List)
              .map((d) => USBDevice.fromJson(d))
              .toList();
        });
      } else if (message['type'] == 'greeting_ack') {
        print('Host acknowledged connection: ${message['message']}');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message['message'])),
        );
      } else if (message['type'] == 'usb_data') {
        // Handle incoming USB data
        // This is where you would send the data to the virtual USB device
        print('Received USB data for device: ${message['deviceId']}');
      } else if (message['type'] == 'device_sharing_started') {
        final success = message['success'] ?? false;
        final deviceId = message['deviceId'];
        if (success) {
          print('Device sharing started successfully: $deviceId');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Connected to device: $deviceId')),
          );
        } else {
          print('Device sharing failed: ${message['error']}');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to connect: ${message['error']}')),
          );
        }
      }
    });
  }

  @override
  void dispose() {
    _wsService.disconnect();
    _keyController.dispose();
    super.dispose();
  }

  void _connectToHost() {
    if (_keyController.text.isNotEmpty) {
      _wsService.connect(_keyController.text, ConnectionMode.client);
    }
  }

  Future<void> _connectToDevice(USBDevice device) async {
    print('Initiating connection to device: ${device.id}');
    try {
      _wsService.sendDirectMessage({
        'type': 'request_device',
        'deviceId': device.id,
      });
      print('Connection request sent for device: ${device.id}');
    } catch (e) {
      print('Error requesting device connection: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Client - Connect to Shared Devices'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _keyController,
                        decoration: const InputDecoration(
                          labelText: 'Enter Connection Key',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    ElevatedButton(
                      onPressed: _connectToHost,
                      child: const Text('Connect'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            if (directlyConnected)
              Card(
                color: Colors.green[100],
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Text('Directly connected to host at $hostIP:$hostPort'),
                ),
              ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Available Remote Devices:',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                StreamBuilder<ConnectionStatus>(
                  stream: _wsService.statusStream,
                  builder: (context, snapshot) {
                    final status = snapshot.data ?? ConnectionStatus.disconnected;
                    return Chip(
                      label: Text(status.toString().split('.').last),
                      backgroundColor: status == ConnectionStatus.connected
                          ? Colors.green[100]
                          : Colors.grey[300],
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 10),
            Expanded(
              child: ListView.builder(
                itemCount: availableDevices.length,
                itemBuilder: (context, index) {
                  final device = availableDevices[index];
                  return Card(
                    child: ListTile(
                      title: Text(device.name),
                      subtitle: Text(device.description),
                      trailing: ElevatedButton(
                        onPressed: () => _connectToDevice(device), // Use the new method
                        child: const Text('Connect'),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
