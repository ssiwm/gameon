extends Control
## Paski życia wrogów i plakietki graczy w warstwie ekranu: nad obrazem 3D i efektami ekranu (winieta, aberracja), pod HUD-em.
## Pozycję daje widok 3D (view3d.gd): punkt nad czubkiem modelu w bieżącej pozie — najwyższa z kości kontrolnych (głowa, a bez niej cały
## szkielet) plus odległość czubka siatki od tych kości w spoczynku — rzutowany kamerą świata na ekran. Rysunek jest w jednostkach okna
## (stretch canvas_items), więc pozostaje ostry w każdej rozdzielczości i nie łapie poświaty ani rozjechania kolorów sceny.
## Symulacja tylko podaje stan: `bar_state()` wroga i gniazda, `plate_state()` gracza.
##
## Pasek wroga: kość na ciemnym torze z obwódką, poniżej LOW_FRAC rdzawy; po trafieniu jasny ślad obrażeń trzyma się GHOST_HOLD s
## i spływa; pasek gaśnie SHOW_S s po ostatnim trafieniu (elita pokazuje go też przy pierwszym wejściu w kadr).

const SHOW_S := 4.0                 ## s widoczności paska wroga po ostatnim trafieniu
const FADE_S := 0.6                 ## s gaśnięcia
const GHOST_HOLD := 0.35            ## s, zanim ślad obrażeń zacznie spływać
const GHOST_RATE := 1.4             ## szybkość spływania śladu [ułamek paska / s]
const BAR_H := 1.4                  ## grubość paska wroga [jednostki okna]
const ELITE_H := 1.8
const BAR_MIN_W := 12.0
const TOP_CAP := 0.35              ## najwyżej tyle wysokości kości nad korzeniem może dołożyć czubek siatki
const GAP := 1.4                    ## odstęp paska / plakietki nad czubkiem modelu [jednostki okna]
const LOW_FRAC := 0.25
const BONE := Color(0.78, 0.73, 0.62)
const LOW := Color(0.87, 0.42, 0.24)
const GHOST := Color(1.0, 0.98, 0.9)
const TRACK := Color(0.043, 0.039, 0.035, 0.85)
const EDGE := Color(0.0, 0.0, 0.0, 0.8)
const MIMIC_COL := Color(0.72, 0.8, 0.72)
## Plakietka gracza (projekt jak dotąd, w px świata przed skalą PLATE_SCALE): font NAME_SIZE, tarcza PLATE_PIP.
const NAME_SIZE := 4.0
const PLATE_PIP := Vector2(3.4, 4.0)
const PLATE_SCALE := 0.5
const FONT_BASE := 16               ## rozmiar, w jakim rasteryzujemy tekst przed skalowaniem do rozmiaru docelowego

var view: Node                      ## view3d.gd: rzut punktów 3D i listy modeli
var _st := {}                       ## id węzła wroga → {frac, ghost, hold, t, a, seen}
var _rigs := {}                     ## id modelu 3D → {bones, off, meshes, sk}
var _bars: Array = []               ## paski do narysowania w tej klatce
var _plates: Array = []             ## plakietki graczy do narysowania w tej klatce
var _font: Font

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	process_priority = 10           # po widoku 3D: kamera i pozy modeli są już z tej klatki
	_font = ThemeDB.fallback_font

func _process(delta: float) -> void:
	_bars.clear()
	_plates.clear()
	if view == null or not is_instance_valid(view):
		queue_redraw()
		return
	modulate.a = float(view.get("label_fade"))
	var cx := get_viewport().get_canvas_transform()
	var zoom := cx.x.length()                         # jednostki okna na px świata (Camera2D, „Camera zoom”)
	var live := {}
	for pair in view.call("bar_targets"):
		var src = pair[0]
		if not is_instance_valid(src) or not (src as Node).has_method("bar_state"):
			continue
		var id: int = (src as Node).get_instance_id()
		live[id] = true
		_enemy(src, pair[1], id, delta, cx, zoom)
	for id in _st.keys():
		if not live.has(id):
			_st.erase(id)
	if not Settings.dev_nohud:
		for p in get_tree().get_nodes_in_group("players"):
			if is_instance_valid(p) and not p.is_queued_for_deletion() and p.has_method("plate_state") and (p as CanvasItem).is_visible_in_tree():
				_player(p, cx, zoom)
	queue_redraw()

# ---------------------------------------------------------------- stan

func _enemy(src: Node2D, model, id: int, delta: float, cx: Transform2D, zoom: float) -> void:
	var bs: Dictionary = src.call("bar_state")
	var f: float = bs["frac"]
	var s: Dictionary = _st.get(id, {})
	if s.is_empty():
		s = {"frac": f, "ghost": f, "hold": 0.0, "t": 0.0, "a": 0.0, "seen": false}
		_st[id] = s
	if f < float(s["frac"]) - 0.0001:
		s["ghost"] = maxf(float(s["ghost"]), float(s["frac"]))       # trafienie: ślad od poprzedniej wartości
		s["hold"] = GHOST_HOLD
		s["t"] = SHOW_S
	s["frac"] = f
	if float(s["hold"]) > 0.0:
		s["hold"] = float(s["hold"]) - delta
	else:
		s["ghost"] = move_toward(float(s["ghost"]), f, GHOST_RATE * delta)
	s["ghost"] = maxf(float(s["ghost"]), f)                          # leczenie (Kapłan): wypełnienie od razu, bez śladu
	var e: Node3D = model as Node3D if model != null and is_instance_valid(model) else null
	var on_screen := e.visible if e != null else src.is_visible_in_tree()
	var alive: bool = bs["alive"]
	if bool(bs["elite"]) and alive and on_screen and not bool(s["seen"]):
		s["seen"] = true
		s["t"] = SHOW_S
	s["t"] = maxf(0.0, float(s["t"]) - delta)
	var want: bool = alive and on_screen and float(s["t"]) > 0.0
	s["a"] = move_toward(float(s["a"]), 1.0 if want else 0.0, delta / (0.12 if want else FADE_S))
	if not alive or not on_screen:
		s["a"] = 0.0
	var label: String = bs["label"]
	if float(s["a"]) <= 0.005 and (label == "" or not alive or not on_screen):
		return
	var top := _anchor(e, src, float(bs["h"]), cx)
	if is_nan(top.x):
		return
	if label != "":
		_plates.append({"pos": top, "u": PLATE_SCALE * zoom, "label": label})
	if float(s["a"]) > 0.005:
		_bars.append({"pos": top, "w": maxf(float(bs["w"]) * zoom, BAR_MIN_W), "frac": f, "ghost": float(s["ghost"]), "a": float(s["a"]),
			"elite": bool(bs["elite"])})

func _player(p: Node2D, cx: Transform2D, zoom: float) -> void:
	var ps: Dictionary = p.call("plate_state")
	var u := PLATE_SCALE * zoom
	if bool(ps["dead"]):
		# leżąca postać: napisy jak dotąd nad punktem stóp (model leży, czubek głowy jest przy ziemi)
		_plates.append({"pos": cx * p.global_position, "zoom": zoom, "st": ps})
		return
	var c3 = view.call("player_model", p)
	var top := Vector2(NAN, NAN)
	if c3 != null:
		var sk = c3.get("_sk")
		var b: Dictionary = c3.get("_b")
		var m = c3.get("_char_node")
		if sk != null and is_instance_valid(sk) and b.has("Head") and m != null and is_instance_valid(m):
			top = _model_top(m, sk, [b["Head"]])
	if is_nan(top.x):
		top = cx * (p.global_position + Vector2(0.0, float(ps["top"])))
	_plates.append({"pos": top, "u": u, "st": ps})

## Ekranowy punkt nad czubkiem modelu wroga; bez modelu — z wysokości sprite'a 2D.
func _anchor(e: Node3D, src: Node2D, h_px: float, cx: Transform2D) -> Vector2:
	if e != null:
		var sk = e.get("_sk")
		if sk != null and is_instance_valid(sk):
			var b: Dictionary = e.get("_b")
			var crawler: bool = (e.get("_spec") as Dictionary).get("crawler", false)
			var bones: Array = [b["Head"]] if b.has("Head") and not crawler else []     # pełzacz (Skoczek): grzbiet i kolce są wyżej niż głowa
			return _model_top(e, sk, bones)
		var rig: Dictionary = _rig(e, null, [])
		var top := _mesh_top(rig["meshes"])
		if not is_inf(top):
			return view.call("screen_point", Vector3(e.global_position.x, top, e.global_position.z))
	return cx * (src.global_position + Vector2(0.0, -h_px))

## Czubek modelu w bieżącej pozie, rzutowany na ekran: najwyższa z kości `bones` (pusta lista = cały szkielet) plus odległość czubka
## siatki od nich w spoczynku. W poziomie bliżej tej kości niż korzenia modelu (pasek nad głową, ale pochylona głowa nie ściąga go całkiem z tułowia).
func _model_top(model: Node3D, sk: Skeleton3D, bones: Array) -> Vector2:
	var rig := _rig(model, sk, bones)
	var gx := sk.global_transform
	var best := Vector3(0.0, -INF, 0.0)
	for i in rig["bones"]:
		var q: Vector3 = gx * sk.get_bone_global_pose(int(i)).origin
		if q.y > best.y:
			best = q
	if is_inf(best.y):
		return Vector2(NAN, NAN)
	var root := model.global_position
	return view.call("screen_point", Vector3(lerpf(root.x, best.x, 0.85), best.y + float(rig["off"]), best.z))

## Dane modelu liczone raz: kości kontrolne, odległość czubka siatki ponad nimi w spoczynku [m], siatki (widoczne przy pierwszym pomiarze).
func _rig(model: Node3D, sk: Skeleton3D, bones: Array) -> Dictionary:
	var id := model.get_instance_id()
	if _rigs.has(id):
		return _rigs[id]
	var meshes: Array = []
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh != null and m.visible:
			meshes.append(m)
	var r := {"bones": bones, "off": 0.0, "meshes": meshes, "sk": sk}
	if sk != null:
		if bones.is_empty():
			for i in sk.get_bone_count():
				bones.append(i)
		var gx := sk.global_transform
		var bone_top := -INF
		for i in bones:
			bone_top = maxf(bone_top, (gx * sk.get_bone_global_rest(int(i)).origin).y)
		var mesh_top := _mesh_top(meshes)
		if not is_inf(mesh_top) and not is_inf(bone_top):
			# AABB siatki to poza wiązania, a nie spoczynek szkieletu — u modeli z Tripo (Trzosek) bywa o połowę wyższa niż stojący model,
			# więc odległość ograniczamy ułamkiem wysokości kości nad korzeniem (głowa człowieka ok. 0,2 m, rogi Wołka ok. 0,6 m mieszczą się)
			r["off"] = clampf(mesh_top - bone_top, 0.0, maxf(bone_top - model.global_position.y, 0.0) * TOP_CAP)
	_rigs[id] = r
	if _rigs.size() > 256:
		for k in _rigs.keys():
			if not is_instance_valid(instance_from_id(int(k))):
				_rigs.erase(k)
	return r

static func _mesh_top(meshes: Array) -> float:
	var top := -INF
	for mi in meshes:
		if is_instance_valid(mi):
			var m := mi as MeshInstance3D
			top = maxf(top, (m.global_transform * m.get_aabb()).end.y)
	return top

# ---------------------------------------------------------------- rysunek

func _draw() -> void:
	for b in _bars:
		_draw_bar(b)
	for p in _plates:
		if p.has("label"):
			_text(p["pos"] - Vector2(0.0, GAP), String(p["label"]), NAME_SIZE * float(p["u"]), Color(MIMIC_COL, 0.45), true)     # jak imię gracza przy pełnym życiu
		elif bool(p["st"]["dead"]):
			_draw_down(p["pos"], float(p["zoom"]), p["st"])
		else:
			_draw_plate(p["pos"] - Vector2(0.0, GAP), float(p["u"]), p["st"])

func _draw_bar(b: Dictionary) -> void:
	var a: float = b["a"]
	var h := ELITE_H if bool(b["elite"]) else BAR_H
	var w: float = b["w"]
	var pos: Vector2 = b["pos"]
	var x := clampf(pos.x, w * 0.5 + 2.0, maxf(size.x - w * 0.5 - 2.0, w * 0.5 + 2.0))     # przy krawędzi ekranu pasek zostaje cały w kadrze
	var r := Rect2(x - w * 0.5, pos.y - GAP - h, w, h)
	var f: float = b["frac"]
	draw_rect(r.grow(0.35), Color(EDGE, EDGE.a * a))
	draw_rect(r, Color(TRACK, TRACK.a * a))
	draw_rect(Rect2(r.position + Vector2(0.0, h - 0.22), Vector2(w, 0.22)), Color(1, 1, 1, 0.12 * a))     # dno toru: pusty pasek widać na ciemnym tle
	draw_rect(Rect2(r.position, Vector2(w * float(b["ghost"]), h)), Color(GHOST, a))
	draw_rect(Rect2(r.position, Vector2(w * f, h)), Color(LOW if f < LOW_FRAC else BONE, a))

## Tekst o wysokości `size` [jednostki okna]: rasteryzowany w FONT_BASE i skalowany, bo rozmiar fontu jest całkowity.
func _text(pos: Vector2, txt: String, size: float, col: Color, center: bool) -> void:
	var sc := size / float(FONT_BASE)
	draw_set_transform(pos, 0.0, Vector2(sc, sc))
	var x := -400.0 if center else 0.0
	var sh := 0.12 / sc                                # cień pod tekstem — czytelność na jasnym tle (snop latarki, flara)
	draw_string(_font, Vector2(x + sh, sh), txt, HORIZONTAL_ALIGNMENT_CENTER if center else HORIZONTAL_ALIGNMENT_LEFT, 800.0 if center else -1.0,
		FONT_BASE, Color(0, 0, 0, 0.8 * col.a))
	draw_string(_font, Vector2(x, 0.0), txt, HORIZONTAL_ALIGNMENT_CENTER if center else HORIZONTAL_ALIGNMENT_LEFT, 800.0 if center else -1.0, FONT_BASE, col)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _text_w(txt: String, size: float) -> float:
	return _font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_BASE).x * size / float(FONT_BASE)

## Powalony gracz: imię, odliczanie (wykrwawianie / porwanie) i pasek podnoszenia — nad punktem stóp, miary jak dotąd w px świata.
func _draw_down(feet: Vector2, zoom: float, ps: Dictionary) -> void:
	var col: Color = ps["col"]
	_text(feet + Vector2(0.0, -26.0 * zoom), String(ps["name"]), NAME_SIZE * zoom, col, true)
	var taken: bool = ps["taken"]
	_text(feet + Vector2(0.0, -18.0 * zoom), "%ds" % int(ps["timer"]), NAME_SIZE * zoom, Color(1.0, 0.5, 0.25) if taken else Color(0.95, 0.4, 0.4), true)
	var rv: float = ps["revive"]
	if rv > 0.0:
		var r := Rect2(feet + Vector2(-12.0, -12.0) * zoom, Vector2(24.0, 3.0) * zoom)
		draw_rect(r.grow(0.3), EDGE)
		draw_rect(r, Color(0.1, 0.1, 0.12, 0.9))
		draw_rect(Rect2(r.position, Vector2(r.size.x * clampf(rv, 0.0, 1.0), r.size.y)), Color(0.4, 0.95, 0.5))

## Plakietka życia nad głową: ciemna płytka z imieniem (kolor slotu) i tarczami jak na karcie drużyny — pełna krwista, pusta tylko obrysem,
## bonusowa złota; przy 1 życiu ramka czerwieni się i pulsuje (puls wyłącza „Reduce effects”). Przy pełnym życiu rysujemy samo imię.
## `o` to środek dolnej krawędzi płytki, `u` — jednostki okna na jednostkę projektu.
func _draw_plate(o: Vector2, u: float, ps: Dictionary) -> void:
	var hp: int = ps["hp"]
	var base: int = ps["base"]
	var hearts := maxi(base, hp)
	var a: float = ps["a"]
	var col: Color = ps["col"]
	var name_txt: String = ps["name"]
	var label_col := Color(col.r, col.g, col.b, lerpf(0.45, 1.0, a))
	var fs := NAME_SIZE * u
	if a < 0.02:
		_text(o + Vector2(0.0, -2.0 * u), name_txt, fs, label_col, true)
		return
	var label_w := _text_w(name_txt, fs) / u
	var pips_w := float(hearts) * PLATE_PIP.x + float(hearts - 1) * 1.2
	var pad := 2.0
	var w := pad + label_w + 2.2 + pips_w + pad
	var x0 := -w * 0.5
	var y := -7.0
	var low := hp <= 1 and base > 1
	var pulse := 1.0
	if low and Settings.fx_mult() > 0.0:
		pulse = 0.65 + 0.35 * sin(float(ps["wound_t"]) * 5.0)
	var edge := Color(0.62, 0.13, 0.13, a * pulse) if low else Color(0.30, 0.26, 0.22, 0.9 * a)
	var r := Rect2(o + Vector2(x0, y) * u, Vector2(w, 7.0) * u)
	draw_rect(r, Color(0.035, 0.03, 0.026, 0.84 * a))
	draw_rect(r, edge, false, maxf(0.5 * u, 0.25))
	_text(o + Vector2(x0 + pad, y + 4.6) * u, name_txt, fs, label_col, false)
	var px := x0 + pad + label_w + 2.2
	var py := y + (7.0 - PLATE_PIP.y) * 0.5
	var flash: float = ps["flash"]
	for i in hearts:
		var ix := px + float(i) * (PLATE_PIP.x + 1.2)
		var pts := PackedVector2Array()
		for q in [Vector2(ix, py), Vector2(ix + PLATE_PIP.x, py), Vector2(ix + PLATE_PIP.x, py + PLATE_PIP.y * 0.6),
				Vector2(ix + PLATE_PIP.x * 0.5, py + PLATE_PIP.y), Vector2(ix, py + PLATE_PIP.y * 0.6)]:
			pts.append(o + (q as Vector2) * u)
		if i < hp:
			draw_colored_polygon(pts, Color(0.84, 0.66, 0.23, a) if i >= base else Color(0.6, 0.1, 0.12, a))     # ponad bazę — złote
		else:
			var ring := Color(0.42, 0.36, 0.31, 0.85 * a)
			if flash > 0.0 and i >= hp and i < base:
				ring = Color(0.95, 0.62, 0.62, minf(1.0, flash * 2.0) * a)          # tarcza utracona przed chwilą błyska obrysem
			pts.append(pts[0])
			draw_polyline(pts, ring, maxf(0.5 * u, 0.25), true)
