import Carbon
import AppKit

/// 全局快捷键（Carbon RegisterEventHotKey，无需辅助功能权限）
/// 默认按需求文档 5.1.4 节：⌘⇧空格 / ⌘⇧←→↑↓ / ⌘⇧0
final class HotkeyManager {

    enum Action: UInt32, CaseIterable {
        case togglePlay = 1
        case back1
        case forward1
        case forward5
        case back5
        case setZero
        case toggleOverlay

        var keyCode: UInt32 {
            switch self {
            case .togglePlay: return UInt32(kVK_Space)
            case .back1: return UInt32(kVK_LeftArrow)
            case .forward1: return UInt32(kVK_RightArrow)
            case .forward5: return UInt32(kVK_UpArrow)
            case .back5: return UInt32(kVK_DownArrow)
            case .setZero: return UInt32(kVK_ANSI_0)
            case .toggleOverlay: return UInt32(kVK_ANSI_H)
            }
        }
    }

    var handler: ((Action) -> Void)?

    private var refs: [EventHotKeyRef?] = []
    private var eventHandlerRef: EventHandlerRef?

    func register() {
        guard refs.isEmpty else { return }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event, let userData else { return noErr }
            var hkID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &hkID)
            let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
            if let action = Action(rawValue: hkID.id) {
                DispatchQueue.main.async { manager.handler?(action) }
            }
            return noErr
        }, 1, &eventType, selfPtr, &eventHandlerRef)

        let modifiers = UInt32(cmdKey | shiftKey)
        for action in Action.allCases {
            var ref: EventHotKeyRef?
            let hkID = EventHotKeyID(signature: OSType(0x444D4B4F) /* 'DMKO' */, id: action.rawValue)
            RegisterEventHotKey(action.keyCode, modifiers, hkID,
                                GetApplicationEventTarget(), 0, &ref)
            refs.append(ref)
        }
    }

    func unregister() {
        for ref in refs { if let ref { UnregisterEventHotKey(ref) } }
        refs.removeAll()
        if let eventHandlerRef { RemoveEventHandler(eventHandlerRef) }
        eventHandlerRef = nil
    }

    deinit { unregister() }
}
