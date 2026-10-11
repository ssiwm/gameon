extends PanelContainer
## Oględziny broni (krótkie [E] przy broni na stojaku albo na ziemi): ciemny panel z modelem 3D broni obracającym się pod jedną ciepłą lampą
## i statystykami obok — kolumna tej broni i kolumna broni trzymanej w ręku. Gra się nie zatrzymuje (co-op): odejście od broni albo drugie [E]
## zamyka panel, przytrzymanie [E] bierze broń (weapon_controller.gd: _tick_take). Model obraca się sam, a ruch celownika w poziomie go dokręca.
## Zablokowana broń (kryjówka, nie kupiona w warsztacie) stoi w półmroku, z czerwoną poświatą i ceną.

const UiTheme := preload("res://scripts/ui_theme.gd")
const Codex := preload("res://scripts/codex.gd")
const Weapons := preload("res://scripts/weapons.gd")

const GUN_DIR := "res://art/char3d/"
const VIEW_PX := Vector2i(560, 380)           ## rozdzielczość podglądu 3D
const VIEW_SIZE := Vector2(150.0, 102.0)      ## rozmiar podglądu w jednostkach HUD
const LAMP := Color(1.0, 0.78, 0.5)

var _vp: SubViewport
var _pivot: Node3D
var _model: Node3D
var _lamp: SpotLight3D
var _rim: OmniLight3D
var _title: Label
var _tag: Label
var _lock: Label
var _grid: GridContainer
var _note: Label
var _foot: Label
var _key := ""                                ## co jest pokazane: id broni, blokada i broń w ręku (zmiana = przebudowa treści)
var _t := 0.0
var _spin := 0.0
var _locked := false

func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.022, 0.024, 0.024, 0.96)
	box.border_color = UiTheme.LAMP_LINE
	box.set_border_width_all(1)
	box.border_width_bottom = 2
	box.set_content_margin_all(7)
	add_theme_stylebox_override("panel", box)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 9)
	add_child(row)
	# --- podgląd 3D: własny świat, jedna lampa z góry, ciemność dookoła
	_vp = SubViewport.new()
	_vp.size = VIEW_PX
	_vp.own_world_3d = true
	_vp.transparent_bg = false
	_vp.msaa_3d = Viewport.MSAA_4X
	_vp.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	add_child(_vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.012, 0.013, 0.014)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.5, 0.6, 0.8)
	env.ambient_light_energy = 0.02
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	_vp.add_child(we)
	var cam := Camera3D.new()
	cam.cull_mask = 3
	cam.fov = 30.0
	cam.position = Vector3(0.0, 0.18, 3.4)
	cam.rotation = Vector3(-0.05, 0.0, 0.0)
	_vp.add_child(cam)
	_lamp = SpotLight3D.new()
	_lamp.light_color = LAMP
	_lamp.spot_range = 6.0
	_lamp.spot_angle = 34.0
	_lamp.shadow_enabled = true
	_lamp.position = Vector3(0.35, 2.0, 2.2)
	_vp.add_child(_lamp)
	_lamp.look_at(Vector3.ZERO)
	_rim = OmniLight3D.new()                              # chłodna kontra zza broni: obrys w mroku
	_rim.omni_range = 4.0
	_rim.light_cull_mask = 1                               # tylko broń — blat zostaje w świetle lampy
	_rim.position = Vector3(-1.2, 0.5, -1.6)
	_vp.add_child(_rim)
	var floor_mi := MeshInstance3D.new()                    # ciemny blat pod bronią: plama światła i cień broni
	var pl := PlaneMesh.new()
	pl.size = Vector2(6.0, 6.0)
	floor_mi.mesh = pl
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.05, 0.043, 0.038)
	fm.roughness = 0.95
	floor_mi.material_override = fm
	floor_mi.position = Vector3(0.0, -0.62, 0.0)
	floor_mi.layers = 2
	_vp.add_child(floor_mi)
	_pivot = Node3D.new()
	_vp.add_child(_pivot)
	var view := TextureRect.new()
	view.texture = _vp.get_texture()
	view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	view.stretch_mode = TextureRect.STRETCH_SCALE
	view.custom_minimum_size = VIEW_SIZE
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(view)
	# --- treść: nazwa, rodzaj, blokada, statystyki (ta broń | w ręku), opis, podpowiedź klawiszy
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	col.custom_minimum_size = Vector2(176.0, 0.0)
	row.add_child(col)
	_title = UiTheme.label("", 15, UiTheme.WARM)
	if UiTheme.heading_font() != null:
		_title.add_theme_font_override("font", UiTheme.heading_font())
	col.add_child(_title)
	_tag = UiTheme.label("", 7, UiTheme.MUTED)
	col.add_child(_tag)
	_lock = UiTheme.label("", 8, UiTheme.DANGER)
	col.add_child(_lock)
	var rule := ColorRect.new()
	rule.color = UiTheme.LAMP_LINE
	rule.custom_minimum_size = Vector2(0.0, 1.0)
	col.add_child(rule)
	_grid = GridContainer.new()
	_grid.columns = 3
	_grid.add_theme_constant_override("h_separation", 10)
	_grid.add_theme_constant_override("v_separation", 0)
	col.add_child(_grid)
	_note = UiTheme.label("", 7, UiTheme.BONE_DIM)
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_note.custom_minimum_size = Vector2(176.0, 0.0)
	col.add_child(_note)
	_foot = UiTheme.label("", 7, UiTheme.ACCENT)
	col.add_child(_foot)

## Pokazuje broń `wid`; `hand` = broń, którą zastąpi (−1 = brak porównania), `lock_text` = warunek odblokowania ("" = dostępna).
func show_weapon(wid: int, gun_key: String, hand: int, lock_text: String, foot: String) -> void:
	var key := "%d|%d|%s|%s" % [wid, hand, lock_text, gun_key]
	if key != _key:
		_key = key
		_fill(wid, gun_key, hand, lock_text)
	_foot.text = foot
	if not visible:
		visible = true
		_spin = -0.45
		modulate.a = 0.0
		create_tween().tween_property(self, "modulate:a", 1.0, 0.18)

func close() -> void:
	visible = false

func _fill(wid: int, gun_key: String, hand: int, lock_text: String) -> void:
	var d: RefCounted = Weapons.def(wid)
	_locked = lock_text != ""
	_title.text = String(d.name)
	_title.add_theme_color_override("font_color", UiTheme.MUTED if _locked else UiTheme.WARM)
	_tag.text = Codex._slot_name(d)
	_lock.text = tr("LOCKED  ·  %s") % lock_text if _locked else ""
	_lock.visible = _locked
	var notes: Array = Codex.WEAPON_TEXT.get(String(d.key), ["", ""])
	_note.text = String(notes[0])
	for c in _grid.get_children():
		_grid.remove_child(c)
		c.queue_free()
	var other := {}
	var compare := hand >= 0 and hand != wid and Weapons.is_valid(hand)
	if compare:
		for r in Codex._weapon_stats(Weapons.def(hand)):
			other[String(r[0])] = String(r[1])
		_grid.add_child(UiTheme.label("", 6, UiTheme.MUTED))
		_grid.add_child(UiTheme.label("", 6, UiTheme.MUTED))
		_grid.add_child(UiTheme.label(tr("IN HAND") + "  " + String(Weapons.def(hand).name), 6, UiTheme.MUTED))
	for r in Codex._weapon_stats(d):
		_grid.add_child(UiTheme.label(tr(String(r[0])), 7, UiTheme.MUTED))
		_grid.add_child(UiTheme.label(String(r[1]), 7, UiTheme.TEXT))
		_grid.add_child(UiTheme.label(String(other.get(String(r[0]), "")) if compare else "", 7, UiTheme.BONE_DIM))
	# model broni: wyśrodkowany i dopasowany do kadru
	if _model != null and is_instance_valid(_model):
		_model.queue_free()
	_model = null
	var path := GUN_DIR + "gun_%s.glb" % gun_key
	if gun_key != "" and ResourceLoader.exists(path):
		var ps := load(path) as PackedScene
		if ps != null:
			_model = ps.instantiate() as Node3D
	if _model != null:
		_pivot.add_child(_model)
		var box := AABB()
		var first := true
		for mi in _model.find_children("*", "MeshInstance3D", true, false):
			var ab: AABB = (mi as MeshInstance3D).global_transform * (mi as MeshInstance3D).get_aabb()
			box = ab if first else box.merge(ab)
			first = false
		var longest := maxf(maxf(box.size.x, box.size.y), box.size.z)
		if longest > 0.0001:
			var k := 2.7 / longest                             # modele mają zapas w ramce (uchwyty) — skala dobrana do kadru
			_model.scale = Vector3(k, k, k)
			_model.position = -box.get_center() * k
	reset_size()

func _process(delta: float) -> void:
	if not visible:
		return
	_t += delta
	_spin += delta * 0.4
	var mx := 0.0
	var vs := get_viewport().get_visible_rect().size
	if vs.x > 0.0:
		mx = clampf(get_viewport().get_mouse_position().x / vs.x - 0.5, -0.5, 0.5)
	_pivot.rotation = Vector3(0.12 * sin(_t * 0.7), _spin + mx * 2.4, 0.0)
	# lampa: nieregularne migotanie i rzadkie przygaśnięcia; zablokowana broń zostaje w półmroku z czerwoną kontrą
	var f := 0.9 + 0.1 * sin(_t * 9.0) * sin(_t * 3.7)
	if fposmod(_t, 5.3) < 0.09 and Settings.fx_mult() > 0.0:
		f *= 0.45
	_lamp.light_energy = (1.5 if _locked else 11.0) * f
	_rim.light_color = Color(0.9, 0.12, 0.08) if _locked else Color(0.45, 0.6, 0.9)
	_rim.light_energy = 1.6 if _locked else 0.7
