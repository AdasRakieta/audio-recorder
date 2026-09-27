import Foundation
import SwiftUI

@MainActor
final class TeamsImportStore: ObservableObject {
    @Published private(set) var recordings: [TeamsRecording] = []

    init() { reload() }

    func importRecording(from source: URL) throws {
        let ext = source.pathExtension.lowercased()
        guard ["mp4", "m4a", "mov", "mp3", "wav"].contains(ext) else {
            throw ImportError.unsupportedRecording
        }
        let hasAccess = source.startAccessingSecurityScopedResource()
        defer { if hasAccess { source.stopAccessingSecurityScopedResource() } }

        let root = try Self.rootDirectory()
        let folder = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        do {
            try FileManager.default.copyItem(at: source, to: folder.appendingPathComponent(source.lastPathComponent))
        } catch {
            try? FileManager.default.removeItem(at: folder)
            throw error
        }
        reload()
    }

    func importTranscript(from source: URL, for recording: TeamsRecording) throws {
        guard source.pathExtension.lowercased() == "vtt" else {
            throw ImportError.unsupportedTranscript
        }
        let hasAccess = source.startAccessingSecurityScopedResource()
        defer { if hasAccess { source.stopAccessingSecurityScopedResource() } }

        let destination = recording.folder.appendingPathComponent("transcript.vtt")
        let temporary = recording.folder.appendingPathComponent("transcript-\(UUID().uuidString).vtt")
        try FileManager.default.copyItem(at: source, to: temporary)
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: temporary, to: destination)
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw error
        }
        reload()
    }

    func reload() {
        guard let root = try? Self.rootDirectory(),
              let folders = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else {
            recordings = []
            return
        }
        recordings = folders.compactMap { folder in
            guard let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil),
                  let media = files.first(where: { ["mp4", "m4a", "mov", "mp3", "wav"].contains($0.pathExtension.lowercased()) }) else {
                return nil
            }
            let transcript = folder.appendingPathComponent("transcript.vtt")
            return TeamsRecording(folder: folder, media: media,
                                  transcript: FileManager.default.fileExists(atPath: transcript.path) ? transcript : nil)
        }.sorted { $0.folder.lastPathComponent > $1.folder.lastPathComponent }
    }

    private static func rootDirectory() throws -> URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let root = documents.appendingPathComponent("TeamsMeetings", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}

struct TeamsRecording: Identifiable {
    let folder: URL
    let media: URL
    let transcript: URL?

    var id: String { folder.lastPathComponent }
    var title: String { media.deletingPathExtension().lastPathComponent }
}

enum ImportError: LocalizedError {
    case unsupportedRecording
    case unsupportedTranscript

    var errorDescription: String? {
        switch self {
        case .unsupportedRecording: return "Wybierz nagranie MP4, M4A, MOV, MP3 lub WAV."
        case .unsupportedTranscript: return "Wybierz transkrypcję Teams w formacie VTT."
        }
    }
}

struct TranscriptCue: Identifiable {
    let start: TimeInterval
    let end: TimeInterval
    let text: String

    var id: String { "\(start)-\(end)-\(text)" }

    static func load(from url: URL?) -> [TranscriptCue] {
        guard let url, let content = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        let lines = content.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var result: [TranscriptCue] = []
        var index = 0
        while index < lines.count {
            let line = lines[index]
            guard line.contains(" --> ") else { index += 1; continue }
            let times = line.components(separatedBy: " --> ")
            guard times.count == 2,
                  let start = parseTime(times[0]),
                  let end = parseTime(times[1].components(separatedBy: " ")[0]) else {
                index += 1
                continue
            }
            index += 1
            var textLines: [String] = []
            while index < lines.count && !lines[index].trimmingCharacters(in: .whitespaces).isEmpty {
                textLines.append(lines[index])
                index += 1
            }
            let text = textLines.joined(separator: " ")
                .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { result.append(TranscriptCue(start: start, end: end, text: text)) }
        }
        return result
    }

    private static func parseTime(_ value: String) -> TimeInterval? {
        let pieces = value.replacingOccurrences(of: ",", with: ".").split(separator: ":")
        guard (2...3).contains(pieces.count), let seconds = Double(pieces[pieces.count - 1]),
              let minutes = Double(pieces[pieces.count - 2]) else { return nil }
        let hours = pieces.count == 3 ? Double(pieces[0]) : 0
        guard let hours else { return nil }
        return hours * 3600 + minutes * 60 + seconds
    }
}
