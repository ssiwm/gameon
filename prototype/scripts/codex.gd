extends RefCounted
## Kodeks (menu pauzy): bestiariusz i opisy broni. Liczby bierzemy Z KODU (Enemy.KINDS, WeaponDef) — tabela
## nie rozjedzie się z grą; tutaj są tylko opisy i wskazówki. Pozycje mają wspólny format dla codex_page.gd:
##   {title, tag, portrait: {type, ...}, stats: [[etykieta, wartość], ...], text, tip}
## Portrety: "sprite" (arkusz + animacja z manifestu), "gun" (wiersz guns.png), "vein" (rysowany w kodzie).

const Enemy := preload("res://scripts/enemy.gd")
const Leech := preload("res://scripts/leech.gd")
const Sprites := preload("res://scripts/sprites.gd")
const Weapons := preload("res://scripts/weapons.gd")
const Upgrades := preload("res://scripts/upgrades.gd")
const WeaponDef := preload("res://scripts/weapon_def.gd")

const PX_PER_M := 16.0               ## lights.gd: 1 m = 16 px

# ---------------------------------------------------------------- bestiariusz

## [klucz w Enemy.KINDS, arkusz, animacja, nazwa, etykieta, opis, wskazówka]
const ENEMIES := [
	["trzosek", "trzosek", "idle", "CUTPURSE", "Pack hunter",
		"Fast and cowardly alone, vicious in a pack of three to six. Sleeps until a shot or a close step wakes it. The oldest of the pack leads — when it dies, the rest panic. Flares make them curious.",
		"Continuous fire or the machete. Kill the leader first and the pack scatters."],
	["wolek", "wolek", "idle", "BULLOCK", "Bruiser",
		"Slow, huge and hard to kill. Winds up a charge that smashes crates and barrels — and stuns itself against a wall. Also hurls loose crates from a distance.",
		"Sidestep the charge and let it hit a wall, then shoot. Its hide is armored: weak bullets and pellets lose damage, heavy hits do not. A shot to the head hurts more. Drops medkits."],
	["skoczek", "skoczek", "idle", "LEAPER", "Ambusher",
		"Hangs from the ceiling above a passage and drops on whoever walks under it.",
		"Look up before you cross a gap, and keep moving."],
	["slepiec", "slepiec", "idle", "BLIND ONE", "Blind hunter",
		"Cannot see — only hears. Walks to the source of the last noise and searches around it.",
		"Crouch (SHIFT) and walk past. Throw a lure (Q) to pull it away. Shots will bring it running."],
	["podsluchacz", "podsluchacz", "idle", "EAVESDROPPER", "Listener",
		"Stands motionless and listens. If it sees or hears you it screams, and every enemy nearby gets a trail to your position.",
		"Kill it quietly — the machete is almost silent — or avoid its line of sight altogether."],
	["mimik", "mimik", "idle", "MIMIC", "Mimic",
		"Stands like a teammate and calls for help in a player's voice. Strikes when you come close.",
		"Tells: no hearts above its head, no footsteps or breathing, glowing eyes in the dark, a strange number on the label. A flashlight or a shot exposes it."],
	["cma", "cma", "idle", "MOTH", "Light moth",
		"Hangs under the ceiling until light wakes it, then flies at the source. Burns up on a flare, bites at a flashlight.",
		"Throw a flare far away and switch the flashlight off. Fragile — a few hits kill it."],
]

static func bestiary() -> Array:
	var out: Array = []
	for e in ENEMIES:
		var d: Dictionary = Enemy.KINDS[e[0]]
		var stats: Array = [
			["HP", "%d" % int(d["hp"])],
			["Speed", "%.1f m/s" % (float(d["speed"]) / PX_PER_M) if float(d["speed"]) > 0.0 else "stationary"],
			["Damage", "%d heart%s" % [int(d["damage"]), "" if int(d["damage"]) == 1 else "s"] if int(d["damage"]) > 0 else "—"],
			["Hearing", "%d m" % int(float(d["hear"]) / PX_PER_M) if float(d["hear"]) > 0.0 else "—"],
			["Sight", "%d m" % int(float(d["sight"]) / PX_PER_M) if float(d["sight"]) > 0.0 else "—"],
		]
		if bool(d.get("fly", false)):
			stats.append(["Movement", "flies"])
		if float(d.get("armor", 0.0)) > 0.0:
			stats.append(["Armor", "−%d per bullet" % int(d["armor"])])
		if float(d.get("head", 0.0)) > 0.0:
			stats.append(["Weak spot", "head"])
		var col: Color = (d["color"] as Color).lerp(Color(1.0, 0.85, 0.7), 0.35)
		out.append({"title": e[3], "tag": e[4], "accent": col, "portrait": {"type": "sprite", "sheet": e[1], "anim": e[2]},
			"stats": stats, "text": e[5], "tip": e[6]})
	out.append({"title": "STALKER", "tag": "Cannot be killed", "accent": Color(0.55, 0.75, 1.0),
		"portrait": {"type": "sprite", "sheet": "stalker", "anim": "idle"},
		"stats": [["HP", "∞"], ["Hunting", "5.5 m/s"], ["Lurking", "3.4 m/s"], ["Wakes at", "60% noise"], ["Sleeps at", "30% noise"], ["Reach", "0.9 m (0.5 m crouched)"]],
		"text": "Reacts to noise only, never to you directly. Walks to the loudest recent sound, listens there, then strikes — with a wind-up you can run from. Light draws him. Attacks make no noise.",
		"tip": "Stop shooting and let the meter fall below 30%. Q lures him away for 20–30 s. Crouch in the dark. You can outrun him (slower than you)."})
	out.append({"title": "NEST", "tag": "Mission objective", "accent": Color(1.0, 0.5, 0.2),
		"portrait": {"type": "sprite", "sheet": "nest", "anim": "pulse"},
		"stats": [["HP", "60"], ["Noise when destroyed", "+8"]],
		"text": "The Vein's limbs. As long as one lives, the mother sleeps and cannot be hurt. A nest is not a threat — bots will not shoot it; destroying one is the squad's decision. It is loud.",
		"tip": "Clear the area first, destroy nests one at a time and let the noise settle between them."})
	out.append({"title": "THE VEIN", "tag": "Boss — Mother of Nests", "accent": Color(0.85, 0.28, 0.22),
		"portrait": {"type": "sprite", "sheet": "vein", "anim": "idle"} if Sprites.has("vein") else {"type": "vein"},
		"stats": [["HP", "750 (+250 per extra player)"], ["Maw closed", "5% damage"], ["Phase 2", "below 66% — enraged"], ["Phase 3", "below 33% — scream"]],
		"text": "Wakes when the last nest dies. Her maw is shut and armoured — it opens only briefly after each attack. Lash up close, tail sweep along the floor, spore spit at range. She spawns young. At 33% she screams: noise goes to 100% and the Stalker wakes.",
		"tip": "Dodge, then shoot while the maw is open. Light her maw during a wind-up to blind her. Q pulls her fire to the lure. Shots from above at a steep angle always do 5%."})
	out.append({"title": "THE LEECH", "tag": "Boss — hides under water", "accent": Color(0.35, 0.68, 0.62),
		"portrait": {"type": "leech"},
		"stats": [["HP", "%d (+%d per extra player)" % [int(Leech.BASE_HP), int(Leech.HP_PER_EXTRA_HUMAN)]],
			["Hidden", "%d%% damage" % int(Leech.SUB_MULT * 100.0)], ["Phase 2", "below 66% — adds"], ["Phase 3", "below 33% — scream"],
			["Surfaced", "full damage"], ["Grab", "%d s — free: %d%% HP" % [int(Leech.GRAB_TIME), int(Leech.GRAB_FRAC * 100.0)]]],   # krótkie etykiety i wartości: siatka 4-kolumnowa nie może być szersza niż DETAIL_W (jak u Żyły)
		"text": "Lives under the flooded hall's pool. Unseen in the dark: only ripples betray it. It swims under whoever wades in the water, telegraphs with churning rings, then bursts out, bites and grabs. A grabbed player is dragged under in four seconds and goes down. Anyone on a catwalk above the water is out of its reach.",
		"tip": "Throw a flare (F) or sweep the flashlight over the ripples — the shadow shows, and then it takes full damage. Shoot a surfaced leech with everything. If someone is grabbed, the whole squad must hurt it; a grabbed player's melee counts double."})
	return out

# ---------------------------------------------------------------- bronie

## Krótki opis i wskazówka; klucz = WeaponDef.key
const WEAPON_TEXT := {
	"m83": ["Standard-issue assault rifle. Quiet while the barrel is cold and louder as it heats.",
		"Fire in short bursts — a long one costs you the night."],
	"spread12": ["Close-range shotgun: five pellets, brutal point-blank, nearly useless past a few metres.",
		"One of the loudest cold shots you own. Use it on a Bullock's back, not across a room."],
	"p64": ["Sidearm with an endless supply — the magazine refills, the reserve never drops. Accurate and cheap on noise.",
		"Your answer when everything else is empty. Crouch to tighten the spread."],
	"srut8": ["Heavy pump shotgun: eight pellets, huge knock-back and a short stun, loaded shell by shell.",
		"Shells load one at a time and loading can be interrupted by firing. Brace — it shoves you back."],
	"lr7": ["Energy beam: a continuous ray that pierces one extra enemy (two in a line). Barely audible — but moths fly at the beam.",
		"The quietest way to hurt a pack. Cell-powered — watch the magazine, not the heat. Fire it near a hanging Moth and it will wake and come for you."],
	"hkm9": ["Flamethrower: short cone of fire that ignites enemies. Burning pack hunters panic and run.",
		"Burning enemies take damage over time and run in panic. Keep it for tight corridors."],
	"gniew4": ["Grenade launcher: lobbed shell that explodes on contact or after a fuse, with a wide blast.",
		"Counts as a lure (+15 noise) and hurts the squad too. Do not fire at your own feet."],
	"sokol6": ["Seeker rifle: bullets bend toward a target inside a cone in front of you. Sloppy aim, steady hits.",
		"Good when you cannot line up the shot: it prefers Moths, Leapers and Eavesdroppers. The bullets are slow — lead moving targets."],
	"widmo1": ["Rail rifle: hold to charge, release for a hit that pierces everything in line. Enormous damage, enormous noise.",
		"Release before the charge completes and the shot is cancelled. The loudest weapon — plan the escape first."],
	"ciegno6": ["Silent bolt gun: one bolt per magazine, huge damage, almost no noise. The bolt sticks in the target and can be picked up.",
		"Aim for the head (×2). The assassin's tool for an Eavesdropper."],
	"maczeta": ["Machete: fast, silent, short reach. Kills a sleeping enemy — or one with its back to you — instantly.",
		"The first answer to any sleeper. No ammo, no noise."],
	"kilof": ["Pickaxe: slow swing, heavy damage and a long stun on hit. A little noise.",
		"Use it as the opener, then back off before the next swing."],
}

static func arsenal() -> Array:
	var out: Array = []
	for d: WeaponDef in Weapons.defs():
		out.append(weapon_entry(d.id))
	return out

## Wpis katalogu dla broni `id` — liczony świeżo (statystyki z ulepszeniami drużyny, poziomy, dostęp), bo zmieniają się w kryjówce.
static func weapon_entry(id: int) -> Dictionary:
	var base: WeaponDef = Weapons.base_def(id)
	var d: WeaponDef = Weapons.def(id)
	var notes: Array = WEAPON_TEXT.get(d.key, ["", ""])
	var tag := _slot_name(d)
	var tiers: Array = []
	var access := ""
	if not Scrap.is_unlocked(id):
		access = "Locked — " + Scrap.lock_text(id)
	if Upgrades.has_tiers(String(d.key)):
		var lv := Scrap.level_of(id)
		tag += "  ·  TIER %d / %d" % [lv, Upgrades.MAX_LEVEL] if Scrap.is_unlocked(id) else ""
		for i in range(1, Upgrades.MAX_LEVEL + 1):
			var t := Upgrades.tier(String(d.key), i)
			var state := 0 if i <= lv else (1 if i == lv + 1 else 2)      # 0 zainstalowany, 1 następny, 2 dalszy
			tiers.append({"head": "T%d  %s" % [i, t["name"]], "desc": t["desc"], "cost": Upgrades.COSTS[i - 1], "state": state})
	return {"title": base.name, "tag": tag, "accent": base.tracer_color, "portrait": {"type": "gun", "row": base.gun_row, "color": base.tracer_color},
		"stats": _weapon_stats(d), "text": notes[0], "tip": notes[1], "weapon_id": id, "tiers": tiers, "access": access}

static func _slot_name(d: WeaponDef) -> String:
	match d.slot:
		WeaponDef.Slot.PRIMARY:
			return "Primary weapon"
		WeaponDef.Slot.SIDEARM:
			return "Sidearm"
	return "Melee"

static func _weapon_stats(d: WeaponDef) -> Array:
	var dmg := "%d" % int(d.damage)
	if d.kind == WeaponDef.Kind.LAUNCHER:
		dmg = "%d blast" % int(d.blast_damage)
	elif d.pellets > 1:
		dmg = "%d × %d pellets" % [int(d.damage), d.pellets]
	elif d.is_continuous():
		dmg = "%d / tick" % int(d.damage)
	var rate := "%d / min" % int(round(d.rpm()))
	if d.is_continuous():
		rate = "continuous"
	elif d.kind == WeaponDef.Kind.RAIL:
		rate = "%.1f s charge" % d.charge_time
	var noise := "%.1f" % d.n_min if is_equal_approx(d.n_min, d.n_max) else "%.1f → %.1f" % [d.n_min, d.n_max]
	var out: Array = [["Damage", dmg], ["Fire rate", rate], ["Range", "%d m" % int(round(d.range_m()))]]
	if d.uses_ammo():
		var ammo := "%d" % d.mag
		ammo += " + ∞" if d.infinite else " + %d" % d.reserve_start
		out.append(["Magazine", ammo])
		out.append(["Reload", "%.1f s" % d.full_reload_time() if not d.reload_per_round else "%.2f s / round" % d.reload_time])
	out.append(["Noise", noise if d.n_max > 0.0 else "silent"])
	if d.kind == WeaponDef.Kind.MELEE:
		out.append(["DPS", "%d" % int(round(d.dps()))])
	return out
