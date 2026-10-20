/// Retains explicit shortcut changes while an existing tap still owns a recording.
/// Retry exhaustion pauses timers; native grant, idle and modifier-release events
/// can still finish the pending work afterwards.
struct PermissionRecoveryState {
    enum Action { case none, retry, rebuild }

    private(set) var hasPendingConfiguration = false
    private var retries = 0
    private let retryLimit: Int

    init(retryLimit: Int = 40) { self.retryLimit = retryLimit }

    mutating func requestConfiguration() {
        hasPendingConfiguration = true
        resumeRetries()
    }

    mutating func resumeRetries() { retries = 0 }

    mutating func nextAction(granted: Bool, busy: Bool, modifiersHeld: Bool, tapsInstalled: Bool) -> Action {
        guard granted, hasPendingConfiguration || !tapsInstalled else { return .none }
        if !busy && !modifiersHeld { return .rebuild }
        return takeRetry() ? .retry : .none
    }

    mutating func takeRetry() -> Bool {
        guard retries < retryLimit else { return false }
        retries += 1
        return true
    }

    mutating func didRebuild(installed: Bool) {
        hasPendingConfiguration = !installed
        if installed { resumeRetries() }
    }

    func shouldObserveModifierRelease(granted: Bool, tapsInstalled: Bool) -> Bool {
        granted && (hasPendingConfiguration || !tapsInstalled)
    }
}
