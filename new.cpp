#include <setupapi.h>
#include <windows.h>
#include <iostream>
#include <string>

// Link with Setupapi.lib
#pragma comment(lib, "Setupapi.lib")

class VirtualUSBDevice {
private:
    HDEVINFO deviceInfoSet;
    SP_DEVINFO_DATA deviceInfoData;
    
public:
    VirtualUSBDevice() {
        deviceInfoSet = INVALID_HANDLE_VALUE;
        ZeroMemory(&deviceInfoData, sizeof(SP_DEVINFO_DATA));
        deviceInfoData.cbSize = sizeof(SP_DEVINFO_DATA);
    }
    
    ~VirtualUSBDevice() {
        if (deviceInfoSet != INVALID_HANDLE_VALUE) {
            SetupDiDestroyDeviceInfoList(deviceInfoSet);
        }
    }
    
    bool CreateDevice(const std::wstring& hardwareId) {
        // Create device information set
        deviceInfoSet = SetupDiCreateDeviceInfoList(nullptr, nullptr);
        if (deviceInfoSet == INVALID_HANDLE_VALUE) {
            std::cerr << "Failed to create device info list. Error: " << GetLastError() << std::endl;
            return false;
        }
        
        // Create new device info
        if (!SetupDiCreateDeviceInfoW(deviceInfoSet,
                                    L"USB\\VirtualDevice",
                                    &GUID_NULL,
                                    nullptr,
                                    nullptr,
                                    DICD_GENERATE_ID,
                                    &deviceInfoData)) {
            std::cerr << "Failed to create device info. Error: " << GetLastError() << std::endl;
            return false;
        }
        
        // Set hardware ID property
        if (!SetupDiSetDeviceRegistryPropertyW(deviceInfoSet,
                                             &deviceInfoData,
                                             SPDRP_HARDWAREID,
                                             (PBYTE)hardwareId.c_str(),
                                             (DWORD)(hardwareId.length() + 1) * sizeof(wchar_t))) {
            std::cerr << "Failed to set hardware ID. Error: " << GetLastError() << std::endl;
            return false;
        }
        
        // Register device
        if (!SetupDiCallClassInstaller(DIF_REGISTERDEVICE,
                                     deviceInfoSet,
                                     &deviceInfoData)) {
            std::cerr << "Failed to register device. Error: " << GetLastError() << std::endl;
            return false;
        }
        
        std::cout << "Virtual USB device created successfully!" << std::endl;
        return true;
    }
    
    bool RemoveDevice() {
        if (deviceInfoSet == INVALID_HANDLE_VALUE) {
            std::cerr << "No device to remove." << std::endl;
            return false;
        }
        
        // Remove the device
        if (!SetupDiCallClassInstaller(DIF_REMOVE,
                                     deviceInfoSet,
                                     &deviceInfoData)) {
            std::cerr << "Failed to remove device. Error: " << GetLastError() << std::endl;
            return false;
        }
        
        std::cout << "Virtual USB device removed successfully!" << std::endl;
        return true;
    }
};

int main() {
    // Create an instance of the virtual USB device manager
    VirtualUSBDevice virtualDevice;
    
    // Create a virtual USB device with a sample hardware ID
    std::wstring hardwareId = L"USB\\VID_0000&PID_0000\\VirtualDevice";
    if (virtualDevice.CreateDevice(hardwareId)) {
        std::cout << "Press Enter to remove the virtual device...";
        std::cin.get();
        virtualDevice.RemoveDevice();
    }
    
    return 0;
}