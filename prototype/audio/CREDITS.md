# Dźwięk — źródła i licencje

GENEROWANE przez `tools/bake_audio.py` z `tools/audio_sources.json` — nie edytuj ręcznie.

Biblioteka jest hybrydowa (`AUDIO_PLAN.md`): synteza z `tools/bake_*.py`, nagrania z bibliotek i pliki wygenerowane lokalnie.
Nagrań z bibliotek nie ma w repo w postaci źródłowej (pobiera je `tools/audio_lib_fetch.py`).
Rejestr obejmuje też źródła wersji alternatywnych z `tools/bake_hybrid.py`, których gra jeszcze nie używa.

## Licencje

- **sonniss-gdc-2.0** — Sonniss GDC Bundle License 2.0 (od 2026-08-27). Wolno używać i przerabiać w dowolnej liczbie projektów własnych, także komercyjnych, bez podawania autora. Nie wolno udostępniać dźwięków innym jako efektów dźwiękowych (także przerobionych; osobno ani w paczce, szablonie czy SDK) ani trenować na nich modeli AI.
  Tekst: <https://sonniss.com/gdc-bundle-license/> (sprawdzony 2026-10-12).
- **stable-audio-community** — Stability AI Community License (karta modelu: stable-audio-community). Wyniki należą do użytkownika i mogą być używane komercyjnie przy rocznym przychodzie do 1 mln USD; użycie komercyjne wymaga rejestracji w Stability AI. Sprawdzony tekst umowy ogólnej z 2024-07-05 — to, że obejmuje modele Stable Audio 3, wynika z nazwy licencji na karcie modelu i wymaga potwierdzenia przed wydaniem.
  Tekst: <https://stability.ai/community-license-agreement> (sprawdzony 2026-10-12).

## Źródła

| Id | Rodzaj | Paczka albo model | Dostawca | Licencja | Plik albo opis |
|---|---|---|---|---|---|
| ak47_open_2m | nagranie | Sonniss GDC 2018 — The Outdoor Gun Acoustics Library | Pole Position Production | sonniss-gdc-2.0 | AK47_big_open_area_2m_above_behind_gun_RSM191_M.wav |
| akm_close_1m | nagranie | Sonniss GDC 2016 — AKM 7.62x39mm | Pole Position Production | sonniss-gdc-2.0 | AKM_7.62x39mm_1m_left_on_ground_DPA4062_clean_Triple_shots_x_1.wav |
| boot_concrete_walk | nagranie | Sonniss GDC 2018 — Ultimate Bare Feet Expansion | Joshua Reinhardt | sonniss-gdc-2.0 | BOOT_CONC CLEAN_WALK.R.wav |
| monster_growls_4 | nagranie | Sonniss GDC 2018 — Monsters | Olivier Girardot | sonniss-gdc-2.0 | Monster Growls 4.wav |
| stalker_growl_gen_a | wygenerowany | Stable Audio 3 Medium (ComfyUI, lokalnie) | wygenerowany w projekcie | stable-audio-community | Deep guttural creature growl, low throaty vocal fry rumble with wet rasp, slow menacing exhale of a large unseen monster, close microphone, dry recording, horror sound effect |
| stalker_growl_gen_b | wygenerowany | Stable Audio 3 Medium (ComfyUI, lokalnie) | wygenerowany w projekcie | stable-audio-community | Deep guttural creature growl, low throaty vocal fry rumble with wet rasp, slow menacing exhale of a large unseen monster, close microphone, dry recording, horror sound effect |
