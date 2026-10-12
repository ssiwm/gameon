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
| arrow_whoosh | nagranie | Sonniss GDC 2020 — PARTICLES An Organic & Granular Journey | SoundFxwizard | sonniss-gdc-2.0 | PARTICLES_WHOOSH_Arrow 01.wav |
| blade_swing_scrape_14 | nagranie | Sonniss GDC 2026 — Melee Weapons Sound Effects Pack 2 | David Dumais Audio | sonniss-gdc-2.0 | METLFric_SWING SCRAPE Swift Melee Weapon Swing With A Long Blade 14_DDUMAIS_MWP2.wav |
| boot_concrete_walk | nagranie | Sonniss GDC 2018 — Ultimate Bare Feet Expansion | Joshua Reinhardt | sonniss-gdc-2.0 | BOOT_CONC CLEAN_WALK.R.wav |
| bow_midflight | nagranie | Sonniss GDC 2019 — Nocked | Eiravaein Works | sonniss-gdc-2.0 | Nocked,archery,firing,loose,Vaeyanbow,midflight,wide,mythic,sleek,swirl,rattle,alt14.wav |
| broom_stick_swings | nagranie | Sonniss GDC 2019 — Swipes And Whooshes | Soundholder | sonniss-gdc-2.0 | swipes and whooshes broom long stick slow and long swings stereo ORTF 8040.wav |
| bullet_drop_wood_04 | nagranie | Sonniss GDC 2016 — Bullet SFX | Stuart Duffield | sonniss-gdc-2.0 | Bullet_Drop_Wood_04.wav |
| crossbow_functions | nagranie | Sonniss GDC 2019 — Nocked | Eiravaein Works | sonniss-gdc-2.0 | Nocked,archery,crossbow1,composite,string,functions,bolt,slideintorest,set,drag,nock,remove,clatter,alt.wav |
| crossbow_loose | nagranie | Sonniss GDC 2019 — Nocked | Eiravaein Works | sonniss-gdc-2.0 | Nocked,archery,firing,loose,crossbow1,carbonbolt,atbow,snap,buzz,airy,bright,alt.wav |
| explosion_deep_02 | nagranie | Sonniss GDC 2020 — Explosions | Stefano Cremona | sonniss-gdc-2.0 | DeepExplosion02.wav |
| explosion_large_08 | nagranie | Sonniss GDC 2017 — Explosion Sound Pack | Gamemaster Audio | sonniss-gdc-2.0 | explosion_large_08.wav |
| fire_ignition_03 | nagranie | Sonniss GDC 2018 — Designed Fire | Gregor Quendel | sonniss-gdc-2.0 | Designed Fire - Impacts - Large, ignition 03.wav |
| g36c_mag_foley | nagranie | Sonniss GDC 2016 — Various Gun Foley & Handling | Pole Position Production | sonniss-gdc-2.0 | Heckler_&_Koch_G36C_5.56mm_foley_close_up_MKH60_mag_in_&_out.wav |
| gas_burner_4 | nagranie | Sonniss GDC 2017 — Driving Forces | Digital Rain Lab | sonniss-gdc-2.0 | Gas Burner Stereo 4.wav |
| grenade_launcher_smoke | nagranie | Sonniss GDC 2023 — Detonation - Explosion | BluezoneCorp | sonniss-gdc-2.0 | Bluezone_BC0277_weapon_smoke_grenade_launcher_003.wav |
| impact_22 | nagranie | Sonniss GDC 2018 — Guns & Explosions | Olivier Girardot | sonniss-gdc-2.0 | Bullet Impact 22.wav |
| impact_body_flesh_25 | nagranie | Sonniss GDC 2020 — Bullet Bys &Impacts | PMSFX | sonniss-gdc-2.0 | PM_BBI_Bullet_Impact_Hit_Body_Flesh_25.wav |
| impact_body_thump | nagranie | Sonniss GDC 2017 — Bullet Impact Sounds | Gamemaster Audio | sonniss-gdc-2.0 | bullet_impact_body_thump_02.wav |
| impact_concrete_brick | nagranie | Sonniss GDC 2017 — Bullet Impact Sounds | Gamemaster Audio | sonniss-gdc-2.0 | bullet_impact_concrete_brick_01.wav |
| impact_rock_4 | nagranie | Sonniss GDC 2020 — Hand Guns Sound Effects Pack | Olivier Girardot | sonniss-gdc-2.0 | Bullet rock Impact 4.wav |
| knife_swing_04 | nagranie | Sonniss GDC 2018 — Punch and Combat Sounds | Gamemaster Audio | sonniss-gdc-2.0 | whoosh_weapon_knife_swing_04.wav |
| monster_growls_4 | nagranie | Sonniss GDC 2018 — Monsters | Olivier Girardot | sonniss-gdc-2.0 | Monster Growls 4.wav |
| saiga12_close_1m | nagranie | Sonniss GDC 2016 — Saiga-12 12g solid slug | Pole Position Production | sonniss-gdc-2.0 | SAIGA-12_12g_solid_slug_1m_left_off_axis_MKH416_clean_Single_shots_x_5.wav |
| saiga12_cocking | nagranie | Sonniss GDC 2016 — Various Gun Foley & Handling | Pole Position Production | sonniss-gdc-2.0 | SAIGA-12_12g_solid_slug_foley_close_up_RSM191_R_cocking.wav |
| shell_bounce_wood_05 | nagranie | Sonniss GDC 2018 — Silenced Gun Sounds | Gamemaster Audio | sonniss-gdc-2.0 | bullet_shell_bounce_wood2_05.wav |
| shell_land_concrete_02 | nagranie | Sonniss GDC 2016 — Bullet SFX | Stuart Duffield | sonniss-gdc-2.0 | ShotgunShell_Land_Concrete_02.wav |
| shell_load_eject | nagranie | Sonniss GDC 2016 — 12 Gauge Shotgun | TS Sound | sonniss-gdc-2.0 | Shell Load_Round Eject.wav |
| shotgun_quick_pump | nagranie | Sonniss GDC 2016 — 12 Gauge Shotgun | TS Sound | sonniss-gdc-2.0 | Shotgun_Quick Pump_01.wav |
| stab_punch_hit | nagranie | Sonniss GDC 2016 — Just Gore _ Add On | SoundBits | sonniss-gdc-2.0 | Stab_Punch_Hit_136.wav |
| usas12_close_1m | nagranie | Sonniss GDC 2016 — USAS-12 12g solid slug | Pole Position Production | sonniss-gdc-2.0 | USAS-12_12g_solid_slug_1m_right_CS3_clean_Double_shots_x_1.wav |
| whip_21 | nagranie | Sonniss GDC 2020 — Hand Guns Sound Effects Pack | Olivier Girardot | sonniss-gdc-2.0 | Whip sound 21.wav |
