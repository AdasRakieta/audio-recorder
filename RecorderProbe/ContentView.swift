import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var capture: CaptureCoordinator

    var body: some View {
        NavigationStack {
            Form {
                Section("Test Teams") {
                    Text("Włącz nagrywanie całego ekranu, przejdź do Teams i odtwórz fragment wykładu. Mikrofon wybierasz w systemowym oknie.")
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
                    Section("Ostatni test") {
                        Text(sessionURL.lastPathComponent)
                            .font(.caption.monospaced())
                        if FileManager.default.fileExists(atPath: sessionURL.appendingPathComponent("system.m4a").path) {
                            ShareLink(item: sessionURL.appendingPathComponent("system.m4a")) {
                                Label("Udostępnij dźwięk aplikacji", systemImage: "square.and.arrow.up")
                            }
                        }
                        if FileManager.default.fileExists(atPath: sessionURL.appendingPathComponent("microphone.m4a").path) {
                            ShareLink(item: sessionURL.appendingPathComponent("microphone.m4a")) {
                                Label("Udostępnij mikrofon", systemImage: "mic")
                            }
                        }
                        ShareLink(item: sessionURL.appendingPathComponent("report.json")) {
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
