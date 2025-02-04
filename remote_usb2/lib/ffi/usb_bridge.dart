import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'dart:async';


final DynamicLibrary _nativeUsbLib = DynamicLibrary.open('usb_bridge.dll');

class USBBridge {
  final _getDevices = _nativeUsbLib.lookupFunction<
    Pointer<Utf8> Function(Pointer<Int32>),
    Pointer<Utf8> Function(Pointer<Int32>)
  >('get_usb_devices');

  List<String> getDevices() {
    final count = calloc<Int32>();
    try {
      final ptr = _getDevices(count);
      return ptr.decodeUtf8().split(';').take(count.value).toList();
    } finally {
      calloc.free(count);
    }
  }
}