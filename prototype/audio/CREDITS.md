# Dźwięk — źródła i licencje

GENEROWANE przez `tools/bake_audio.py` z `tools/audio_sources.json` — nie edytuj ręcznie.

Biblioteka jest hybrydowa (`AUDIO_PLAN.md`): synteza z `tools/bake_*.py`, nagrania z bibliotek i pliki wygenerowane lokalnie.
Repo jest publiczne, a licencja bibliotek zabrania udostępniania dźwięków dalej, więc w repo nie ma ani nagrań,
ani assetów z nich zrobionych: lokalny bake zapisuje je do `prototype/audio_licensed/` (poza repo), a gra używa ich
zamiast syntezy, jeśli tam są. Nagrania pobiera `tools/audio_lib_fetch.py sync`.

## Licencje

- **sonniss-gdc-2.0** — Sonniss GDC Bundle License 2.0 (od 2026-08-27). Wolno używać i przerabiać w dowolnej liczbie projektów własnych, także komercyjnych, bez podawania autora. Nie wolno udostępniać dźwięków innym jako efektów dźwiękowych (także przerobionych; osobno ani w paczce, szablonie czy SDK) ani trenować na nich modeli AI.
  Tekst: <https://sonniss.com/gdc-bundle-license/> (sprawdzony 2026-10-12).

## Źródła

| Id | Rodzaj | Paczka albo model | Dostawca | Licencja | Plik albo opis |
|---|---|---|---|---|---|
| ak47_open_2m | nagranie | Sonniss GDC 2018 — The Outdoor Gun Acoustics Library | Pole Position Production | sonniss-gdc-2.0 | AK47_big_open_area_2m_above_behind_gun_RSM191_M.wav |
| akm_close_1m | nagranie | Sonniss GDC 2016 — AKM 7.62x39mm | Pole Position Production | sonniss-gdc-2.0 | AKM_7.62x39mm_1m_left_on_ground_DPA4062_clean_Triple_shots_x_1.wav |
| boot_concrete_walk | nagranie | Sonniss GDC 2018 — Ultimate Bare Feet Expansion | Joshua Reinhardt | sonniss-gdc-2.0 | BOOT_CONC CLEAN_WALK.R.wav |
| monster_growls_4 | nagranie | Sonniss GDC 2018 — Monsters | Olivier Girardot | sonniss-gdc-2.0 | Monster Growls 4.wav |
