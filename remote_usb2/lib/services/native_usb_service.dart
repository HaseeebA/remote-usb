import 'package:flutter/services.dart';

class NativeUSBService {
  static const _channel = MethodChannel('com.example.remote_usb/usb');

  Future<List<int>?> readDeviceData(String deviceId) async {
    try {
      final data = await _channel.invokeMethod('readDeviceData', {'deviceId': deviceId});
      return List<int>.from(data);
    } on PlatformException {
      return null;
    }
  }

  Future<bool> writeData(String deviceId, List<int> data) async {
    try {
      return await _channel.invokeMethod('writeDeviceData', {
        'deviceId': deviceId,
        'data': data,
      });
    } on PlatformException {
      return false;
    }
  }
}