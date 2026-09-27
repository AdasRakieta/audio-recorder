import AVFoundation
import AVKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var capture: CaptureCoordinator
    @StateObject private var teamsImports = TeamsImportStore()
    @State private var importingRecording = false
    @State private var importError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Nagrania ze spotkań Teams") {
                    Text("Podczas spotkania uruchom nagrywanie w Teams. Po spotkaniu pobierz nagranie do Plików i zaimportuj je tutaj. Recorder Probe nie przechwytuje obecnie głosu uczestników Teams bezpośrednio.")
                        .foregroundStyle(.secondary)
                    Button {
                        importingRecording = true
                    } label: {
                        Label("Importuj nagranie Teams", systemImage: "square.and.arrow.down")
                    }
                    ForEach(teamsImports.recordings) { recording in
                        NavigationLink {
                            TeamsRecordingDetail(store: teamsImports, recordingID: recording.id)
                        } label: {
                            VStack(alignment: .leading) {
                                Text(recording.title)
                                Text(recording.transcript == nil ? "Bez transkrypcji" : "Transkrypcja VTT dostępna")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section("Test Teams") {
                    Text("W oknie systemowym wybierz cały ekran. Recorder Probe jest odbiorcą nagrania, a nie źródłem dźwięku. Następnie przejdź do Teams. Mikrofon wybierasz w oknie systemowym.")
                        .foregroundStyle(.secondary)
                    Button {
                        capture.presentPicker()
                    } label: {
                        Label("Wybierz ekran i rozpocznij", systemImage: "record.circle")
                    }
                    .disabled(capture.isCapturing || capture.isFinishing)

                    Button(role: .destructive) {
                        Task { await capture.stop() }
                    } label: {
                        Label("Zakończ i zapisz", systemImage: "stop.circle")
                    }
                    .disabled(!capture.isCapturing || capture.isFinishing)
                }

                Section("Stan") {
                    LabeledContent("Przechwytywanie", value: capture.status)
                    LabeledContent("Próbki z aplikacji", value: "\(capture.systemSamples)")
                    LabeledContent("Próbki z mikrofonu", value: "\(capture.microphoneSamples)")
                    Text("Licznik próbek potwierdza tylko dostarczenie danych przez system. Odsłuchaj plik, aby sprawdzić, czy zawiera głos z Teams.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if let sessionURL = capture.lastSessionURL {
                    let systemURL = CaptureCoordinator.fileURL(in: sessionURL, named: "system.m4a")
                    let microphoneURL = CaptureCoordinator.fileURL(in: sessionURL, named: "microphone.m4a")
                    let reportURL = CaptureCoordinator.fileURL(in: sessionURL, named: "report.json")
                    Section("Ostatni test") {
                        Text(sessionURL.lastPathComponent)
                            .font(.caption.monospaced())
                        if FileManager.default.fileExists(atPath: systemURL.path) {
                            ShareLink(item: systemURL) {
                                Label("Udostępnij dźwięk aplikacji", systemImage: "square.and.arrow.up")
                            }
                        }
                        if FileManager.default.fileExists(atPath: microphoneURL.path) {
                            ShareLink(item: microphoneURL) {
                                Label("Udostępnij mikrofon", systemImage: "mic")
                            }
                        }
                        ShareLink(item: reportURL) {
                            Label("Udostępnij raport", systemImage: "doc.text")
                        }
                    }
                }

                if let error = capture.lastError {
                    Section("Błąd") {
                        Text(error)
                            .foregroundStyle(.red)
                            .textSelection(.enabled)
                    }
                }
            }
            .navigationTitle("Recorder Probe")
            .fileImporter(isPresented: $importingRecording, allowedContentTypes: [.movie, .audio]) { result in
                do { try teamsImports.importRecording(from: result.get()) }
                catch { importError = error.localizedDescription }
            }
            .alert("Błąd importu", isPresented: Binding(
                get: { importError != nil },
                set: { if !$0 { importError = nil } }
            )) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(importError ?? "")
            }
        }
    }
}

private struct TeamsRecordingDetail: View {
    @ObservedObject var store: TeamsImportStore
    let recordingID: String
    @State private var player: AVPlayer?
    @State private var isPlaying = false
    @State private var importingTranscript = false
    @State private var importError: String?

    private var recording: TeamsRecording? {
        store.recordings.first { $0.id == recordingID }
    }

    var body: some View {
        Form {
            if let recording {
                Section("Nagranie") {
                    Text(recording.title)
                    if let player {
                        if ["mp4", "mov"].contains(recording.media.pathExtension.lowercased()) {
                            VideoPlayer(player: player)
                                .frame(minHeight: 260)
                        } else {
                            Button {
                                if isPlaying { player.pause() } else { player.play() }
                                isPlaying.toggle()
                            } label: {
                                Label(isPlaying ? "Pauza" : "Odtwórz", systemImage: isPlaying ? "pause.fill" : "play.fill")
                            }
                        }
                    }
                    ShareLink(item: recording.media) {
                        Label("Udostępnij nagranie", systemImage: "square.and.arrow.up")
                    }
                }
                Section("Transkrypcja Teams") {
                    Button {
                        importingTranscript = true
                    } label: {
                        Label("Importuj plik VTT", systemImage: "doc.text")
                    }
                    if let transcript = recording.transcript {
                        ShareLink(item: transcript) {
                            Label("Udostępnij VTT", systemImage: "square.and.arrow.up")
                        }
                        ForEach(TranscriptCue.load(from: transcript)) { cue in
                            Button {
                                player?.seek(to: CMTime(seconds: cue.start, preferredTimescale: 600))
                                player?.play()
                                isPlaying = true
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(Self.timeLabel(cue.start))
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                    Text(cue.text)
                                        .foregroundStyle(.primary)
                                }
                            }
                        }
                    } else {
                        Text("Po spotkaniu pobierz transkrypcję VTT z Teams. Jeśli nie masz prawa do pobrania, poproś organizatora o plik.")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Spotkanie Teams")
        .task(id: recording?.media) {
            if let recording { player = AVPlayer(url: recording.media) }
        }
        .onDisappear { player?.pause() }
        .fileImporter(isPresented: $importingTranscript, allowedContentTypes: [.item]) { result in
            guard let recording else { return }
            do { try store.importTranscript(from: result.get(), for: recording) }
            catch { importError = error.localizedDescription }
        }
        .alert("Błąd importu", isPresented: Binding(
            get: { importError != nil },
            set: { if !$0 { importError = nil } }
        )) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(importError ?? "")
        }
    }

    private static func timeLabel(_ seconds: TimeInterval) -> String {
        let whole = Int(seconds)
        return String(format: "%02d:%02d:%02d", whole / 3600, (whole / 60) % 60, whole % 60)
    }
}
