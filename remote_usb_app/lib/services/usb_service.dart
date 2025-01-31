import 'dart:async';
import 'dart:io';
import 'dart:convert';
import '../models/usb_device.dart';

class USBService {
  static final USBService _instance = USBService._internal();
  factory USBService() => _instance;
  USBService._internal();

  final _deviceController = StreamController<List<USBDevice>>.broadcast();
  Stream<List<USBDevice>> get deviceStream => _deviceController.stream;

  // Function to manually refresh devices
  Future<void> refreshDevices() async {
    final devices = await detectDevices();
    _deviceController.add(devices);
  }

  Future<List<USBDevice>> detectDevices() async {
    try {
      if (Platform.isWindows) {
        const command = r'''
        Get-PnpDevice | Where-Object {
          ($_.Class -eq 'USB' -or $_.Class -eq 'USBDevice' -or $_.Class -eq 'USBHub' -or $_.Class -eq 'DiskDrive' -or $_.Class -eq 'USBSTOR') -and
          $_.Status -eq 'OK'
        } | Select-Object -Property InstanceId, FriendlyName, Class, Status, Present, Description |
        ConvertTo-Json -Depth 5
        ''';

        final result = await Process.run('powershell', ['-Command', command]);

        if (result.exitCode == 0 && result.stdout.toString().isNotEmpty) {
          try {
            final List<dynamic> deviceList = json.decode(result.stdout.toString());
            final List<USBDevice> devices = deviceList
                .where((device) => 
                    device['FriendlyName'] != null && 
                    !device['FriendlyName'].toString().toLowerCase().contains('root hub'))
                .map((device) => USBDevice(
                      id: device['InstanceId'] ?? '',
                      name: device['FriendlyName'] ?? 'Unknown Device',
                      description: '${device['Description'] ?? ''}\nClass: ${device['Class']}, Status: ${device['Status']}',
                    ))
                .toList();

            return devices;
          } catch (e) {
            print('Error parsing USB devices: $e');
          }
        }
      }
    } catch (e) {
      print('Error detecting USB devices: $e');
    }
    return [];
  }
}
