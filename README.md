# Recorder Probe — test wykonalności na iPadOS 27

To jest **pierwszy etap** planowanej aplikacji. Korzysta z ScreenCaptureKit, który Apple udostępniło do przechwytywania całego ekranu na iOS/iPadOS 27. Wcześniej planowane ReplayKit Broadcast Upload Extension jest w dokumentacji Apple oznaczone jako niewspierane. Prototyp zapisuje **wyłącznie dźwięk**; klatki obrazu odrzuca.

## Co sprawdzamy

1. Czy strumień `.audio` zawiera głos wykładowcy z Teams przy wyłączonym mikrofonie nagrywania — osobno na głośniku i na słuchawkach.
2. Czy przełączenie mikrofonu w systemowym oknie przechwytywania daje osobny strumień `.microphone`, także gdy sam Teams używa mikrofonu.
3. Czy nagrywanie trwa po przejściu z aplikacji do Teams i bez sieci.
4. Czy aplikację można bezpłatnie podpisać na iPadzie i później odświeżyć.

Sama liczba buforów **nie oznacza**, że słychać głos Teams. Każdy plik trzeba odsłuchać. Aplikacja nie uruchamia nagrywania automatycznie: wymaga wyboru całego ekranu w oknie systemowym.

## Budowanie

Projekt jest opisany w `project.yml` dla [XcodeGen](https://github.com/yonaskolb/XcodeGen). Na Macu z Xcode 27: `xcodegen generate`, potem otworzyć `RecorderProbe.xcodeproj` i wybrać własny zespół podpisujący. Bezpłatny Personal Team trzeba sprawdzić na urządzeniu; sam build bez podpisu niczego tu nie potwierdza.

Workflow GitHub Actions buduje na standardowym runnerze `xcode-27` i publikuje **niepodpisane IPA** jako artifact. Plik nie instaluje się bez ponownego podpisania przez AltStore/AltServer. Nie umieszczaj Apple ID, haseł, profili ani kluczy podpisu w repozytorium lub artifactach.

Na Windows AltServer jest już zainstalowany. Najprostsza próba bez logowania się na konto iCloud iPada: połącz iPada przez USB, zaakceptuj **Zaufaj temu komputerowi**, włącz tryb deweloperski na iPadzie, a następnie przytrzymaj **Shift** i kliknij ikonę AltServer w zasobniku Windows. Wybierz **Sideload .ipa…** i wskaż wyodrębniony `RecorderProbe-unsigned.ipa` (nie plik ZIP). Do podpisu użyj konta Apple dostępnego na komputerze; nie trzeba zmieniać konta iCloud iPada. Ta ścieżka wymaga ręcznego ponowienia instalacji przed upływem 7 dni. [Instrukcja AltStore dla Windows](https://faq.altstore.io/altstore-classic/how-to-install-altstore-windows), [opcja Sideload .ipa w AltServer](https://faq.altstore.io/release-notes/altserver).

Gdy test nagrywania przejdzie, można rozważyć odświeżanie przez SideStore, które nie wymaga logowania do konta iCloud urządzenia, lecz wymaga zalogowania konta podpisującego wewnątrz SideStore na iPadzie. Nie zakładamy, że jest to możliwe w obecnym układzie kont. Jeśli instalacja lub podpisanie się nie uda, zapisz dokładny komunikat — to część testu wykonalności.

## Przebieg testu

1. Zainstaluj prototyp na iPadzie 10. generacji z iPadOS 27. Uruchom go i dotknij **Wybierz ekran i rozpocznij**. W systemowym oknie wybierz **cały ekran**; mikrofon na początek zostaw wyłączony.
2. Przejdź do Teams i odtwórz 30–60 sekund głosu podczas połączenia przez głośnik iPada. Wróć do prototypu i wybierz **Zakończ i zapisz**. Udostępnij i odsłuchaj `system.m4a`.
3. Powtórz ze słuchawkami. Następnie powtórz z włączonym mikrofonem w systemowym oknie i sprawdź oba pliki, w tym zachowanie po wyciszeniu i odciszeniu mikrofonu w Teams.
4. Wyłącz Wi-Fi i dane komórkowe, wykonaj krótki test offline, a następnie ponów na kilku minutach po zmianie wyjścia audio. W `CaptureTests/<UUID>/report.json` sprawdź liczniki i błędy.
5. Odrębnie przetestuj darmową instalację oraz odświeżenie na docelowym iPadzie i malinie. Nie zakładaj, że zgodność AltServer-Linux z iPadOS 27 jest pewna.

Po potwierdzeniu tych warunków rozwijamy zapis segmentowy, synchronizację z Raspberry Pi, transkrypcję i pełny interfejs. Jeśli cyfrowy strumień nie zawiera Teams lub darmowe odświeżanie nie działa, projekt zatrzymuje się na tej bramce i wymaga zmiany założeń.

## Ograniczenia prototypu

Prototyp nie obsługuje sześciogodzinnych sesji ani odzyskiwania po nagłym zamknięciu. Może zużywać pamięć przy długim nagrywaniu i nie powinien służyć do zapisu ważnych wykładów. `system.m4a` oraz `microphone.m4a` są osobnymi plikami. Ich obecność i liczniki stanowią materiał diagnostyczny, nie dowód zgodności Teams z przechwytywaniem.

Źródła: [przykład Apple dla ScreenCaptureKit na iOS 27](https://developer.apple.com/documentation/screencapturekit/capturing-screen-content-on-ios), [Apple o darmowych profilach](https://developer.apple.com/help/account/basics/about-your-developer-account), [AltServer-Linux](https://github.com/NyaMisty/AltServer-Linux).
