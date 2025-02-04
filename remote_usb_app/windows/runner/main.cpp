#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif

#include <winsock2.h>
#include <ws2tcpip.h>
#include <windows.h>

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>
#include <flutter/method_result_functions.h>
#include <flutter/standard_method_codec.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/encodable_value.h>
#include <winusb.h>
#include <setupapi.h>
#include <memory>
#include <iostream>
#include <vector>
#include <thread>
#include <chrono>

#include "flutter_window.h"
#include "utils.h"

// Add WinUSB GUID
DEFINE_GUID(GUID_DEVINTERFACE_USB_DEVICE, 0xA5DCBF10L, 0x6530, 0x11D2, 0x90, 0x1F, 0x00, \
    0xC0, 0x4F, 0xB9, 0x51, 0xED);

// Forward declarations from usb_bridge.cpp
extern "C" {
    __declspec(dllimport) HANDLE __stdcall openDevice(const char* devicePath);
    __declspec(dllimport) int __stdcall readDevice(HANDLE handle, BYTE* buffer, int length);
    __declspec(dllimport) int __stdcall writeDevice(HANDLE handle, BYTE* buffer, int length);
}

// Global device handle (initialized to INVALID_HANDLE_VALUE)
static HANDLE g_deviceHandle = INVALID_HANDLE_VALUE;

// Forward declaration
class FlutterWindow;

// Global method channel pointer for invoking method calls back to Flutter.
std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> method_channel_ptr;

// Helper function: USB read loop for host.
void StartUsbReadLoop() {
    const int bufferSize = 1024;
    BYTE* buffer = new BYTE[bufferSize];
    while (g_deviceHandle != INVALID_HANDLE_VALUE) {
        int bytesRead = readDevice(g_deviceHandle, buffer, bufferSize);
        if (bytesRead > 0) {
            std::vector<flutter::EncodableValue> dataList;
            for (int i = 0; i < bytesRead; i++) {
                dataList.push_back(flutter::EncodableValue(static_cast<int>(buffer[i])));
            }
            // Send the read data back to Flutter as "usb_data" message.
            std::unique_ptr<flutter::EncodableValue> args =
                std::make_unique<flutter::EncodableValue>(dataList);
            method_channel_ptr->InvokeMethod("usb_data", std::move(args), nullptr);
        }
        std::this_thread::sleep_for(std::chrono::milliseconds(1));
    }
    delete[] buffer;
}

// New helper function: starts a TCP server socket to stream USB device data.
void StartUsbTcpServer() {
    // Initialize Winsock
    WSADATA wsaData;
    if (WSAStartup(MAKEWORD(2,2), &wsaData) != 0) return;
    SOCKET serverSocket = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
    if (serverSocket == INVALID_SOCKET) return;
    sockaddr_in serverAddr;
    serverAddr.sin_family = AF_INET;
    serverAddr.sin_addr.s_addr = INADDR_ANY;
    serverAddr.sin_port = htons(9000); // example port
    if (bind(serverSocket, (sockaddr*)&serverAddr, sizeof(serverAddr)) == SOCKET_ERROR) {
      closesocket(serverSocket);
      WSACleanup();
      return;
    }
    listen(serverSocket, 1);
    // Accept connection from the relay server.
    SOCKET clientSocket = accept(serverSocket, nullptr, nullptr);
    if (clientSocket != INVALID_SOCKET) {
        const int bufferSize = 1024;
        BYTE* buffer = new BYTE[bufferSize];
        // Stream loop: read from the USB device and send over socket.
        while (g_deviceHandle != INVALID_HANDLE_VALUE) {
            int bytesRead = readDevice(g_deviceHandle, buffer, bufferSize);
            if (bytesRead > 0) {
                send(clientSocket, reinterpret_cast<const char*>(buffer), bytesRead, 0);
            }
            std::this_thread::sleep_for(std::chrono::milliseconds(1));
        }
        delete[] buffer;
        closesocket(clientSocket);
    }
    closesocket(serverSocket);
    WSACleanup();
}

void RegisterMethodChannel(flutter::FlutterEngine* engine) {
    auto channel = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
        engine->messenger(),
        "com.example.remote_usb/usb",
        &flutter::StandardMethodCodec::GetInstance()
    );

    channel->SetMethodCallHandler(
        [](const auto& call, auto result) {
            if (call.method_name() == "host_connect") {
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
                    std::cout << "Host: Attempting to connect to device: " << device_id << std::endl;
                    g_deviceHandle = openDevice(device_id.c_str());
                    if (g_deviceHandle == INVALID_HANDLE_VALUE) {
                        DWORD error = GetLastError();
                        std::cerr << "Failed to open device with error: " << error << std::endl;
                        result->Error("CONNECT_ERROR", "Failed to open device");
                        return;
                    }
                    std::cout << "Device connected successfully: " << device_id << std::endl;
                    // Start a background thread to read USB data and send to Flutter.
                    std::thread(StartUsbReadLoop).detach();
                    result->Success(flutter::EncodableValue(true));
                } catch (const std::exception& e) {
                    result->Error("CONNECT_ERROR", e.what());
                }
            } else if (call.method_name() == "write_usb_data") {
                if (g_deviceHandle == INVALID_HANDLE_VALUE) {
                    result->Error("DEVICE_NOT_CONNECTED", "No device connected");
                    return;
                }
                try {
                    const auto* arguments = std::get_if<flutter::EncodableMap>(call.arguments());
                    if (!arguments) {
                        result->Error("INVALID_ARGUMENTS", "Arguments must be a map");
                        return;
                    }
                    auto data_it = arguments->find(flutter::EncodableValue("data"));
                    if (data_it == arguments->end()) {
                        result->Error("INVALID_ARGUMENTS", "data is required");
                        return;
                    }
                    const auto& dataList = std::get<std::vector<flutter::EncodableValue>>(data_it->second);
                    std::vector<int> data;
                    for (const auto& val : dataList) {
                        data.push_back(std::get<int>(val));
                    }
                    // Write data to the USB device.
                    BYTE* buffer = new BYTE[data.size()];
                    for (size_t i = 0; i < data.size(); i++) {
                        buffer[i] = static_cast<BYTE>(data[i]);
                    }
                    // Cast data.size() to int to avoid conversion warnings.
                    int bytesWritten = writeDevice(g_deviceHandle, buffer, static_cast<int>(data.size()));
                    delete[] buffer;
                    
                    if (bytesWritten != static_cast<int>(data.size())) {
                        result->Error("WRITE_ERROR", "Failed to write all data");
                        return;
                    }
                    result->Success(flutter::EncodableValue(true));
                } catch (const std::exception& e) {
                    result->Error("WRITE_ERROR", e.what());
                }
            } else if (call.method_name() == "start_usb_stream") {
                // New branch: start TCP server for USB streaming.
                std::thread(StartUsbTcpServer).detach();
                result->Success(flutter::EncodableValue(true));
            } else if (call.method_name() == "readDeviceData") {
                if (g_deviceHandle == INVALID_HANDLE_VALUE) {
                    result->Error("DEVICE_NOT_CONNECTED", "No device connected");
                    return;
                }
                try {
                    const int bufferSize = 1024;
                    BYTE buffer[bufferSize];
                    int bytesRead = readDevice(g_deviceHandle, buffer, bufferSize);
                    std::vector<flutter::EncodableValue> dataList;
                    for (int i = 0; i < bytesRead; i++) {
                        dataList.push_back(flutter::EncodableValue(static_cast<int>(buffer[i])));
                    }
                    result->Success(flutter::EncodableValue(dataList));
                } catch (const std::exception& e) {
                    result->Error("READ_ERROR", e.what());
                }
            } else if (call.method_name() == "writeDeviceData") {
                if (g_deviceHandle == INVALID_HANDLE_VALUE) {
                    result->Error("DEVICE_NOT_CONNECTED", "No device connected");
                    return;
                }
                try {
                    const auto* arguments = std::get_if<flutter::EncodableMap>(call.arguments());
                    if (!arguments) {
                        result->Error("INVALID_ARGUMENTS", "Arguments must be a map");
                        return;
                    }
                    auto data_it = arguments->find(flutter::EncodableValue("data"));
                    if (data_it == arguments->end()) {
                        result->Error("INVALID_ARGUMENTS", "data is required");
                        return;
                    }
                    const auto& dataList = std::get<std::vector<flutter::EncodableValue>>(data_it->second);
                    std::vector<int> data;
                    for (const auto& val : dataList) {
                        data.push_back(std::get<int>(val));
                    }
                    BYTE* buffer = new BYTE[data.size()];
                    for (size_t i = 0; i < data.size(); i++) {
                        buffer[i] = static_cast<BYTE>(data[i]);
                    }
                    int bytesWritten = writeDevice(g_deviceHandle, buffer, static_cast<int>(data.size()));
                    delete[] buffer;
                    if (bytesWritten != static_cast<int>(data.size())) {
                        result->Error("WRITE_ERROR", "Failed to write all data");
                        return;
                    }
                    result->Success(flutter::EncodableValue(true));
                } catch (const std::exception& e) {
                    result->Error("WRITE_ERROR", e.what());
                }
            } else {
                result->NotImplemented();
            }
        }
    );
    method_channel_ptr = std::move(channel);
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
