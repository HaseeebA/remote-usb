#include <windows.h>
#include <setupapi.h>
#include <initguid.h>
#include <usbiodef.h>
#include <iostream>
#include <string>
#include <cstdlib>

// Helper function to convert wide string to std::string.
std::string WideStringToString(const wchar_t* wstr) {
    if (!wstr) return "";
    int size = WideCharToMultiByte(CP_UTF8, 0, wstr, -1, NULL, 0, NULL, NULL);
    if (size == 0) return "";
    std::string result(size, 0);
    WideCharToMultiByte(CP_UTF8, 0, wstr, -1, &result[0], size, NULL, NULL);
    if (!result.empty() && result.back() == '\0')
        result.pop_back();
    return result;
}

// Helper function to get proper device interface path from instance ID.
std::string GetDeviceInterfacePathFromInstanceId(const std::string& instanceId) {
    HDEVINFO hDevInfo = SetupDiGetClassDevsW(&GUID_DEVINTERFACE_USB_DEVICE, nullptr, nullptr, DIGCF_PRESENT | DIGCF_DEVICEINTERFACE);
    if (hDevInfo == INVALID_HANDLE_VALUE) {
        std::cerr << "SetupDiGetClassDevs failed.\n";
        return "";
    }

    SP_DEVICE_INTERFACE_DATA interfaceData;
    interfaceData.cbSize = sizeof(SP_DEVICE_INTERFACE_DATA);
    DWORD index = 0;
    std::string devicePath;
    
    while (SetupDiEnumDeviceInterfaces(hDevInfo, nullptr, &GUID_DEVINTERFACE_USB_DEVICE, index, &interfaceData)) {
        DWORD requiredSize = 0;
        SetupDiGetDeviceInterfaceDetailW(hDevInfo, &interfaceData, nullptr, 0, &requiredSize, nullptr);
        PSP_DEVICE_INTERFACE_DETAIL_DATA_W detailData = (PSP_DEVICE_INTERFACE_DETAIL_DATA_W)malloc(requiredSize);
        if (!detailData) {
            index++;
            continue;
        }
        detailData->cbSize = sizeof(SP_DEVICE_INTERFACE_DETAIL_DATA_W);
        SP_DEVINFO_DATA devInfoData;
        devInfoData.cbSize = sizeof(SP_DEVINFO_DATA);
        if (SetupDiGetDeviceInterfaceDetailW(hDevInfo, &interfaceData, detailData, requiredSize, nullptr, &devInfoData)) {
            wchar_t instanceIdBuffer[256];
            if (SetupDiGetDeviceInstanceIdW(hDevInfo, &devInfoData, instanceIdBuffer, sizeof(instanceIdBuffer)/sizeof(wchar_t), nullptr)) {
                std::string currentInstanceId = WideStringToString(instanceIdBuffer);
                if (instanceId == currentInstanceId) {
                    devicePath = WideStringToString(detailData->DevicePath);
                    free(detailData);
                    break;
                }
            }
        }
        free(detailData);
        index++;
    }

    SetupDiDestroyDeviceInfoList(hDevInfo);
    return devicePath;
}

extern "C" {
    __declspec(dllexport) HANDLE __stdcall openDevice(const char* devicePath) {
        std::string instanceId(devicePath);
        // Get full device interface path from instance ID.
        std::string fullPath = GetDeviceInterfacePathFromInstanceId(instanceId);
        if (fullPath.empty()) {
            std::cerr << "Failed to get device interface path for instance id: " << instanceId << std::endl;
            return INVALID_HANDLE_VALUE;
        }
        HANDLE deviceHandle = CreateFileA(
            fullPath.c_str(),
            GENERIC_READ | GENERIC_WRITE,
            FILE_SHARE_READ | FILE_SHARE_WRITE,
            NULL,
            OPEN_EXISTING,
            FILE_FLAG_OVERLAPPED,
            NULL
        );
        if (deviceHandle == INVALID_HANDLE_VALUE) {
            DWORD error = GetLastError();
            std::cerr << "openDevice failed for \"" << fullPath << "\" with error: " << error << std::endl;
        }
        return deviceHandle;
    }

    __declspec(dllexport) int __stdcall readDevice(HANDLE handle, BYTE* buffer, int length) {
        DWORD bytesRead = 0;
        OVERLAPPED overlapped = { 0 };
        overlapped.hEvent = CreateEvent(NULL, TRUE, FALSE, NULL);

        if (!ReadFile(handle, buffer, length, &bytesRead, &overlapped)) {
            if (GetLastError() == ERROR_IO_PENDING) {
                WaitForSingleObject(overlapped.hEvent, INFINITE);
                GetOverlappedResult(handle, &overlapped, &bytesRead, TRUE);
            }
        }

        CloseHandle(overlapped.hEvent);
        return bytesRead;
    }

    __declspec(dllexport) int __stdcall writeDevice(HANDLE handle, BYTE* buffer, int length) {
        DWORD bytesWritten = 0;
        OVERLAPPED overlapped = { 0 };
        overlapped.hEvent = CreateEvent(NULL, TRUE, FALSE, NULL);

        if (!WriteFile(handle, buffer, length, &bytesWritten, &overlapped)) {
            if (GetLastError() == ERROR_IO_PENDING) {
                WaitForSingleObject(overlapped.hEvent, INFINITE);
                GetOverlappedResult(handle, &overlapped, &bytesWritten, TRUE);
            }
        }

        CloseHandle(overlapped.hEvent);
        return bytesWritten;
    }
}
