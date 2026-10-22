extends RefCounted
## Części broni w gniazdach (GUNSMITH_PLAN.md §4, etap 2a, od 1.7.319) — zastępują trzy liniowe poziomy ulepszeń (dawne upgrades.gd).
##
## Każda broń ma kilka gniazd (zasilanie, lufa, wylot, mechanizm, kolba…), w każdym fabryczny element i 1–3 części do wyboru.
## Część ma zysk i KOSZT (zasada pilnowana testem: co najmniej jeden modyfikator na minus) — wybór części to decyzja, nie formalność.
## Odblokowanie (zakup za złom w warsztacie) jest wspólne dla drużyny (Scrap.parts, zapis u hosta), a MONTAŻ prywatny: każdy gracz
## składa własną broń (Profile.fits, replikowane jako player.fits). Gniazdo, w którym gracz niczego nie wybrał, dostaje pierwszą
## odblokowaną część z listy — dzięki temu dawne poziomy ulepszeń (migracja w Scrap.load_progress) działają od razu.
##
## Konfiguracja broni to liczba `fit`: dla każdego gniazda broni (kolejność SLOT_ORDER) 2 bity = indeks części (0 = fabryczny, 1..3).
## Razem z typem naboju tworzy kod `build` = ammo | fit << 4 (Weapons.def_build), który płynie przez sieć ze strzałem.
##
## Modyfikator: [pole WeaponDef, "mul"|"add"|"set", wartość] — jak w ammo.gd. Części nie zmieniają zapasu drużyny (`reserve_max`):
## zapas jest wspólny, a montaż prywatny. `tier` = numer dawnego poziomu ulepszenia (migracja zapisów sprzed 1.7.319).

const SLOT_ORDER := ["feed", "barrel", "muzzle", "action", "stock", "optic", "edge", "head", "special"]
const SLOT_NAMES := {
	"feed": "Feed", "barrel": "Barrel", "muzzle": "Muzzle", "action": "Action", "stock": "Stock / grip", "optic": "Sight / seeker",
	"edge": "Edge", "head": "Head", "special": "Special",
}
const MAX_PER_SLOT := 3

## klucz broni → części (kolejność w gnieździe = kolejność na liście; pierwsza odblokowana montuje się sama)
const PARTS := {
	"m83": [
		{"id": "m83_rpk40", "slot": "feed", "tier": 1, "cost": 60, "name": "RPK magazine",
			"desc": "40-round magazine from the RPK: +10 rounds; longer, so the reload takes a little longer (+0.15 s)",
			"mods": [["mag", "add", 10], ["reload_time", "add", 0.15], ["mass", "add", 0.25]]},
		{"id": "m83_drum75", "slot": "feed", "cost": 160, "name": "RPK drum",
			"desc": "75-round drum: +45 rounds, but a slow, fiddly reload (+1.2 s) and a heavier gun to draw (+0.1 s)",
			"mods": [["mag", "add", 45], ["reload_time", "add", 1.2], ["draw_time", "add", 0.1], ["mass", "add", 1.6]]},
		{"id": "m83_rpkbar", "slot": "barrel", "tier": 2, "cost": 120, "name": "RPK barrel",
			"desc": "Longer, heavier barrel: tighter grouping (spread −30%, bloom −20%), hits hard farther out and heats up 30% slower; heavier to draw (+0.05 s)",
			"mods": [["jitter_deg", "mul", 0.7], ["bloom_max", "mul", 0.8], ["falloff_start", "add", 30.0], ["barrel_heat", "mul", 0.7], ["draw_time", "add", 0.05], ["mass", "add", 1]]},
		{"id": "m83_short", "slot": "barrel", "cost": 90, "name": "Short barrel",
			"desc": "Cut-down barrel: draws 30% faster, but spread +30%, range −15%, a louder, brighter muzzle blast and it heats up 25% faster",
			"mods": [["draw_time", "mul", 0.7], ["jitter_deg", "mul", 1.3], ["range_px", "mul", 0.85], ["n_min", "mul", 1.15], ["n_max", "mul", 1.15], ["flash_size", "mul", 1.4], ["barrel_heat", "mul", 1.25], ["mass", "add", -0.3]]},
		{"id": "m83_pbs1", "slot": "muzzle", "tier": 3, "cost": 220, "name": "PBS-1 suppressor",
			"desc": "Much quieter: noise −40% / −30%, flash almost gone; with subsonic US rounds the shot barely carries. Longer and heavier (+0.05 s draw)",
			"mods": [["n_min", "mul", 0.6], ["n_max", "mul", 0.7], ["suppressor", "add", 1.0], ["flash_size", "mul", 0.3], ["flash_light", "mul", 0.3], ["draw_time", "add", 0.05], ["mass", "add", 0.45]]},
		{"id": "m83_hider", "slot": "muzzle", "cost": 70, "name": "Flash hider",
			"desc": "The muzzle flash shrinks to a third (less light to give you away); the slant brake is gone, so the camera kicks harder (+15%)",
			"mods": [["flash_size", "mul", 0.35], ["flash_light", "mul", 0.35], ["cam_kick", "mul", 1.15], ["mass", "add", -0.05]]},
		{"id": "m83_akms", "slot": "stock", "cost": 60, "name": "AKMS folding stock",
			"desc": "Folding stock: draws 20% faster, but the gun climbs more (bloom per shot +15%, camera kick +25%)",
			"mods": [["draw_time", "mul", 0.8], ["bloom_per_shot", "mul", 1.15], ["cam_kick", "mul", 1.25], ["mass", "add", -0.2]]},
	],
	"p64": [
		{"id": "p64_ext", "slot": "feed", "tier": 1, "cost": 50, "name": "Magazine extension",
			"desc": "+2 rounds per magazine (extended base plate); it snags the holster (+0.03 s draw)",
			"mods": [["mag", "add", 2], ["draw_time", "add", 0.03], ["mass", "add", 0.03]]},
		{"id": "p64_match", "slot": "barrel", "tier": 2, "cost": 95, "name": "Match barrel",
			"desc": "Tighter grouping: spread −40%, bloom per shot −25%; a tight fit that needs a firmer rack (+0.1 s reload)",
			"mods": [["jitter_deg", "mul", 0.6], ["bloom_per_shot", "mul", 0.75], ["reload_time", "add", 0.1]]},
		{"id": "p64_supp", "slot": "muzzle", "tier": 3, "cost": 175, "name": "Suppressor",
			"desc": "Quieter: noise −30% (the 9×18 round is subsonic, so it works well), flash almost gone. Longer pistol (+0.05 s draw)",
			"mods": [["n_min", "mul", 0.7], ["n_max", "mul", 0.7], ["suppressor", "add", 1.0], ["flash_size", "mul", 0.3], ["flash_light", "mul", 0.3], ["draw_time", "add", 0.05], ["mass", "add", 0.2]]},
		{"id": "p64_long", "slot": "barrel", "cost": 85, "name": "Long barrel",
			"desc": "A longer barrel: the 9×18 keeps its punch 25% farther out and flies 20% farther; it no longer fits the holster (+0.15 s draw)",
			"mods": [["falloff_start", "add", 40.0], ["range_px", "mul", 1.2], ["draw_time", "add", 0.15], ["mass", "add", 0.15]]},
		{"id": "p64_stock", "slot": "stock", "cost": 110, "name": "Holster stock",
			"desc": "A wooden holster clipped to the grip as a shoulder stock: the pistol climbs and wanders far less (bloom per shot −45%, camera kick −40%, spread −25%) — with endless ammo it becomes a steady backup carbine. Clipping it on takes time (+0.35 s draw)",
			"mods": [["bloom_per_shot", "mul", 0.55], ["cam_kick", "mul", 0.6], ["jitter_deg", "mul", 0.75], ["draw_time", "add", 0.35], ["mass", "add", 0.5]]},
	],
	"spread12": [
		{"id": "sp12_drum30", "slot": "feed", "tier": 1, "cost": 60, "name": "Extended drum",
			"desc": "+5 shells per drum; heavier and slower to swap (+0.3 s reload, +0.05 s draw)",
			"mods": [["mag", "add", 5], ["reload_time", "add", 0.3], ["draw_time", "add", 0.05], ["mass", "add", 0.4]]},
		{"id": "sp12_box8", "slot": "feed", "cost": 50, "name": "8-round box magazine",
			"desc": "Short box magazine: only 8 shells, but swapped 40% faster and the gun draws faster",
			"mods": [["mag", "set", 8], ["reload_time", "mul", 0.6], ["draw_time", "mul", 0.85], ["mass", "add", -0.9]]},
		{"id": "sp12_choke", "slot": "barrel", "tier": 2, "cost": 120, "name": "Choke",
			"desc": "Pattern 20% tighter: more pellets on target and lethal a little farther out, but a narrower cone up close",
			"mods": [["spread_deg", "mul", 0.8], ["falloff_start", "add", 15.0], ["mass", "add", 0.05]]},
		{"id": "sp12_ported", "slot": "muzzle", "tier": 3, "cost": 220, "name": "Ported barrel",
			"desc": "Gas ports tame the kick: camera kick −35%, shake −30%; the shot is a little louder (+10%)",
			"mods": [["cam_kick", "mul", 0.65], ["shake", "mul", 0.7], ["n_min", "mul", 1.1], ["n_max", "mul", 1.1], ["mass", "add", 0.1]]},
		{"id": "sp12_sawn", "slot": "barrel", "cost": 70, "name": "Sawn-off barrel",
			"desc": "Cut down for the tunnels: the pattern opens 35% wider (more pellets land on whatever is in your face) and the gun draws 25% faster, but the shot dies 20% sooner",
			"mods": [["spread_deg", "mul", 1.35], ["draw_time", "mul", 0.75], ["range_px", "mul", 0.8], ["falloff_start", "add", -10.0], ["mass", "add", -0.5]]},
	],
	"srut8": [
		{"id": "s8_tube", "slot": "feed", "tier": 1, "cost": 70, "name": "Magazine tube extension",
			"desc": "+2 shells in the tube; a longer, front-heavy gun (+0.08 s draw)",
			"mods": [["mag", "add", 2], ["draw_time", "add", 0.08], ["mass", "add", 0.25]]},
		{"id": "s8_pump", "slot": "action", "tier": 2, "cost": 145, "name": "Slick pump, recoil pad",
			"desc": "12% faster pump cycling, camera kick −25%; hurried follow-ups are less precise (spread +10%)",
			"mods": [["cooldown", "mul", 0.88], ["cam_kick", "mul", 0.75], ["jitter_deg", "mul", 1.1]]},
		{"id": "s8_carrier", "slot": "stock", "tier": 3, "cost": 265, "name": "Shell carrier",
			"desc": "Shells strapped to the receiver: loading each shell 25% faster; a heavier gun (+0.05 s draw)",
			"mods": [["reload_time", "mul", 0.75], ["draw_time", "add", 0.05], ["mass", "add", 0.35]]},
		{"id": "s8_slam", "slot": "action", "cost": 130, "name": "Slam-fire action",
			"desc": "No trigger disconnector: hold the trigger and every pump fires — 30% faster follow-ups, but hurried shots kick harder (+30%) and stray wider (+25%)",
			"mods": [["auto", "set", 1.0], ["cooldown", "mul", 0.7], ["jitter_deg", "mul", 1.25], ["cam_kick", "mul", 1.3]]},
		{"id": "s8_long", "slot": "barrel", "cost": 110, "name": "Long barrel",
			"desc": "A longer barrel: a 15% tighter pattern that stays deadly 20 px farther; heavier at the front (+0.08 s draw)",
			"mods": [["spread_deg", "mul", 0.85], ["falloff_start", "add", 20.0], ["draw_time", "add", 0.08], ["mass", "add", 0.3]]},
	],
	"lr7": [
		{"id": "lr7_cell", "slot": "feed", "tier": 1, "cost": 70, "name": "Extended cell",
			"desc": "+20 charge per cell; a bigger cell swaps slower (+0.4 s) and weighs more (+0.05 s draw)",
			"mods": [["mag", "add", 20], ["reload_time", "add", 0.4], ["draw_time", "add", 0.05], ["mass", "add", 0.6]]},
		{"id": "lr7_coil", "slot": "action", "tier": 2, "cost": 145, "name": "Overdrive coil",
			"desc": "+20% beam damage; the emitter heats 40% faster, so a long burn gets loud sooner",
			"mods": [["damage", "mul", 1.2], ["heat_gain", "mul", 1.4], ["mass", "add", 0.3]]},
		{"id": "lr7_lens", "slot": "muzzle", "tier": 3, "cost": 265, "name": "Focusing lens",
			"desc": "The beam pierces one more target; the hotter focus heats the emitter 20% faster",
			"mods": [["pierce", "add", 1], ["heat_gain", "mul", 1.2], ["mass", "add", 0.1]]},
		{"id": "lr7_diffuser", "slot": "muzzle", "cost": 120, "name": "Diffuser lens",
			"desc": "Fans the beam out: it passes through two more targets — good against a pack in a corridor — but reaches only 60% as far and burns 15% weaker",
			"mods": [["pierce", "add", 2], ["range_px", "mul", 0.6], ["damage", "mul", 0.85], ["mass", "add", 0.1]]},
	],
	"hkm9": [
		{"id": "hkm_tank", "slot": "feed", "tier": 1, "cost": 70, "name": "Extended tank",
			"desc": "+20 fuel per tank; heavier to carry and swap (+0.1 s draw, +0.3 s reload)",
			"mods": [["mag", "add", 20], ["draw_time", "add", 0.1], ["reload_time", "add", 0.3], ["mass", "add", 1.5]]},
		{"id": "hkm_mix", "slot": "action", "tier": 2, "cost": 145, "name": "Hot mix",
			"desc": "+25% damage, burns 30% longer; the jet roars louder (+30% noise)",
			"mods": [["damage", "mul", 1.25], ["ignite", "mul", 1.3], ["n_min", "mul", 1.3], ["n_max", "mul", 1.3]]},
		{"id": "hkm_nozzle", "slot": "muzzle", "tier": 3, "cost": 265, "name": "Long nozzle",
			"desc": "+30% flame range, but a narrower jet (arc −20%) and a longer gun (+0.05 s draw)",
			"mods": [["range_px", "mul", 1.3], ["arc_deg", "mul", 0.8], ["draw_time", "add", 0.05], ["mass", "add", 0.4]]},
		{"id": "hkm_gel", "slot": "muzzle", "cost": 150, "name": "Gel nozzle",
			"desc": "Thickened fuel clings where it lands: ground fire twice as often and burning 2.5× longer — a wall the shy ones won't cross. The heavy gel flies 25% shorter",
			"mods": [["patch_life", "mul", 2.5], ["patch_every", "mul", 0.5], ["range_px", "mul", 0.75], ["mass", "add", 0.2]]},
	],
	"gniew4": [
		{"id": "g4_loader", "slot": "feed", "tier": 1, "cost": 90, "name": "Speed loader",
			"desc": "Grenades slide in 30% faster; the loader hangs off the frame (+0.05 s draw)",
			"mods": [["reload_time", "mul", 0.7], ["draw_time", "add", 0.05], ["mass", "add", 0.2]]},
		{"id": "g4_heavy", "slot": "special", "tier": 2, "cost": 180, "name": "Heavy warhead",
			"desc": "+25% blast damage, +12% radius; heavier grenades fly a little slower and arm later (+16 px)",
			"mods": [["blast_damage", "mul", 1.25], ["blast_radius", "mul", 1.12], ["speed", "mul", 0.95], ["arm_dist", "add", 16.0], ["mass", "add", 0.3]]},
		{"id": "g4_cluster", "slot": "special", "tier": 3, "cost": 330, "name": "Cluster warheads",
			"desc": "Two bomblets scatter after the blast (half damage each, no extra noise); the main blast is 10% weaker",
			"mods": [["cluster", "add", 2], ["blast_damage", "mul", 0.9]]},
		{"id": "g4_short", "slot": "barrel", "cost": 120, "name": "Cut-down tube",
			"desc": "A short tube and a pistol grip: draws 30% faster and comes up in a tight corner, but the grenade leaves slower (−15%), so it drops sooner",
			"mods": [["draw_time", "mul", 0.7], ["speed", "mul", 0.85], ["mass", "add", -0.6]]},
	],
	"sokol6": [
		{"id": "f6_belt", "slot": "feed", "tier": 1, "cost": 80, "name": "Extended belt",
			"desc": "+20 rockets per belt; a longer belt to feed (+0.4 s reload, +0.08 s draw)",
			"mods": [["mag", "add", 20], ["reload_time", "add", 0.4], ["draw_time", "add", 0.08], ["mass", "add", 0.8]]},
		{"id": "f6_seeker", "slot": "optic", "tier": 2, "cost": 155, "name": "Sharper seeker",
			"desc": "+40% turn rate, +30% lock range; the narrower seeker looks only 80% as wide",
			"mods": [["homing", "mul", 1.4], ["homing_range", "mul", 1.3], ["homing_cone", "mul", 0.8]]},
		{"id": "f6_salvo", "slot": "action", "tier": 3, "cost": 285, "name": "Triple salvo",
			"desc": "Each trigger pull launches three rockets for two rounds; weaker rockets (−20%) and a slower rate (+50%)",
			"mods": [["pellets", "add", 2], ["spread_deg", "add", 8.0], ["ammo_per_shot", "add", 1], ["damage", "mul", 0.8], ["cooldown", "mul", 1.5], ["mass", "add", 0.4]]},
	],
	"widmo1": [
		{"id": "w1_cap", "slot": "feed", "tier": 1, "cost": 100, "name": "Extended capacitor",
			"desc": "+2 rounds per magazine; a bigger bank swaps slower (+0.4 s reload)",
			"mods": [["mag", "add", 2], ["reload_time", "add", 0.4], ["mass", "add", 0.5]]},
		{"id": "w1_fast", "slot": "action", "tier": 2, "cost": 205, "name": "Fast capacitor",
			"desc": "Charges 30% faster, 15% faster reload; the coils whine louder (+10% noise)",
			"mods": [["charge_time", "mul", 0.7], ["reload_time", "mul", 0.85], ["n_min", "mul", 1.1], ["n_max", "mul", 1.1]]},
		{"id": "w1_rails", "slot": "barrel", "tier": 3, "cost": 375, "name": "Hardened rails",
			"desc": "The slug passes through one layer of wall; heavier rails slow it a little (−10% damage)",
			"mods": [["wall_pierce", "add", 24.0], ["damage", "mul", 0.9], ["mass", "add", 0.6]]},
		{"id": "w1_over", "slot": "action", "cost": 240, "name": "Overcharge capacitor",
			"desc": "Dumps the whole bank into one slug: +30% damage, but the charge takes 35% longer and the coils scream (+15% noise)",
			"mods": [["damage", "mul", 1.3], ["charge_time", "mul", 1.35], ["n_min", "mul", 1.15], ["n_max", "mul", 1.15], ["mass", "add", 0.4]]},
	],
	"ciegno6": [
		{"id": "c6_twin", "slot": "feed", "tier": 1, "cost": 90, "name": "Twin bolt",
			"desc": "Two bolts loaded; heavier to draw (+0.1 s) and slower to load (+0.3 s)",
			"mods": [["mag", "add", 1], ["draw_time", "add", 0.1], ["reload_time", "add", 0.3], ["mass", "add", 0.2]]},
		{"id": "c6_bands", "slot": "action", "tier": 2, "cost": 180, "name": "Double bands",
			"desc": "A second rubber band: bolt speed +25%, range +20%; pulling both bands back takes 30% longer",
			"mods": [["speed", "mul", 1.25], ["range_px", "mul", 1.2], ["reload_time", "mul", 1.3], ["mass", "add", 0.1]]},
		{"id": "c6_tether", "slot": "special", "tier": 3, "cost": 330, "name": "Barbed tether",
			"desc": "Pierces one more enemy, +20% damage; a line yanks hit enemies toward you, but drags the bolt (speed −15%)",
			"mods": [["pierce", "add", 1], ["stun", "add", 0.4], ["damage", "mul", 1.2], ["pull", "add", 260.0], ["speed", "mul", 0.85], ["mass", "add", 0.2]]},
	],
	"maczeta": [
		{"id": "mc_honed", "slot": "edge", "tier": 1, "cost": 50, "name": "Honed edge",
			"desc": "+20% damage; the thin edge bites in instead of shoving (knock-back −20%)",
			"mods": [["damage", "mul", 1.2], ["knock", "mul", 0.8]]},
		{"id": "mc_long", "slot": "stock", "tier": 2, "cost": 95, "name": "Long grip",
			"desc": "+50% arc, +6 px reach; a longer swing (+12% swing time)",
			"mods": [["arc_deg", "mul", 1.5], ["reach", "add", 6.0], ["cooldown", "mul", 1.12], ["mass", "add", 0.15]]},
		{"id": "mc_exec", "slot": "special", "tier": 3, "cost": 175, "name": "Executioner",
			"desc": "Kills any enemy below 35% HP outright; the heavier blade swings 10% slower",
			"mods": [["execute_frac", "add", 0.35], ["cooldown", "mul", 1.1], ["mass", "add", 0.2]]},
		{"id": "mc_short", "slot": "stock", "cost": 60, "name": "Short grip",
			"desc": "A cut-down handle for close work: swings 15% faster, but a narrower arc (−20%) and 4 px less reach",
			"mods": [["cooldown", "mul", 0.85], ["arc_deg", "mul", 0.8], ["reach", "add", -4.0], ["mass", "add", -0.1]]},
	],
	"kilof": [
		{"id": "kf_sharp", "slot": "edge", "tier": 1, "cost": 50, "name": "Sharpened pick",
			"desc": "+15% damage, 12% faster swing; the point digs in instead of stunning (stun −20%)",
			"mods": [["damage", "mul", 1.15], ["cooldown", "mul", 0.88], ["stun", "mul", 0.8]]},
		{"id": "kf_heavy", "slot": "head", "tier": 2, "cost": 95, "name": "Heavy head",
			"desc": "+0.6 s stun, +30% knock-back; a slower swing (+12%)",
			"mods": [["stun", "add", 0.6], ["knock", "mul", 1.3], ["cooldown", "mul", 1.12], ["mass", "add", 0.6]]},
		{"id": "kf_seismic", "slot": "head", "tier": 3, "cost": 175, "name": "Seismic head",
			"desc": "A wider arc (+60%) and a longer stun (+0.8 s); slower (+15%) and louder (+30% noise)",
			"mods": [["arc_deg", "mul", 1.6], ["stun", "add", 0.8], ["cooldown", "mul", 1.15], ["n_min", "mul", 1.3], ["n_max", "mul", 1.3], ["mass", "add", 0.8]]},
	],
}

static var _by_id: Dictionary = {}

## Część po id (pusty słownik, gdy nie ma).
static func get_part(id: String) -> Dictionary:
	if _by_id.is_empty():
		for k in PARTS:
			for p in PARTS[k]:
				var e: Dictionary = (p as Dictionary).duplicate()
				e["weapon"] = k
				_by_id[String(p["id"])] = e
	return _by_id.get(id, {})

static func is_valid(id: String) -> bool:
	return not get_part(id).is_empty()

## Wszystkie id części w stałej kolejności (indeks = `arg` znajdźki „part” — ten sam u serwera i klientów).
static func all_ids() -> Array:
	var out: Array = []
	for k in PARTS:
		for p in PARTS[k]:
			out.append(String(p["id"]))
	return out

static func of(key: String) -> Array:
	return PARTS.get(key, []) as Array

## Gniazda broni w stałej kolejności (tylko te, w których są części).
static func slots_of(key: String) -> Array:
	var out: Array = []
	for s in SLOT_ORDER:
		for p in of(key):
			if String(p["slot"]) == s:
				out.append(s)
				break
	return out

## Części jednego gniazda (indeks 1..n w kodzie `fit`).
static func in_slot(key: String, slot: String) -> Array:
	var out: Array = []
	for p in of(key):
		if String(p["slot"]) == slot:
			out.append(p)
	return out

## Kod `fit` z wyboru {gniazdo: id części ("" = fabryczny)}; nieznane id pomijamy.
static func encode(key: String, choice: Dictionary) -> int:
	var code := 0
	var slots := slots_of(key)
	for i in slots.size():
		var id := String(choice.get(slots[i], ""))
		if id == "":
			continue
		var ps := in_slot(key, String(slots[i]))
		for j in ps.size():
			if String(ps[j]["id"]) == id:
				code |= (j + 1) << (2 * i)
	return code

## Id zamontowanych części z kodu `fit` (kolejność gniazd).
static func decode(key: String, code: int) -> Array:
	var out: Array = []
	var slots := slots_of(key)
	for i in slots.size():
		var j := (code >> (2 * i)) & 3
		var ps := in_slot(key, String(slots[i]))
		if j >= 1 and j <= ps.size():
			out.append(String(ps[j - 1]["id"]))
	return out

## Kod `fit` z listy id części (testy, narzędzia).
static func encode_ids(key: String, ids: Array) -> int:
	var choice := {}
	for id in ids:
		var p := get_part(String(id))
		if not p.is_empty() and String(p["weapon"]) == key:
			choice[String(p["slot"])] = String(id)
	return encode(key, choice)

## Serwer: zostawia w kodzie tylko części odblokowane przez drużynę (`owned` = Scrap.parts) i znane tej broni.
static func sanitize(key: String, code: int, owned: Dictionary) -> int:
	var ok: Array = []
	for id in decode(key, code):
		if owned.has(id):
			ok.append(id)
	return encode_ids(key, ok)

## Nakłada części z kodu `fit` na świeżo zbudowaną definicję (przed amunicją).
static func apply(d: RefCounted, code: int) -> void:
	d.set("fit", code)
	for id in decode(String(d.key), code):
		for m in get_part(String(id)).get("mods", []):
			var cur: Variant = d.get(String(m[0]))
			var out: float
			match String(m[1]):
				"mul":
					out = float(cur) * float(m[2])
				"set":
					out = float(m[2])
				_:
					out = float(cur) + float(m[2])
			if typeof(cur) == TYPE_BOOL:
				d.set(String(m[0]), out != 0.0)                  # przełącznik (np. `auto`): "set" 1 włącza, 0 wyłącza
			else:
				d.set(String(m[0]), int(roundf(out)) if typeof(cur) == TYPE_INT else out)

## Największy magazynek, jaki broń może mieć z częściami (serwer ogranicza nim prośby o naboje i zwroty) — z nabojem w komorze.
static func max_capacity(d: RefCounted) -> int:
	var best := int(d.mag)
	for p in of(String(d.key)):
		for m in p.get("mods", []):
			if String(m[0]) == "mag":
				best = maxi(best, int(d.mag) + int(m[2]) if String(m[1]) == "add" else int(m[2]))
	return best + 1

## Cena części dla kupującego (`mult` = perk „Smith”), zaokrąglona do 5.
static func cost(id: String, mult := 1.0) -> int:
	return int(roundf(float(get_part(id).get("cost", 0)) * mult / 5.0)) * 5

## Części dawnych poziomów 1..`level` broni `key` (migracja zapisów sprzed 1.7.319).
static func from_level(key: String, level: int) -> Array:
	var out: Array = []
	for p in of(key):
		if int(p.get("tier", 0)) >= 1 and int(p.get("tier", 0)) <= level:
			out.append(String(p["id"]))
	return out

## Czy modyfikator pogarsza broń (koszt części). Kierunek „lepiej” zależy od pola.
const LOWER_IS_BETTER := ["draw_time", "reload_time", "cooldown", "jitter_deg", "bloom_per_shot", "bloom_max", "cam_kick", "shake", "patch_every", "mass",
	"n_min", "n_max", "heat_gain", "charge_time", "arm_dist", "flash_size", "flash_light", "spread_deg", "barrel_heat"]
static func is_cost(m: Array, base: RefCounted) -> bool:
	var f := String(m[0])
	var cur := float(base.get(f))
	var out: float
	match String(m[1]):
		"mul":
			out = cur * float(m[2])
		"set":
			out = float(m[2])
		_:
			out = cur + float(m[2])
	if is_equal_approx(out, cur):
		return false
	var lower_better := f in LOWER_IS_BETTER
	return (out > cur) == lower_better

## Sprawdza katalog: znane bronie i pola, unikalne id, najwyżej MAX_PER_SLOT części w gnieździe, każda część ma koszt
## (modyfikator na minus) poza wyjątkami zapisanymi w tabeli jako zamierzone (dławik: węższy stożek z bliska nie jest polem). Wołane przez --weapontest.
static func validate(defs: Array) -> Array:
	var errs: Array = []
	var keys := {}
	for d in defs:
		keys[String(d.key)] = d
	var seen := {}
	for k in PARTS:
		if not keys.has(k):
			errs.append("części: nieznana broń '%s'" % k)
			continue
		for s in slots_of(String(k)):
			if in_slot(String(k), String(s)).size() > MAX_PER_SLOT:
				errs.append("części: %s / %s ma więcej niż %d części" % [k, s, MAX_PER_SLOT])
		for p in PARTS[k]:
			var id := String(p["id"])
			if seen.has(id):
				errs.append("części: powtórzone id '%s'" % id)
			seen[id] = true
			if not (String(p["slot"]) in SLOT_ORDER):
				errs.append("części: %s — nieznane gniazdo '%s'" % [id, p["slot"]])
			var has_cost := false
			for m in p.get("mods", []):
				if not (String(m[0]) in keys[k]):
					errs.append("części: %s — nieznane pole '%s'" % [id, m[0]])
				elif is_cost(m, keys[k]):
					has_cost = true
			if not has_cost and id != "sp12_choke":
				errs.append("części: %s nie ma kosztu (żaden modyfikator nie pogarsza broni)" % id)
			if int(p.get("cost", 0)) <= 0:
				errs.append("części: %s bez ceny" % id)
	return errs
