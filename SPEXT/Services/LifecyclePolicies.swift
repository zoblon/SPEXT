import Foundation

enum RecordingMode {
    case direct
    case polish
}

enum RecordingOwnershipPolicy {
    static func mayStop(owner: RecordingMode?, trigger: RecordingMode?) -> Bool {
        trigger == nil || trigger == owner
    }
}

enum GenerationPolicy {
    static func shouldApply(completed: UInt64, latest: UInt64) -> Bool {
        completed == latest
    }
}

enum KeychainMigrationPolicy {
    static func shouldRemoveLegacy(
        existingKey: String,
        attemptedKey: String,
        saveSucceeded: Bool,
        readbackKey: String
    ) -> Bool {
        !existingKey.isEmpty || (saveSucceeded && readbackKey == attemptedKey)
    }
}
