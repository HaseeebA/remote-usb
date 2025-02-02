import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';

typedef UsbOpenFunc = Pointer Function(Pointer<Utf8> devicePath);
typedef UsbReadFunc = Int32 Function(Pointer handle, Pointer<Uint8> buffer, Int32 length);
typedef UsbWriteFunc = Int32 Function(Pointer handle, Pointer<Uint8> buffer, Int32 length);

class USBDeviceStream {
  static final DynamicLibrary _nativeLib = Platform.isWindows
      ? DynamicLibrary.open('usb_bridge.dll')
      : DynamicLibrary.open('libusb_bridge.so');

  final _usbOpen = _nativeLib.lookupFunction<UsbOpenFunc, UsbOpenFunc>('usb_open');
  final _usbRead = _nativeLib.lookupFunction<UsbReadFunc, UsbReadFunc>('usb_read');
  final _usbWrite = _nativeLib.lookupFunction<UsbWriteFunc, UsbWriteFunc>('usb_write');

  Pointer? _deviceHandle;
  StreamController<List<int>>? _dataStreamController;
  bool _isStreaming = false;

  Stream<List<int>>? get dataStream => _dataStreamController?.stream;

  Future<bool> startStreaming(String devicePath) async {
    if (_isStreaming) return false;

    try {
      final pathPointer = devicePath.toNativeUtf8();
      _deviceHandle = _usbOpen(pathPointer);
      malloc.free(pathPointer);

      if (_deviceHandle == null || _deviceHandle == nullptr) {
        return false;
      }

      _dataStreamController = StreamController<List<int>>.broadcast();
      _isStreaming = true;

      // Start reading data
      _startReading();
      return true;
    } catch (e) {
      print('Error starting USB stream: $e');
      return false;
    }
  }

  void _startReading() async {
    const bufferSize = 1024;
    final buffer = calloc<Uint8>(bufferSize);

    while (_isStreaming) {
      try {
        final bytesRead = _usbRead(_deviceHandle!, buffer, bufferSize);
        if (bytesRead > 0) {
          final data = List<int>.generate(
              bytesRead, (i) => buffer.elementAt(i).value);
          _dataStreamController?.add(data);
        }
        await Future.delayed(const Duration(milliseconds: 1));
      } catch (e) {
        print('Error reading USB data: $e');
        break;
      }
    }

    calloc.free(buffer);
  }

  Future<bool> writeData(List<int> data) async {
    if (!_isStreaming) return false;

    try {
      final buffer = calloc<Uint8>(data.length);
      for (var i = 0; i < data.length; i++) {
        buffer[i] = data[i];
      }

      final bytesWritten = _usbWrite(_deviceHandle!, buffer, data.length);
      calloc.free(buffer);

      return bytesWritten == data.length;
    } catch (e) {
      print('Error writing USB data: $e');
      return false;
    }
  }

  void stopStreaming() {
    _isStreaming = false;
    _dataStreamController?.close();
    _dataStreamController = null;
    // Clean up native resources
    if (_deviceHandle != null) {
      // Add cleanup call to native library here
      _deviceHandle = null;
    }
  }
}
