import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';

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

  Future<void> connect(String key, ConnectionMode mode) async {
    disconnect(); // Close any existing connection
    _status = ConnectionStatus.connecting;
    _statusController.add(_status);
    
    try {
      // Make sure to use the wss:// protocol and remove any path components
      final wsUrl = Uri.parse('ws://localhost:8765');
      print('Connecting to WebSocket at: $wsUrl');
      
      _channel = WebSocketChannel.connect(wsUrl,
        // Add protocols if needed
        protocols: ['wss'],
      );
      
      // Wait for connection
      await _channel!.ready;
      
      // Send initial connection message
      _channel!.sink.add(jsonEncode({
        'type': mode == ConnectionMode.host ? 'host_connect' : 'client_connect',
        'key': key,
      }));

      _channel!.stream.listen(
        (message) {
          try {
            final data = jsonDecode(message.toString());
            print('Received WebSocket message: $data'); // Debug log
            
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

  void updateDeviceList(List<Map<String, dynamic>> devices) {
    if (_status == ConnectionStatus.connected) {
      try {
        final message = {
          'type': 'device_list_update',
          'devices': devices,
        };
        print('Sending device list update: $message'); // Debug log
        _channel?.sink.add(jsonEncode(message));
      } catch (e) {
        print('Error updating device list: $e');
      }
    }
  }

  void disconnect() {
    _channel?.sink.close();
    _channel = null;
  }
}
