extends SceneTree
## Test muzyki adaptacyjnej (MUSIC_PLAN.md E0, scripts/music_director.gd + AudioDirector.music_set_layer):
## wynik zagrożenia T (sam hałas nie włącza muzyki, świadomy wróg w zasięgu tak, dalszy słabiej, poza zasięgiem wcale, elita mocniej,
## boss, Stalker na łowach wg odległości, świeże trafienie), stany AI → świadomość, warstwy z histerezą, cisza poza misją i w kryjówce,
## „oddech” w długiej ciszy i przerwanie go zagrożeniem, prawdziwy wróg ze sceny, a w AudioDirector: cisza nie uruchamia stemów,
## warstwa -1 po zejściu wycisza wszystkie stemy.
##   godot --headless --path prototype -s tools/test_music.gd     → ostatni wiersz: PASS / FAIL

var _fails := 0
var MD: GDScript                ## music_director.gd odwołuje się do autoloadu NoiseMgr — ładowany po pierwszej klatce, nie preload


## Udawany gracz: pozycja i życie.
class FakePlayer extends Node2D:
	var hp := 3


func _check(name: String, ok: bool) -> void:
	print("[MUSIC] %s  %s" % ["PASS" if ok else "FAIL", name])
	if not ok:
		_fails += 1


func _enemy(pos: Vector2, aware: int, elite := false) -> Dictionary:
	return {"pos": pos, "what": "enemy", "aware": aware, "elite": elite}


func _initialize() -> void:
	await process_frame                                  # autoloady (Audio, NoiseMgr) są w drzewie od pierwszej klatki
	MD = load("res://scripts/music_director.gd")
	if MD == null or not MD.can_instantiate():
		print("FAIL: music_director.gd się nie kompiluje")
		quit(1)
		return
	var noise_mgr: Node = root.get_node("NoiseMgr")
	var me := Vector2(1000, 500)

	# --- wynik zagrożenia
	_check("cisza: bez zagrożeń T = 0", MD.score(me, [], 0.0, false, 0.0) == 0.0)
	var t_noise: float = MD.score(me, [], 100.0, false, 0.0)
	_check("sam hałas (Uwaga 100) nie przekracza progu kontaktu (T %.0f < %.0f)" % [t_noise, MD.UP[0]], t_noise < float(MD.UP[0]))
	var t_one: float = MD.score(me, [_enemy(me + Vector2(40, 0), 2)], 0.0, false, 0.0)
	_check("świadomy wróg tuż obok → kontakt (T %.0f)" % t_one, MD.pick_layer(t_one, -1) == 1)
	var t_two: float = MD.score(me, [_enemy(me + Vector2(40, 0), 2), _enemy(me - Vector2(60, 0), 2)], 0.0, false, 0.0)
	_check("dwóch świadomych blisko → walka (T %.0f)" % t_two, MD.pick_layer(t_two, -1) == 2)
	var t_far: float = MD.score(me, [_enemy(me + Vector2(MD.RANGE * 0.9, 0), 2)], 0.0, false, 0.0)
	_check("dalszy świadomy liczy się słabiej (%.0f < %.0f)" % [t_far, t_one], t_far < t_one and t_far > 0.0)
	_check("wróg poza zasięgiem nie gra", MD.score(me, [_enemy(me + Vector2(MD.RANGE + 10.0, 0), 2)], 0.0, false, 0.0) == 0.0)
	_check("śpiący wróg obok nie gra", MD.score(me, [_enemy(me + Vector2(20, 0), 0)], 0.0, false, 0.0) == 0.0)
	var t_contact: float = MD.score(me, [_enemy(me + Vector2(40, 0), 1)], 0.0, false, 0.0)
	_check("wróg sprawdzający ślad: słabiej niż świadomy, sam nie włącza muzyki", t_contact > 0.0 and t_contact < t_one and MD.pick_layer(t_contact, -1) == -1)
	_check("elita mocniej niż zwykły", MD.score(me, [_enemy(me + Vector2(40, 0), 2, true)], 0.0, false, 0.0) > t_one)
	var t_boss: float = MD.score(me, [{"pos": me + Vector2(300, 0), "what": "boss", "aware": 2, "elite": true}], 0.0, false, 0.0)
	_check("obudzony boss w zasięgu → pościg (T %.0f)" % t_boss, MD.pick_layer(t_boss, -1) == 3)
	var st_near := [{"pos": me + Vector2(60, 0), "what": "stalker", "aware": 0, "elite": false}]
	var st_far := [{"pos": me + Vector2(5000, 0), "what": "stalker", "aware": 0, "elite": false}]
	_check("Stalker śpi → nic", MD.score(me, st_near, 0.0, false, 0.0) == 0.0)
	var t_st_near: float = MD.score(me, st_near, 0.0, true, 0.0)
	var t_st_far: float = MD.score(me, st_far, 0.0, true, 0.0)
	_check("Stalker na łowach: blisko walka, daleko tylko kontakt (%.0f / %.0f)" % [t_st_near, t_st_far],
		MD.pick_layer(t_st_near, -1) == 2 and MD.pick_layer(t_st_far, -1) == 1)
	var t_hit: float = MD.score(me, [], 0.0, false, 1.0)
	_check("świeże trafienie → kontakt (T %.0f)" % t_hit, MD.pick_layer(t_hit, -1) == 1)
	_check("T najwyżej 100", MD.score(me, [_enemy(me, 2, true), _enemy(me, 2, true), _enemy(me, 2, true), _enemy(me, 2, true)], 100.0, true, 1.0) == 100.0)

	# --- stany AI
	var E: GDScript = load("res://scripts/enemy.gd")
	_check("goni / zamach / skok / zauważył / krzyk / specjalny = świadomy",
		[E.Ai.CHASE, E.Ai.WINDUP, E.Ai.LUNGE, E.Ai.ALERT, E.Ai.SCREAM, E.Ai.SPECIAL].all(func(a: int) -> bool: return MD.awareness(a) == 2))
	_check("sprawdza ślad / szuka = kontakt", MD.awareness(E.Ai.INVESTIGATE) == 1 and MD.awareness(E.Ai.SEARCH) == 1)
	_check("śpi / wisi / słucha / wraca / panika = nic",
		[E.Ai.SLEEP, E.Ai.HANG, E.Ai.LISTEN, E.Ai.RETURN, E.Ai.PANIC, E.Ai.DEAD].all(func(a: int) -> bool: return MD.awareness(a) == 0))

	# --- histereza
	_check("wejście w górę od razu", MD.pick_layer(40.0, 0) == 2 and MD.pick_layer(70.0, -1) == 3)
	_check("tuż pod progiem walki zostaje walka", MD.pick_layer(MD.UP[1] - 1.0, 2) == 2)
	_check("wyraźnie pod progiem schodzi o warstwę", MD.pick_layer(MD.DOWN[1] - 1.0, 2) == 1)
	_check("z pościgu do ciszy w jednym kroku przy T = 0", MD.pick_layer(0.0, 3) == -1)

	# --- dyrektor: cisza poza misją i w kryjówce, oddech, przerwanie
	var p := FakePlayer.new()
	p.position = me
	root.add_child(p)
	var md = MD.new(7)
	_check("poza misją (menu) cisza", md.update(0.1, p, false) == -1)
	noise_mgr.safe_zone = true
	_check("w kryjówce cisza (radio to E5)", md.update(0.1, p, true) == -1)
	noise_mgr.safe_zone = false
	var breath_at := -1.0
	var breath_end := -1.0
	var t := 0.0
	while t < MD.BREATH_EVERY.y + MD.BREATH_LEN.y + 5.0:
		var l: int = md.update(0.5, p, true)
		if l == 0 and breath_at < 0.0:
			breath_at = t
		if l == -1 and breath_at >= 0.0 and breath_end < 0.0:
			breath_end = t
		t += 0.5
	_check("oddech w długiej ciszy po %.0f s, trwa %.0f s" % [breath_at, breath_end - breath_at],
		breath_at >= MD.BREATH_EVERY.x - 1.0 and breath_at <= MD.BREATH_EVERY.y + 1.0
		and breath_end - breath_at >= MD.BREATH_LEN.x - 1.0 and breath_end - breath_at <= MD.BREATH_LEN.y + 1.0)
	p.hp = 2
	var hit_t := 0.0
	while hit_t < 3.0 and md.update(0.1, p, true) != 1:
		hit_t += 0.1
	_check("trafienie gracza → kontakt po %.1f s (wygładzenie)" % hit_t, md.layer == 1 and hit_t > 0.2)
	var calm := 0.0
	while calm < 40.0 and md.update(0.1, p, true) != -1:
		calm += 0.1
	_check("trafienie wygasa → cisza dopiero po %.0f s (≥ MIN_ON)" % calm, md.layer == -1 and calm >= MD.MIN_ON - 1.0)

	# --- płynność (MUSIC_PLAN.md E0, odsłuch 1.7.578: 28 wejść w 6 min, mediana 3,6 s)
	var sm = MD.new(3)
	for i in 5:
		sm.step(0.1, 22.0)                               # mignięcie „zauważył” przez 0,5 s
	for i in 20:
		sm.step(0.1, 0.0)
	_check("mignięcie zauważył przez 0,5 s nie włącza muzyki (T %.0f)" % sm.threat, sm.layer == -1)
	sm = MD.new(3)
	var on_t := 0.0
	while sm.layer < 1 and on_t < 5.0:
		sm.step(0.1, 22.0)
		on_t += 0.1
	var gone := 0.0
	while sm.layer >= 0 and gone < 60.0:
		sm.step(0.1, 0.0)
		gone += 0.1
	_check("wróg świadomy: wejście po %.1f s, po zniknięciu muzyka gra jeszcze %.0f s (≥ MIN_ON)" % [on_t, gone], on_t >= 0.5 and on_t <= 3.0 and gone + on_t >= MD.MIN_ON)
	sm = MD.new(3)
	for i in 100:
		sm.step(0.1, 40.0)
	var changes := 0
	var last: int = sm.layer
	for i in 200:                                        # 20 s: T skacze 40 ↔ 20 co 0,5 s
		sm.step(0.1, 40.0 if (i / 5) % 2 == 0 else 20.0)
		if sm.layer != last:
			changes += 1
			last = sm.layer
	_check("migające zagrożenie 40 ↔ 20 co 0,5 s: zmian warstwy %d (≤ 2)" % changes, changes <= 2)
	sm = MD.new(3)
	for i in 100:
		sm.step(0.1, 22.0)
	for i in 600:
		sm.step(0.1, MD.NOISE_MAX)
	_check("sam hałas (najwyżej NOISE_MAX) nie podtrzymuje muzyki", sm.layer == -1 and MD.NOISE_MAX < float(MD.DOWN[0]))

	# --- prawdziwy wróg ze sceny
	var foe: Node2D = load("res://scenes/enemy.tscn").instantiate()
	foe.position = me + Vector2(50, 0)
	root.add_child(foe)
	await process_frame
	foe._ai = E.Ai.CHASE
	var found: Array = MD.gather(self)
	_check("wróg ze sceny w pogoni: świadomy (%s)" % str(found), found.size() == 1 and int(found[0]["aware"]) == 2)
	foe._ai = E.Ai.SLEEP
	_check("wróg ze sceny śpi: nie gra", MD.gather(self).is_empty())
	foe._ai = E.Ai.CHASE
	foe.alive = false
	_check("martwy wróg nie gra", MD.gather(self).is_empty())
	foe.queue_free()
	p.queue_free()

	# --- AudioDirector: warstwa -1
	var audio: Node = root.get_node("Audio")
	audio.set_enabled(true)
	audio.music_set_layer(-1)
	_check("cisza nie uruchamia stemów", not audio._music_started)
	audio.music_set_layer(1)
	_check("kontakt uruchamia stemy 0–1", audio._music_started and audio._stem_target[0] == 1.0 and audio._stem_target[1] == 1.0 and audio._stem_target[2] == 0.0)
	audio.music_set_layer(-1)
	_check("zejście do ciszy zaplanowane z opóźnieniem", audio._drop_to == -1 and audio._drop_at > audio._clock)
	audio._clock = audio._drop_at + 0.01
	audio._update_music(0.0)
	_check("po opóźnieniu wszystkie stemy gasną, stemy grają dalej po cichu (rytm)",
		audio._music_layer == -1 and audio._drop_to == audio.NO_DROP and audio._stem_target.all(func(v: float) -> bool: return v == 0.0) and audio._music_started)
	audio.music_set_layer(2)
	_check("powrót z ciszy od razu do walki", audio._music_layer == 2 and audio._stem_target[2] == 1.0)
	_check("krzywa przejścia w dB: 0 → cisza, połowa → %.0f dB, koniec → 0 dB" % linear_to_db(audio._fade_gain(0.5)),
		audio._fade_gain(0.0) == 0.0 and absf(linear_to_db(audio._fade_gain(0.5)) - audio.MUSIC_FADE_FLOOR_DB * 0.5) < 0.1 and absf(audio._fade_gain(1.0) - 1.0) < 0.001)
	var blend: Array = load("res://scripts/audio_manifest.gd").MUSIC_BLEND
	_check("wejście stemów ≥ 1,5 s, wyciszanie ≥ 5 s (było 0,35–1,6 s i 1,2–6 s)",
		blend.all(func(v: float) -> bool: return v >= 1.5) and audio.MUSIC_FADE_OUT.all(func(v: float) -> bool: return v >= 5.0))
	audio.shutdown()

	print("%s (test_music: %d błędów)" % ["PASS" if _fails == 0 else "FAIL", _fails])
	quit(0 if _fails == 0 else 1)
