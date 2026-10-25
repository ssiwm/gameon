# Dead Air '87 — wydanie na Steam (krok po kroku)

Przewodnik dopasowany do **tego** repo (Godot 4.7.2 + GodotSteam 4.23). Opisuje drogę od
protypu/testów (App ID 480) do **własnej aplikacji Steam** i wysyłki builda przez SteamPipe.

> Stan obecny: gra łączy się przez ENet (IP), a Steam (`scripts/steam_net.gd`) to dodatkowy
> transport — lobby, zaproszenia, relay Valve. Na dev/test używa się publicznego App ID
> **480** (Spacewar). Pod wydanie potrzebny jest **własny App ID**.

---

## Faza 0 — co już masz w repo (sprawdź przed startem)

- [x] Wtyczka **GodotSteam 4.23** w `prototype/addons/godotsteam/` (win64 + linux64, `SteamMultiplayerPeer`).
- [x] Wrapper sieci: `prototype/scripts/steam_net.gd` (lobby, `+connect_lobby`, overlay F2).
- [x] Presety eksportu: `prototype/export_presets.cfg` → Windows i Linux.
- [ ] **Własny App ID** (obecnie `480`) — Faza 2 poniżej.
- [ ] **Strona sklepowa** Steam (capsule, opis, trailer) — Faza 3.
- [ ] **Build produkcyjny** + SteamPipe upload — Fazy 4–5.
- [ ] *(Opcjonalnie)* **Osiągnięcia / statystyki** — Faza 6.

Narzędzia do zainstalowania na komputerze buildowym:
- Godot 4.7.2 + **export templates 4.7.2** (Editor → Manage Export Templates).
- **SteamCMD** + **Steamworks SDK** (do uploadu): <https://partner.steamgames.com/downloads/list>.
- Klient Steam, zalogowany na konto deweloperskie.

---

## Faza 1 — konto Steamworks + Steam Direct (formalności)

1. Wejdź na <https://partner.steamgames.com/> i zaloguj się kontem Steam (tym samym, którym wydajesz grę).
2. Wypełnij **profil deweloperski** firmy: dane, adres, osoba kontaktowa.
3. Opłać **Steam Direct**:
   - jednorazowo **100 USD** na aplikację,
   - **zwrot** po osiągnięciu **1000 USD** przychodu z aplikacji,
   - podajasz **konto bankowe** (do wypłat), dane podatnika (formularz W-8BEN / W-9),
   - **weryfikacja wieku** (selfie z dokumentem) oraz weryfikacja tożsamości firmy.
4. Poczekaj na akceptację (zazwyczaj kilka dni do ~2 tygodni). Do czasu akceptacji nie możesz
   utworzyć aplikacji.

> Bez Steam Direct nie dostaniesz własnego App ID — gra wtedy działa tylko na testowym 480.

---

## Faza 2 — utworzenie aplikacji i podmiana App ID

1. W Steamworks: **Users & Permissions → Applications → Create New Application**. Nadaj nazwę
   (np. *Dead Air '87*) i zapisz nadany **AppID** (np. `2XXXXXX`) oraz **AppID typu "Game"**.
2. **Podmień App ID w dwóch miejscach** (reszta kodu tego nie twardzi):

   ```bash
   # 1) wrapper sieci
   prototype/scripts/steam_net.gd
   #   linia: const APP_ID := 480      →  const APP_ID := 2XXXXXX

   # 2) plik testowy obok projektu (TYLKO do dev/testu!)
   prototype/steam_appid.txt
   #   480                             →  2XXXXXX
   ```

3. W Steamworks skonfigururuj podstawy instalacji:
   - **Install → General**: nazwa, foldery, obsługiwane systemy (Windows x64, Linux — i dzięki
     Proton Steam Deck).
   - **Supported Languages**: angielski + polski (gra ma już tłumaczenia w `translations/`).

> **Ważne pod build sklepowy:** plik `steam_appid.txt` **musi zostać usunięty z paczki**, która
> idzie do graczy. Na prawdziwym Steamie App ID pochodzi z uruchomionego klienta; plik w folderze
> gry służy wyłącznie do uruchamiania z edytora/testów. Zobacz Faza 5, krok 3.

## Faza 3 — strona sklepowa (można robić równolegle, zanim gra jest gotowa)

W Steamworks → **Store Page → Basic Info** przygotuj obowiązkowe elementy (strona musi być
**publicznie widoczna** min. **2 tygodnie** przed premierą):

- [ ] **Capsule art** (nagłówek + grafiki: hero capsule, small capsule).
- [ ] **Opis gry** (krótki + rozszerzony) — PL i EN. Bazuj na sekcjach 1–2 `GDD.md`.
- [ ] **Trailer** (minutowe, gameplay; „scream moments" z GDD §17.3).
- [ ] **Min. 5 zrzutów ekranu** (1920×1080).
- [ ] **Tagi i gatunek**: Co-op, Horror, Retro, Pixel Graphics, Action, 1980s, Atmospheric.
- [ ] **Cena** (GDD: 9.99 USD), data premiery (nawet wstępna), linki społeczności (Discord).
- [ ] **Film na YouTube** + link do press-kitu (PL/EN).

> **Wishlisty od dnia 1.** Cel z GDD §17.3: 10–15k wishlist przed EA. Demo (Strefa I) na
> **Steam Next Fest** — 2 festiwale przed premierą.

---

## Faza 4 — build produkcyjny

Presety są gotowe w `export_presets.cfg`. Eksportujesz z wiersza poleceń (na komputerze z
zainstalowanymi szablonami 4.7.2):

```bash
# Windows x64  →  prototype/build/windows/dead-air-87.exe  (+ .pck)
godot --headless --path prototype --export-release "Windows"

# Linux x64    →  prototype/build/linux/dead-air-87.x86_64  (+ .pck)
godot --headless --path prototype --export-release "Linux"
```

`embed_pck=false`, więc `.pck` leży obok binarki — **wysyłaj cały folder, nie sam `.exe`**.

### Biblioteki Steam (KRYTYCZNE — bez nich gra w ogóle nie wystartuje z siecią)

Gra potrzebuje **obok binarii** (nie w podfolderze!) natywnych bibliotek GodotSteam:

| Plik (źródło) | Skąd | Do celu (Windows) |
|---|---|---|
| `libgodotsteam.windows.template_release.x86_64.dll` | `addons/godotsteam/win64/` | obok `.exe` |
| `steam_api64.dll` | `addons/godotsteam/win64/` | obok `.exe` |

```bash
# po eksporcie Windows — skopiuj biblioteki obok .exe
cp prototype/addons/godotsteam/win64/*.dll prototype/build/windows/

# dla Linux analogicznie (.so obok binarki)
cp prototype/addons/godotsteam/linux64/*.so prototype/build/linux/
```

- **Windows wymaga też** zainstalowanego **Visual C++ 2015–2022 x64 Redistributable** — gra
  sprawdza to i pokazuje jasny komunikat, jeśli brakuje (`steam_net.gd:48`). Valve zwykle dba
  o ten runtime, ale przy własnym zipie/instalatorze dołóż go.
- Sprawdź logikę braku Steama: bez klienta/pluginu gra ma działać dalej na ENet (przyciski
  Steam w lobby wyszarzone) — wrapper to już obsługuje (`SteamNet.is_available()`).

## Faza 5 — SteamPipe: wysyłka builda do Steam

1. **SteamCMD** — rozpakuj pobrany SDK, np. do `C:\steamcmd`.
2. **Skrypty VDF** — przygotuj trzy pliki (klucze Steamworks znajdziesz w
   **Edit Store → SteamPipe → Builds**):

   `app_build_1234.vdf` (upload całej aplikacji):
   ```vdf
   "AppBuild"
   {
       "AppID" "1234567"            // ← twój AppID (ten typu Game)
       "Desc" "Dead Air '87 release build"
       "ContentRoot" "..\content\" // folder, w którym leżą podfoldery depotów
       "BuildOutput" "..\output\"
       "Depots"
       {
           "1234561" "depot_1234561.vdf"   // Windows depot
           "1234562" "depot_1234562.vdf"   // Linux depot
       }
   }
   ```

   `depot_1234561.vdf` (Windows depot):
   ```vdf
   "DepotBuild"
   {
       "DepotID" "1234561"
       "ContentRoot" "C:\path\to\prototype\build\windows\"   // pliki do wysłania
       "FileMapping"
       {
           "LocalPath" "*"      // wszystko z ContentRoot
           "DepotPath" "."      // w korzeniu depotu
           "Recursive" "1"
       }
       "FileExclusion" "steam_appid.txt"   // ← usuń plik testowy z paczki sklepowej!
   }
   ```
   (depot Linux — analogicznie, `ContentRoot` na `build\linux\`.)

3. **Upload** przez SteamCMD:
   ```bash
   steamcmd +login <konto_dev> +app_build "C:\sciezka\app_build_1234.vdf" +quit
   ```

4. W Steamworks ustaw **build na default** na odpowiedniej gałęzi (branch):
   - gałąź `default` → widoczna dla wszystkich,
   - gałąź `beta` / `playtest` → zamknięte testy (tu świetnie sprawdzi się obecny App ID 480,
     zanim dostaniesz własny).

5. **Test:** zainstaluj grę przez Steam na czystym koncie testowym, sprawdź start, lobby Steam,
   zaproszenia (F2), relay — u siebie, potem u znajomego z innej sieci.

---

## Faza 6 — osiągnięcia i statystyki (opcjonalnie, ale polecane przed premierą)

Obecnie w kodzie **nie ma** achievementów — to do dodania. Steam definiuje je w panelu
(**Stats & Achievements → New Achievement**), a gra wywołuje je przez GodotSteam:

```gdscript
# Steam (przez singleton "Steam"): Steam.setAchievement("ACH_...") ; Steam.storeStats()
```

Proponowane proste osiągnięcia bazujące na istniejących systemach (hałas, Stalker, boss, bronie):
- „Pierwszy kontakt" — zabij pierwszego Trzoska.
- „Cisza to złoto" — ukończ misję bez alarmu.
- „Przesterowanie" — użyj Q, by ściągnąć Stalkera z drużyny.
- „Ktoś to słyszy" — obudź Stalkera strzałem SPECTER-1.
- „Matka" — pokonaj Żyłę (boss).

## Faza 7 — Steam Deck i Proton

- Preset **Linux** masz — Steam automatycznie rozpozna wersję Linuksową i uruchomi ją natywnie
  na Decku (najlepsza opcja, bez nakładu Proton).
- Zweryfikuj zgodność: w Steamworks **Decky** lub zwykły test na Steam Decku. Upewnij się, że:
  - sterowanie padakiem działa (mapowanie w Godot — sprawdź akcje pad w `actions.gd`),
  - `GL Compatibility` (używany renderer) działa pod Protonem/Linux (zazwyczaj tak),
  - tekst jest czytelny przy małym oknie (HUD ma skalę — sprawdź `hud.gd`).

---

## Faza 8 — checklista przed premierą (podsumowanie)

- [ ] Steam Direct opłacony, konto bankowe + podatki zweryfikowane.
- [ ] Własny App ID podmieniony w `steam_net.gd` (`APP_ID`) i `steam_appid.txt`.
- [ ] Strona sklepowa kompletna i widoczna ≥2 tyg. przed premierą.
- [ ] Build Windows + Linux wyeksportowany, biblioteki `*.dll`/`*.so` obok binarki.
- [ ] `steam_appid.txt` **wykluczony** z depotów (lub usunięty z folderu paczki).
- [ ] Upload przez SteamPipe zakończony, build ustawiony na `default`.
- [ ] Test instalacji ze Steam na czystym koncie (start, lobby, overlay F2, relay).
- [ ] *(Opcjonalnie)* Osiągnięcia dodane w panelu i wywoływane w grze.
- [ ] *(Opcjonalnie)* Steam Deck — zweryfikowana zgodność.

---

### Szybka ściąga — co i gdzie zmienić

| Co | Plik | Wartość |
|---|---|---|
| App ID (kod) | `prototype/scripts/steam_net.gd` | `const APP_ID := 480` → własny |
| App ID (test) | `prototype/steam_appid.txt` | `480` → własny (usuń z paczki!) |
| Nazwa gry | `prototype/project.godot` | `config/name="Dead Air '87 Prototype"` → finalna |
| Wersja/demo | `prototype/scripts/settings.gd` | `DEMO` / `STORE_URL` ustaw pod wydanie |
| Export | `prototype/export_presets.cfg` | presety Windows/Linux gotowe |
