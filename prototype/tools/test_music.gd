extends SceneTree
## Test muzyki adaptacyjnej (MUSIC_PLAN.md E0, scripts/music_director.gd + AudioDirector.music_set_layer):
## wynik zagrożenia T (sam hałas nie włącza muzyki, świadomy wróg w zasięgu tak, dalszy słabiej, poza zasięgiem wcale, elita mocniej,
## boss, Stalker na łowach wg odległości, świeże trafienie), stany AI → świadomość, warstwy z histerezą, cisza poza misją i w kryjówce,
## „oddech” w długiej ciszy i przerwanie go zagrożeniem, prawdziwy wróg ze sceny, a w AudioDirector: cisza nie uruchamia stemów,
## warstwa -1 po zejściu wycisza wszystkie stemy; E1: motyw Stalkera wg odległości (tylko gdy poluje), sygnały elity i hordy
## (raz, z odstępem), stan życia (ostatnie serce, leży: muzyka ciszej i za filtrem, serce), muzyka ustępuje głosowi Stalkera.
## E4: sceny bossa (wejście i histereza zasięgu, faza, śmierć → odwrót ze zwycięstwem, odwrót z misji), warstwy pod sceną,
## w AudioDirector warstwy sceny na takcie, uderzenie fazy na beat, kadencja śmierci na takcie z wycięciem bossa i odwrotem
## po ogonie, zwykłe wyciszenie bez zwycięstwa, paleta czeka na ciszę scen, pliki scen na siatce (odwrót = dwie pętle).
##   godot --headless --path prototype -s tools/test_music.gd     → ostatni wiersz: PASS / FAIL

var _fails := 0
var MD: GDScript                ## music_director.gd odwołuje się do autoloadu NoiseMgr — ładowany po pierwszej klatce, nie preload


## Udawany gracz: pozycja i życie.
class FakePlayer extends Node2D:
	var hp := 3
	var dead := false


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
	# przebieg z odsłuchu 1.7.580 (dziennik sesji): T walki krąży wokół progu pościgu — surowo 85 przez 7 s, 40 przez 9 s
	sm = MD.new(3)
	var chase_in := 0
	var chase_len := 0.0
	var chase_min := 1e9
	var flips := 0
	last = -1
	for i in 3000:
		sm.step(0.1, 85.0 if (i % 160) < 70 else 40.0)
		if sm.layer == 3:
			chase_len += 0.1
		if sm.layer != last:
			flips += 1
			if sm.layer == 3:
				chase_in += 1
			elif last == 3:
				chase_min = minf(chase_min, chase_len)
			if sm.layer != 3:
				chase_len = 0.0
			last = sm.layer
	_check("T krąży wokół progu pościgu przez 5 min: %d wejść pościgu (było ~14), najkrótszy %.0f s, %d zmian warstwy" % [chase_in, chase_min, flips],
		chase_in <= 6 and chase_min >= MD.CHASE_MIN_ON - 0.01 and flips <= 13)
	var hc = MD.new(4)
	hc._base = 2
	var hme := Vector2.ZERO
	var harr: Array = []
	for i in MD.HORDE_N:
		harr.append({"pos": Vector2(100 + i * 10, 0), "what": "enemy", "aware": 2, "elite": false, "id": 900 + i, "scream": false})
	hc.cues(0.1, hme, harr)
	_check("w trwającej walce horda nie gra drugi raz", hc.cue == "")

	# --- E1: motyw Stalkera
	var mo = MD.new(5)
	var st := func(dist: float) -> Array: return [{"pos": me + Vector2(dist, 0), "what": "stalker", "aware": 0, "elite": false}]
	mo.motif(me, st.call(300.0), false)
	_check("Stalker śpi: motywu nie ma", mo.motif_far == 0.0 and mo.motif_near == 0.0)
	mo.motif(me, st.call(3000.0), true)
	_check("Stalker poluje daleko: cichy motyw daleki (%.2f), bez bliskiego" % mo.motif_far, absf(mo.motif_far - MD.MOTIF_FAR_MIN) < 0.01 and mo.motif_near == 0.0)
	mo.motif(me, st.call(500.0), true)
	var mid_far: float = mo.motif_far
	var mid_near: float = mo.motif_near
	mo.motif(me, st.call(150.0), true)
	_check("bliżej motyw bliski rośnie, daleki ustępuje (500 px: %.2f / %.2f, 150 px: %.2f / %.2f)" % [mid_far, mid_near, mo.motif_far, mo.motif_near],
		mid_near > 0.0 and mid_near < 1.0 and mo.motif_near == 1.0 and mo.motif_far < mid_far)

	# --- E1: sygnały elity i hordy
	var cu = MD.new(5)
	var foe_at := func(id: int, dx: float, elite: bool, scream := false) -> Dictionary:
		return {"pos": me + Vector2(dx, 0), "what": "enemy", "aware": 2, "elite": elite, "id": id, "scream": scream}
	cu.cues(0.1, me, [foe_at.call(1, 100.0, true)])
	_check("elita zauważyła → sygnał elity", cu.cue == "cue_elite")
	cu.cues(0.1, me, [foe_at.call(1, 100.0, true)])
	_check("ta sama elita w następnej klatce → nic", cu.cue == "")
	cu.cues(0.1, me, [])
	for i in 300:
		cu.cues(0.1, me, [])
	cu.cues(0.1, me, [foe_at.call(1, 100.0, true)])
	_check("ta sama elita znów świadoma po przerwie → bez drugiego sygnału", cu.cue == "")
	cu.cues(0.1, me, [foe_at.call(2, MD.CUE_RANGE + 50.0, true)])
	_check("elita poza zasięgiem sygnałów → nic", cu.cue == "")
	var hd = MD.new(5)
	var pack: Array = []
	var got := ""
	for i in MD.HORDE_N:
		pack.append(foe_at.call(10 + i, 80.0 + i * 30.0, false))
		hd.cues(0.3, me, pack)
		if hd.cue != "":
			got = hd.cue
	_check("%d nowych świadomych w %.1f s → sygnał hordy" % [MD.HORDE_N, 0.3 * MD.HORDE_N], got == "cue_horde")
	pack.append(foe_at.call(99, 60.0, false, true))
	hd.cues(0.1, me, pack)
	_check("krzyk w trakcie odstępu hordy → bez drugiego sygnału", hd.cue == "")
	var sc = MD.new(5)
	sc.cues(0.1, me, [foe_at.call(50, 200.0, false, true)])
	_check("krzyk alarmu blisko → sygnał hordy", sc.cue == "cue_horde")
	var slow = MD.new(5)
	var slow_got := ""
	for i in MD.HORDE_N:
		var arr: Array = []
		for j in i + 1:
			arr.append(foe_at.call(70 + j, 100.0, false))
		slow.cues(MD.HORDE_WINDOW / 2.0 + 0.1, me, arr)
		slow_got += slow.cue
	_check("wrogowie zauważają powoli (co %.1f s) → to nie horda" % (MD.HORDE_WINDOW / 2.0), slow_got == "")

	# --- E1: stan życia
	var hp_p := FakePlayer.new()
	hp_p.position = me
	root.add_child(hp_p)
	var hm = MD.new(5)
	hm.update(0.1, hp_p, true)
	var h0: int = hm.health
	hp_p.hp = 1
	hm.update(0.1, hp_p, true)
	var h1: int = hm.health
	hp_p.dead = true
	hm.update(0.1, hp_p, true)
	_check("stan życia: zdrowy %d, ostatnie serce %d, leży %d" % [h0, h1, hm.health], h0 == 0 and h1 == 1 and hm.health == 2)
	hm.update(0.1, hp_p, false)
	_check("poza misją stan życia i motyw od nowa", hm.health == 0 and hm.motif_far == 0.0 and hm.cue == "")
	hp_p.queue_free()

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
	# --- AudioDirector E1
	audio.shutdown()
	audio.set_enabled(true)
	audio.music_set_motif(0.0, 0.0)
	_check("motyw zero nie uruchamia muzyki", not audio._music_started)
	audio.music_set_motif(0.75, 0.0)
	_check("motyw uruchamia stemy po cichu, warstwy zostają w ciszy", audio._music_started and audio._music_layer == -1
		and audio._stem_target.all(func(v: float) -> bool: return v == 0.0) and audio._motif_target[0] == 0.75 and audio._motif[0].playing)
	for i in 40:
		audio._update_music(0.1)
	_check("motyw daleki dochodzi do celu (%.2f) w %.0f s" % [audio._motif_x[0], audio.MOTIF_FADE_IN], absf(audio._motif_x[0] - 0.75) < 0.01)
	audio.music_set_motif(0.0, 0.0)
	audio._update_music(1.0)
	_check("motyw gaśnie powoli (po 1 s %.2f)" % audio._motif_x[0], audio._motif_x[0] > 0.5)
	audio.music_set_health(1)
	_check("ostatnie serce: bije serce", audio.loop_playing("heart_slow_loop"))
	for i in 30:
		audio._update_deafness(0.1)
	_check("ostatnie serce: muzyka ciszej (%.1f dB) i za filtrem (%.0f Hz)" % [audio._health_db, audio._music_lp_hz],
		absf(audio._health_db - audio.HEALTH_DB[1]) < 0.5 and audio._music_lp_hz < 2000.0)
	audio.music_set_health(2)
	for i in 30:
		audio._update_deafness(0.1)
	_check("leży: ciszej i głębiej za filtrem (%.1f dB, %.0f Hz)" % [audio._health_db, audio._music_lp_hz], audio._health_db < -10.0 and audio._music_lp_hz < 900.0)
	audio.music_set_health(0)
	_check("zdrowy: serce milknie", not audio.loop_playing("heart_slow_loop"))
	audio._duck_db = 0.0
	audio.music_cue("cue_elite")
	_check("sygnał gra na muzyce, a muzyka ustępuje (%.0f dB)" % audio._duck_db, audio._duck_db <= -6.0)
	audio._duck_db = 0.0
	audio.play("ui_click", audio.BUS_STALKER, -20.0)
	audio._duck_under_stalker()
	_check("muzyka ustępuje głosowi Stalkera (%.0f dB)" % audio._duck_db, audio._duck_db <= audio.STALKER_DUCK_DB)
	var man: GDScript = load("res://scripts/audio_manifest.gd")
	_check("w manifeście motyw (pętle) i sygnały", ["mus_stalker_far", "mus_stalker_near", "cue_elite", "cue_horde"].all(func(k: String) -> bool: return man.PATHS.has(k))
		and man.LOOPS.has("mus_stalker_far") and man.LOOPS.has("mus_stalker_near"))
	# --- E2: segmenty, kadencje, palety
	var segs: Dictionary = man.MUSIC_SEGMENTS
	var seg_ok := true
	for pal in segs:
		for lay in segs[pal]:
			for k in lay:
				seg_ok = seg_ok and man.PATHS.has(k) and man.LOOPS.has(k)
	_check("palety: każdy wariant w manifeście i zapętlony", seg_ok and segs.has("default") and (segs["default"] as Array).size() == man.MUSIC_STEMS.size())
	_check("domyślna paleta: każda warstwa ma ≥ 2 warianty, pierwszy = stem bazowy",
		range(man.MUSIC_STEMS.size()).all(func(i: int) -> bool: return (segs["default"][i] as Array).size() >= 2 and segs["default"][i][0] == man.MUSIC_STEMS[i]))
	_check("kadencje walki i pościgu w manifeście, jednorazowe", ["mus_combat_end", "mus_chase_end"].all(func(k: String) -> bool: return man.PATHS.has(k) and not man.LOOPS.has(k))
		and man.MUSIC_CADENCES[2] == "mus_combat_end" and man.MUSIC_CADENCES[3] == "mus_chase_end" and man.MUSIC_CADENCES[0] == "")
	_check("paleta wg mapy: z1_b1 → własna, z1_m1 → default, pusta → default",
		audio.palette_for("z1_b1") == "z1_b1" and audio.palette_for("z1_m1") == "default" and audio.palette_for("") == "default")
	audio.set_enabled(true)
	audio.music_set_layer(2)
	var all_play := true
	for i in audio._seg.size():
		for v in audio._seg_n[i]:
			all_play = all_play and audio._seg[i][v].playing
	_check("start: wszystkie warianty grają razem (%s)" % str(audio._seg_n), all_play and audio._seg_n == [2, 2, 2, 2])
	audio._stem_gain[2] = 1.0
	audio._health_db = 0.0
	audio._duck_db = 0.0
	audio._update_music(0.0)
	_check("słychać tylko pierwszy wariant (%.0f / %.0f dB)" % [audio._seg[2][0].volume_db, audio._seg[2][1].volume_db],
		audio._seg[2][0].volume_db > -3.0 and audio._seg[2][1].volume_db <= -79.0)
	var loop_s: float = man.MUSIC_LOOP_SEC
	audio._seg_rng.seed = 87
	audio._sec_left = 2
	audio._seg_next_ok = 0.0
	audio._update_segments(audio._bar_len() * 4.0 - 0.3)
	_check("granica frazy w środku pętli: sekcja się nie zmienia", audio._seg_cur.all(func(v: int) -> bool: return v == 0) and audio._sec_left == 2)
	audio._update_segments(loop_s - 0.3)
	_check("pierwsza granica pętli: sekcja trwa dalej (przydział 2 pętle)", audio._seg_cur.all(func(v: int) -> bool: return v == 0) and audio._sec_left == 1)
	audio._clock += 1.5
	audio._update_segments(loop_s - 0.3)
	_check("koniec przydziału: cała muzyka naraz w sekcji B (%s)" % str(audio._seg_cur), audio._seg_cur.all(func(v: int) -> bool: return v == 1) and audio._seg_prev.all(func(v: int) -> bool: return v == 0))
	var wcur: float = audio._seg_weight(2, 1)
	_check("przenikanie w połowie (%.2f) kończy się na początku pętli" % wcur, wcur > 0.4 and wcur < 0.6 and absf(wcur + audio._seg_weight(2, 0) - 1.0) < 0.001)
	var cur_before: Array = audio._seg_cur.duplicate()
	audio._update_segments(loop_s - 0.1)
	_check("jedna decyzja na granicę", audio._seg_cur == cur_before)
	audio._clock += 0.31
	audio._update_segments(0.01)
	_check("po granicy gra sama sekcja B", audio._seg_prev.all(func(v: int) -> bool: return v == -1) and audio._seg_weight(2, 1) == 1.0 and audio._seg_weight(2, 0) == 0.0)
	# 8 minut: sekcje się zmieniają, ale nigdy częściej niż co 2 pętle (40 s), i zawsze wszystkie warstwy razem
	var sec_changes := 0
	var min_gap := 1e9
	var since := 0.0
	var together := true
	var prev_cur: Array = audio._seg_cur.duplicate()
	for k in int(480.0 / loop_s):
		audio._clock += loop_s
		since += loop_s
		audio._update_segments(loop_s - 0.3)
		audio._clock += 0.5
		audio._update_segments(0.2)
		together = together and audio._seg_cur.all(func(v: int) -> bool: return v == audio._seg_cur[0])
		if audio._seg_cur != prev_cur:
			sec_changes += 1
			min_gap = minf(min_gap, since)
			since = 0.0
		prev_cur = audio._seg_cur.duplicate()
	_check("8 min: %d zmian sekcji, najkrócej %.0f s, zawsze cała muzyka naraz" % [sec_changes, min_gap], sec_changes >= 3 and min_gap >= 2.0 * loop_s and together)
	# kadencja: walka kończy się uderzeniem na takcie, nie wyciszeniem
	var bar: float = audio._bar_len()
	_check("kadencja: następny takt (%.2f s)" % audio._cadence_wait(0.1), absf(audio._cadence_wait(0.1) - (bar - 0.1)) < 0.001)
	var skip: Array = man.MUSIC_CADENCE_SKIP_BARS
	_check("kadencja siada na następnym takcie poza MUSIC_CADENCE_SKIP_BARS (%s)" % str(skip),
		absf(audio._cadence_wait(2.0 * bar + 0.5) - ((2.0 if skip.has(3) else 1.0) * bar - 0.5)) < 0.001
		and absf(audio._cadence_wait(6.0 * bar + 0.5) - ((2.0 if skip.has(7) else 1.0) * bar - 0.5)) < 0.001)
	_check("E3: 64 BPM, pętla 30 s, pedał D — kadencja na każdym takcie", man.MUSIC_BPM == 64.0 and absf(man.MUSIC_LOOP_SEC - 30.0) < 0.001 and skip.is_empty())
	_check("kadencja nie bliżej niż przedbieg pliku", absf(audio._cadence_wait(bar - 0.1) - (bar + 0.1)) < 0.001)
	audio.music_set_layer(2)
	audio._stem_gain[1] = 1.0
	audio._stem_gain[2] = 1.0
	audio.music_set_layer(1)
	audio._clock = audio._drop_at
	audio._update_music(0.0)
	_check("zejście z walki: kadencja w drodze (%s za %.2f s), walka gra do taktu" % [audio._cad_key, audio._cad_land - audio._clock],
		audio._cad_key == "mus_combat_end" and audio._cad_land > audio._clock and audio._stem_target[2] == 1.0)
	audio._clock = audio._cad_land - 0.1
	audio._update_music(0.0)
	_check("kadencja rusza z przedbiegiem przed taktem", audio._cad_started and audio._cad.playing)
	audio._clock = audio._cad_land + 0.01
	audio._update_music(0.0)
	audio._update_music(0.35)
	_check("na takcie walka schodzi pod uderzeniem (%.2f), napięcie zostaje (%.2f)" % [audio._stem_gain[2], audio._stem_gain[1]],
		audio._music_layer == 1 and audio._stem_fast[2] and audio._stem_gain[2] < 0.6 and audio._stem_gain[1] == 1.0 and audio._cad_key == "")
	audio._update_music(0.5)
	_check("walka ucichła w < 1 s", audio._stem_gain[2] == 0.0)
	audio.music_set_layer(2)
	audio._stem_gain[2] = 1.0
	audio.music_set_layer(1)
	audio._clock = audio._drop_at
	audio._update_music(0.0)
	audio.music_set_layer(2)
	_check("walka wraca przed taktem: kadencja odwołana", audio._cad_key == "" and audio._drop_to == audio.NO_DROP and audio._stem_target[2] == 1.0)
	audio._stem_gain[2] = 0.3
	audio.music_set_layer(1)
	audio._clock = audio._drop_at
	audio._update_music(0.0)
	_check("ledwo słyszana walka: bez kadencji, zwykłe wyciszenie", audio._cad_key == "" and audio._stem_target[2] == 0.0 and not audio._stem_fast[2])
	# paleta strefy podmienia się dopiero w ciszy
	var gs := GDScript.new()
	gs.source_code = "extends Node\nvar map_id := \"z1_b1\"\n"
	gs.reload()
	var lvl: Node = gs.new()
	lvl.add_to_group("level")
	root.add_child(lvl)
	audio._palette_t = 0.0
	audio._update_music(0.0)
	_check("mapa bossa, muzyka gra: paleta czeka (%s)" % audio._palette, audio._palette == "default" and audio._palette_want == "z1_b1")
	for i in audio._stem_gain.size():
		audio._stem_gain[i] = 0.0
		audio._stem_target[i] = 0.0
	audio._motif_x.fill(0.0)
	audio._palette_t = 0.0
	audio._update_music(0.0)
	_check("w ciszy paleta bossa: zaczyna od sekcji B (%s)" % audio._seg[1][0].stream.resource_path.get_file(),
		audio._palette == "z1_b1" and audio._seg[1][0].stream.resource_path.ends_with("mus_tension_b.ogg") and audio._seg_n[1] == 2 and audio._seg[1][0].playing)
	# --- E4: sceny (boss, odwrót)
	var sd = MD.new(9)
	sd.scene_step(0.1, 1200.0, 1, false, false)
	_check("boss dalej niż zasięg wejścia: bez sceny", sd.scene == "")
	sd.scene_step(0.1, 600.0, 1, false, false)
	_check("obudzony boss w zasięgu: scena bossa, faza 1", sd.scene == "boss" and sd.boss_phase == 1 and not sd.scene_won)
	sd.scene_step(0.1, 1200.0, 2, false, false)
	_check("odejście do 1200 px: scena trwa (histereza), faza 2", sd.scene == "boss" and sd.boss_phase == 2)
	sd.scene_step(0.1, INF, 0, true, false)
	_check("boss padł: odwrót ze zwycięstwem", sd.scene == "retreat" and sd.scene_won and sd.boss_phase == 0)
	sd.scene_step(0.1, INF, 0, true, false)
	_check("zwycięstwo tylko w jednej klatce, odwrót czeka na ekstrakcję", sd.scene == "retreat" and not sd.scene_won)
	sd.scene_step(3.0, INF, 0, true, false)
	_check("bez ekstrakcji po %.0f s odwrót gaśnie" % sd.WON_HOLD, sd.scene == "")
	sd.scene_step(0.1, INF, 0, false, true)
	_check("ekstrakcja (cel, zawał, nadawanie): odwrót bez zwycięstwa", sd.scene == "retreat" and not sd.scene_won)
	var sd2 = MD.new(9)
	sd2.scene_step(0.1, 600.0, 3, false, false)
	sd2.scene_step(0.1, 1500.0, 3, false, false)
	_check("gracz uciekł poza 1400 px: scena znika bez zwycięstwa", sd2.scene == "" and not sd2.scene_won)
	_check("pod bossem warstwy 1–2 (puls zawsze, bez pościgu), pod odwrotem ≥ 1, bez sceny bez zmian",
		MD.scene_layer(-1, "boss") == 1 and MD.scene_layer(3, "boss") == 2 and MD.scene_layer(-1, "retreat") == 1
		and MD.scene_layer(3, "retreat") == 3 and MD.scene_layer(-1, "") == -1 and MD.scene_layer(2, "") == 2)
	var ms := GDScript.new()
	ms.source_code = "extends Node\nfunc music_retreat() -> bool:\n\treturn true\n"
	ms.reload()
	var mis: Node = ms.new()
	mis.add_to_group("mission")
	root.add_child(mis)
	var me2 := FakePlayer.new()
	root.add_child(me2)
	var sd3 = MD.new(9)
	sd3._drive_scene(0.1, me2)
	_check("misja w ekstrakcji (drzewo sceny): odwrót", sd3.scene == "retreat")
	mis.queue_free()
	me2.queue_free()

	var man_s = load("res://scripts/audio_manifest.gd")
	var loop_len: float = man_s.MUSIC_LOOP_SEC
	var keys_ok := true
	for k in audio.SCENE_KEYS + [audio.SCENE_HIT, audio.SCENE_BOSS_END]:
		keys_ok = keys_ok and man_s.PATHS.has(k) and audio.stream(k) != null
	_check("pliki scen w manifeście", keys_ok)
	var lens: Array = audio.SCENE_KEYS.map(func(k: String) -> float: return audio.stream(k).get_length())
	_check("sceny na siatce: boss = pętla, odwrót = dwie pętle (%s)" % str(lens),
		absf(lens[0] - loop_len) < 0.01 and absf(lens[1] - loop_len) < 0.01 and absf(lens[2] - loop_len) < 0.01 and absf(lens[3] - 2.0 * loop_len) < 0.01)
	audio.shutdown()
	audio.set_enabled(true)
	audio._health_db = 0.0
	audio._duck_db = 0.0
	var beat_s: float = 60.0 / float(man_s.MUSIC_BPM)
	var bar_s: float = audio._bar_len()
	audio.music_set_scene("boss", 1)
	_check("scena bossa uruchamia muzykę i faza 1 (%s)" % str(audio._scene_target),
		audio._music_started and audio._scene_target == [1.0, 0.0, 0.0, 0.0] and audio._scene_p[0].playing and audio._scene_p[3].playing)
	_check("start bossa: uderzenie na najbliższym beacie, warstwa na takcie",
		audio._hits.size() == 1 and audio._hits[0]["key"] == audio.SCENE_HIT and float(audio._hits[0]["land"]) - audio._clock <= beat_s + 0.3
		and audio._scene_enter_at[0] - audio._clock <= bar_s + 0.01)
	audio._clock = audio._scene_enter_at[0]
	for i in 30:
		audio._clock += 0.1
		audio._update_music(0.1)
	_check("faza 1 słychać w pełni (%.2f), uderzenie zagrane" % audio._scene_x[0], audio._scene_x[0] == 1.0 and audio._hits.is_empty()
		and audio._hit_p.any(func(hp: AudioStreamPlayer) -> bool: return hp.stream != null))
	audio.music_set_scene("boss", 2)
	_check("faza 2: dokłada warstwę i uderzenie", audio._scene_target == [1.0, 1.0, 0.0, 0.0] and audio._hits.size() == 1)
	audio._hits.clear()
	audio.music_set_scene("boss", 2)
	_check("ta sama faza co klatkę: nic nowego", audio._hits.is_empty())
	audio._scene_x[1] = 1.0
	audio.music_set_scene("retreat", 0, true)
	var land: float = audio._scene_cut_at[0]
	_check("śmierć bossa: kadencja na takcie, warstwy bossa wycinane pod nią, odwrót po %d taktach ogona" % audio.SCENE_RETREAT_AFTER_BARS,
		audio._hits.size() == 1 and audio._hits[0]["key"] == audio.SCENE_BOSS_END and is_equal_approx(float(audio._hits[0]["land"]), land)
		and land - audio._clock <= bar_s + 0.3 and audio._scene_cut_at[1] == land and audio._scene_target == [0.0, 0.0, 0.0, 1.0]
		and is_equal_approx(audio._scene_enter_at[3], land + audio.SCENE_RETREAT_AFTER_BARS * bar_s))
	audio._clock = land - 0.05
	audio._update_music(0.05)
	_check("boss gra aż do uderzenia (%.2f)" % audio._scene_x[0], audio._scene_x[0] == 1.0)
	audio._clock = land + 0.8
	audio._update_music(0.8)
	_check("po uderzeniu boss cichnie w %.1f s" % audio.CADENCE_CUT, audio._scene_x[0] == 0.0 and audio._scene_x[1] == 0.0
		and audio._hit_p.any(func(hp: AudioStreamPlayer) -> bool: return hp.stream != null and hp.stream.resource_path.contains("mus_boss_end")))
	_check("odwrót jeszcze czeka na koniec ogona", audio._scene_x[3] == 0.0)
	audio._clock = audio._scene_enter_at[3]
	for i in 31:
		audio._clock += 0.1
		audio._update_music(0.1)
	_check("odwrót gra (%.2f)" % audio._scene_x[3], audio._scene_x[3] == 1.0)
	audio._palette_want = "z1_b1"
	audio._palette = "default"
	for i in audio._stem_gain.size():
		audio._stem_gain[i] = 0.0
	audio._palette_t = 0.0
	audio._update_music(0.0)
	_check("paleta czeka, dopóki gra scena", audio._palette == "default")
	audio.music_set_scene("")
	audio._clock += 1.0
	audio._update_music(1.0)
	_check("koniec odwrotu bez zwycięstwa: zwykłe wyciszenie (po 1 s %.2f)" % audio._scene_x[3], audio._scene_x[3] > 0.7 and audio._scene_x[3] < 1.0
		and audio._scene_cut_at[3] < 0.0 and audio._hits.is_empty())

	lvl.queue_free()
	audio.shutdown()
	_check("wyłączenie: sceny i uderzenia stoją", audio._scene_p.all(func(sp: AudioStreamPlayer) -> bool: return not sp.playing and sp.stream == null)
		and audio._scene == "" and audio._scene_x == [0.0, 0.0, 0.0, 0.0])
	_check("wyłączenie: wszystkie warianty i kadencja stoją", audio._seg.all(func(a: Array) -> bool: return a.all(func(p: AudioStreamPlayer) -> bool: return not p.playing and p.stream == null)) and not audio._cad.playing)

	print("%s (test_music: %d błędów)" % ["PASS" if _fails == 0 else "FAIL", _fails])
	quit(0 if _fails == 0 else 1)
