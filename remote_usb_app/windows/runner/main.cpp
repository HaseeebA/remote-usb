#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>
#include <flutter/method_result_functions.h>
#include <flutter/standard_method_codec.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/encodable_value.h>
#include <windows.h>
#include <winusb.h>
#include <setupapi.h>
#include <memory>
#include <iostream>
#include <vector>

#include "flutter_window.h"
#include "utils.h"

// Add WinUSB GUID
DEFINE_GUID(GUID_DEVINTERFACE_USB_DEVICE, 0xA5DCBF10L, 0x6530, 0x11D2, 0x90, 0x1F, 0x00, \
    0xC0, 0x4F, 0xB9, 0x51, 0xED);

// Forward declarations from usb_bridge.cpp
extern "C" {
    __declspec(dllimport) HANDLE __stdcall openDevice(const char* devicePath);
    __declspec(dllimport) int __stdcall readDevice(HANDLE handle, BYTE* buffer, int length);
    // __declspec(dllimport) int __stdcall writeDevice(HANDLE handle, BYTE* buffer, int length);
}

// Global device handle (initialized to INVALID_HANDLE_VALUE)
static HANDLE g_deviceHandle = INVALID_HANDLE_VALUE;

// Forward declaration
class FlutterWindow;

// Global method channel
std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> method_channel;

void RegisterMethodChannel(flutter::FlutterEngine* engine) {
    auto channel = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
        engine->messenger(),
        "com.example.remote_usb/usb",
        &flutter::StandardMethodCodec::GetInstance()
    );

    channel->SetMethodCallHandler(
        [](const auto& call, auto result) {
            if (call.method_name() == "connectDevice") {
                try {
                    const auto* arguments = std::get_if<flutter::EncodableMap>(call.arguments());
                    if (!arguments) {
                        result->Error("INVALID_ARGUMENTS", "Arguments must be a map");
                        return;
                    }

                    auto device_id_it = arguments->find(flutter::EncodableValue("deviceId"));
                    if (device_id_it == arguments->end()) {
                        result->Error("INVALID_ARGUMENTS", "deviceId is required");
                        return;
                    }

                    const auto& device_id = std::get<std::string>(device_id_it->second);
                    std::cout << "Attempting to connect to device: " << device_id << std::endl;

                    // Call the native usb_bridge's openDevice function.
                    g_deviceHandle = openDevice(device_id.c_str());
                    if (g_deviceHandle == INVALID_HANDLE_VALUE) {
                        result->Error("CONNECT_ERROR", "Failed to open device");
                        return;
                    }
                    result->Success(flutter::EncodableValue(true));
                } catch (const std::exception& e) {
                    result->Error("CONNECT_ERROR", e.what());
                }
            } else if (call.method_name() == "readDeviceData") {
                // Read device data using usb_bridge's readDevice functionality.
                if (g_deviceHandle == INVALID_HANDLE_VALUE) {
                    result->Error("DEVICE_NOT_CONNECTED", "No device connected");
                    return;
                }
                const int bufferSize = 1024;
                BYTE* buffer = new BYTE[bufferSize];
                int bytesRead = readDevice(g_deviceHandle, buffer, bufferSize);
                
                if (bytesRead <= 0) {
                    delete[] buffer;
                    result->Error("READ_ERROR", "Failed to read data or no data available");
                    return;
                }
                // Build an EncodableList for the read bytes.
                std::vector<flutter::EncodableValue> dataList;
                for (int i = 0; i < bytesRead; i++) {
                    dataList.push_back(flutter::EncodableValue(static_cast<int>(buffer[i])));
                }
                delete[] buffer;
                result->Success(flutter::EncodableValue(dataList));
            } else {
                result->NotImplemented();
            }
        }
    );

    method_channel = std::move(channel);
}

int APIENTRY wWinMain(HINSTANCE instance, HINSTANCE prev,
                      wchar_t *command_line, int show_command) {
  // Removed unused variable "hwnd" to eliminate warning
  // HWND hwnd = nullptr;

  flutter::DartProject project(L"data");
  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"Remote USB Share", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  RegisterMethodChannel(window.GetController()->engine());

  MSG msg;
  while (GetMessage(&msg, nullptr, 0, 0)) {
    TranslateMessage(&msg);
    DispatchMessage(&msg);
  }

  return EXIT_SUCCESS;
}
