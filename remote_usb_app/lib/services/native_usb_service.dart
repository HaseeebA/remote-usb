import 'package:flutter/services.dart';

class NativeUSBService {
  static const platform = MethodChannel('com.example.remote_usb/usb');
  
  Future<List<Map<String, dynamic>>> getDevices() async {
    try {
      final List<dynamic> result = await platform.invokeMethod('getUsbDevices');
      return List<Map<String, dynamic>>.from(result);
    } catch (e) {
      print('Error getting USB devices: $e');
      return [];
    }
  }

  Future<bool> connectDevice(String deviceId) async {
    try {
      return await platform.invokeMethod('connectDevice', {'deviceId': deviceId});
    } catch (e) {
      print('Error connecting device: $e');
      return false;
    }
  }

  Future<bool> disconnectDevice(String deviceId) async {
    try {
      return await platform.invokeMethod('disconnectDevice', {'deviceId': deviceId});
    } catch (e) {
      print('Error disconnecting device: $e');
      return false;
    }
  }
}
