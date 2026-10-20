import Carbon.HIToolbox
import Foundation

/// System-wide ⌃⌥ shortcuts through Carbon `RegisterEventHotKey`, which needs no Accessibility permission and
/// works while another app (the presentation) is frontmost. Registered only while the teleprompter is visible.
@MainActor
final class GlobalHotKeys {
    enum Key: UInt32 {
        case space = 49, left = 123, right = 124, down = 125, up = 126, escape = 53, equal = 24, minus = 27
    }

    struct Binding {
        var key: Key
        var action: @MainActor () -> Void
    }

    private static let signature: OSType = 0x4354_4450 // "CTDP"
    private static var actions: [UInt32: @MainActor () -> Void] = [:]
    private static var handler: EventHandlerRef?
    private var refs: [EventHotKeyRef] = []
    private var ids: [UInt32] = []
    private static var nextID: UInt32 = 1

    func register(_ bindings: [Binding]) {
        Self.installHandlerIfNeeded()
        for binding in bindings {
            let id = Self.nextID
            Self.nextID += 1
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(binding.key.rawValue, UInt32(controlKey | optionKey),
                                             EventHotKeyID(signature: Self.signature, id: id), GetApplicationEventTarget(), 0, &ref)
            guard status == noErr, let ref else { continue }
            refs.append(ref)
            ids.append(id)
            Self.actions[id] = binding.action
        }
    }

    func unregisterAll() {
        refs.forEach { UnregisterEventHotKey($0) }
        ids.forEach { Self.actions[$0] = nil }
        refs = []
        ids = []
    }

    private static func installHandlerIfNeeded() {
        guard handler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hotKey = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                           nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKey)
            guard status == noErr else { return status }
            // Carbon delivers hotkey events on the main thread.
            MainActor.assumeIsolated { GlobalHotKeys.actions[hotKey.id]?() }
            return noErr
        }, 1, &spec, nil, &handler)
    }
}
