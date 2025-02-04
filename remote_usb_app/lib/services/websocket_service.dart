import 'dart:async';
import 'dart:convert';
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
        // Then connect to WebSocket and send port info
        _channel!.sink.add(jsonEncode({
          'type': 'host_connect',
          'key': key,
        }));

        // Ensure port is sent after connection is established
        await Future.delayed(const Duration(milliseconds: 100));
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

  Future<bool> startDeviceSharing(String deviceId) async {
    print('Starting device sharing via WebSocket...');
    if (_isSharing) {
      print('Error: Already sharing a device');
      return false;
    }

    // Connect to the device before starting to read data
    final connected = await _nativeUsbService.connectDevice(deviceId);
    if (!connected) {
      print('Error: Failed to connect to device');
      return false;
    }

    // Instead of direct USB bridging, just notify server:
    try {
      sendMessage({
        'type': 'start_usb_stream',
        'deviceId': deviceId,
      });
      _isSharing = true;
      _activeDeviceId = deviceId;

      // Start sending USB data periodically
      _nativeUsbService.usbDataStream(deviceId).listen((data) {
        sendMessage({
          'type': 'usb_data',
          'deviceId': deviceId,
          'data': base64Encode(data), // Send as base64
        });
      });

  return true;

      return true;
    } catch (e) {
      print('Error in startDeviceSharing: $e');
      return false;
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
      
      sendMessage({
        'type': 'device_sharing_stopped',
        'deviceId': deviceId,
      });
    } catch (e) {
      print('Error stopping device sharing: $e');
    }
  }

  void requestStopSharing(String deviceId) {
    // Client calls this to end sharing on host
    sendMessage({
      'type': 'stop_sharing',
      'deviceId': deviceId,
    });
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

  void disconnect() {
    stopDeviceSharing();

    _channel?.sink.close();
    _channel = null;
  }

  @override
  void dispose() {
    stopDeviceSharing();
    disconnect();
  }
}
