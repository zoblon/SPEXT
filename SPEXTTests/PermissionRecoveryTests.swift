import Foundation

@main
struct PermissionRecoveryTests {
    static func main() {
        // Each case describes an unsafe user-visible transition, rather than native grants
        // or event-tap calls mocked to return the answer we want.
        let cases: [(String, Bool, Bool, Bool, Bool, Bool, Bool)] = [
            ("idle app with native grant", true, false, false, false, false, true),
            ("a switch enabled for another app does not replace a native grant", false, false, false, false, false, false),
            ("startup still owns the shortcut", true, true, false, false, false, false),
            ("recording must retain its key release callback", true, false, true, false, false, false),
            ("processing is not interrupted", true, false, false, true, false, false),
            ("returning with Command held cannot start a new shortcut", true, false, false, false, true, false),
            ("overlapping busy states stay blocked", true, true, true, true, true, false)
        ]
        for (name, granted, starting, recording, transcribing, held, expected) in cases {
            var state = PermissionRecoveryState()
            state.requestConfiguration()
            expect((state.nextAction(granted: granted, busy: starting || recording || transcribing,
                                     modifiersHeld: held, tapsInstalled: true) == .rebuild) == expected, name)
        }
        for directInstalled in [false, true] {
            for messageInstalled in [false, true] {
                var state = PermissionRecoveryState()
                let expected: PermissionRecoveryState.Action = directInstalled && messageInstalled ? .none : .rebuild
                expect(state.nextAction(granted: true, busy: false, modifiersHeld: false,
                                        tapsInstalled: directInstalled && messageInstalled) == expected,
                       "recover a missing tap but preserve installed taps")
            }
        }
        verifyDeferredConfiguration()
        verifyBundleIdentity()
        print("PASS: Permission recovery safety (7 lifecycle cases, 4 tap states, deferred settings and late modifier release) and running-bundle identity")
    }

    private static func verifyDeferredConfiguration() {
        var state = PermissionRecoveryState(retryLimit: 2)
        state.requestConfiguration()
        expect(state.nextAction(granted: true, busy: true, modifiersHeld: false, tapsInstalled: true) == .retry,
               "changing shortcuts during transcription stays pending even with existing taps")
        expect(state.nextAction(granted: true, busy: true, modifiersHeld: false, tapsInstalled: true) == .retry,
               "busy reconfiguration can retry within its budget")
        expect(state.nextAction(granted: true, busy: true, modifiersHeld: false, tapsInstalled: true) == .none,
               "busy retries are bounded")
        expect(state.hasPendingConfiguration, "exhausting retries must not drop a settings change")
        expect(state.nextAction(granted: true, busy: false, modifiersHeld: false, tapsInstalled: true) == .rebuild,
               "idle lifecycle completion applies pending changes after retries expired")
        state.didRebuild(installed: true)
        expect(!state.hasPendingConfiguration, "successful replacement completes the settings change")
        expect(!state.shouldObserveModifierRelease(granted: true, tapsInstalled: true),
               "successful replacement removes the extra release observer")
        expect(state.nextAction(granted: true, busy: false, modifiersHeld: false, tapsInstalled: true) == .none,
               "completed recovery preserves installed taps")

        var cold = PermissionRecoveryState(retryLimit: 1)
        expect(cold.nextAction(granted: true, busy: false, modifiersHeld: true, tapsInstalled: false) == .retry,
               "cold launch with held modifiers waits")
        expect(cold.nextAction(granted: true, busy: false, modifiersHeld: true, tapsInstalled: false) == .none,
               "long held modifiers exhaust the short retry budget")
        expect(cold.shouldObserveModifierRelease(granted: true, tapsInstalled: false),
               "missing cold-launch taps retain a release observer beyond the retry budget")
        expect(cold.nextAction(granted: true, busy: false, modifiersHeld: false, tapsInstalled: false) == .rebuild,
               "modifier release installs missing taps even after the retry budget")

        state.requestConfiguration()
        expect(state.nextAction(granted: false, busy: false, modifiersHeld: false, tapsInstalled: true) == .none,
               "denied native access never retries or rebuilds")
        expect(!state.shouldObserveModifierRelease(granted: false, tapsInstalled: true),
               "native denial disables the extra release observer")
        expect(state.hasPendingConfiguration, "permission denial preserves the requested settings change")
        expect(state.nextAction(granted: true, busy: false, modifiersHeld: false, tapsInstalled: true) == .rebuild,
               "a later native grant applies the pending settings change")
    }

    private static func verifyBundleIdentity() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        do {
            var identities: [PermissionRecoveryIdentity] = []
            for (folder, version, build) in [("old", "1.0.24", "24"), ("current", "1.0.25", "25")] {
                let appURL = root.appendingPathComponent(folder).appendingPathComponent("SPEXT.app")
                let contents = appURL.appendingPathComponent("Contents")
                try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
                let info: [String: Any] = [
                    "CFBundleIdentifier": "de.Rehkopf.SPEXT.PermissionFixture",
                    "CFBundlePackageType": "APPL",
                    "CFBundleShortVersionString": version,
                    "CFBundleVersion": build
                ]
                let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
                try data.write(to: contents.appendingPathComponent("Info.plist"))
                guard let bundle = Bundle(url: appURL) else { fatalError("invalid bundle fixture") }
                let identity = PermissionRecoveryIdentity(bundle: bundle)
                expect(identity.version == version && identity.build == build, "identify the actual bundle version and build")
                expect(identity.appURL == bundle.bundleURL, "the revealed app must be the exact bundle being inspected")
                identities.append(identity)
            }
            expect(identities[0].appURL != identities[1].appURL, "same app name in two locations must stay distinguishable")
        } catch {
            fputs("FAIL: bundle identity fixture: \(error)\n", stderr)
            exit(1)
        }
    }

    private static func expect(_ condition: Bool, _ message: String) {
        guard condition else {
            fputs("FAIL: \(message)\n", stderr)
            exit(1)
        }
    }
}
