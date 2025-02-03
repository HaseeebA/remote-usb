import 'dart:async';
import 'package:flutter/services.dart';

class USBDeviceStream {
  static const MethodChannel _channel =
      MethodChannel('com.example.remote_usb/usb');

  static final USBDeviceStream _instance = USBDeviceStream._internal();
  factory USBDeviceStream() => _instance;
  USBDeviceStream._internal();

  final StreamController<List<int>> _dataStreamController =
      StreamController<List<int>>.broadcast();

  // Expose the stream of USB data.
  Stream<List<int>> get dataStream => _dataStreamController.stream;

  // Initialize listener for incoming USB data.
  void initialize() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'usb_data') {
        final List<dynamic> dataDynamic = call.arguments as List<dynamic>;
        final List<int> data = dataDynamic.cast<int>();
        _dataStreamController.add(data);
      }
    });
  }

  // For host: Connect to USB device.
  Future<bool> hostConnect(String deviceId) async {
    try {
      final result = await _channel.invokeMethod('host_connect', <String, dynamic>{
        'deviceId': deviceId,
      });
      return result as bool;
    } catch (e) {
      print('hostConnect error: $e');
      return false;
    }
  }

  // For host: Write USB data.
  Future<bool> writeUsbData(List<int> data) async {
    try {
      final result = await _channel.invokeMethod(
          'write_usb_data', <String, dynamic>{'data': data});
      return result as bool;
    } catch (e) {
      print('writeUsbData error: $e');
      return false;
    }
  }

  // For cleanup, if needed.
  void dispose() {
    _dataStreamController.close();
  }
}
