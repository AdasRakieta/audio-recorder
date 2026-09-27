import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var capture: CaptureCoordinator

    var body: some View {
        NavigationStack {
            Form {
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
        }
    }
}
