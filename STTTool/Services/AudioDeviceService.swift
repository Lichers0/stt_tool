import AVFoundation
import Combine
import CoreAudio

/// Enumerates, monitors, and selects audio input devices using CoreAudio C API.
@MainActor
final class AudioDeviceService: ObservableObject {
    @Published private(set) var availableDevices: [AudioDevice] = []
    @Published var selectedDeviceUID: String = "system-default"
    @Published private(set) var activeDevice: AudioDevice?

    // nonisolated(unsafe) to allow access from deinit and CoreAudio listener callbacks
    nonisolated(unsafe) private var deviceListListenerId: AudioObjectPropertyListenerBlock?
    nonisolated(unsafe) private var defaultDeviceListenerId: AudioObjectPropertyListenerBlock?
    private let listenerQueue = DispatchQueue(label: "audio-device-listener")
    private var debounceTask: Task<Void, Never>?

    private let selectedDeviceKey = "selectedAudioDeviceUID"

    init() {
        selectedDeviceUID = UserDefaults.standard.string(forKey: selectedDeviceKey) ?? "system-default"
        refreshDeviceList()
        resolveActiveDevice()
        installListeners()
    }

    deinit {
        removeListeners()
    }

    // MARK: - Public

    func selectDevice(uid: String) {
        selectedDeviceUID = uid
        UserDefaults.standard.set(uid, forKey: selectedDeviceKey)
        resolveActiveDevice()
    }

    /// Returns the AudioDeviceID to use for recording.
    /// Returns nil if "system-default" is selected (AVAudioEngine will use system default).
    var effectiveDeviceID: AudioDeviceID? {
        guard selectedDeviceUID != "system-default" else { return nil }
        if let device = availableDevices.first(where: { $0.uid == selectedDeviceUID }) {
            return device.id
        }
        // Selected device not available — fallback to system default
        return nil
    }

    // MARK: - Device Enumeration

    func refreshDeviceList() {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress, 0, nil, &dataSize
        ) == noErr else { return }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)

        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress, 0, nil, &dataSize, &deviceIDs
        ) == noErr else { return }

        var inputDevices: [AudioDevice] = []
        for deviceID in deviceIDs {
            guard hasInputStreams(deviceID),
                  let name = deviceName(deviceID),
                  let uid = deviceUID(deviceID) else { continue }
            inputDevices.append(AudioDevice(id: deviceID, name: name, uid: uid))
        }

        availableDevices = inputDevices
    }

    // MARK: - Private Helpers

    private func resolveActiveDevice() {
        if selectedDeviceUID == "system-default" {
            activeDevice = systemDefaultDevice()
        } else if let device = availableDevices.first(where: { $0.uid == selectedDeviceUID }) {
            activeDevice = device
        } else {
            // Selected device not available — fallback to default and normalize selection
            if selectedDeviceUID != "system-default" {
                selectedDeviceUID = "system-default"
                UserDefaults.standard.set("system-default", forKey: selectedDeviceKey)
            }
            activeDevice = systemDefaultDevice()
        }
    }

    private func systemDefaultDevice() -> AudioDevice? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID: AudioDeviceID = 0
        var dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)

        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress, 0, nil, &dataSize, &deviceID
        ) == noErr, deviceID != kAudioObjectUnknown else { return nil }

        guard let name = deviceName(deviceID),
              let uid = deviceUID(deviceID) else { return nil }
        return AudioDevice(id: deviceID, name: name, uid: uid)
    }

    private func hasInputStreams(_ deviceID: AudioDeviceID) -> Bool {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            deviceID, &propertyAddress, 0, nil, &dataSize
        ) == noErr else { return false }
        return dataSize > 0
    }

    private func deviceName(_ deviceID: AudioDeviceID) -> String? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var name: CFString = "" as CFString
        var dataSize = UInt32(MemoryLayout<CFString>.size)
        guard AudioObjectGetPropertyData(
            deviceID, &propertyAddress, 0, nil, &dataSize, &name
        ) == noErr else { return nil }
        return name as String
    }

    private func deviceUID(_ deviceID: AudioDeviceID) -> String? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var uid: CFString = "" as CFString
        var dataSize = UInt32(MemoryLayout<CFString>.size)
        guard AudioObjectGetPropertyData(
            deviceID, &propertyAddress, 0, nil, &dataSize, &uid
        ) == noErr else { return nil }
        return uid as String
    }

    // MARK: - CoreAudio Listeners

    private func installListeners() {
        // Listen for device list changes
        var devicesAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let devicesBlock: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.handleDeviceChange()
        }
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &devicesAddress, self.listenerQueue, devicesBlock
        )
        deviceListListenerId = devicesBlock

        // Listen for default input device changes
        var defaultAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let defaultBlock: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.handleDeviceChange()
        }
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &defaultAddress, self.listenerQueue, defaultBlock
        )
        defaultDeviceListenerId = defaultBlock
    }

    nonisolated private func removeListeners() {
        var devicesAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        if let block = deviceListListenerId {
            AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject),
                &devicesAddress, listenerQueue, block
            )
        }

        var defaultAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        if let block = defaultDeviceListenerId {
            AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject),
                &defaultAddress, listenerQueue, block
            )
        }
    }

    nonisolated private func handleDeviceChange() {
        Task { @MainActor [weak self] in
            self?.debounceTask?.cancel()
            self?.debounceTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                self?.refreshDeviceList()
                self?.resolveActiveDevice()
            }
        }
    }
}

extension AudioDeviceService: AudioDeviceServiceProtocol {}
