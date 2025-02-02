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
      print('NativeUSBService: Connecting to device $deviceId');
      final result = await platform.invokeMethod('connectDevice', {'deviceId': deviceId});
      print('NativeUSBService: Connect result: $result');
      return result == true;
    } catch (e) {
      print('NativeUSBService: Error connecting device: $e');
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

  Future<bool> writeData(String deviceId, List<int> data) async {
    try {
      return await platform.invokeMethod('writeDeviceData', {
        'deviceId': deviceId,
        'data': data,
      });
    } catch (e) {
      print('Error writing device data: $e');
      return false;
    }
  }

  Future<List<int>?> readDeviceData(String deviceId) async {
    try {
      final result = await platform.invokeMethod('readDeviceData', {
        'deviceId': deviceId,
      });
      if (result != null) {
        print('NativeUSBService: Read ${List<int>.from(result).length} bytes');
      }
      return result != null ? List<int>.from(result) : null;
    } catch (e) {
      print('NativeUSBService: Error reading device data: $e');
      return null;
    }
  }
}
