import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'services/usb_service.dart';
import 'services/websocket_service.dart';
import 'models/usb_device.dart';

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

  void _onDeviceShareChanged(USBDevice device, bool? value) {
    setState(() {
      device.isShared = value!;
      // Send updated device list to server immediately
      final sharedDevices = usbDevices
          .where((d) => d.isShared)
          .map((d) => d.toJson())
          .toList();
      print('Sending updated device list: $sharedDevices'); // Debug log
      _wsService.updateDeviceList(sharedDevices);
    });
  }

  @override
  void initState() {
    super.initState();
    _generateNewKey();
    _refreshDevices();
    
    // Only listen for initial device detection
    _usbService.deviceStream.listen((devices) {
      setState(() => usbDevices = devices);
    });
  }

  void _refreshDevices() async {
    await _usbService.refreshDevices();
  }

  @override
  void dispose() {
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

  @override
  void initState() {
    super.initState();
    _wsService.messageStream.listen((message) {
      if (message['type'] == 'device_list') {
        setState(() {
          availableDevices = (message['devices'] as List)
              .map((d) => USBDevice.fromJson(d))
              .toList();
        });
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
                        onPressed: () async {
                          final success = await _wsService.connectToDevice(
                            device.id,
                            _keyController.text,
                          );
                          if (success) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Device connected successfully')),
                            );
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Failed to connect to device')),
                            );
                          }
                        },
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
