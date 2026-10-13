DEAD AIR '87 — build testowy {VERSION} (Windows)
=====================================================

Dziękujemy za pomoc w testach. To wczesna wersja gry: co-op dla 1–4 osób.

1. URUCHOMIENIE
---------------
- Rozpakuj CAŁY zip do zwykłego folderu (np. na pulpicie). Nie uruchamiaj gry z wnętrza archiwum.
- Uruchom dead-air-87.exe.
- Windows może pokazać okno „System Windows ochronił ten komputer" (plik nie jest podpisany):
  kliknij „Więcej informacji", potem „Uruchom mimo to".
- Wymagania: Windows 10 albo 11 (64-bit), karta graficzna z obsługą Vulkan albo DirectX 12.
- Graj w słuchawkach — dźwięk jest częścią rozgrywki.

2. GRA W SIECI
--------------
Wszyscy gracze muszą mieć TEN SAM build. Numer wersji jest w stopce menu głównego: {VERSION}

W menu głównym wybierz „LAN / STEAM". Są dwa sposoby połączenia:

A) Przez Steam (przez internet, bez ustawiania routera)
   - Każdy ma uruchomionego i zalogowanego Steama.
   - Wszyscy gracze są znajomymi hosta na Steamie.
   - Host: STEAM HOST. Potem F2 (zaproszenie znajomych) albo przepisanie ID lobby pozostałym.
   - Pozostali: przyjmują zaproszenie albo wpisują ID lobby i klikają STEAM JOIN.
   - W Steamie gra jest widoczna jako „Spacewar" (testowy identyfikator) — to normalne.

B) Po adresie IP (sieć lokalna albo wspólny VPN)
   - Host: HOST GAME. Przy pierwszym uruchomieniu Zapora Windows zapyta o dostęp do sieci — zezwól.
   - Pozostali: wpisują adres IP hosta (np. 192.168.0.12) i klikają JOIN.
   - Gra używa portu 8910 (UDP). Przez internet bez Steama host musi przekierować ten port
     na routerze albo wszyscy muszą być w jednej sieci VPN.

3. STEROWANIE
-------------
Lista klawiszy jest na dole ekranu w grze oraz pod klawiszem pomocy. Gra obsługuje też pada.

4. PO TEŚCIE — CO ODESŁAĆ
-------------------------
- Numer wersji: {VERSION}
- Host: folder z dziennikiem sesji
  %APPDATA%\Godot\app_userdata\Dead Air '87 Prototype\sessions\
  (wklej tę ścieżkę w pasek adresu Eksploratora; pliki nigdzie nie są wysyłane same).
- Opis błędu: co robiłeś, co się stało, ilu było graczy i kto był hostem.
  Zrzut ekranu albo nagranie bardzo pomagają.
