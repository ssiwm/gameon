extends Node3D
## Strzelnica FPP — szafa z bronią (RANGE_FPS_PLAN.md §13). W tunelu: stalowa szafa przy lewej ścianie przed ławą, w niej każda broń palna gry
## kolbą w dół (modele gun_<klucz>.glb); broń, którą gracz ma właśnie z szafy w ręku, znika ze stojaka. Na ekranie (interfejs, [F]): lista broni
## z zaznaczeniem — wybór i logika w fp_mode.gd (`locker_open`, `locker_sel`, `locker_pick`), tu tylko obraz i klik myszą.

const RangeSim := preload("res://scripts/range3d/range_sim.gd")
const Weapons := preload("res://scripts/weapons.gd")
const GunModel := preload("res://scripts/gun_model.gd")
const Char3D := preload("res://scripts/char3d.gd")
const UiTheme := preload("res://scripts/ui_theme.gd")
const Actions := preload("res://scripts/actions.gd")
const WeaponDef := preload("res://scripts/weapon_def.gd")

const POS := Vector3(-2.78, 0.0, -1.55)       ## środek podstawy szafy (przy lewej ścianie, przed ławą — widać ją po obrocie w lewo)
const SIZE := Vector3(0.42, 2.0, 1.5)         ## głębokość (x), wysokość, szerokość (wzdłuż tunelu)
const GUN_BASIS := Basis(Vector3(0, 1, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1))   ## broń kolbą w dół: lufa w górę, wierzch do ściany
const SHELF_Y := 0.78                         ## m — półka pod kolby: niżej broń chowa się za przegrodą stanowiska
const ROW_H := 13.0                           ## px interfejsu (640×360) na wiersz listy

var view: Node                                ## range_view.gd
var fp: Node                                  ## fp_mode.gd
var _guns := {}                               ## id broni → model na stojaku
var _ui: Control
var _rows: Array = []                         ## [{bg: ColorRect, name: Label, info: Label}]
var _foot: Label

func setup(v: Node, f: Node) -> void:
	view = v
	fp = f

func _ready() -> void:
	_build_cabinet()
	_build_ui()

## Szafa: tył, boki, strop, dno, półka na kolby, listwa z wycięciami na lufy, szyld i lampka; bronie w rzędzie.
func _build_cabinet() -> void:
	var steel: StandardMaterial3D = view._flat(Color(0.2, 0.22, 0.2), 0.55, 0.6)
	var dark: StandardMaterial3D = view._flat(Color(0.32, 0.3, 0.26), 0.9, 0.0)        # jasna płyta tylna: ciemne bronie odcinają się od tła
	var felt: StandardMaterial3D = view._flat(Color(0.12, 0.05, 0.04), 0.95)
	var b := POS
	view._box(Vector3(0.03, SIZE.y, SIZE.z), b + Vector3(-SIZE.x * 0.5, SIZE.y * 0.5, 0.0), dark)                     # tył
	for sz in [-1.0, 1.0]:
		view._box(Vector3(SIZE.x, SIZE.y, 0.03), b + Vector3(0.0, SIZE.y * 0.5, sz * SIZE.z * 0.5), steel)          # boki
		view._box(Vector3(0.025, SIZE.y, 0.6), b + Vector3(SIZE.x * 0.5 + 0.2, SIZE.y * 0.5, sz * (SIZE.z * 0.5 + 0.02)), steel)   # otwarte drzwi
	view._box(Vector3(SIZE.x, 0.04, SIZE.z), b + Vector3(0.0, SIZE.y - 0.02, 0.0), steel)                         # strop
	view._box(Vector3(SIZE.x, SHELF_Y, SIZE.z), b + Vector3(0.0, SHELF_Y * 0.5, 0.0), steel)                       # dół z szufladami
	for k in 3:
		var dy := SHELF_Y * (float(k) + 0.5) / 3.0
		view._box(Vector3(0.012, SHELF_Y / 3.0 - 0.03, SIZE.z - 0.1), b + Vector3(SIZE.x * 0.5 + 0.006, dy, 0.0), dark)   # front szuflady
		view._box(Vector3(0.03, 0.02, 0.25), b + Vector3(SIZE.x * 0.5 + 0.02, dy + 0.06, 0.0), steel)                     # uchwyt
	view._box(Vector3(SIZE.x - 0.04, 0.03, SIZE.z - 0.06), b + Vector3(0.0, SHELF_Y + 0.015, 0.0), felt)          # filc pod kolbami
	view._box(Vector3(0.05, 0.04, SIZE.z - 0.06), b + Vector3(-0.06, SHELF_Y + 0.75, 0.0), felt)                # listwa pod lufy
	var ids: Array = fp.locker_weapons()
	var step := (SIZE.z - 0.16) / float(maxi(1, ids.size() - 1))
	for i in ids.size():
		var key := String(Weapons.def(int(ids[i])).key)
		if not ResourceLoader.exists(Char3D.DIR + "gun_%s.glb" % key):
			continue
		var g: Node3D = GunModel.build(key, [], Char3D.gun_info(key)["muzzle"])
		g.basis = GUN_BASIS
		g.position = b + Vector3(-0.05, 0.13, -SIZE.z * 0.5 + 0.08 + step * float(i))
		for mi in g.find_children("*", "MeshInstance3D", true, false):
			(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(g)
		var bb := _bounds(g)                                       # początek modelu nie leży przy kolbie: stawiamy po obrysie
		g.position += Vector3(b.x + 0.02 - bb.get_center().x, b.y + SHELF_Y + 0.03 - bb.position.y, 0.0)
		_guns[int(ids[i])] = g
	var inner := OmniLight3D.new()                                # świetlówka pod stropem szafy
	inner.light_color = Color(1.0, 0.92, 0.78)
	inner.light_energy = 1.6
	inner.omni_range = 2.2
	inner.position = b + Vector3(0.12, SIZE.y - 0.12, 0.0)
	add_child(inner)
	view._box(Vector3(0.04, 0.03, SIZE.z - 0.2), inner.position + Vector3(0.0, 0.03, 0.0), view._glow(Color(1.0, 0.92, 0.8), 2.5))
	var lamp := SpotLight3D.new()
	lamp.light_color = Color(1.0, 0.88, 0.7)
	lamp.light_energy = 2.2
	lamp.spot_range = 3.0
	lamp.spot_angle = 55.0
	lamp.position = b + Vector3(0.7, SIZE.y + 0.5, 0.0)
	lamp.rotation = Vector3(deg_to_rad(-70.0), deg_to_rad(90.0), 0.0)            # z tunelu w szafę (−x), w dół
	add_child(lamp)
	var sign_l := Label3D.new()
	sign_l.text = tr("WEAPON LOCKER  ·  [%s]") % Actions.key("range_locker")
	sign_l.font_size = 40
	sign_l.pixel_size = 0.004
	sign_l.modulate = Color(0.95, 0.8, 0.45)
	sign_l.outline_size = 6
	sign_l.position = b + Vector3(SIZE.x * 0.5 + 0.01, SIZE.y + 0.12, 0.0)
	sign_l.rotation.y = PI * 0.5                                  # napis do tunelu (+x)
	add_child(sign_l)

## Obrys modelu w świecie (wszystkie siatki).
func _bounds(n: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var bb := m.global_transform * m.get_aabb()
		out = bb if first else out.merge(bb)
		first = false
	return out

func _build_ui() -> void:
	_ui = Control.new()
	_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.visible = false
	view.add_child(_ui)
	var ids: Array = fp.locker_weapons()
	var w := 236.0
	var h := 46.0 + ROW_H * float(ids.size())
	var panel := Panel.new()
	panel.add_theme_stylebox_override("panel", UiTheme.panel_box())
	panel.position = Vector2(30.0, (360.0 - h) * 0.5)
	panel.size = Vector2(w, h)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_ui.add_child(panel)
	var title := _label(tr("WEAPON LOCKER"), UiTheme.T_BODY, UiTheme.ACCENT)
	title.position = Vector2(10.0, 5.0)
	if UiTheme.heading_font() != null:
		title.add_theme_font_override("font", UiTheme.heading_font())
	panel.add_child(title)
	var sub := _label(tr("Range only · free · back in the locker when you leave"), UiTheme.T_CAPTION - 1, UiTheme.MUTED)
	sub.position = Vector2(10.0, 18.0)
	panel.add_child(sub)
	for i in ids.size():
		var bg := ColorRect.new()
		bg.position = Vector2(6.0, 30.0 + ROW_H * float(i))
		bg.size = Vector2(w - 12.0, ROW_H - 1.0)
		bg.mouse_filter = Control.MOUSE_FILTER_STOP
		bg.gui_input.connect(_on_row_input.bind(i))
		bg.mouse_entered.connect(func() -> void: fp.locker_sel = i)
		panel.add_child(bg)
		var nm := _label("", UiTheme.T_CAPTION, UiTheme.TEXT)
		nm.position = Vector2(6.0, 1.0)
		bg.add_child(nm)
		var inf := _label("", UiTheme.T_CAPTION - 1, UiTheme.MUTED)
		inf.position = Vector2(92.0, 2.0)
		bg.add_child(inf)
		_rows.append({"bg": bg, "name": nm, "info": inf, "w": int(ids[i])})
	_foot = _label("", UiTheme.T_CAPTION - 1, UiTheme.MUTED)
	_foot.position = Vector2(10.0, h - 13.0)
	panel.add_child(_foot)

func _label(t: String, size: int, c: Color) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", c)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

## Lista na ekranie znika od razu (wyjście ze strzelnicy — range_view.release; `tick` już wtedy nie biegnie).
func hide_ui() -> void:
	_ui.visible = false

func _on_row_input(ev: InputEvent, i: int) -> void:
	if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		fp.locker_pick(i)

## Co klatkę (range_view._process): bronie z szafy w rękach gracza znikają ze stojaka; lista z zaznaczeniem, gdy szafa otwarta.
func tick() -> void:
	var wc = fp.player.weapons
	var own: Array = (fp._kit.get("loadout", []) as Array)
	for w in _guns:
		(_guns[w] as Node3D).visible = not (wc.carries(int(w)) and not own.has(int(w)))
	_ui.visible = bool(fp.locker_open)
	if not _ui.visible:
		return
	var held := int(wc.cur().id)
	for i in _rows.size():
		var r: Dictionary = _rows[i]
		var w := int(r["w"])
		var d = Weapons.def(w)
		(r["bg"] as ColorRect).color = Color(UiTheme.ACCENT, 0.28) if i == int(fp.locker_sel) else Color(0.0, 0.0, 0.0, 0.0)
		(r["name"] as Label).text = String(d.name)
		var info := tr("in hand") if w == held else (tr("yours") if own.has(w) else "")
		(r["info"] as Label).text = ("%s  ·  %s" % [_kind(d), info]) if info != "" else _kind(d)
	_foot.text = tr("%s/%s choose  ·  %s take  ·  %s close") % [Actions.key("menu_up"), Actions.key("menu_down"), Actions.key("menu_accept"), Actions.key("range_locker")]

## Krótki opis broni w wierszu: kaliber i magazynek albo rodzaj broni specjalnej.
func _kind(d) -> String:
	if d.is_continuous():
		return tr("beam") if d.kind == WeaponDef.Kind.BEAM else tr("flame")
	if d.kind == WeaponDef.Kind.RAIL:
		return tr("rail")
	if String(d.caliber) == "":
		return tr("%d rds") % int(d.mag)                        # mikrorakiety, harpun — bez kalibru naboju
	return tr("%s · %d rds") % [String(d.caliber), int(d.mag)]
