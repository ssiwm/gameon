extends Control
## Oględziny broni ([F] przy broni na stojaku albo na ziemi; weapon_controller.gd: _tick_inspect). Widok 3D przechodzi w tym czasie do widoku
## z oczu gracza (view3d.gd: _sync_camera), a ten ekran kładzie na niego trzy warstwy: rozmycie i przyciemnienie tła, broń unoszącą się przed
## oczami (model 3D pod jedną ciepłą, migoczącą lampą — obracasz ją myszą z wciśniętym przyciskiem albo prawym drążkiem) oraz po prawej panel
## ze statystykami: ta broń i broń trzymana w ręku. Gra się nie zatrzymuje (co-op): [F] zamyka, [E] bierze broń, odejście albo trafienie
## też zamyka. Zablokowana broń (kryjówka, nie kupiona w warsztacie) zostaje w półmroku z czerwoną kontrą i warunkiem odblokowania.

const UiTheme := preload("res://scripts/ui_theme.gd")
const Codex := preload("res://scripts/codex.gd")
const Weapons := preload("res://scripts/weapons.gd")
const GunModel := preload("res://scripts/gun_model.gd")
const Parts := preload("res://scripts/parts.gd")
const Char3D := preload("res://scripts/char3d.gd")

const GUN_DIR := "res://art/char3d/"
const VIEW_PX := Vector2i(1280, 800)          ## rozdzielczość warstwy z bronią
const LAMP := Color(1.0, 0.78, 0.5)
const BLUR_SHADER := "shader_type canvas_item;
uniform sampler2D screen : hint_screen_texture, filter_linear_mipmap;
uniform float amount = 0.0;
void fragment() {
	vec3 c = textureLod(screen, SCREEN_UV, amount * 3.6).rgb;
	float vig = smoothstep(0.25, 0.95, distance(SCREEN_UV, vec2(0.5)));
	COLOR = vec4(c * mix(1.0, 0.42, amount) * (1.0 - 0.55 * vig * amount), 1.0);
}
"

var level := 0.0                              ## 0..1: wygładzone otwarcie (rozmycie tła, przezroczystość broni i panelu)
var _open := false
var _blur: ColorRect
var _blur_mat: ShaderMaterial
var _vp: SubViewport
var _view: TextureRect
var _pivot: Node3D
var _model: Node3D
var _lamp: SpotLight3D
var _rim: OmniLight3D
var _panel: PanelContainer
var _title: Label
var _tag: Label
var _lock: Label
var _grid: GridContainer
var _note: Label
var _foot: Label
var _key := ""                                ## co jest pokazane: id broni, blokada i broń w ręku (zmiana = przebudowa treści)
var _t := 0.0
var _yaw := 0.0
var _pitch := 0.0
var _idle := 0.0                              ## s od ostatniego ręcznego obrotu (potem broń obraca się sama)
var _locked := false
var _cabinet := false                         ## oglądana broń wisi w gablocie (show_weapon)

func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# --- tło: rozmycie i przyciemnienie wszystkiego, co pod spodem (świat i HUD)
	_blur = ColorRect.new()
	_blur.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = BLUR_SHADER
	_blur_mat = ShaderMaterial.new()
	_blur_mat.shader = sh
	_blur.material = _blur_mat
	add_child(_blur)
	# --- broń: własny świat 3D na przezroczystym tle, jedna lampa z góry i chłodna kontra
	_vp = SubViewport.new()
	_vp.size = VIEW_PX
	_vp.own_world_3d = true
	_vp.transparent_bg = true
	_vp.msaa_3d = Viewport.MSAA_4X
	_vp.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	add_child(_vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.5, 0.6, 0.8)
	env.ambient_light_energy = 0.03
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	_vp.add_child(we)
	var cam := Camera3D.new()
	cam.fov = 30.0
	cam.position = Vector3(0.0, 0.0, 4.6)
	_vp.add_child(cam)
	_lamp = SpotLight3D.new()
	_lamp.light_color = LAMP
	_lamp.spot_range = 8.0
	_lamp.spot_angle = 36.0
	_lamp.position = Vector3(0.5, 2.2, 2.6)
	_vp.add_child(_lamp)
	_lamp.look_at(Vector3.ZERO)
	_rim = OmniLight3D.new()
	_rim.omni_range = 5.0
	_rim.position = Vector3(-1.4, 0.6, -1.8)
	_vp.add_child(_rim)
	_pivot = Node3D.new()
	_vp.add_child(_pivot)
	_view = TextureRect.new()
	_view.texture = _vp.get_texture()
	_view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_view.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_view)
	# --- panel po prawej: nazwa, rodzaj, blokada, statystyki (ta broń | w ręku), opis, klawisze
	_panel = PanelContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.022, 0.024, 0.024, 0.9)
	box.border_color = UiTheme.LAMP_LINE
	box.set_border_width_all(1)
	box.border_width_bottom = 2
	box.set_content_margin_all(8)
	_panel.add_theme_stylebox_override("panel", box)
	add_child(_panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	col.custom_minimum_size = Vector2(178.0, 0.0)
	_panel.add_child(col)
	_title = UiTheme.label("", 16, UiTheme.WARM)
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
	_note.custom_minimum_size = Vector2(178.0, 0.0)
	col.add_child(_note)
	_foot = UiTheme.label("", 7, UiTheme.ACCENT)
	col.add_child(_foot)

## Pokazuje broń `wid`; `hand` = broń, którą zastąpi (−1 = brak porównania), `lock_text` = warunek odblokowania ("" = dostępna).
## `cabinet`: broń z gabloty — kamera patrzy na samą gablotę (view3d.gd), więc bez rozmycia tła i bez broni unoszącej się przed oczami.
func show_weapon(wid: int, gun_key: String, hand: int, lock_text: String, foot: String, cabinet := false) -> void:
	_cabinet = cabinet
	var key := "%d|%d|%s|%s|%d|%d" % [wid, hand, lock_text, gun_key, Profile.fit_code(wid) if Weapons.is_valid(wid) else 0,
		int(Profile.condition(String(Weapons.def(wid).key))) if Weapons.is_valid(wid) else 100]
	if Weapons.is_valid(wid):
		key += "|%d" % Profile.kills(String(Weapons.def(wid).key))
	if key != _key:
		_key = key
		_fill(wid, gun_key, hand, lock_text)
	_foot.text = foot
	if not _open:
		_open = true
		_yaw = -0.5
		_pitch = 0.08
		_idle = 9.0
	visible = true

func close() -> void:
	_open = false

## Broń w oględzinach pokazujemy taką, jaką ma ten gracz: z jego częściami (statystyki i model — gun_model.gd).
func _fill(wid: int, gun_key: String, hand: int, lock_text: String) -> void:
	var fit: int = Profile.fit_code(wid) if Weapons.is_valid(wid) else 0
	var d: RefCounted = Weapons.def_build(wid, Weapons.build_of(0, fit))
	_locked = lock_text != ""
	_title.text = String(d.name)
	_title.add_theme_color_override("font_color", UiTheme.MUTED if _locked else UiTheme.WARM)
	_tag.text = Codex._slot_name(d)
	if Settings.reliability_mult() > 0.0 and not d.is_melee():
		_tag.text += tr("  ·  CONDITION %d%%") % int(Profile.condition(String(d.key)))     # stan techniczny (etap 4a): poniżej 70 % broń się zacina
	if Profile.kills(String(d.key)) > 0:
		_tag.text += tr("  ·  KILLS %d") % Profile.kills(String(d.key))           # historia broni (etap 5b)
		if Profile.notches(String(d.key)) > 0:
			_tag.text += tr("  ·  NOTCHES %d") % Profile.notches(String(d.key))
	if Profile.mastery_level(String(d.key)) > 0:
		_tag.text += tr("  ·  MASTERY %s") % ["0", "I", "II", "III", "IV", "V"][Profile.mastery_level(String(d.key))]     # wprawa (etap 5a)
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
		for r in Codex._weapon_stats(Weapons.def_build(hand, Weapons.build_of(0, Profile.fit_code(hand)))):
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
		_model = GunModel.build(gun_key, Parts.decode(gun_key, fit if String(d.key) == gun_key else 0), Char3D.gun_info(gun_key)["muzzle"],
			Profile.notches(gun_key), Profile.boss_notches(gun_key))
	if _model != null:
		_pivot.add_child(_model)
		var box := AABB()
		var first := true
		var inv := _model.global_transform.affine_inverse()        # ramka w układzie modelu — oś obrotu po poprzednich oględzinach nie stoi w zerze
		for mi in _model.find_children("*", "MeshInstance3D", true, false):
			var ab: AABB = (inv * (mi as MeshInstance3D).global_transform) * (mi as MeshInstance3D).get_aabb()
			box = ab if first else box.merge(ab)
			first = false
		var longest := maxf(maxf(box.size.x, box.size.y), box.size.z)
		if longest > 0.0001:
			var k := 3.0 / longest                             # modele mają zapas w ramce (uchwyty) — skala dobrana do kadru
			_model.scale = Vector3(k, k, k)
			_model.position = -box.get_center() * k
	_panel.reset_size()

## Obrót myszą z wciśniętym przyciskiem (strzał jest w oględzinach wyłączony — weapon_controller.gd).
func _input(event: InputEvent) -> void:
	if not _open:
		return
	if event is InputEventMouseMotion and (event as InputEventMouseMotion).button_mask != 0:
		var rel := (event as InputEventMouseMotion).relative
		_yaw += rel.x * 0.008
		_pitch = clampf(_pitch + rel.y * 0.006, -1.1, 1.1)
		_idle = 0.0

func _process(delta: float) -> void:
	level = move_toward(level, 1.0 if _open else 0.0, delta * 4.0)
	if level <= 0.0 and not _open:
		visible = false
		return
	_t += delta
	_idle += delta
	var stick := Vector2(Input.get_joy_axis(0, JOY_AXIS_RIGHT_X), Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y))
	if stick.length() > 0.25:
		_yaw += stick.x * delta * 2.6
		_pitch = clampf(_pitch + stick.y * delta * 1.8, -1.1, 1.1)
		_idle = 0.0
	if _idle > 1.5:
		_yaw += delta * 0.4                                    # nikt nie obraca: broń kręci się sama
	var e := smoothstep(0.0, 1.0, level)
	_blur_mat.set_shader_parameter("amount", e * (0.0 if _cabinet else 1.0))
	# broń wypływa z dołu i lekko się kołysze, jakby wisiała w powietrzu przed oczami
	_pivot.rotation = Vector3(_pitch + 0.03 * sin(_t * 0.9), _yaw, 0.02 * sin(_t * 0.6))
	_pivot.position = Vector3(0.0, 0.05 * sin(_t * 1.1) - 0.5 * (1.0 - e), 0.0)
	_view.modulate.a = 0.0 if _cabinet else e
	_panel.modulate.a = e
	# układ: tło na cały ekran, broń zajmuje lewą i środkową część, panel stoi przy prawej krawędzi
	_blur.position = Vector2.ZERO
	_blur.size = size
	_panel.position = Vector2(size.x - _panel.size.x - 14.0 + 12.0 * (1.0 - e), (size.y - _panel.size.y) * 0.42)
	_view.position = Vector2(0.0, size.y * 0.2)             # środek broni nieco poniżej środka ekranu — na wysokości rąk, nie nad głową
	_view.size = Vector2(_panel.position.x - 6.0, size.y * 0.74)
	# lampa: nieregularne migotanie i rzadkie przygaśnięcia
	var f := 0.9 + 0.1 * sin(_t * 9.0) * sin(_t * 3.7)
	if fposmod(_t, 5.3) < 0.09 and Settings.fx_mult() > 0.0:
		f *= 0.45
	_lamp.light_energy = (1.6 if _locked else 12.0) * f
	_rim.light_color = Color(0.9, 0.12, 0.08) if _locked else Color(0.45, 0.6, 0.9)
	_rim.light_energy = 1.8 if _locked else 0.9
