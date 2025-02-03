import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'native_usb_service.dart';  // Add this import

enum ConnectionMode { host, client }
enum ConnectionStatus { disconnected, connecting, connected, error }

class WebSocketService {
  static final WebSocketService _instance = WebSocketService._internal();
  factory WebSocketService() => _instance;
  WebSocketService._internal();

  WebSocketChannel? _channel;
  final _messageController = StreamController<dynamic>.broadcast();
  Stream<dynamic> get messageStream => _messageController.stream;

  ConnectionStatus _status = ConnectionStatus.disconnected;
  ConnectionStatus get status => _status;
  final _statusController = StreamController<ConnectionStatus>.broadcast();
  Stream<ConnectionStatus> get statusStream => _statusController.stream;

  ServerSocket? _tcpServer;
  Socket? _tcpConnection;
  int? _listeningPort;

  final _nativeUsbService = NativeUSBService();
  bool _isSharing = false;
  String? _activeDeviceId;  // Track currently shared device ID

  Future<void> connect(String key, ConnectionMode mode) async {
    disconnect(); // Close any existing connection
    _status = ConnectionStatus.connecting;
    _statusController.add(_status);
    
    try {
      // Make sure to use the wss:// protocol and remove any path components
      final wsUrl = Uri.parse('ws://134.209.86.113:8765');
      print('Connecting to WebSocket at: $wsUrl');
      
      _channel = WebSocketChannel.connect(wsUrl);
      await _channel!.ready;

      if (mode == ConnectionMode.host) {
        // Start TCP server first
        await startHosting();
        
        // Then connect to WebSocket and send port info
        _channel!.sink.add(jsonEncode({
          'type': 'host_connect',
          'key': key,
        }));

        // Ensure port is sent after connection is established
        await Future.delayed(const Duration(milliseconds: 100));
        print('Sending TCP port to server: $_listeningPort');
        _channel!.sink.add(jsonEncode({
          'type': 'host_port_update',
          'port': _listeningPort,
        }));
      } else {
        // Client connection
        _channel!.sink.add(jsonEncode({
          'type': 'client_connect',
          'key': key,
        }));
      }

      // Set up message listener
      _channel!.stream.listen(
        (message) {
          try {
            final data = jsonDecode(message.toString());
            print('Received WebSocket message: $data');
            
            if (data['type'] == 'error') {
              _status = ConnectionStatus.error;
              print('Connection error: ${data['message']}');
            } else {
              _status = ConnectionStatus.connected;
            }
            _statusController.add(_status);
            _messageController.add(data);
          } catch (e) {
            print('Error processing message: $e');
          }
        },
        onError: (error) {
          print('WebSocket error: $error');
          _status = ConnectionStatus.error;
          _statusController.add(_status);
        },
        onDone: () {
          print('WebSocket connection closed');
          _status = ConnectionStatus.disconnected;
          _statusController.add(_status);
        },
      );
    } catch (e) {
      print('WebSocket connection error: $e');
      _status = ConnectionStatus.error;
      _statusController.add(_status);
      rethrow;
    }
  }

  Future<void> startHosting() async {
    try {
      _tcpServer = await ServerSocket.bind(InternetAddress.anyIPv4, 0);
      _listeningPort = _tcpServer!.port;
      print('TCP Server started on port: $_listeningPort');
      
      _tcpServer!.listen((Socket socket) {
        print('Client connected from: ${socket.remoteAddress}:${socket.remotePort}');
        _tcpConnection = socket;
        
        // Send immediate acknowledgment to client
        sendDirectMessage({
          'type': 'greeting_ack',
          'message': 'Host acknowledges connection'
        });
        
        socket.listen(
          (data) {
            try {
              // Split messages in case multiple are received together
              final messages = utf8.decode(data).split('\n');
              for (var msg in messages) {
                if (msg.trim().isEmpty) continue;
                final jsonData = jsonDecode(msg.trim());
                print('Host received TCP message: $jsonData');
                _messageController.add(jsonData);
              }
            } catch (e) {
              print('Error processing TCP message: $e');
            }
          },
          onError: (error) => print('TCP Error: $error'),
          onDone: () {
            print('Client disconnected');
            _tcpConnection = null;
          },
        );
      });
    } catch (e) {
      print('Error starting TCP server: $e');
      rethrow;  // Propagate error so connect() knows it failed
    }
  }

  Future<void> connectToHost(String ip, int port) async {
    try {
      _tcpConnection = await Socket.connect(ip, port);
      print('Connected to host at $ip:$port');
      
      // Send initial greeting right after connection
      await Future.delayed(const Duration(milliseconds: 100));
      sendDirectMessage({
        'type': 'greeting',
        'message': 'Client connected directly!'
      });
      
      _tcpConnection!.listen(
        (data) {
          try {
            // Split messages in case multiple are received together
            final messages = utf8.decode(data).split('\n');
            for (var msg in messages) {
              if (msg.trim().isEmpty) continue;
              final jsonData = jsonDecode(msg.trim());
              print('Client received TCP message: $jsonData');
              _messageController.add(jsonData);
            }
          } catch (e) {
            print('Error processing TCP message: $e');
          }
        },
        onError: (error) => print('TCP Error: $error'),
        onDone: () {
          print('Disconnected from host');
          _tcpConnection = null;
        },
      );
    } catch (e) {
      print('Error connecting to host: $e');
    }
  }

  Future<bool> connectToDevice(String deviceId, String key) async {
    if (_status != ConnectionStatus.connected) return false;
    
    try {
      final completer = Completer<bool>();
      
      // One-time listener for the connection response
      late StreamSubscription subscription;
      subscription = _messageController.stream.listen((message) {
        if (message['type'] == 'device_connection_status' &&
            message['device_id'] == deviceId) {
          completer.complete(message['success'] as bool);
          subscription.cancel();
        }
      });

      // Send connection request
      sendMessage({
        'type': 'connect_device',
        'device_id': deviceId,
        'key': key,
      });

      return await completer.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          subscription.cancel();
          return false;
        },
      );
    } catch (e) {
      print('Error connecting to device: $e');
      return false;
    }
  }

  Future<bool> startDeviceSharing(String deviceId) async {
    print('Starting device sharing process...');
    if (_tcpConnection == null) {
      print('Error: No TCP connection available');
      return false;
    }
    if (_isSharing) {
      print('Error: Already sharing a device');
      return false;
    }

    try {
      print('Attempting to connect to device: $deviceId');
      final success = await _nativeUsbService.connectDevice(deviceId);
      print('Native USB connect result: $success');

      if (success) {
        _isSharing = true;
        _activeDeviceId = deviceId;
        print('Device sharing started successfully');
        
        // Notify client
        sendDirectMessage({
          'type': 'device_sharing_started',
          'deviceId': deviceId,
          'success': true,
        });

        // Start the data forwarding
        _startUsbDataForwarding(deviceId);
        return true;
      } else {
        print('Failed to connect to device');
        sendDirectMessage({
          'type': 'device_sharing_started',
          'deviceId': deviceId,
          'success': false,
          'error': 'Failed to connect to device',
        });
        return false;
      }
    } catch (e) {
      print('Error in startDeviceSharing: $e');
      sendDirectMessage({
        'type': 'device_sharing_started',
        'deviceId': deviceId,
        'success': false,
        'error': e.toString(),
      });
      return false;
    }
  }

  void _startUsbDataForwarding(String deviceId) {
    print('Starting USB data forwarding for device: $deviceId');
    Timer.periodic(const Duration(milliseconds: 16), (timer) async {
      if (!_isSharing || _tcpConnection == null) {
        print('Stopping USB forwarding: sharing=$_isSharing, connection=${_tcpConnection != null}');
        timer.cancel();
        return;
      }

      try {
        final data = await _nativeUsbService.readDeviceData(deviceId);
        if (data != null && data.isNotEmpty) {
          print('Read ${data.length} bytes from device');
          sendDirectMessage({
            'type': 'usb_data',
            'deviceId': deviceId,
            'data': data,
          });
        }
      } catch (e) {
        print('Error in USB forwarding: $e');
        timer.cancel();
      }
    });
  }

  Future<bool> sendDeviceData(String deviceId, List<int> data) async {
    // Use native USB service instead of _usbStream
    try {
      return await _nativeUsbService.writeData(deviceId, data);
    } catch (e) {
      print('Error sending device data: $e');
      return false;
    }
  }

  void stopDeviceSharing() {
    if (!_isSharing || _activeDeviceId == null) return;
    
    try {
      _nativeUsbService.disconnectDevice(_activeDeviceId!);
      final deviceId = _activeDeviceId;  // Store for message
      _isSharing = false;
      _activeDeviceId = null;
      
      sendDirectMessage({
        'type': 'device_sharing_stopped',
        'deviceId': deviceId,
      });
    } catch (e) {
      print('Error stopping device sharing: $e');
    }
  }

  void disconnectDevice() {
    sendMessage({'type': 'disconnect_device'});
  }

  void sendMessage(Map<String, dynamic> message) {
    if (_status == ConnectionStatus.connected) {
      try {
        _channel?.sink.add(jsonEncode(message));
      } catch (e) {
        print('Error sending message: $e');
      }
    }
  }

  void sendDirectMessage(Map<String, dynamic> message) {
    if (_tcpConnection != null) {
      try {
        final jsonStr = '${jsonEncode(message)}\n';
        print('Sending direct message: $jsonStr');
        _tcpConnection!.write(jsonStr);
        _tcpConnection!.flush();
      } catch (e) {
        print('Error sending direct message: $e');
      }
    } else {
      print('Cannot send message: no TCP connection');
    }
  }

  void _checkConnectionState() {
    if (_tcpConnection != null) {
      _tcpConnection!.done.then((closed) {
        if (closed) {
          _tcpConnection = null;
        }
      }).catchError((e) {
        print('Error checking connection state: $e');
        _tcpConnection = null;
      });
    }
  }

  void updateDeviceList(List<Map<String, dynamic>> devices) {
    if (_tcpConnection != null) {
      try {
        final message = {
          'type': 'device_list_update',
          'devices': devices,
        };
        print('Host sending device list through TCP: $message');
        sendDirectMessage(message);
      } catch (e) {
        print('Error updating device list: $e');
      }
    }
  }

  void disconnect() {
    stopDeviceSharing();
    
    if (_tcpConnection != null) {
      _tcpConnection!.close().then((_) {
        _tcpConnection = null;
      });
    }

    _channel?.sink.close();
    _channel = null;
    
    if (_tcpServer != null) {
      _tcpServer!.close().then((_) {
        _tcpServer = null;
      });
    }
  }

  @override
  void dispose() {
    stopDeviceSharing();
    disconnect();
  }
}
