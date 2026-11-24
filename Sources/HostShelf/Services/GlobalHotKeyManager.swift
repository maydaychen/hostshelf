import AppKit
import Carbon
import HostShelfCore
import Observation

@MainActor
@Observable
final class GlobalHotKeyManager {
    static let preferenceKey = "quickLauncherHotKey"
    private static let signature: OSType = 0x4853_484B
    private static let hotKeyID: UInt32 = 1

    private(set) var shortcut: HotKeyShortcut?
    private(set) var registrationError: String?
    var onTrigger: (@MainActor () -> Void)?

    @ObservationIgnored private let preferences: UserDefaults
    @ObservationIgnored private let customRegistrar: ((HotKeyShortcut) -> OSStatus)?
    @ObservationIgnored private let customUnregistrar: (() -> Void)?
    @ObservationIgnored private var hotKeyRef: EventHotKeyRef?
    @ObservationIgnored private var eventHandlerRef: EventHandlerRef?

    init(preferences: UserDefaults = .standard) {
        self.preferences = preferences
        self.customRegistrar = nil
        self.customUnregistrar = nil
        if let data = preferences.data(forKey: Self.preferenceKey),
           let decoded = try? JSONDecoder().decode(HotKeyShortcut.self, from: data),
           decoded.isValidForGlobalRegistration {
            self.shortcut = decoded
        } else {
            self.shortcut = nil
        }
        if let shortcut {
            _ = applyRegistration(shortcut)
        }
    }

    init(
        preferences: UserDefaults = .standard,
        registerHotKey: @escaping @MainActor (HotKeyShortcut) -> OSStatus,
        unregisterHotKey: @escaping @MainActor () -> Void
    ) {
        self.preferences = preferences
        self.customRegistrar = registerHotKey
        self.customUnregistrar = unregisterHotKey
        if let data = preferences.data(forKey: Self.preferenceKey),
           let decoded = try? JSONDecoder().decode(HotKeyShortcut.self, from: data),
           decoded.isValidForGlobalRegistration {
            self.shortcut = decoded
        } else {
            self.shortcut = nil
        }
        if let shortcut {
            _ = applyRegistration(shortcut)
        }
    }

    func setShortcut(_ candidate: HotKeyShortcut) {
        guard candidate.isValidForGlobalRegistration else {
            registrationError = "全局快捷键需至少包含 Control、Option 或 Command 修饰键。"
            return
        }
        guard applyRegistration(candidate) else { return }
        shortcut = candidate
        if let encoded = try? JSONEncoder().encode(candidate) {
            preferences.set(encoded, forKey: Self.preferenceKey)
        }
    }

    func applyRecommendedShortcut() {
        setShortcut(.recommendedDefault)
    }

    func clearShortcut() {
        tearDownSystemRegistration()
        shortcut = nil
        registrationError = nil
        preferences.removeObject(forKey: Self.preferenceKey)
    }

    private func applyRegistration(_ candidate: HotKeyShortcut) -> Bool {
        tearDownSystemRegistration()
        if let customRegistrar {
            let status = customRegistrar(candidate)
            if status != noErr {
                registrationError = "系统快捷键 \(candidate.displayString) 可能已被其他应用占用（错误码 \(status)）。"
                return false
            }
            registrationError = nil
            return true
        }

        installEventHandlerIfNeeded()
        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: Self.signature, id: Self.hotKeyID)
        let status = RegisterEventHotKey(
            candidate.keyCode,
            candidate.carbonModifiers,
            id,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        guard status == noErr, let ref else {
            registrationError = "系统快捷键 \(candidate.displayString) 注册失败，可能已被其他应用占用（错误码 \(status)）。"
            return false
        }
        hotKeyRef = ref
        registrationError = nil
        return true
    }

    private func installEventHandlerIfNeeded() {
        guard eventHandlerRef == nil else { return }
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let userData = Unmanaged.passUnretained(self).toOpaque()
        var handlerRef: EventHandlerRef?
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, rawUserData -> OSStatus in
                guard let event, let rawUserData else { return OSStatus(eventNotHandledErr) }
                var hotKeyID = EventHotKeyID()
                let readStatus = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard readStatus == noErr,
                      hotKeyID.signature == GlobalHotKeyManager.signature,
                      hotKeyID.id == GlobalHotKeyManager.hotKeyID else {
                    return OSStatus(eventNotHandledErr)
                }
                let manager = Unmanaged<GlobalHotKeyManager>.fromOpaque(rawUserData).takeUnretainedValue()
                DispatchQueue.main.async {
                    manager.onTrigger?()
                }
                return noErr
            },
            1,
            &spec,
            userData,
            &handlerRef
        )
        if status == noErr {
            eventHandlerRef = handlerRef
        }
    }

    private func tearDownSystemRegistration() {
        if let customUnregistrar {
            customUnregistrar()
            return
        }
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let eventHandlerRef { RemoveEventHandler(eventHandlerRef) }
    }
}
