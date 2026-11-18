extends SceneTree
## Test klas rzadkości znajdziek (DIG_LOOT_PLAN.md K6, pickup.gd `rarity`): tabela klas (zwykła / rzadka / fabularna), próg złomu, broń
## porzucona i na stojaku zwykła, mocniejsza poświata rzadkiej, pulsowanie rzadkiej i oddech fabularnej przy stałej zwykłej, akcent przy
## lądowaniu tylko dla rzadkiej i fabularnej, która wypadła w trakcie gry (węzeł „Item…”), nie dla leżącej od startu na mapie; dźwięki
## `loot_rare` i `loot_story` w banku.
##   godot --headless --path prototype -s tools/test_loot_rarity.gd     → ostatni wiersz: [LOOT-RARITY] PASS / FAIL

var _fails := 0
var _root: Node2D


func _check(name: String, ok: bool) -> void:
	print("[LOOT-RARITY] %s  %s" % ["PASS" if ok else "FAIL", name])
	if not ok:
		_fails += 1


func _initialize() -> void:
	_run.call_deferred()


func _make(P: GDScript, n: String, k: String, r: int, rack := false) -> Node2D:
	var it: Node2D = P.new()
	it.name = n
	it.kind = k
	it.rounds = r
	it.static_display = rack
	_root.add_child(it)
	return it


## Dopiero po starcie: pickup.gd używa autoloadów (Audio, Scrap), których przy kompilacji skryptu `-s` jeszcze nie ma (stąd load).
func _run() -> void:
	var P: GDScript = load("res://scripts/pickup.gd")
	var Manifest: GDScript = load("res://scripts/audio_manifest.gd")
	_root = Node2D.new()
	root.add_child(_root)
	var C := 0
	var R := 1
	var S := 2
	var table := [["health", 0, C], ["ammo", 30, C], ["cache", 0, C], ["mag", 12, C], ["battery", 0, C], ["flares", 2, C], ["supply", 0, C],
		["scrap", 1, C], ["scrap", 9, C], ["scrap", 10, R], ["scrap", 40, R], ["part", 0, R], ["power", 40, R], ["stash", 20, R],
		["weapon", 30, R], ["weapon", 0, C], ["tape", 0, S], ["tag", 0, S]]
	var bad: Array = []
	for e in table:
		if int(P.rarity_of(String(e[0]), int(e[1]))) != int(e[2]):
			bad.append("%s/%d" % [e[0], e[1]])
	_check("tabela klas: zwykłe (apteczka, amunicja, bateria, złom < %d…), rzadkie (część, moc, skrytka, nowa broń, złom ≥ %d), fabularne (taśma, nieśmiertelnik) %s"
		% [P.RARE_SCRAP, P.RARE_SCRAP, str(bad)], bad.is_empty())

	var common := _make(P, "Item1", "scrap", 3)
	var rare := _make(P, "Item2", "scrap", 15)
	var story := _make(P, "Item3", "tape", 0)
	var map_rare := _make(P, "MapPower0", "power", 40)
	var dropped := _make(P, "Item4", "weapon", 0)
	var rack := _make(P, "Item5", "weapon", 30, true)
	_check("klasy węzłów: złom 3 zwykły, pakunek 15 rzadki, taśma fabularna, porzucona broń i broń na stojaku zwykłe",
		common.rarity == C and rare.rarity == R and story.rarity == S and dropped.rarity == C and rack.rarity == C)
	_check("rzadka sięga poświatą dalej niż zwykła tego samego rodzaju (%.0f vs %.0f px), fabularna jak dotąd" % [rare._glow.range_px, common._glow.range_px],
		rare._glow.range_px > common._glow.range_px * 1.2 and is_equal_approx(story._glow.range_px, common._glow.range_px))
	var st := {}                                               # klasa → [min, max, suma, zmian kierunku]
	for pk in [common, rare, story]:
		st[pk] = [1e9, 0.0, 0.0]
	for i in 160:                                              # 8 s
		for pk in [common, rare, story]:
			pk._physics_process(0.05)
			var e: float = pk._glow.energy
			st[pk] = [minf(st[pk][0], e), maxf(st[pk][1], e), float(st[pk][2]) + e / 160.0]
	_check("poświata: rzadka jaśniejsza (śr. %.2f vs %.2f) i mocniej pulsuje, fabularna oddycha płyciej niż zwykła (%.2f vs %.2f)"
		% [st[rare][2], st[common][2], st[story][1] - st[story][0], st[common][1] - st[common][0]],
		st[rare][2] > st[common][2] * 1.5 and st[rare][1] - st[rare][0] > st[common][1] - st[common][0]
		and st[story][1] - st[story][0] > 0.1 and st[story][1] - st[story][0] < st[common][1] - st[common][0])

	for pk in [common, rare, story, map_rare, dropped]:
		pk._rarity_accent()
	_check("akcent przy lądowaniu: rzadka i fabularna z gry tak; zwykła, porzucona broń i rzadka leżąca od startu na mapie — nie",
		rare.accents == 1 and story.accents == 1 and common.accents == 0 and map_rare.accents == 0 and dropped.accents == 0)
	var paths: Dictionary = Manifest.PATHS
	_check("dźwięki akcentu w banku (loot_rare, loot_story)", paths.has("loot_rare") and paths.has("loot_story")
		and ResourceLoader.exists(String(paths["loot_rare"])) and ResourceLoader.exists(String(paths["loot_story"])))
	print("[LOOT-RARITY] %s" % ("PASS" if _fails == 0 else "FAIL (%d)" % _fails))
	quit(1 if _fails > 0 else 0)
