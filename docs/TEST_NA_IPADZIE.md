# Instalacja i test Recorder Probe na iPadzie

To **prototyp wykonalności**, nie gotowy dyktafon do ważnych wykładów. Jego zadaniem jest sprawdzić, czy iPadOS 27 udostępnia głos rozmówcy Teams w przechwytywaniu dźwięku. Nie zakładaj sukcesu, dopóki nie odsłuchasz plików z rzeczywistego połączenia.

## Kto za co odpowiada

| Element | Zadanie | Konto Apple |
| --- | --- | --- |
| GitHub Actions | Buduje **niepodpisane** IPA. | Nie używa Twojego konta. |
| Raspberry Pi | Przechowuje IPA, sumę SHA-256, stronę `/audio/` i `source.json`. | Nie loguje się do Apple, nie podpisuje ani nie odnawia certyfikatu. |
| Windows + iloader | Jednorazowo instaluje SideStore przez USB. | W iloader logujesz konto, którym chcesz podpisywać aplikacje. |
| iPad + SideStore | Pobiera IPA, podpisuje go dla tego iPada, instaluje i odnawia podpis. | W SideStore logujesz **to samo** konto co w iloader. Nie zmieniasz konta iCloud iPada. |

Nie ma tutaj gotowego „podpisanego przez malinę” IPA. Przy darmowym koncie Apple certyfikat jest krótkotrwały i związany z urządzeniem; samo pobranie pliku w Safari nie wystarcza do instalacji. Strona nie może kliknięciem odnowić podpisu. SideStore robi to na iPadzie, zwykle na 7 dni. Nie wpisuj hasła Apple na stronie maliny, w repozytorium ani w terminalu SSH. [Instrukcja instalacji SideStore](https://docs.sidestore.io/docs/installation/install), [opis podpisywania i odświeżania](https://docs.sidestore.io/docs/faq).

## 1. Sprawdzenie maliny

Malina jest już skonfigurowana. Jej strona działa tylko w prywatnej sieci Tailscale:

- Strona: <https://malina.tail384b18.ts.net/audio/>
- Źródło aktualizacji: <https://malina.tail384b18.ts.net/audio/source.json>
- Aktualne IPA: <https://malina.tail384b18.ts.net/audio/releases/RecorderProbe-0.1.0-1-unsigned.ipa>

Na Windows z włączonym Tailscale otwórz stronę. Powinieneś zobaczyć **Recorder Probe**, wersję `0.1.0 (1)` i trzy przyciski. W PowerShell można sprawdzić odpowiedź serwera:

```powershell
curl.exe -I https://malina.tail384b18.ts.net/audio/
curl.exe -I https://malina.tail384b18.ts.net/audio/source.json
```

Obie odpowiedzi powinny mieć kod `200`. Jeśli potrzebujesz sprawdzić konfigurację na malinie, zaloguj się przez SSH i uruchom `tailscale serve status`; powinien pokazać ścieżkę `/audio/` prowadzącą do katalogu `audio-recorder-distribution`. Port `8444` nie jest już używany. [Dokumentacja Tailscale Serve](https://tailscale.com/docs/reference/tailscale-cli/serve).

## 2. Pierwsza instalacja SideStore: Windows i iPad

Przygotuj kabel USB do transmisji danych, iPada z kodem blokady, Wi-Fi, konto Apple do podpisu i możliwość odebrania kodu uwierzytelnienia Apple. Konto iCloud zalogowane na iPadzie **może być inne**. Zainstaluj na iPadzie z App Store **LocalDevVPN** oraz **Tailscale**; iPad musi należeć do tej samej sieci Tailscale co malina. Tailscale był wcześniej widoczny w sieci, ale sprawdź stan aplikacji na iPadzie.

1. Na Windows zainstaluj iTunes oraz najnowszy **iloader** według [wymagań SideStore dla Windows](https://docs.sidestore.io/docs/installation/prerequisites). Posiadany AltServer nie zastępuje iloader w tej ścieżce. Dokumentacja SideStore zaleca iTunes pobrany bezpośrednio od Apple; jeżeli wykrywanie urządzenia nie działa, podaje też Apple Devices jako alternatywę.
2. Podłącz odblokowanego iPada przez USB. Na iPadzie wybierz **Zaufaj temu komputerowi** i wpisz kod urządzenia.
3. Otwórz iloader na Windows. Zaloguj konto Apple, którego chcesz użyć **w SideStore**. Wybierz iPada i **Install SideStore (Stable)**. Jeśli Apple poprosi o kod 2FA, dokończ logowanie w iloader. Nie wylogowuj konta iCloud na iPadzie.
4. Jeśli przy otwieraniu SideStore pojawia się **„Niezaufany deweloper”**, na iPadzie wejdź w **Ustawienia → Ogólne → VPN i zarządzanie urządzeniem**. W sekcji aplikacji dewelopera wybierz konto użyte w iloader i dotknij **Zaufaj** lub **Pozwól i uruchom ponownie**; po restarcie dokończ potwierdzenie kodem urządzenia. Zrób to przy połączeniu z Internetem. To osobna czynność od włączenia Trybu dewelopera. Następnie w **Ustawienia → Prywatność i ochrona** włącz **Tryb dewelopera**. W tej ścieżce jest potrzebny do uruchomienia aplikacji podpisanej dewelopersko. Przełącznik może nie być widoczny **przed** sparowaniem urządzenia i próbą instalacji przez iloader; Apple pokazuje go dopiero po zainicjowaniu parowania. Po włączeniu iPad uruchomi się ponownie, a po restarcie trzeba potwierdzić tryb kodem urządzenia. Jeśli po udanej instalacji SideStore przełącznika nadal nie ma, uruchom ponownie iPada, ponownie otwórz Ustawienia i sprawdź parowanie USB. [Wyjaśnienie Apple](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device), [instrukcja SideStore](https://docs.sidestore.io/docs/installation/install).
5. Połącz iPada z Wi-Fi. Uruchom LocalDevVPN i wybierz **Connect**. Otwórz SideStore, zaloguj **to samo konto** co w iloader, przejdź do **My Apps** i dotknij licznika `7 DAYS` przy SideStore, aby wykonać pierwszy refresh. Jeżeli pojawi się pytanie o certyfikat, zastosuj wskazówki SideStore.
6. Sprawdź, czy SideStore ponownie się uruchamia i licznik pokazuje około 7 dni. Dopiero teraz przejdź do instalowania Recorder Probe.

Jeśli iloader nie widzi iPada, najpierw sprawdź kabel, komunikat **Zaufaj**, iTunes/Apple Devices oraz sterowniki Apple według [oficjalnej instrukcji](https://docs.sidestore.io/docs/installation/prerequisites). Nie kasuj istniejących aplikacji tylko po to, by ponowić próbę.

## 3. Instalacja Recorder Probe ze strony

Na tym iPadzie aktywowanie LocalDevVPN wyłącza Tailscale. SideStore wymaga LocalDevVPN podczas instalowania, aktualizowania i odświeżania, więc **nie próbuj utrzymywać obu VPN jednocześnie**. [Wymagania SideStore](https://docs.sidestore.io/docs/installation/prerequisites).

1. Na iPadzie włącz Tailscale. W Safari otwórz <https://malina.tail384b18.ts.net/audio/>. Upewnij się, że widzisz wersję `0.1.0 (1)`.
2. Wybierz **Pobierz IPA do Plików**. Jeśli Safari tylko pokaże pobranie, otwórz **Pliki → Pobrane** i upewnij się, że znajduje się tam `RecorderProbe-0.1.0-1-unsigned.ipa`. To plik niepodpisany; samo pobranie go nie instaluje.
3. Wyłącz Tailscale, włącz LocalDevVPN i pozostaw Wi-Fi aktywne.
4. Otwórz **SideStore → My Apps → +** i wybierz pobrany IPA z aplikacji Pliki. Zaczekaj, aż SideStore go podpisze i zainstaluje. Sprawdź, czy `Recorder Probe` pojawił się na ekranie początkowym oraz w My Apps; zanotuj liczbę dni do końca podpisu.

Źródło `source.json` i przycisk **Otwórz IPA w SideStore** wymagają, by SideStore mogło w trakcie instalacji pobrać plik z adresu Tailscale. Przy obecnym konflikcie VPN **nie traktujemy instalacji ani automatycznych aktualizacji z tego prywatnego URL jako działających**. Nowe wersje pobieraj tą samą metodą do Plików i importuj w SideStore. Odświeżenie już zainstalowanej aplikacji wykonuj z LocalDevVPN; nie wymaga otwierania strony maliny. Jeśli lokalny import albo odświeżenie się nie powiedzie, zanotuj dokładny komunikat.

## 4. Test nagrywania Teams

Zrób krótką, umówioną rozmowę testową z drugą osobą i upewnij się, że nagrywanie jest dozwolone. Nie zaczynaj od sześciogodzinnego wykładu. Po każdym teście zatrzymaj zapis w aplikacji, wyeksportuj pliki i **odsłuchaj je**. Licznik próbek nie dowodzi, że zapisano głos rozmówcy.

| Próba | Ustawienie | Spodziewany materiał do sprawdzenia |
| --- | --- | --- |
| A | Głośnik iPada; mikrofon w systemowym oknie nagrywania **wyłączony**; 30–60 s wypowiedzi rozmówcy w Teams. | `system.m4a`: czy słychać rozmówcę. `microphone.m4a` nie powinien zawierać Twojego głosu. |
| B | Słuchawki; mikrofon nagrywania wyłączony; ta sama próba. | `system.m4a`: czy nadal słychać rozmówcę. |
| C | Mikrofon nagrywania **włączony**; mówisz Ty i rozmówca; w Teams przełączasz własne wyciszenie. | `system.m4a` i `microphone.m4a`: czy strumienie są odrębne i co dzieje się po zmianie stanu mikrofonu w Teams. |
| D | Krótka próba bez połączenia z maliną; potem zmiana wyjścia audio. | Czy ukończone pliki zostają lokalnie i czy raport pokazuje przerwę lub błąd. |

Dla każdej próby:

1. Otwórz **Recorder Probe** i dotknij **Wybierz ekran i rozpocznij**.
2. W systemowym oknie wybierz **cały ekran**. Przełącznik mikrofonu ustaw zgodnie z próbą. Wróć do Teams i prowadź rozmowę 30–60 sekund.
3. Wróć do Recorder Probe i dotknij **Zakończ i zapisz**. Poczekaj na stan **Zakończono**. Jeśli widać **Przerwano**, **Nie rozpoczęto** albo sekcję **Błąd**, zapisz komunikat.
4. W sekcji **Ostatni test** użyj **Udostępnij dźwięk aplikacji**, **Udostępnij mikrofon** i **Udostępnij raport**. Zapisz pliki w aplikacji **Pliki**. W katalogu sesji są `system.m4a`, opcjonalnie `microphone.m4a`, oraz `report.json`.
5. Odsłuchaj każdy plik przez słuchawki. W `report.json` sprawdź `status`, liczbę próbek i `errors`. Zanotuj, czy słychać rozmówcę, własny mikrofon, ciszę, trzaski lub przerwy.

Przetestuj osobno zablokowanie ekranu i przerwanie rozmowy. Obecny prototyp nie jest jeszcze odpornym rejestratorem segmentowym: sześciogodzinna sesja, odzyskanie po zamknięciu aplikacji i brak miejsca **nie są** gotowymi funkcjami. Najpierw musimy potwierdzić podstawową jakość audio i podpisywanie.

## 5. Odświeżenie podpisu i aktualizacja

W SideStore otwórz **My Apps** i zapisz dzień wygaśnięcia aplikacji. Następnego dnia, przy Wi-Fi i LocalDevVPN, dotknij licznika dni przy `Recorder Probe` i sprawdź, czy wraca do około 7 dni. Powtórz przed upływem tygodnia. SideStore podejmuje próby odświeżania w tle, lecz iPadOS może opóźniać zadania; przez pełny cykl siedmiodniowy sprawdzaj licznik ręcznie. Malina nie uczestniczy w odświeżaniu podpisu. [FAQ SideStore](https://docs.sidestore.io/docs/faq).

Nowa wersja aplikacji wymaga nowego buildu z wyższym numerem w `project.yml` oraz ponownego uruchomienia `publish_portal.py` na malinie. Wtedy pojawi się w źródle SideStore; aktualizację wybierasz świadomie na iPadzie, poza nagrywaniem. Samo odświeżenie podpisu **nie** wymaga nowego buildu. Wersji `0.1.0 (1)` nie aktualizujemy poprzez podmianę IPA o tej samej nazwie.

## Co zgłosić po próbie

Podaj: model iPada i dokładną wersję iPadOS, czy działa strona z samym Tailscale i z włączonym LocalDevVPN, czy SideStore dodało źródło i zainstalowało IPA, stan/licznik po teście oraz wynik odsłuchu prób A–C. Przy błędzie przepisz dokładny komunikat. Do ustalenia przyczyny nagrywania przydatny jest `report.json` i krótki fragment audio z testu, o ile możesz go bezpiecznie udostępnić.
