import Foundation

/// What the app does on every launch.
enum LaunchSyncMode: String, CaseIterable, Sendable {
    case full, dataOnly, off

    var label: String {
        switch self {
        case .full: "Sincronización completa"
        case .dataOnly: "Solo datos (sin archivos)"
        case .off: "Desactivada"
        }
    }
}

/// Decides whether the launch-time background sync starts. Pure.
enum LaunchSyncPolicy {
    enum Reason: Equatable, Sendable {
        case disabledByEnvironment, onboardingIncomplete, modeOff, noCredentials, noPython, syncInProgress, throttled
    }

    enum Decision: Equatable, Sendable {
        case start(includeFiles: Bool)
        case skip(Reason)
    }

    static func decide(
        mode: LaunchSyncMode, onboardingCompleted: Bool, hasCredentials: Bool, hasPython: Bool,
        lastSuccess: Date?, now: Date, minIntervalMinutes: Int, isSyncRunning: Bool, disabledByEnvironment: Bool
    ) -> Decision {
        if disabledByEnvironment { return .skip(.disabledByEnvironment) }
        if !onboardingCompleted { return .skip(.onboardingIncomplete) }
        if mode == .off { return .skip(.modeOff) }
        if !hasCredentials { return .skip(.noCredentials) }
        if !hasPython { return .skip(.noPython) }
        if isSyncRunning { return .skip(.syncInProgress) }
        if let last = lastSuccess, minIntervalMinutes > 0 {
            let elapsed = now.timeIntervalSince(last)
            if elapsed >= 0, elapsed < Double(minIntervalMinutes) * 60 { return .skip(.throttled) }
        }
        return .start(includeFiles: mode == .full)
    }
}

/// Spanish wording of a sync result for toasts and notifications.
enum SyncSummary {
    static func text(for diff: ActivityDiff) -> String {
        var parts: [String] = []
        func add(_ n: Int, _ one: String, _ many: String) { if n > 0 { parts.append("\(n) \(n == 1 ? one : many)") } }
        add(diff.added.count, "actividad nueva", "actividades nuevas")
        add(diff.removed.count, "actividad eliminada", "actividades eliminadas")
        add(diff.dueChanges.count, "fecha cambió", "fechas cambiaron")
        add(diff.statusChanges.count, "estado cambió", "estados cambiaron")
        return parts.isEmpty ? "Sin cambios" : parts.joined(separator: " · ")
    }

    /// New activities or moved deadlines deserve a system notification; other changes do not.
    static func isNotable(_ diff: ActivityDiff) -> Bool { !diff.added.isEmpty || !diff.dueChanges.isEmpty }

    /// Banner text for a failed run; nil for success or a user cancellation.
    static func failure(for outcome: SyncOutcome) -> (text: String, needsSettings: Bool)? {
        switch outcome {
        case .success: nil
        case .failed(let code) where code == -15: nil
        case .loginFailed: ("No se pudo iniciar sesión en SAIA. Revise sus credenciales en Ajustes.", true)
        case .missingCredentials: ("Faltan las credenciales de SAIA. Ingréselas en Ajustes.", true)
        case .missingPython: ("No se encontró un intérprete de Python válido. Configúrelo en Ajustes.", true)
        case .installFailed: ("No se pudo preparar el script de sincronización.", false)
        case .failed: ("La sincronización en segundo plano no se completó.", false)
        }
    }
}
