import AVFoundation
import Foundation

/// Merges recording segments after format changes. Runs exclusively
/// on the recorder queue after the tap has stopped writing data.
enum RecordingAssembler {
    static func export(segments: [URL]) throws -> URL {
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathExtension("m4a")
        do {
            try write(segments: segments, to: destination)
            return destination
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
    }

    private static func write(segments: [URL], to destination: URL) throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: 24_000, channels: 1)!
        let output = try AVAudioFile(forWriting: destination, settings: [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: format.channelCount,
            AVEncoderBitRateKey: 64_000
        ])
        for url in segments {
            let input = try AVAudioFile(forReading: url)
            guard input.length > 0 else { continue }
            guard let converter = AVAudioConverter(from: input.processingFormat, to: format),
                  let converted = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4096) else {
                throw assemblyError("Audioformat konnte nicht umgewandelt werden.")
            }
            var readError: Error?
            var emptyPasses = 0
            while true {
                var conversionError: NSError?
                let status = converter.convert(to: converted, error: &conversionError) { requested, status in
                    guard input.framePosition < input.length else {
                        status.pointee = .endOfStream
                        return nil
                    }
                    guard let buffer = AVAudioPCMBuffer(pcmFormat: input.processingFormat,
                                                         frameCapacity: max(requested, 1)) else {
                        readError = assemblyError("Audiospeicher konnte nicht angelegt werden.")
                        status.pointee = .endOfStream
                        return nil
                    }
                    do {
                        try input.read(into: buffer)
                        status.pointee = buffer.frameLength > 0 ? .haveData : .endOfStream
                        return buffer.frameLength > 0 ? buffer : nil
                    } catch {
                        readError = error
                        status.pointee = .endOfStream
                        return nil
                    }
                }
                if let readError { throw readError }
                if let conversionError { throw conversionError }
                if status == .error { throw assemblyError("Audio konnte nicht zusammengeführt werden.") }
                if converted.frameLength > 0 {
                    try output.write(from: converted)
                    emptyPasses = 0
                } else {
                    emptyPasses += 1
                }
                if status == .endOfStream { break }
                guard emptyPasses < 3 else { throw assemblyError("Audio-Umwandlung liefert keine Daten.") }
            }
        }
        guard output.length > 0 else { throw assemblyError("Die Aufnahme enthält keine Audiodaten.") }
    }

    private static func assemblyError(_ message: String) -> NSError {
        NSError(domain: "SPEXT.RecordingAssembler", code: 1,
                userInfo: [NSLocalizedDescriptionKey: message])
    }
}

/// Monotonic time values; speech pauses are no proof of a device failure.
enum RecordingHealthPolicy {
    static let missingBufferTimeout: TimeInterval = 2.5
    static let quietWarningDelay: TimeInterval = 4

    static func hasStalled(now: TimeInterval, lastBufferAt: TimeInterval) -> Bool {
        now - lastBufferAt >= missingBufferTimeout
    }

    static func needsSignalWarning(now: TimeInterval, lastSpeechAt: TimeInterval) -> Bool {
        now - lastSpeechAt >= quietWarningDelay
    }
}
