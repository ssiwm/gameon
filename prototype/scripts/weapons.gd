extends RefCounted
## Rejestr broni — JEDNO źródło prawdy dla rytmu ognia, obrażeń, hałasu i amunicji
## (GDD §6, §8.1 „Model rozgrzania lufy", §23). Identyczny w trybie solo i sieciowym.
##
## Dane żyją w tabelach poniżej; weapon_def.gd nadaje im typ i wielkości pochodne.
## Nowa broń = nowy wpis + wiersz w art/sprites/guns.png + klucze audio — bez zmian
## w player.gd, kontrolerze ani HUD.
##
## Hałas strzału = lerp(n_min, n_max, heat), a heat rośnie o heat_gain na strzał
## i spada o heat_decay/s (WŁASNE dla każdej broni). Krótka seria jest tania,
## ciągły ogień drogi. Wcześniej wspólny decay 1,2/s zjadał przyrost M-83 i P-64
## (gain × tempo < decay), więc tylko strzelba w ogóle się rozgrzewała — patrz
## `--weapontest`, który pilnuje, żeby każda broń z n_min < n_max osiągała n_max.

const WeaponDef := preload("res://scripts/weapon_def.gd")

const M83 := 0
const SPREAD12 := 1
const P64 := 2
const SRUT8 := 3
const LR7 := 4
const HKM9 := 5
const GNIEW4 := 6
const SOKOL6 := 7
const WIDMO1 := 8
const CIEGNO6 := 9
const MACZETA := 10
const KILOF := 11
const COUNT := 12

const Kind := WeaponDef.Kind
const Slot := WeaponDef.Slot

## Domyślny zestaw na starcie: dwie bronie główne + sidearm, broń biała osobno (GDD §6 „Zasady ogólne").
const START_PRIMARY_A := M83
const START_PRIMARY_B := SPREAD12
const START_SIDEARM := P64
const START_MELEE := MACZETA

static var _defs: Array = []

static func _table() -> Array:
	return [
		{
			"key": "m83", "name": "M-83", "slot": Slot.PRIMARY, "kind": Kind.BULLET,
			"auto": true, "cooldown": 0.11, "draw_time": 0.28,
			"damage": 8.0, "crit_mult": 1.5, "knock": 55.0,
			"jitter_deg": 0.8, "bloom_per_shot": 0.45, "bloom_max": 4.0, "bloom_decay": 9.0,
			"speed": 340.0, "range_px": 240.0, "falloff_start": 190.0, "falloff_min": 0.5,
			"n_min": 0.6, "n_max": 1.5, "heat_gain": 0.09, "heat_decay": 0.30,
			"mag": 30, "reserve_start": 150, "reserve_max": 270, "pickup_rounds": 30,
			"reload_time": 1.35, "reload_empty_extra": 0.45,
			"shake": 0.7, "cam_kick": 0.5, "recoil": 2.5, "flash_size": 3.5, "flash_light": 1.3,
			"tracer_len": 12.0, "casing": 1, "gun_len": 12.0, "gun_row": 0,
			"sfx": "m83_shot", "sfx_count": 6, "sfx_vol": -7.0,
		},
		{
			"key": "spread12", "name": "SPREAD-12", "slot": Slot.PRIMARY, "kind": Kind.BULLET,
			"auto": false, "cooldown": 0.26, "draw_time": 0.35,
			"damage": 7.0, "pellets": 5, "knock": 30.0,
			"spread_deg": 14.0, "jitter_deg": 1.5,
			"speed": 300.0, "range_px": 135.0, "falloff_start": 40.0, "falloff_min": 0.35,
			"n_min": 3.5, "n_max": 5.0, "heat_gain": 0.40, "heat_decay": 1.2,
			"mag": 24, "reserve_start": 48, "reserve_max": 96, "pickup_rounds": 12,
			"reload_time": 2.0, "reload_empty_extra": 0.5,
			"shake": 2.4, "cam_kick": 2.6, "kick": 55.0, "recoil": 5.0, "flash_size": 6.0, "flash_light": 1.7,
			"tracer_len": 7.0, "casing": 2, "gun_len": 14.0, "gun_row": 1,
			"sfx": "spread12_shot", "sfx_count": 3, "sfx_vol": -3.0,
		},
		{
			"key": "p64", "name": "P-64", "slot": Slot.SIDEARM, "kind": Kind.BULLET,
			"auto": false, "cooldown": 0.20, "draw_time": 0.2,
			"damage": 11.0, "crit_mult": 2.0, "knock": 60.0,
			"jitter_deg": 0.35, "bloom_per_shot": 0.8, "bloom_max": 3.0, "bloom_decay": 10.0, "crouch_accuracy": 0.5,
			"speed": 360.0, "range_px": 208.0, "falloff_start": 160.0, "falloff_min": 0.6,
			"n_min": 0.5, "n_max": 0.9, "heat_gain": 0.16, "heat_decay": 0.6,
			"mag": 12, "infinite": true, "reload_time": 1.1, "reload_empty_extra": 0.3,
			"shake": 0.5, "cam_kick": 0.4, "recoil": 2.5, "flash_size": 3.0, "flash_light": 1.2,
			"tracer_len": 9.0, "casing": 1, "gun_len": 9.0, "gun_row": 2,
			"sfx": "p64_shot", "sfx_count": 4, "sfx_vol": -8.0,
		},
		{
			"key": "srut8", "name": "SRUT-8", "slot": Slot.PRIMARY, "kind": Kind.BULLET,
			"auto": false, "cooldown": 0.8, "draw_time": 0.45,
			"damage": 7.0, "pellets": 8, "knock": 45.0, "stun": 0.2,
			"spread_deg": 17.0, "jitter_deg": 1.0,
			"speed": 280.0, "range_px": 100.0, "falloff_start": 20.0, "falloff_min": 0.25,
			"n_min": 4.5, "n_max": 6.0, "heat_gain": 0.5, "heat_decay": 0.4,
			"mag": 8, "reserve_start": 24, "reserve_max": 48, "pickup_rounds": 8,
			"reload_time": 0.45, "reload_per_round": true, "reload_sfx": "reload_shell", "reload_sfx_count": 3,
			"shake": 4.0, "cam_kick": 4.5, "kick": 130.0, "recoil": 7.0, "flash_size": 8.0, "flash_light": 2.0,
			"tracer_len": 6.0, "casing": 2, "gun_len": 15.0, "gun_row": 3,
			"sfx": "srut8_shot", "sfx_count": 3, "sfx_vol": -2.0, "sfx_cycle": "srut8_pump", "sfx_cycle_count": 2,
		},
		{
			"key": "lr7", "name": "LR-7", "slot": Slot.PRIMARY, "kind": Kind.BEAM,
			"auto": true, "cooldown": 0.1, "draw_time": 0.4,
			"damage": 7.0, "pierce": 2, "knock": 8.0,
			"range_px": 224.0,
			"n_min": 0.18, "n_max": 0.18, "heat_gain": 0.0,
			"mag": 100, "reserve_start": 200, "reserve_max": 400, "pickup_rounds": 80,
			"reload_time": 2.0, "reload_empty_extra": 0.0, "reload_sfx": "reload_cell", "reload_sfx_count": 2,
			"shake": 0.25, "recoil": 0.8, "flash_size": 3.0, "flash_light": 1.1,
			"flash_color": Color(0.55, 0.85, 1.0), "tracer_color": Color(0.55, 0.9, 1.0),
			"casing": 0, "gun_len": 13.0, "gun_row": 4,
			"sfx": "lr7_start", "sfx_count": 1, "sfx_vol": -9.0, "sfx_loop": "lr7_beam_loop",
		},
		{
			"key": "hkm9", "name": "HKM-9", "slot": Slot.PRIMARY, "kind": Kind.FLAME,
			"auto": true, "cooldown": 0.1, "draw_time": 0.45,
			"damage": 3.0, "ignite": 3.0, "knock": 12.0,
			"range_px": 64.0, "arc_deg": 20.0, "falloff_start": 30.0, "falloff_min": 0.5,
			"n_min": 0.3, "n_max": 0.3, "heat_gain": 0.0,
			"mag": 80, "reserve_start": 160, "reserve_max": 320, "pickup_rounds": 60,
			"reload_time": 2.6, "reload_empty_extra": 0.0, "reload_sfx": "reload_cell", "reload_sfx_count": 2,
			"shake": 0.3, "recoil": 0.8, "flash_size": 4.0, "flash_light": 1.5,
			"flash_color": Color(1.0, 0.55, 0.2), "tracer_color": Color(1.0, 0.6, 0.2),
			"casing": 0, "gun_len": 14.0, "gun_row": 5,
			"sfx": "hkm9_ignite", "sfx_count": 1, "sfx_vol": -7.0, "sfx_loop": "hkm9_flame_loop",
		},
		{
			"key": "gniew4", "name": "GNIEW-4", "slot": Slot.PRIMARY, "kind": Kind.LAUNCHER,
			"auto": false, "cooldown": 1.2, "draw_time": 0.55,
			"damage": 25.0, "knock": 160.0, "stun": 0.5,
			"jitter_deg": 0.5, "speed": 280.0, "range_px": 330.0, "gravity": 300.0,
			"blast_radius": 48.0, "blast_damage": 80.0, "fuse": 1.6,
			"n_min": 3.0, "n_max": 3.0, "heat_gain": 0.0,
			"mag": 6, "reserve_start": 12, "reserve_max": 24, "pickup_rounds": 6,
			"reload_time": 0.7, "reload_per_round": true, "reload_sfx": "reload_launcher", "reload_sfx_count": 1,
			"shake": 3.0, "cam_kick": 5.0, "kick": 120.0, "recoil": 8.0, "flash_size": 7.0, "flash_light": 1.8,
			"tracer_color": Color(0.7, 0.75, 0.45), "tracer_len": 8.0, "casing": 0, "gun_len": 14.0, "gun_row": 6,
			"sfx": "gniew4_shot", "sfx_count": 2, "sfx_vol": -2.0,
		},
		{
			"key": "sokol6", "name": "SOKOL-6", "slot": Slot.PRIMARY, "kind": Kind.BULLET,
			"auto": true, "cooldown": 0.2, "draw_time": 0.35,
			"damage": 7.0, "knock": 25.0,
			"jitter_deg": 5.0, "speed": 170.0, "range_px": 210.0,
			"homing": 4.5, "homing_cone": 60.0, "homing_range": 190.0,
			"n_min": 1.2, "n_max": 2.4, "heat_gain": 0.10, "heat_decay": 0.3,
			"mag": 40, "reserve_start": 80, "reserve_max": 160, "pickup_rounds": 40,
			"reload_time": 2.2, "reload_empty_extra": 0.5,
			"shake": 0.6, "recoil": 2.0, "flash_size": 4.0, "flash_light": 1.3,
			"flash_color": Color(1.0, 0.7, 0.35), "tracer_color": Color(1.0, 0.8, 0.5), "tracer_len": 14.0,
			"casing": 0, "gun_len": 13.0, "gun_row": 7,
			"sfx": "sokol6_shot", "sfx_count": 3, "sfx_vol": -8.0,
		},
		{
			"key": "widmo1", "name": "WIDMO-1", "slot": Slot.PRIMARY, "kind": Kind.RAIL,
			"auto": false, "cooldown": 0.9, "draw_time": 0.6, "charge_time": 1.2,
			"damage": 150.0, "pierce": 99, "knock": 200.0, "stun": 0.6,
			"range_px": 480.0,
			"n_min": 14.0, "n_max": 14.0, "heat_gain": 0.0,
			"mag": 5, "reserve_start": 10, "reserve_max": 20, "pickup_rounds": 5,
			"reload_time": 2.8, "reload_empty_extra": 0.5, "reload_sfx": "reload_rail", "reload_sfx_count": 1,
			"shake": 6.0, "cam_kick": 7.0, "kick": 170.0, "recoil": 9.0, "flash_size": 10.0, "flash_light": 2.4,
			"flash_color": Color(0.7, 0.9, 1.0), "tracer_color": Color(0.65, 0.92, 1.0), "tracer_len": 40.0,
			"casing": 0, "gun_len": 16.0, "gun_row": 8,
			"sfx": "widmo1_shot", "sfx_count": 2, "sfx_vol": 0.0, "sfx_loop": "widmo1_charge",
		},
		{
			"key": "ciegno6", "name": "CIEGNO-6", "slot": Slot.PRIMARY, "kind": Kind.BULLET,
			"auto": false, "cooldown": 0.8, "draw_time": 0.4,
			"damage": 45.0, "crit_mult": 2.0, "knock": 150.0, "stun": 0.8, "sticks": true,
			"jitter_deg": 0.2, "speed": 400.0, "range_px": 300.0,
			"n_min": 0.08, "n_max": 0.08, "heat_gain": 0.0,
			"mag": 1, "reserve_start": 6, "reserve_max": 12, "pickup_rounds": 3,
			"reload_time": 1.5, "reload_empty_extra": 0.0, "reload_sfx": "reload_bolt", "reload_sfx_count": 1,
			"shake": 0.6, "recoil": 4.0, "flash_size": 0.0, "flash_light": 0.0,
			"tracer_color": Color(0.82, 0.78, 0.62), "tracer_len": 14.0, "casing": 0, "gun_len": 13.0, "gun_row": 9,
			"sfx": "ciegno6_shot", "sfx_count": 2, "sfx_vol": -6.0,
		},
		{
			"key": "maczeta", "name": "MACHETE", "slot": Slot.MELEE, "kind": Kind.MELEE,
			"auto": false, "cooldown": 0.42, "draw_time": 0.2,
			"damage": 30.0, "knock": 60.0, "reach": 22.0, "arc_deg": 60.0,
			"n_min": 0.0, "n_max": 0.0, "mag": 0, "infinite": true,
			"shake": 0.8, "recoil": 0.0, "flash_size": 0.0, "flash_light": 0.0, "casing": 0,
			"gun_len": 12.0, "gun_row": 10, "sfx": "maczeta", "sfx_count": 2, "sfx_vol": -6.0,
		},
		{
			"key": "kilof", "name": "PICKAXE", "slot": Slot.MELEE, "kind": Kind.MELEE,
			"auto": false, "cooldown": 0.9, "draw_time": 0.3,
			"damage": 55.0, "knock": 160.0, "stun": 1.2, "reach": 24.0, "arc_deg": 50.0,
			"n_min": 0.8, "n_max": 0.8, "mag": 0, "infinite": true,
			"shake": 2.0, "recoil": 0.0, "flash_size": 0.0, "flash_light": 0.0, "casing": 0,
			"gun_len": 13.0, "gun_row": 11, "sfx": "kilof_swing", "sfx_count": 2, "sfx_vol": -5.0,
		},
	]

static func defs() -> Array:
	if _defs.is_empty():
		var t := _table()
		for i in t.size():
			_defs.append(WeaponDef.make(i, t[i]))
	return _defs

static func def(id: int) -> WeaponDef:
	return defs()[clampi(id, 0, COUNT - 1)]

static func is_valid(id: int) -> bool:
	return id >= 0 and id < COUNT

## Hałas strzału dla danego rozgrzania (0–1).
static func shot_noise(id: int, heat: float) -> float:
	return def(id).noise(heat)

## Broń główna? (podnoszenie zastępuje slot głównej; sidearm i broń biała mają własne sloty)
static func is_primary(id: int) -> bool:
	return def(id).slot == Slot.PRIMARY

## Rozgrzanie po `shots` strzałach w serii o danym tempie (symulacja kroku 1/60 s,
## jak w grze). Służy testom i narzędziom balansu — kontroler używa tej samej reguły.
static func simulate_heat(id: int, seconds: float) -> Dictionary:
	var d := def(id)
	var dt := 1.0 / 60.0
	var heat := 0.0
	var cd := 0.0
	var t := 0.0
	var shots := 0
	var noise_sum := 0.0
	var peak := 0.0
	while t < seconds:
		heat = maxf(0.0, heat - d.heat_decay * dt)
		cd -= dt
		if cd <= 0.0:
			noise_sum += d.noise(heat)
			heat = minf(1.0, heat + d.heat_gain)
			cd += d.cooldown
			shots += 1
			peak = maxf(peak, heat)
		t += dt
	return {"shots": shots, "peak_heat": peak, "noise_per_s": noise_sum / seconds}

## Kierunki śrucin dla jednego strzału. Wyznaczane z `seed`, więc serwer i wszyscy
## klienci dostają IDENTYCZNY rozrzut bez przesyłania wektorów każdej śruciny.
## `extra_deg` = rozrzut dokładany przez strzelca (bloom, ruch, kucanie).
static func pellet_dirs(d: WeaponDef, dir: Vector2, seed: int, extra_deg: float) -> PackedVector2Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var out := PackedVector2Array()
	var jitter: float = d.jitter_deg + maxf(extra_deg, 0.0)
	for i in d.pellets:
		var off := rng.randf_range(-jitter, jitter)
		if d.pellets > 1:
			off += lerpf(-d.spread_deg, d.spread_deg, float(i) / float(d.pellets - 1))
		out.append(dir.rotated(deg_to_rad(off)))
	return out

## Sprawdza spójność tabel — zwraca listę błędów (pusta = OK). Wołane przez --weapontest.
static func validate() -> Array:
	var errs: Array = []
	for d in defs():
		if d.cooldown <= 0.0:
			errs.append("%s: cooldown <= 0" % d.key)
		if d.n_min > d.n_max:
			errs.append("%s: n_min > n_max" % d.key)
		if d.uses_ammo() and not d.infinite and d.reserve_max < d.reserve_start:
			errs.append("%s: reserve_max < reserve_start" % d.key)
		if d.uses_ammo() and d.mag < d.ammo_per_shot:
			errs.append("%s: magazynek mniejszy niż koszt strzału" % d.key)
		if d.kind == Kind.MELEE and (d.reach <= 0.0 or d.arc_deg <= 0.0):
			errs.append("%s: melee bez zasięgu/łuku" % d.key)
		if d.kind != Kind.MELEE and d.kind != Kind.RAIL and d.kind != Kind.BEAM and d.speed <= 0.0 and d.kind != Kind.FLAME:
			errs.append("%s: brak prędkości pocisku" % d.key)
		if d.kind == Kind.RAIL and d.charge_time <= 0.0:
			errs.append("%s: RAIL bez czasu ładowania" % d.key)
		if d.kind == Kind.LAUNCHER and d.blast_radius <= 0.0:
			errs.append("%s: LAUNCHER bez promienia wybuchu" % d.key)
		if d.sfx == "":
			errs.append("%s: brak klucza audio" % d.key)
		if d.n_min < d.n_max:
			var sim := simulate_heat(d.id, 12.0)
			if float(sim["peak_heat"]) < 0.99:
				errs.append("%s: ciągły ogień nie rozgrzewa lufy (peak heat %.2f) — n_max nieosiągalne" % [d.key, sim["peak_heat"]])
	return errs
