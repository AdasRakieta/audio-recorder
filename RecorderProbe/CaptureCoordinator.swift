import AVFoundation
import CoreMedia
import Foundation
import ScreenCaptureKit

@MainActor
final class CaptureCoordinator: NSObject, ObservableObject {
    @Published private(set) var status = "Gotowe"
    @Published private(set) var isCapturing = false
    @Published private(set) var isFinishing = false
    @Published private(set) var systemSamples = 0
    @Published private(set) var microphoneSamples = 0
    @Published private(set) var lastSessionURL: URL?
    @Published private(set) var lastError: String?

    private let picker = SCContentSharingPicker.shared
    private lazy var delegateProxy = CaptureDelegateProxy(owner: self)
    private var stream: SCStream?
    private var systemWriter: AudioFileWriter?
    private var microphoneWriter: AudioFileWriter?
    private var currentSessionURL: URL?
    private var startedAt: Date?
    private var microphoneEnabled = false
    private var observerAdded = false

    func presentPicker() {
        guard !isCapturing && !isFinishing else { return }
        lastError = nil
        if !observerAdded {
            picker.add(delegateProxy)
            observerAdded = true
        }
        var configuration = SCContentSharingPickerConfiguration()
        configuration.showsMicrophoneControl = true
        picker.defaultConfiguration = configuration
        picker.isActive = true
        picker.present()
    }

    fileprivate func start(filter: SCContentFilter) async {
        guard !isCapturing && !isFinishing else { return }
        systemSamples = 0
        microphoneSamples = 0
        lastSessionURL = nil
        lastError = nil
        status = "Uruchamianie"
        microphoneEnabled = filter.isMicrophoneEnabled
        do {
            let startDate = Date()
            let session = try Self.createSessionDirectory(startedAt: startDate)
            currentSessionURL = session
            startedAt = startDate

            if microphoneEnabled {
                try AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP])
                try AVAudioSession.sharedInstance().setActive(true)
            }

            let configuration = SCStreamConfiguration()
            configuration.capturesAudio = true
            configuration.excludesCurrentProcessAudio = true
            configuration.sampleRate = 48_000
            configuration.channelCount = 2
            // Screen frames are delivered to the delegate but never stored.
            let newStream = SCStream(filter: filter, configuration: configuration, delegate: delegateProxy)
            try newStream.addStreamOutput(delegateProxy, type: .screen, sampleHandlerQueue: .main)
            try newStream.addStreamOutput(delegateProxy, type: .audio, sampleHandlerQueue: .main)
            if microphoneEnabled {
                try newStream.addStreamOutput(delegateProxy, type: .microphone, sampleHandlerQueue: .main)
            }
            stream = newStream
            try await newStream.startCapture()
            isCapturing = true
            status = "Nagrywanie"
        } catch {
            await finish(status: "Nie rozpoczęto", error: error.localizedDescription)
        }
    }

    func stop() async {
        guard isCapturing && !isFinishing else { return }
        isFinishing = true
        status = "Zapisywanie"
        do {
            try await stream?.stopCapture()
            await finish(status: "Zakończono", error: nil)
        } catch {
            await finish(status: "Przerwano", error: error.localizedDescription)
        }
    }

    fileprivate func finish(status finalStatus: String, error: String?) async {
        isCapturing = false
        isFinishing = true
        stream = nil

        var errors = [String]()
        if let error { errors.append(error) }
        if let writer = systemWriter {
            do { try await writer.finish() } catch { errors.append("Audio aplikacji: \(error.localizedDescription)") }
        }
        if let writer = microphoneWriter {
            do { try await writer.finish() } catch { errors.append("Mikrofon: \(error.localizedDescription)") }
        }
        systemWriter = nil
        microphoneWriter = nil

        if systemSamples == 0 { errors.append("Nie otrzymano próbek audio aplikacji") }
        if microphoneEnabled && microphoneSamples == 0 { errors.append("Nie otrzymano próbek mikrofonu") }
        let result = errors.isEmpty ? finalStatus : "Wymaga sprawdzenia"
        if let session = currentSessionURL {
            let report = CaptureReport(
                startedAt: startedAt ?? Date(), finishedAt: Date(),
                microphoneEnabled: microphoneEnabled, systemSamples: systemSamples,
                microphoneSamples: microphoneSamples, status: result, errors: errors
            )
            do {
                let data = try JSONEncoder.pretty.encode(report)
                try data.write(to: Self.fileURL(in: session, named: "report.json"), options: .atomic)
                lastSessionURL = session
            } catch {
                errors.append("Raport: \(error.localizedDescription)")
            }
        }
        currentSessionURL = nil
        startedAt = nil
        status = result
        lastError = errors.isEmpty ? nil : errors.joined(separator: "\n")
        isFinishing = false
        if microphoneEnabled { try? AVAudioSession.sharedInstance().setActive(false) }
    }

    private static func recordingsDirectory() throws -> URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let directory = base.appendingPathComponent("CaptureTests", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func createSessionDirectory(startedAt date: Date) throws -> URL {
        let root = try recordingsDirectory()
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy_MM_dd_HH_mm_ss"
        let timestamp = formatter.string(from: date)
        var name = timestamp
        var number = 2
        while FileManager.default.fileExists(atPath: root.appendingPathComponent(name).path) {
            name = "\(timestamp)_\(number)"
            number += 1
        }
        let session = root.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: session, withIntermediateDirectories: false)
        return session
    }

    static func fileURL(in session: URL, named name: String) -> URL {
        session.appendingPathComponent("\(session.lastPathComponent)_\(name)")
    }

    fileprivate func pickerCanceled() {
        status = "Anulowano"
    }

    fileprivate func pickerFailed(_ error: Error) {
        lastError = error.localizedDescription
        status = "Nie rozpoczęto"
    }

    fileprivate func handleSample(_ sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard isCapturing, CMSampleBufferDataIsReady(sampleBuffer), let session = currentSessionURL else { return }
        switch type {
        case .audio:
            if systemWriter == nil {
                systemWriter = try? AudioFileWriter(url: Self.fileURL(in: session, named: "system.m4a"), firstSample: sampleBuffer)
            }
            if let systemWriter, systemWriter.append(sampleBuffer) { systemSamples += 1 }
        case .microphone:
            if microphoneWriter == nil {
                microphoneWriter = try? AudioFileWriter(url: Self.fileURL(in: session, named: "microphone.m4a"), firstSample: sampleBuffer)
            }
            if let microphoneWriter, microphoneWriter.append(sampleBuffer) { microphoneSamples += 1 }
        default:
            break
        }
    }

    fileprivate func streamFailed(_ error: Error) {
        guard isCapturing && !isFinishing else { return }
        Task { await finish(status: "Przerwano", error: error.localizedDescription) }
    }
}

private final class CaptureDelegateProxy: NSObject, SCContentSharingPickerObserver, SCStreamOutput, SCStreamDelegate {
    weak var owner: CaptureCoordinator?

    init(owner: CaptureCoordinator) {
        self.owner = owner
    }

    func contentSharingPicker(_ picker: SCContentSharingPicker, didCancelFor stream: SCStream?) {
        Task { @MainActor [weak owner] in owner?.pickerCanceled() }
    }

    func contentSharingPicker(_ picker: SCContentSharingPicker, didUpdateWith filter: SCContentFilter, for stream: SCStream?) {
        guard stream == nil else { return }
        Task { @MainActor [weak owner] in await owner?.start(filter: filter) }
    }

    func contentSharingPickerStartDidFailWithError(_ error: Error) {
        Task { @MainActor [weak owner] in owner?.pickerFailed(error) }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio || type == .microphone else { return }
        Task { @MainActor [weak owner] in owner?.handleSample(sampleBuffer, of: type) }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        Task { @MainActor [weak owner] in owner?.streamFailed(error) }
    }
}

private struct CaptureReport: Codable {
    let startedAt: Date
    let finishedAt: Date
    let microphoneEnabled: Bool
    let systemSamples: Int
    let microphoneSamples: Int
    let status: String
    let errors: [String]
}

private extension JSONEncoder {
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private final class AudioFileWriter {
    let writer: AVAssetWriter
    let input: AVAssetWriterInput

    init(url: URL, firstSample: CMSampleBuffer) throws {
        guard let description = CMSampleBufferGetFormatDescription(firstSample),
              let basic = CMAudioFormatDescriptionGetStreamBasicDescription(description)?.pointee else {
            throw NSError(domain: "RecorderProbe", code: 1, userInfo: [NSLocalizedDescriptionKey: "Brak formatu audio"])
        }
        writer = try AVAssetWriter(outputURL: url, fileType: .m4a)
        input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: basic.mSampleRate,
            AVNumberOfChannelsKey: Int(basic.mChannelsPerFrame),
            AVEncoderBitRateKey: 128_000
        ])
        input.expectsMediaDataInRealTime = true
        writer.add(input)
        guard writer.startWriting() else {
            throw writer.error ?? NSError(domain: "RecorderProbe", code: 2)
        }
        writer.startSession(atSourceTime: CMSampleBufferGetPresentationTimeStamp(firstSample))
    }

    func append(_ sample: CMSampleBuffer) -> Bool {
        guard writer.status == .writing, input.isReadyForMoreMediaData else { return false }
        return input.append(sample)
    }

    func finish() async throws {
        guard writer.status == .writing else {
            if writer.status == .failed { throw writer.error ?? NSError(domain: "RecorderProbe", code: 3) }
            return
        }
        input.markAsFinished()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            writer.finishWriting { continuation.resume() }
        }
        if writer.status != .completed { throw writer.error ?? NSError(domain: "RecorderProbe", code: 4) }
    }
}
