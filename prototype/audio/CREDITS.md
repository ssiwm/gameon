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
| alien_death_01 | nagranie | Sonniss GDC 2017 — CREATURES ZONE | MatiasMacSD | sonniss-gdc-2.0 | Creature_Alien_Death_01.wav |
| aquatic_gurgling_2 | nagranie | Sonniss GDC 2026 — Vox Bestiae - Source Elements | SoundBits | sonniss-gdc-2.0 | CREAAqua_Aquatic Creature Gurgling 2_SNDBTS_VB-SE.wav |
| arrow_whoosh | nagranie | Sonniss GDC 2020 — PARTICLES An Organic & Granular Journey | SoundFxwizard | sonniss-gdc-2.0 | PARTICLES_WHOOSH_Arrow 01.wav |
| bag_grab_04 | nagranie | Sonniss GDC 2018 — Footstep and Foley Sounds | Gamemaster Audio | sonniss-gdc-2.0 | foley_sports_bag_grab_pickup_catch_04.wav |
| banshee_damage_07 | nagranie | Sonniss GDC 2020 — Monster Roars | Phase 4 Libraries | sonniss-gdc-2.0 | MR - Banshee Damage VO 07.wav |
| beast01_attack_08 | nagranie | Sonniss GDC 2020 — Monsters | SmartSoundFX | sonniss-gdc-2.0 | BEAST 01 Attack 08.wav |
| beast01_threaten_06 | nagranie | Sonniss GDC 2020 — Monsters | SmartSoundFX | sonniss-gdc-2.0 | BEAST 01 Threaten Short 06.wav |
| behemoth_talk_04 | nagranie | Sonniss GDC 2018 — 6Monsters | Lukas Tvrdon | sonniss-gdc-2.0 | 6Monsters_Behemoth_Talk_04.wav |
| blackboss_scream_04 | nagranie | Sonniss GDC 2018 — 6Monsters | Lukas Tvrdon | sonniss-gdc-2.0 | 6Monsters_BlackBoss_Scream_04.wav |
| blade_swing_scrape_14 | nagranie | Sonniss GDC 2026 — Melee Weapons Sound Effects Pack 2 | David Dumais Audio | sonniss-gdc-2.0 | METLFric_SWING SCRAPE Swift Melee Weapon Swing With A Long Blade 14_DDUMAIS_MWP2.wav |
| blocked_door_creaks_09 | nagranie | Sonniss GDC 2017 — Unsettling Creaks and Squeaks – Extension I | SoundBits | sonniss-gdc-2.0 | UCnS_BlockedDoor_01_Creaks_09.wav |
| boot_concrete_walk | nagranie | Sonniss GDC 2018 — Ultimate Bare Feet Expansion | Joshua Reinhardt | sonniss-gdc-2.0 | BOOT_CONC CLEAN_WALK.R.wav |
| boot_metal_walk | nagranie | Sonniss GDC 2017 — Edward – Foleyart Collection Add-On Extended Footsteps | Tovusound | sonniss-gdc-2.0 | 237_Foley_Footsteps_Metal_Boot_Walk_Normal_Close.wav |
| bow_midflight | nagranie | Sonniss GDC 2019 — Nocked | Eiravaein Works | sonniss-gdc-2.0 | Nocked,archery,firing,loose,Vaeyanbow,midflight,wide,mythic,sleek,swirl,rattle,alt14.wav |
| breaker_on | nagranie | Sonniss GDC 2018 — The Cabin Audio Playset | UberDuo | sonniss-gdc-2.0 | Switch,ElectricalPanelBreaker,On.wav |
| building_collapse | nagranie | Sonniss GDC 2023 — Building Collapse | BluezoneCorp | sonniss-gdc-2.0 | Bluezone_BC0275_building_collapse_debris_falling_rock_rubble_008.wav |
| bullet_drop_wood_04 | nagranie | Sonniss GDC 2016 — Bullet SFX | Stuart Duffield | sonniss-gdc-2.0 | Bullet_Drop_Wood_04.wav |
| cannonball_impact_005 | nagranie | Sonniss GDC 2023 — Naval Warfare | Gladestock Studios | sonniss-gdc-2.0 | GS cannonball impact 005.wav |
| cartridge_handling_018 | nagranie | Sonniss GDC 2023 — Detonation - Explosion | BluezoneCorp | sonniss-gdc-2.0 | Bluezone_BC0277_cartridge_case_handling_018.wav |
| chain_clinking_04 | nagranie | Sonniss GDC 2019 — Ghosts Return | Articulated Sounds | sonniss-gdc-2.0 | METAL CHAIN Old Barn, Manipulation, Clinking 04.wav |
| creature_step_damp | nagranie | Sonniss GDC 2020 — Cave Creature Sound Effects | Bluezone | sonniss-gdc-2.0 | Bluezone_BC0272_creature_footstep_damp_015.wav |
| creature_step_mud | nagranie | Sonniss GDC 2020 — Mountain Dweller - Orc Sound Effects | Bluezone | sonniss-gdc-2.0 | Bluezone_BC0261_mountain_dweller_creature_orc_footstep_mud_texture_003.wav |
| creature_step_wood | nagranie | Sonniss GDC 2020 — Forest Creature Sound Effects | Bluezone | sonniss-gdc-2.0 | Bluezone_BC0269_creature_wood_footstep_medium_004.wav |
| crossbow_functions | nagranie | Sonniss GDC 2019 — Nocked | Eiravaein Works | sonniss-gdc-2.0 | Nocked,archery,crossbow1,composite,string,functions,bolt,slideintorest,set,drag,nock,remove,clatter,alt.wav |
| crossbow_loose | nagranie | Sonniss GDC 2019 — Nocked | Eiravaein Works | sonniss-gdc-2.0 | Nocked,archery,firing,loose,crossbow1,carbonbolt,atbow,snap,buzz,airy,bright,alt.wav |
| deep_thud_10 | nagranie | Sonniss GDC 2019 — IMPACT | Baxter Audio | sonniss-gdc-2.0 | 10 Hit Deep Thud.wav |
| dirt_walk_loop | nagranie | Sonniss GDC 2019 — STEPS Dirt & Gravel | PMSFX | sonniss-gdc-2.0 | PM_SDNG_Stereo_Walk_Seamless_Loop_1.wav |
| dog_bark_growl | nagranie | Sonniss GDC 2019 — Dogs - game ready | Bart Kamski | sonniss-gdc-2.0 | Dog_big_close_barking_growling.wav |
| dog_whimper | nagranie | Sonniss GDC 2020 — Dogs | Soundopolis | sonniss-gdc-2.0 | Dog_German Short-Haired Pointer_Bark and Whimper_Fienup_001.wav |
| door_creak_metal | nagranie | Sonniss GDC 2018 — The Creepy Door | RZ Post | sonniss-gdc-2.0 | Creepy Door, Fast Metal Creak_02.wav |
| door_impact_metal | nagranie | Sonniss GDC 2018 — The Creepy Door | RZ Post | sonniss-gdc-2.0 | Creepy Door, Metal,Door,Medium,Impact_01.wav |
| dragon_roar_01 | nagranie | Sonniss GDC 2017 — CREATURES ZONE | MatiasMacSD | sonniss-gdc-2.0 | Creature_Dragon_Roar_01.wav |
| dry_ice_shriek_3 | nagranie | Sonniss GDC 2018 — The Dry Ice Library | Alexander Kopeikin | sonniss-gdc-2.0 | dry ice shriek - very hot knife pressed against block of dry ice 003.wav |
| ethereal_pain_4 | nagranie | Sonniss GDC 2026 — Vox Bestiae - Source Elements | SoundBits | sonniss-gdc-2.0 | CREAEthr_Ethereal Entity Grim Pain Long 4_SNDBTS_VB-SE.wav |
| evil_exhale | nagranie | Sonniss GDC 2018 — Variety 1 Sound Effects | Airborne Sound | sonniss-gdc-2.0 | Breaths,Male,Exhale,Ghost,Evil,Hostile,Snarl,1.wav |
| explosion_deep_02 | nagranie | Sonniss GDC 2020 — Explosions | Stefano Cremona | sonniss-gdc-2.0 | DeepExplosion02.wav |
| explosion_large_08 | nagranie | Sonniss GDC 2017 — Explosion Sound Pack | Gamemaster Audio | sonniss-gdc-2.0 | explosion_large_08.wav |
| fire_ignition_03 | nagranie | Sonniss GDC 2018 — Designed Fire | Gregor Quendel | sonniss-gdc-2.0 | Designed Fire - Impacts - Large, ignition 03.wav |
| flutter_death_05 | nagranie | Sonniss GDC 2026 — Humanoid Creatures Vol 4 - Monstrous and Undead Creature Vocalization Sound Sets | Epic Stock Media | sonniss-gdc-2.0 | VOXReac_Construction Kit Male Flutter Death Vocal Stuttered Long 05_ESM_HC4.wav |
| forest_winter_night | nagranie | Sonniss GDC 2018 — Winter Forest Ambience | Articulated Sounds | sonniss-gdc-2.0 | WINTER Forest night dark moon with distant wolves howls, North Laurentian Woods, Canada_LOOP.LR.wav |
| g36c_mag_foley | nagranie | Sonniss GDC 2016 — Various Gun Foley & Handling | Pole Position Production | sonniss-gdc-2.0 | Heckler_&_Koch_G36C_5.56mm_foley_close_up_MKH60_mag_in_&_out.wav |
| gas_burner_4 | nagranie | Sonniss GDC 2017 — Driving Forces | Digital Rain Lab | sonniss-gdc-2.0 | Gas Burner Stereo 4.wav |
| gear_running_10 | nagranie | Sonniss GDC 2016 — INTERVENTION | SoundMorph | sonniss-gdc-2.0 | Gear - movements_running_10.wav |
| glass_impact_break | nagranie | Sonniss GDC 2023 — Broken Glass | BluezoneCorp | sonniss-gdc-2.0 | Bluezone_BC0274_glass_impact_break_002.wav |
| glass_shards_smash | nagranie | Sonniss GDC 2017 — Shards Broken Glass | Chris Skyes | sonniss-gdc-2.0 | Glass,Shards,Smash,Medium Impact,Lots of Large Shards.wav |
| glass_window_break | nagranie | Sonniss GDC 2017 — Shards Broken Glass | Chris Skyes | sonniss-gdc-2.0 | Window,Small,Break,Medium Impact,Large Amount of Clinking Pieces.wav |
| grenade_launcher_smoke | nagranie | Sonniss GDC 2023 — Detonation - Explosion | BluezoneCorp | sonniss-gdc-2.0 | Bluezone_BC0277_weapon_smoke_grenade_launcher_003.wav |
| hellhound_idle | nagranie | Sonniss GDC 2020 — Monsters | SmartSoundFX | sonniss-gdc-2.0 | HELLHOUND Idle Weak 03.wav |
| impact_22 | nagranie | Sonniss GDC 2018 — Guns & Explosions | Olivier Girardot | sonniss-gdc-2.0 | Bullet Impact 22.wav |
| impact_body_flesh_25 | nagranie | Sonniss GDC 2020 — Bullet Bys &Impacts | PMSFX | sonniss-gdc-2.0 | PM_BBI_Bullet_Impact_Hit_Body_Flesh_25.wav |
| impact_body_thump | nagranie | Sonniss GDC 2017 — Bullet Impact Sounds | Gamemaster Audio | sonniss-gdc-2.0 | bullet_impact_body_thump_02.wav |
| impact_concrete_brick | nagranie | Sonniss GDC 2017 — Bullet Impact Sounds | Gamemaster Audio | sonniss-gdc-2.0 | bullet_impact_concrete_brick_01.wav |
| impact_rock_4 | nagranie | Sonniss GDC 2020 — Hand Guns Sound Effects Pack | Olivier Girardot | sonniss-gdc-2.0 | Bullet rock Impact 4.wav |
| jump_land_two_feet | nagranie | Sonniss GDC 2017 — Edward – Foleyart Collection Add-On Extended Footsteps | Tovusound | sonniss-gdc-2.0 | 289_Foley_Footsteps_Rocks_Sneaker_Jump_Land_On_Two_Feet_Close.wav |
| knife_swing_04 | nagranie | Sonniss GDC 2018 — Punch and Combat Sounds | Gamemaster Audio | sonniss-gdc-2.0 | whoosh_weapon_knife_swing_04.wav |
| large_beast_taunt_03 | nagranie | Sonniss GDC 2018 — Monster Within | SoundMorph | sonniss-gdc-2.0 | Monster Within - Large Beast - Taunt2Stun03.wav |
| large_monster11_roar03 | nagranie | Sonniss GDC 2023 — Monster Sound FX Pack 2 | David Dumais Audio | sonniss-gdc-2.0 | MonsterPack2_LargeMonster11_Roar03.wav |
| male_death_low_09 | nagranie | Sonniss GDC 2017 — Human Vocalizations | Gamemaster Audio | sonniss-gdc-2.0 | voice_male_b_death_low_09.wav |
| male_grunt_shout_317 | nagranie | Sonniss GDC 2016 — Screams & Shouts 2 - Humans | SoundBits | sonniss-gdc-2.0 | Male_Grunt-Shout_317.wav |
| male_shout_pain_132 | nagranie | Sonniss GDC 2016 — Screams & Shouts 2 - Humans | SoundBits | sonniss-gdc-2.0 | Male_Shout-of-Pain_132.wav |
| metal_creak_13 | nagranie | Sonniss GDC 2017 — Unsettling Creaks and Squeaks | SoundBits | sonniss-gdc-2.0 | Metal_Creak_13.wav |
| monster_growls_4 | nagranie | Sonniss GDC 2018 — Monsters | Olivier Girardot | sonniss-gdc-2.0 | Monster Growls 4.wav |
| object_grab_04 | nagranie | Sonniss GDC 2018 — Punch and Combat Sounds | Gamemaster Audio | sonniss-gdc-2.0 | foley_object_grab_pickup_04.wav |
| orc_grunt_003 | nagranie | Sonniss GDC 2020 — Mountain Dweller - Orc Sound Effects | Bluezone | sonniss-gdc-2.0 | Bluezone_BC0261_mountain_dweller_creature_orc_grunt_003.wav |
| organic_texture_041 | nagranie | Sonniss GDC 2023 — Biohazard - Organic Textures and Ambiences | BluezoneCorp | sonniss-gdc-2.0 | Bluezone_BC0280_biohazard_creature_organic_texture_041.wav |
| puddle_splashes | nagranie | Sonniss GDC 2020 — Footsteps | Wav Junction Sound Effects | sonniss-gdc-2.0 | 0014_Footsteps_water_puddle_single_splashes.wav |
| quake_rumble | nagranie | Sonniss GDC 2024 — Alien Tripod | BluezoneCorp | sonniss-gdc-2.0 | Bluezone_BC0292_alien_tripod_debris_rock_collapse_earthquake_rumble_large_005.wav |
| radio_tuning_static | nagranie | Sonniss GDC 2016 — NOISE | MatiasMacSD | sonniss-gdc-2.0 | OldRadioTuningStaticNoise_001.wav |
| rain_hard_loop | nagranie | Sonniss GDC 2017 — Rain and Thunder | Double Trouble Audio | sonniss-gdc-2.0 | RATH - Rain Hard Loop 08.wav |
| rain_on_plastic | nagranie | Sonniss GDC 2017 — Rain and Thunder | Double Trouble Audio | sonniss-gdc-2.0 | RATH - Rain on Plastic Outside Loop.wav |
| rifle_pickup_004 | nagranie | Sonniss GDC 2017 — MECHANISM | SoundMorph | sonniss-gdc-2.0 | Mechanism - AssaultRifle_PickUp_004.wav |
| rockslide_02 | nagranie | Sonniss GDC 2018 — Foley Elements Rocks, Dirt And Stone | Soundrangers | sonniss-gdc-2.0 | rockslide_02.wav |
| saiga12_close_1m | nagranie | Sonniss GDC 2016 — Saiga-12 12g solid slug | Pole Position Production | sonniss-gdc-2.0 | SAIGA-12_12g_solid_slug_1m_left_off_axis_MKH416_clean_Single_shots_x_5.wav |
| saiga12_cocking | nagranie | Sonniss GDC 2016 — Various Gun Foley & Handling | Pole Position Production | sonniss-gdc-2.0 | SAIGA-12_12g_solid_slug_foley_close_up_RSM191_R_cocking.wav |
| scrap_pile_03 | nagranie | Sonniss GDC 2017 — Junk and Debris | Double Trouble Audio | sonniss-gdc-2.0 | Pile of Scrap Metal - Metal Scrap Pile, Rustle, Drop, Long Tail 03.wav |
| screeching_monster_2 | nagranie | Sonniss GDC 2020 — Monster Sounds & Atmospheres | Olivier Girardot | sonniss-gdc-2.0 | Screeching Monster 2-1.wav |
| sea_beast_yell_04 | nagranie | Sonniss GDC 2026 — Humanoid Creatures Vol 4 - Monstrous and Undead Creature Vocalization Sound Sets | Epic Stock Media | sonniss-gdc-2.0 | CREAMnstr_Designed Sea Beast Creature Pain Intense Yell Long 04_ESM_HC4.wav |
| shell_bounce_wood_05 | nagranie | Sonniss GDC 2018 — Silenced Gun Sounds | Gamemaster Audio | sonniss-gdc-2.0 | bullet_shell_bounce_wood2_05.wav |
| shell_land_concrete_02 | nagranie | Sonniss GDC 2016 — Bullet SFX | Stuart Duffield | sonniss-gdc-2.0 | ShotgunShell_Land_Concrete_02.wav |
| shell_load_eject | nagranie | Sonniss GDC 2016 — 12 Gauge Shotgun | TS Sound | sonniss-gdc-2.0 | Shell Load_Round Eject.wav |
| shepherd_barks | nagranie | Sonniss GDC 2019 — Barking Dog | Pole Position | sonniss-gdc-2.0 | Dog_German_Shepherd_t2_Ext_Field_Bark_Many_TImes_Start_and_Stop_DPA4060.wav |
| shotgun_quick_pump | nagranie | Sonniss GDC 2016 — 12 Gauge Shotgun | TS Sound | sonniss-gdc-2.0 | Shotgun_Quick Pump_01.wav |
| stab_punch_hit | nagranie | Sonniss GDC 2016 — Just Gore _ Add On | SoundBits | sonniss-gdc-2.0 | Stab_Punch_Hit_136.wav |
| swamp_fish_damage_08 | nagranie | Sonniss GDC 2020 — Monster Roars | Phase 4 Libraries | sonniss-gdc-2.0 | MR - Swamp Fish Creature Damage VO 08.wav |
| tape_play_stop | nagranie | Sonniss GDC 2020 — Studer A80 Master recorder analog tape machine | Ivo Vicic | sonniss-gdc-2.0 | 50 Studer A80_play_stop_15 IPS_mono_contact mic_B.wav |
| thunder_clap_04 | nagranie | Sonniss GDC 2018 — Thunder | Soundrangers | sonniss-gdc-2.0 | thunder_clap_04.wav |
| thunder_crack_02 | nagranie | Sonniss GDC 2018 — Thunder | Soundrangers | sonniss-gdc-2.0 | thunder_mountainous_big_crack_02.wav |
| thunder_strike_03 | nagranie | Sonniss GDC 2018 — Thunder | Soundrangers | sonniss-gdc-2.0 | thunder_strike_03.wav |
| troll_death_01 | nagranie | Sonniss GDC 2017 — Troll Monster Vocalizations | Gamemaster Audio | sonniss-gdc-2.0 | troll_monster_death_01.wav |
| usas12_close_1m | nagranie | Sonniss GDC 2016 — USAS-12 12g solid slug | Pole Position Production | sonniss-gdc-2.0 | USAS-12_12g_solid_slug_1m_right_CS3_clean_Double_shots_x_1.wav |
| walkie_beep | nagranie | Sonniss GDC 2020 — Interception - Radio Transmission | Bluezone | sonniss-gdc-2.0 | Bluezone_BC0266_radio_beep_walkie_talkie_002.wav |
| walkie_kenwood | nagranie | Sonniss GDC 2016 — Handheld Tranceivers | Sergey Eybog | sonniss-gdc-2.0 | Walkie Talkie,Kenwood TK-3107 FM,Radio Communication,No Speech,Static,Feedback Squelch,Manipulations.wav |
| water_movement_large_009 | nagranie | Sonniss GDC 2020 — Cave Creature Sound Effects | Bluezone | sonniss-gdc-2.0 | Bluezone_BC0272_creature_texture_water_movement_large_animal_009.wav |
| whip_21 | nagranie | Sonniss GDC 2020 — Hand Guns Sound Effects Pack | Olivier Girardot | sonniss-gdc-2.0 | Whip sound 21.wav |
| whoosh_wind_gust_11 | nagranie | Sonniss GDC 2024 — Distinct Whooshes | Rescopic Sound | sonniss-gdc-2.0 | WHSH_Airy-Whoosh Wind Gust 11_RSCPC_DW.wav |
| wind_howl_gust | nagranie | Sonniss GDC 2016 — Howling Winds - Interior | Hzandbits | sonniss-gdc-2.0 | Wind,Int,Howl,Forceful,Tonal,Vocal,Gust.wav |
| wind_mountain_loop | nagranie | Sonniss GDC 2018 — Wind | Soundrangers | sonniss-gdc-2.0 | wind_harsh_mountain_02_30_loop.wav |
| yeti_grumble_02 | nagranie | Sonniss GDC 2018 — Yeti Monster | Articulated Sounds | sonniss-gdc-2.0 | MONSTER Yeti grumble 02.wav |
| zipper_smallbag | nagranie | Sonniss GDC 2017 — Open & Close | SoundBits | sonniss-gdc-2.0 | Zipper_SmallBag_01_04.wav |
