import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:flutter/material.dart';
import '../models/connection_status.dart';
import 'dart:async';
import 'dart:convert'; // For jsonEncode/jsonDecode

class WebSocketService {
  WebSocketChannel? _channel;
  final _messageController = StreamController<dynamic>.broadcast();
final _statusController = StreamController<ConnectionStatus>.broadcast();
  ConnectionStatus _status = ConnectionStatus.disconnected;

  Stream<dynamic> get messageStream => _messageController.stream;
  Stream<ConnectionStatus> get statusStream => _statusController.stream;

  Future<void> connect(String key, ConnectionMode mode) async {
    final isHost = mode == ConnectionMode.host;
    disconnect();
    _updateStatus(ConnectionStatus.connecting);
    
    try {
      _channel = WebSocketChannel.connect(Uri.parse('ws://134.209.86.113:8765'));
      await _channel!.ready;

      _channel!.sink.add(jsonEncode({
        'type': isHost ? 'host_connect' : 'client_connect',
        'key': key,
      }));

      _channel!.stream.listen(
        (message) => _handleMessage(message),
        onError: (error) => _updateStatus(ConnectionStatus.error),
        onDone: () => _updateStatus(ConnectionStatus.disconnected),
      );
    } catch (e) {
      _updateStatus(ConnectionStatus.error);
      rethrow;
    }
  }

  Future<bool> startDeviceSharing(String deviceId) async {
    sendMessage({
      'type': 'start_usb_stream',
      'deviceId': deviceId,
    });
    return true;
  }

  void stopDeviceSharing() {
    sendMessage({'type': 'stop_sharing'});
  }

  Future<bool> sendDeviceData(String deviceId, List<int> data) async {
    sendMessage({
      'type': 'usb_data',
      'deviceId': deviceId,
      'data': data,
    });
    return true;
  }

  void requestStopSharing(String deviceId) {
    sendMessage({
      'type': 'stop_sharing',
      'deviceId': deviceId,
    });
  }

  void _handleMessage(dynamic message) {
    try {
      final data = jsonDecode(message);
      _messageController.add(data);
      _updateStatus(ConnectionStatus.connected);
    } catch (e) {
      debugPrint('WebSocket message error: $e');
    }
  }

  void _updateStatus(ConnectionStatus status) {
    _status = status;
    _statusController.add(status);
  }

  void sendMessage(Map<String, dynamic> message) {
    if (_status == ConnectionStatus.connected) {
      _channel?.sink.add(jsonEncode(message));
    }
  }

  void disconnect() {
    _channel?.sink.close();
    _updateStatus(ConnectionStatus.disconnected);
  }
}