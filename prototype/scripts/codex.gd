extends RefCounted
## Kodeks (menu pauzy): bestiariusz i opisy broni. Liczby bierzemy Z KODU (Enemy.KINDS, WeaponDef) — tabela
## nie rozjedzie się z grą; tutaj są tylko opisy i wskazówki. Pozycje mają wspólny format dla codex_page.gd:
##   {title, tag, portrait: {type, ...}, stats: [[etykieta, wartość], ...], text, tip}
## Portrety: "image" (render modelu 3D gry, tools/bake_portraits.gd → art/portraits/), "sprite" (arkusz — zapas, gdy brak renderu),
## "gun" (render broni), "vein" / "leech" (rysowane w kodzie — zapas). Bestiariusz z odkrywaniem (od 1.7.407): wpis z `beast` jest zakryty,
## dopóki gracz nie spotka tego wroga (Profile.knows, bestiary_watch.gd); `group` — nagłówek na liście kodeksu.

const Enemy := preload("res://scripts/enemy.gd")
const Leech := preload("res://scripts/leech.gd")
const Sprites := preload("res://scripts/sprites.gd")
const Weapons := preload("res://scripts/weapons.gd")
const Parts := preload("res://scripts/parts.gd")
const WeaponDef := preload("res://scripts/weapon_def.gd")
const Throwables := preload("res://scripts/throwables.gd")
const Perks := preload("res://scripts/perks.gd")
const EnemyDefs := preload("res://scripts/enemy_defs.gd")

const PX_PER_M := 16.0               ## lights.gd: 1 m projektowy = 16 px (w świecie 3D ok. 1,31 m)
const PORTRAITS := "res://art/portraits/"

# ---------------------------------------------------------------- bestiariusz

## [klucz w Enemy.KINDS, arkusz, animacja, nazwa, etykieta, opis, wskazówka]; elity (bez arkusza 2D) mają ósmy element — ścieżkę portretu z konceptu modelu 3D.
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
		"Crouch ({crouch}) and walk past. Throw a lure ({overcharge}) to pull it away. Shots will bring it running."],
	["podsluchacz", "podsluchacz", "idle", "EAVESDROPPER", "Listener",
		"Stands motionless and listens. If it sees or hears you it screams, and every enemy nearby gets a trail to your position.",
		"Kill it quietly — the machete is almost silent — or avoid its line of sight altogether."],
	["mimik", "mimik", "idle", "MIMIC", "Mimic",
		"Stands like a teammate and calls for help in a player's voice. Strikes when you come close.",
		"Tells: no hearts above its head, no footsteps or breathing, glowing eyes in the dark, a strange number on the label. A flashlight or a shot exposes it."],
	["cma", "cma", "idle", "MOTH", "Light moth",
		"Nests in swarms under the ceiling until it sees light, then flies at the source. It does not bite: it smothers your flashlight — a shorter, dimmer beam, a draining battery and loud fluttering that carries.",
		"A flare or fire pulls the whole swarm off you and burns it. Switching the flashlight off shakes them loose. Fragile, but kill one at your face and its dust makes you cough."],
	["kaplan", "", "idle", "THE PRIEST", "Elite — support",
		"Never strikes. Keeps behind the pack, heals wounded Cutpurses in sight and wails when you get close: everyone caught in the wave is stunned — no shooting, jumping or melee — and every enemy nearby hears it.",
		"Back out of the ring while the wind-up shows, or kill him before the wail ends. Without him the pack loses its nerve. Armored — heavy hits and the head work best.",
		"res://art/portraits/kaplan.png"],
	["rzeznik", "", "idle", "THE BUTCHER", "Elite — bruiser",
		"A Bullock turned up to eleven. Charges harder and further, smashes through bricked-up passages and does not stagger from hits or stuns. Hurls nothing — all he needs is his cleaver.",
		"Leave the charge line and let him run past, then shoot his back. A wall stuns him for a long moment. Armor −4 per bullet: bring heavy weapons.",
		"res://art/portraits/rzeznik.png"],
	["zerca", "", "idle", "THE DEVOURER", "Elite — abductor",
		"Invisible and untouchable until he strikes. Smells a downed player from afar, sneaks up and grabs them, then drags the victim to his lair. If the victim is not freed in time, they are devoured: back to the mission start with starting gear. Shots do not slow him.",
		"Never leave a downed teammate alone — pick them up fast. A faint breath nearby means he is already coming. Kill him while he drags and the victim is released.",
		"res://art/portraits/zerca.png"],
]

static func bestiary() -> Array:
	var out: Array = []
	for e in ENEMIES:
		var d: Dictionary = Enemy.KINDS[e[0]]
		var stats: Array = [
			["HP", "%d" % int(d["hp"])],
			["Speed", "%.1f m/s" % (float(d["speed"]) / PX_PER_M) if float(d["speed"]) > 0.0 else "stationary"],
			["Damage", TranslationServer.translate_plural("%d heart", "%d hearts", int(d["damage"])) % int(d["damage"]) if int(d["damage"]) > 0 else "—"],
			["Hearing", "%d m" % int(float(d["hear"]) / PX_PER_M) if float(d["hear"]) > 0.0 else "—"],
			["Sight", "%d m" % int(float(d["sight"]) / PX_PER_M) if float(d["sight"]) > 0.0 else "—"],
		]
		if bool(d.get("fly", false)):
			stats.append(["Movement", "flies"])
		if float(d.get("armor", 0.0)) > 0.0:
			stats.append(["Armor", TranslationServer.translate("−%d per bullet") % int(d["armor"])])
		if float(d.get("head", 0.0)) > 0.0:
			stats.append(["Weak spot", "head"])
		var col: Color = (d["color"] as Color).lerp(Color(1.0, 0.85, 0.7), 0.35)
		var portrait := _portrait_of(String(e[0]), {"type": "image", "path": e[7]} if e.size() > 7 else {"type": "sprite", "sheet": e[1], "anim": e[2]})
		out.append({"title": e[3], "tag": e[4], "accent": col, "portrait": portrait, "beast": String(e[0]),
			"group": "ELITES" if EnemyDefs.is_elite(String(e[0])) else "COMMON", "stats": stats, "text": e[5], "tip": e[6]})
	out.append({"title": "STALKER", "tag": "Cannot be killed", "accent": Color(0.55, 0.75, 1.0), "beast": "stalker", "group": "SPECIAL",
		"portrait": _portrait_of("stalker", {"type": "sprite", "sheet": "stalker", "anim": "idle"}),
		"stats": [["HP", "∞"], ["Hunting", "5.5 m/s"], ["Lurking", "3.4 m/s"], ["Wakes at", "60% noise"], ["Sleeps at", "30% noise"], ["Reach", "0.9 m (0.5 m crouched)"]],
		"text": "Reacts to noise only, never to you directly. Walks to the loudest recent sound, listens there, then strikes — with a wind-up you can run from. Light draws him. Attacks make no noise.",
		"tip": "Stop shooting and let the meter fall below 30%. {overcharge} lures him away for 20–30 s. Crouch in the dark. You can outrun him (slower than you)."})
	out.append({"title": "NEST", "tag": "Mission objective", "accent": Color(1.0, 0.5, 0.2), "beast": "nest", "group": "SPECIAL",
		"portrait": _portrait_of("nest", {"type": "sprite", "sheet": "nest", "anim": "pulse"}),
		"stats": [["HP", "60"], ["Noise when destroyed", "+8"]],
		"text": "The Vein's limbs. As long as one lives, the mother sleeps and cannot be hurt. A nest is not a threat — bots will not shoot it; destroying one is the squad's decision. It is loud.",
		"tip": "Clear the area first, destroy nests one at a time and let the noise settle between them."})
	out.append({"title": "THE VEIN", "tag": "Boss — Mother of Nests", "accent": Color(0.85, 0.28, 0.22), "beast": "vein", "group": "BOSSES",
		"portrait": _portrait_of("vein", {"type": "sprite", "sheet": "vein", "anim": "idle"} if Sprites.has("vein") else {"type": "vein"}),
		"stats": [["HP", "750 (+250 per extra player)"], ["Maw closed", "5% damage, blasts 35%"], ["Phase 2", "below 66% — enraged"], ["Phase 3", "below 33% — scream"]],
		"text": "Wakes when the last nest dies. Her maw is shut and armoured — it opens only briefly after each attack. Lash up close, tail sweep along the floor, spore spit at range. She spawns young. At 33% she screams: noise goes to 100% and the Stalker wakes.",
		"tip": "Dodge, then shoot while the maw is open. Light her maw during a wind-up to blind her. {overcharge} pulls her fire to the lure. Shots from above at a steep angle always do 5%; blasts have no direction."})
	out.append({"title": "THE LEECH", "tag": "Boss — hides under water", "accent": Color(0.35, 0.68, 0.62), "beast": "leech", "group": "BOSSES",
		"portrait": _portrait_of("leech", {"type": "leech"}),
		"stats": [["HP", _t("%d (+%d per extra player)") % [int(Leech.BASE_HP), int(Leech.HP_PER_EXTRA_HUMAN)]],
			["Hidden", _t("%d%% (lit %d%%)") % [int(Leech.SUB_MULT * 100.0), int(Leech.LIT_MULT * 100.0)]], ["Phase 2", "below 66% — adds"], ["Phase 3", "below 33% — scream"],
			["Surfaced", "full damage"], ["Grab", _t("%.1f s — free: %d%% HP") % [Leech.GRAB_TIME, int(Leech.GRAB_FRAC * 100.0)]]],   # krótkie etykiety i wartości: siatka 4-kolumnowa nie może być szersza niż DETAIL_W (jak u Żyły)
		"text": "Lives under the flooded hall's pool. Unseen in the dark: only ripples betray it — and in the dark it heals. It swims under whoever wades in the water, stands on a low catwalk or crowds the shore, telegraphs with churning rings, then bursts out, bites and grabs. A grabbed player is dragged under in three and a half seconds and goes down. From the second phase it also spits acid at anyone it cannot reach, even on the high catwalks. Its minions crawl out of the water from the start. In the later phases a tidal wave floods the low catwalks and the shore every ~25 s — it hurts and douses flares there.",
		"tip": "Throw a flare ({flare}) or sweep the flashlight over the ripples — the shadow shows, but only 40% of your damage lands on it. Bait the ambush, then hit it while it is out of the water. A flare that lands in the water burns out in 8 s. Keep moving: the high catwalks stop its bite and the tide, but not its acid. Shoot a surfaced leech with everything; if someone is grabbed, the whole squad must hurt it and their melee counts double."})
	return out

## Portret wpisu: render modelu 3D z art/portraits/, a gdy go brak — dotychczasowy rysunek (`fallback`).
static func _portrait_of(id: String, fallback: Dictionary) -> Dictionary:
	var path := PORTRAITS + id + ".png"
	return {"type": "image", "path": path} if ResourceLoader.exists(path) else fallback

## Nazwa wpisu bestiariusza (klucz tłumaczenia) — komunikat o nowym wpisie.
static func beast_name(id: String) -> String:
	for e in ENEMIES:
		if e[0] == id:
			return String(e[3])
	return {"stalker": "STALKER", "nest": "NEST", "vein": "THE VEIN", "leech": "THE LEECH"}.get(id, id.to_upper())

## Wpis bestiariusza taki, jak go widzi gracz: nieznany — sylwetka, „???” i bez opisu; znany — z licznikiem zabójstw tego gracza.
static func beast_view(e: Dictionary) -> Dictionary:
	var id := String(e.get("beast", ""))
	if id == "":
		return e
	var v := e.duplicate()
	if not Profile.knows(id):
		var p: Dictionary = (e["portrait"] as Dictionary).duplicate()
		p["unknown"] = true
		v["title"] = "???"
		v["tag"] = "Not encountered yet"
		v["accent"] = Color(0.45, 0.45, 0.42)
		v["portrait"] = p
		v["stats"] = []
		v["text"] = "You have not met it yet. The entry fills in after the first encounter — or the first kill."
		v["tip"] = ""
		return v
	if _counts_kills(id):
		var stats: Array = (e["stats"] as Array).duplicate()
		stats.append(["Your kills", "%d" % Profile.beast_kills(id)])
		v["stats"] = stats
	return v

## Licznik zabójstw ma sens dla wrogów z enemy_defs.gd (Stalker jest nieśmiertelny, gniazd i bossów nie liczy server_award_kill).
static func _counts_kills(id: String) -> bool:
	return Enemy.KINDS.has(id)

# ---------------------------------------------------------------- bronie

## Krótki opis i wskazówka; klucz = WeaponDef.key
const WEAPON_TEXT := {
	"m83": ["Standard-issue assault rifle. Quiet while the barrel is cold and louder as it heats. {firemode} switches between full auto and a 3-round burst: slower, tighter and much quieter.",
		"Burst mode is the sneaking mode: about 20% less damage per second for half the noise, and the barrel heats up much slower. A long full-auto spray costs you the night."],
	"spread12": ["Drum-fed semi-auto shotgun on a Kalashnikov action: five pellets a shot, 25-shell drum, brutal point-blank, nearly useless past a few metres.",
		"One of the loudest cold shots you own. Use it on a Bullock's back, not across a room."],
	"p64": ["Sidearm with an endless supply — the magazine refills, the reserve never drops. Accurate and cheap on noise.",
		"Your answer when everything else is empty. Crouch to tighten the spread."],
	"srut8": ["Heavy pump shotgun: eight pellets, huge knock-back and a short stun, loaded shell by shell.",
		"Shells load one at a time and loading can be interrupted by firing."],
	"lr7": ["Energy beam: a continuous ray that pierces one extra enemy (two in a line), weaker at range. Quiet when cold, louder as the beam heats — and moths fly at it.",
		"Short bursts keep it quiet; a long burn is not. A small cell: six seconds of fire. Fire it near a hanging Moth and it will wake and come for you."],
	"hkm9": ["Flamethrower: short cone of fire that ignites enemies and leaves burning patches on the floor for 4 s. Burning pack hunters panic and run.",
		"Burning enemies take damage over time and run in panic. Keep it for tight corridors."],
	"gniew4": ["Grenade launcher: lobbed shell that explodes on contact or after a fuse, with a wide blast.",
		"Counts as a lure (+15 noise) and hurts the squad too. Do not fire at your own feet."],
	"sokol6": ["Seeker rifle: bullets bend toward a target inside a cone in front of you. Sloppy aim, steady hits.",
		"Good when you cannot line up the shot: it prefers Moths, Leapers and Eavesdroppers. The bullets are slow — lead moving targets."],
	"widmo1": ["Rail rifle: hold to charge, release for a hit that pierces everything in line. Enormous damage, enormous noise.",
		"Release before the charge completes and the shot is cancelled. The loudest weapon — plan the escape first."],
	"ciegno6": ["Silent bolt gun: one bolt per magazine, huge damage, almost no noise. The bolt sticks in the target and can be picked up.",
		"Aim for the head (×2) and hold higher on far targets — the bolt drops. The assassin's tool for an Eavesdropper. Tier 3 adds a tether line that yanks hit enemies toward you."],
	"maczeta": ["Machete: fast, silent, short reach. Kills a sleeping enemy — or one with its back to you — instantly.",
		"The first answer to any sleeper. No ammo, no noise."],
	"kilof": ["Pickaxe: slow swing, heavy damage and a long stun on hit. A little noise. It is the only tool that breaks cracked brick walls (and a grenade does too).",
		"Use it as the opener, then back off before the next swing. A bricked-up passage usually hides a stash — but breaking it is LOUD."],
}

## Opisy i wskazówki ekwipunku zużywalnego (karta GEAR w menu pauzy); liczby bierzemy z throwables.gd.
const GEAR_TEXT := {
	"frag": ["A fragmentation grenade on a short fuse. Everything within 4 m takes up to 90 damage — the squad included.",
		"Throw it at a pack from behind cover. It also breaks cracked brick walls. Loud."],
	"phos": ["Phosphorus: a field of fire on the floor for 15 s. It ignites whoever stands in it and enemies that are afraid of fire will not cross it.",
		"Use it to close a corridor behind you. Cutpurses, Blind Ones and Leapers stop at the flames; a Bullock walks through. It does not hurt the squad."],
	"smoke": ["A smoke cloud for 12 s. Enemies cannot see through it — but they still hear everything.",
		"Break line of sight to slip away or to reach a downed teammate. Stay quiet inside the cloud."],
	"mine": ["Placed at your feet, facing where you aim. Arms in 1 s, then the first awake enemy in its cone sets it off for 120 damage to everything in front of it. Sleepers and the squad do not trigger it.",
		"Put it in a corridor behind you and run. It does not fire at a sleeping enemy."],
	"charge": ["A demolition charge: 4 s fuse, 5 m blast, 150 damage. Breaks cracked brick walls and wounds a boss. The loudest item you carry, and it hurts the squad too.",
		"Place it, then get out of range. Plan the noise before you use it."],
	"medkit": ["Hold the item key for 5 s next to a wounded teammate (or yourself): +1 heart. You cannot move or shoot meanwhile, and taking damage cancels it.",
		"Use it in cover or behind smoke. The AI companion will use the squad's medkits on you too."],
	"cleankit": ["Hold the item key for 6 s: you strip and clean the gun in your hands, +40% condition, and a jam is cleared. You cannot move or shoot meanwhile, and taking damage cancels it.",
		"A dirty gun jams. One kit is issued every mission — use it in a quiet moment, not in the middle of a fight."],
	"defib": ["Hold the item key for 1.5 s: revives a downed teammate up to 10 m away in line of sight. One is issued every mission and it cannot be bought.",
		"Faster and safer than walking to a downed friend under fire. The AI companion uses it on you."],
	"scanner": ["The Owl motion scanner: for 10 s you see enemy silhouettes through walls within 15 m (red = awake). It emits 1 noise per second.",
		"Use it briefly before entering a dark room. A Stalker is not a threat on the scanner — it is just noise."],
}

## Karta PERKS w menu pauzy: wpis perku liczony świeżo (stan zależy od profilu: poziom, założone sloty).
static func perks() -> Array:
	var out: Array = []
	for id in Perks.ORDER:
		out.append(perk_entry(String(id)))
	return out

static func perk_entry(id: String) -> Dictionary:
	var d: Dictionary = Perks.PERKS[id]
	var at: int = Profile.equipped.find(id)
	var tl := func(s: String) -> String: return TranslationServer.translate(s)
	var status: String = tl.call("Equipped — slot %d") % (at + 1) if at >= 0 else (tl.call("Available") if Profile.is_unlocked(id) else tl.call("Locked — level %d") % int(d["level"]))
	return {"title": String(tl.call(String(d["name"]))).to_upper(), "tag": String(tl.call("Perk  ·  unlocks at level %d")) % int(d["level"]), "accent": d["color"],
		"portrait": {"type": "perk", "id": id}, "perk_id": id, "group": String(tl.call("LEVEL %d")) % int(d["level"]),
		"stats": [["Status", status], ["Your level", "%d" % Profile.level()], ["Slots open", TranslationServer.translate("%d of %d") % [Profile.slots(), Profile.SLOT_LEVELS.size()]]],
		"text": String(d["desc"]),
		"tip": _t("Equip perks at your locker in the safe room. The first slot opens at level %d, the second at level %d.") % [int(Profile.SLOT_LEVELS[0]), int(Profile.SLOT_LEVELS[1])]}

const GEAR_GROUPS := ["THROWN", "PLACED", "TOOLS"]

static func gear() -> Array:
	var out: Array = []
	for k in Throwables.ORDER:
		var d: Dictionary = Throwables.KINDS[k]
		var text: Array = GEAR_TEXT.get(k, ["", ""])
		var mode: String = {"throw": "Throwable", "place": "Placed", "use": "Tool"}[String(d["mode"])]
		var price := Throwables.price_of(k)
		var stats: Array = [["Type", mode], ["Carry", TranslationServer.translate("%d (issued %d)") % [int(d["max"]), int(d["issue"])]],
			["Price", TranslationServer.translate("%d scrap") % price if price > 0 else "issued only"]]
		match k:
			"frag":
				stats.append_array([["Fuse", "%.1f s" % float(d["fuse"])], ["Blast", TranslationServer.translate("%d m · %d dmg") % [int(float(d["radius"]) / PX_PER_M), int(d["damage"])]]])
			"phos":
				stats.append_array([["Fuse", "%.1f s" % float(d["fuse"])], ["Fire", TranslationServer.translate("%d s · 4.5 m wide") % int(d["field_life"])]])
			"smoke":
				stats.append_array([["Fuse", "%.1f s" % float(d["fuse"])], ["Cloud", "3.5 m · %d s" % int(d["cloud_life"])]])
			"mine":
				stats.append_array([["Arms in", "%.0f s" % float(d["arm"])], ["Cone", "±%d° · %d m" % [int(d["half_deg"]), int(float(d["range"]) / PX_PER_M)]], ["Damage", "%d" % int(d["damage"])]])
			"charge":
				stats.append_array([["Fuse", "%.0f s" % float(d["fuse"])], ["Blast", TranslationServer.translate("%d m · %d dmg") % [int(float(d["radius"]) / PX_PER_M), int(d["damage"])]]])
			"medkit":
				stats.append_array([["Use time", "%.0f s" % float(d["time"])], ["Heals", "+1 heart"]])
			"defib":
				stats.append_array([["Use time", "%.1f s" % float(d["time"])], ["Range", "%d m" % int(float(d["range"]) / PX_PER_M)]])
			"cleankit":
				stats.append_array([["Use time", "%.0f s" % float(d["time"])], ["Condition", "+%d%%" % int(d["restore"])]])
			"scanner":
				stats.append_array([["Duration", "%d s" % int(d["time"])], ["Range", "%d m" % int(float(d["range"]) / PX_PER_M)]])
		stats.append(["Noise", noise_text(k)])
		out.append({"title": String(d["name"]), "tag": TranslationServer.translate(String(d["full"])) + "  ·  " + TranslationServer.translate(mode), "accent": d["color"],
			"portrait": {"type": "item", "kind": k}, "stats": stats, "text": text[0], "tip": text[1],
			"group": {"throw": "THROWN", "place": "PLACED", "use": "TOOLS"}[String(d["mode"])]})
	var grouped: Array = []                                      # sort_custom nie jest stabilny — grupy składamy po kolei, kolejność w grupie z Throwables.ORDER
	for g in GEAR_GROUPS:
		grouped.append_array(out.filter(func(x: Dictionary) -> bool: return x["group"] == g))
	return grouped

## Hałas przedmiotu w punktach miernika Uwagi (0–100); skaner hałasuje co sekundę, wybuchy mają własną głośność.
static func noise_text(k: String) -> String:
	var d: Dictionary = Throwables.KINDS[k]
	if not d.has("noise"):
		return _t("explosion") if k in ["frag", "charge"] else "—"
	return (_t("+%d / s") if k == "scanner" else _t("+%d of 100")) % int(round(float(d["noise"])))

static func arsenal() -> Array:
	var out: Array = []
	for slot in [WeaponDef.Slot.PRIMARY, WeaponDef.Slot.SIDEARM, WeaponDef.Slot.MELEE]:
		for d: WeaponDef in Weapons.defs():
			if d.slot == slot:
				out.append(weapon_entry(d.id))
	return out

## Paski porównawcze karty broni: [etykieta, ułamek 0..1 względem najlepszej broni arsenału, napis, ułamek broni przy sobie z tego slotu
## albo −1]. `carried` — id broni lokalnego gracza w tym samym slocie (−1: brak albo to ta sama broń). Normalizacja po broniach fabrycznych.
static func weapon_bars(d: WeaponDef, carried: WeaponDef = null) -> Array:
	var top := {"dps": 0.0, "range": 0.0, "noise": 0.0, "mass": 0.0}
	for b: WeaponDef in Weapons.defs():
		top["dps"] = maxf(top["dps"], b.dps())
		top["range"] = maxf(top["range"], b.range_m())
		top["noise"] = maxf(top["noise"], b.n_max)
		top["mass"] = maxf(top["mass"], b.mass)
	var frac := func(v: float, m: float) -> float: return clampf(v / maxf(m, 0.001), 0.0, 1.0)
	var mark := func(f: Callable, m: float) -> float: return -1.0 if carried == null else frac.call(f.call(carried), m)
	var rows: Array = [
		["Firepower", frac.call(d.dps(), top["dps"]), _t("%d dmg/s") % int(round(d.dps())), mark.call(func(w: WeaponDef) -> float: return w.dps(), top["dps"])],
		["Range" if d.kind != WeaponDef.Kind.MELEE else "Reach", frac.call(d.range_m(), top["range"]), "%d m" % int(round(d.range_m())), mark.call(func(w: WeaponDef) -> float: return w.range_m(), top["range"])],
		["Loudness", frac.call(d.n_max, top["noise"]), _t("silent") if d.n_max <= 0.0 else "+%.1f" % d.n_max, mark.call(func(w: WeaponDef) -> float: return w.n_max, top["noise"])],
	]
	if d.mass > 0.0:
		rows.append(["Mass", frac.call(d.mass, top["mass"]), "%.2f kg" % d.mass, mark.call(func(w: WeaponDef) -> float: return w.mass, top["mass"])])
	return rows

## Wpis katalogu dla broni `id` — liczony świeżo (statystyki z częściami zamontowanymi przez TEGO gracza, części, dostęp),
## bo zmieniają się w kryjówce.
static func weapon_entry(id: int) -> Dictionary:
	var base: WeaponDef = Weapons.base_def(id)
	var d: WeaponDef = Weapons.def_build(id, Weapons.build_of(0, Profile.fit_code(id)))
	var notes: Array = WEAPON_TEXT.get(d.key, ["", ""])
	var tag := TranslationServer.translate(_slot_name(d))
	var tiers: Array = []
	var access := ""
	if not Scrap.is_unlocked(id):
		access = TranslationServer.translate("Locked — ") + Scrap.lock_text(id)
	var key := String(d.key)
	if not Parts.of(key).is_empty():
		if Scrap.is_unlocked(id):
			tag += TranslationServer.translate("  ·  PARTS %d / %d") % [Scrap.parts_owned(id), Parts.of(key).size()]
		for s in Parts.slots_of(key):
			for p in Parts.in_slot(key, String(s)):
				var pid := String(p["id"])
				var state := 0 if Profile.fitted(key, String(s)) == pid else (1 if Scrap.has_part(pid) else 2)      # 0 zamontowana, 1 odblokowana, 2 do kupienia
				tiers.append({"head": "%s  %s" % [TranslationServer.translate(Parts.SLOT_NAMES[s]).to_upper(), TranslationServer.translate(p["name"])],
					"desc": TranslationServer.translate(p["desc"]), "cost": Scrap.part_cost(pid), "state": state})
	return {"title": base.name, "tag": tag, "accent": base.tracer_color, "portrait": {"type": "gun", "row": base.gun_row, "color": base.tracer_color},
		"stats": _weapon_stats(d), "text": notes[0], "tip": notes[1], "weapon_id": id, "tiers": tiers, "access": access,
		"group": {WeaponDef.Slot.PRIMARY: "PRIMARY WEAPONS", WeaponDef.Slot.SIDEARM: "SIDEARMS"}.get(d.slot, "MELEE")}

## Szablon tłumaczony PRZED podstawieniem liczb — gotowy napis („120 blast”) nie trafiłby w klucz ui.csv.
static func _t(s: String) -> String:
	return TranslationServer.translate(s)

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
		dmg = _t("%d blast") % int(d.blast_damage)
	elif d.pellets > 1:
		dmg = _t("%d × %d pellets") % [int(d.damage), d.pellets]
	elif d.is_continuous():
		dmg = _t("%d / tick") % int(d.damage)
	var rate := "%d / min" % int(round(d.rpm()))
	if d.is_continuous():
		rate = "continuous"
	elif d.kind == WeaponDef.Kind.RAIL:
		rate = _t("%.1f s charge") % d.charge_time
	var noise := _t("+%.1f per shot") % d.n_min if is_equal_approx(d.n_min, d.n_max) else _t("+%.1f → +%.1f per shot") % [d.n_min, d.n_max]      # punkty miernika Uwagi (0–100)
	var melee := d.kind == WeaponDef.Kind.MELEE                       # broń biała: tempo ciosów i zasięg ręki, nie szybkostrzelność
	var out: Array = [["Damage", dmg], ["Swing rate" if melee else "Fire rate", rate], ["Reach" if melee else "Range", "%d m" % int(round(d.range_m()))]]
	if d.uses_ammo():
		out.append(["Magazine", _t("%d · reserve ∞") % d.mag if d.infinite else _t("%d · reserve %d") % [d.mag, d.reserve_start]])
		out.append(["Reload", "%.1f s" % d.full_reload_time() if not d.reload_per_round else _t("%.2f s / round") % d.reload_time])
	out.append(["Noise", noise if d.n_max > 0.0 else "silent"])
	if d.kind == WeaponDef.Kind.MELEE:
		out.append(["DPS", "%d" % int(round(d.dps()))])
	if d.mass > 0.0:
		out.append(["Mass", "%.2f kg" % d.mass])                       # masa z częściami (W5): suma ekwipunku zmienia bieg
	return out
