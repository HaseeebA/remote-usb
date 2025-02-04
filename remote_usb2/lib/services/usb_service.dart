import 'package:flutter/services.dart';
import '../models/usb_device.dart';
import 'dart:async'; // Add this import

class USBService {
  static const _channel = MethodChannel('com.example.remote_usb/usb');
  final _deviceStream = StreamController<List<USBDevice>>.broadcast();

  Stream<List<USBDevice>> get deviceStream => _deviceStream.stream;

  Future<void> refreshDevices() async {
    try {
      final devices = await _channel.invokeMethod('getUsbDevices');
      _deviceStream.add(_parseDevices(devices));
    } on PlatformException catch (e) {
      print('Failed to refresh devices: ${e.message}');
    }
  }

  List<USBDevice> _parseDevices(dynamic data) {
    return (data as List).map((d) => USBDevice(
      id: d['id'],
      name: d['name'],
      description: d['description'],
    )).toList();
  }

  Future<bool> connectDevice(String deviceId) async {
    try {
      return await _channel.invokeMethod('connectDevice', {'deviceId': deviceId});
    } on PlatformException {
      return false;
    }
  }

  Future<void> disconnectDevice(String deviceId) async {
    await _channel.invokeMethod('disconnectDevice', {'deviceId': deviceId});
  }
}