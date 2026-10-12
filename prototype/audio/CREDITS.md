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
| crossbow_loose | nagranie | Sonniss GDC 2019 — Nocked | Eiravaein Works | sonniss-gdc-2.0 | Nocked,archery,firing,loose,crossbow1,carbonbolt,atbow,snap,buzz,airy,bright,alt.wav |
| explosion_deep_02 | nagranie | Sonniss GDC 2020 — Explosions | Stefano Cremona | sonniss-gdc-2.0 | DeepExplosion02.wav |
| explosion_large_08 | nagranie | Sonniss GDC 2017 — Explosion Sound Pack | Gamemaster Audio | sonniss-gdc-2.0 | explosion_large_08.wav |
| grenade_launcher_smoke | nagranie | Sonniss GDC 2023 — Detonation - Explosion | BluezoneCorp | sonniss-gdc-2.0 | Bluezone_BC0277_weapon_smoke_grenade_launcher_003.wav |
| monster_growls_4 | nagranie | Sonniss GDC 2018 — Monsters | Olivier Girardot | sonniss-gdc-2.0 | Monster Growls 4.wav |
| saiga12_close_1m | nagranie | Sonniss GDC 2016 — Saiga-12 12g solid slug | Pole Position Production | sonniss-gdc-2.0 | SAIGA-12_12g_solid_slug_1m_left_off_axis_MKH416_clean_Single_shots_x_5.wav |
| shotgun_quick_pump | nagranie | Sonniss GDC 2016 — 12 Gauge Shotgun | TS Sound | sonniss-gdc-2.0 | Shotgun_Quick Pump_01.wav |
| usas12_close_1m | nagranie | Sonniss GDC 2016 — USAS-12 12g solid slug | Pole Position Production | sonniss-gdc-2.0 | USAS-12_12g_solid_slug_1m_right_CS3_clean_Double_shots_x_1.wav |
