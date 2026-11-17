extends Control
## Tło ekranów startowych (menu główne, lobby): nocny las z żywą mgłą, wąska ścieżka do radiostacji z masztem (`menu_forest.gd`,
## scena 3D we własnym świecie, jedna kopia dla menu i lobby). Do czasu zbudowania sceny — i na stałe w trybie zgodności (OpenGL
## bez mgły wolumetrycznej) oraz headless — stoi statyczny kadr tej samej sceny (`art/menu/backdrop.jpg`: `tools/menu_forest_shot.gd`
## → `tools/menu_backdrop.py`) z powolnym najazdem i dwiema warstwami mgły dryfującej w poziomie; gotowa scena przenika się z nim
## w `FADE_S`. Obraz kryje cały ekran (cover). „Reduce effects" zatrzymuje ruch (scena: mgła, światła, kamera; kadr: najazd i mgła).
## Ruchome warstwy kadru (`_pan`, pasy mgły) to Node2D, nie Control: kontrolki mają pozycję zaokrąglaną do piksela bazowego widoku
## (`gui/common/snap_controls_to_pixels`, baza 640×360 → 3 px ekranu w 1080p, 6 px w 4K), więc najazd i mgła szły skokami.

const MenuForest := preload("res://scripts/menu_forest.gd")
const BACKDROP := preload("res://art/menu/backdrop.jpg")
const FOG := preload("res://art/menu/fog.png")
const IMG := Vector2(2560, 1440)
const FOCUS_UV := Vector2(0.62, 0.55)  ## punkt, na który najeżdża kamera kadru: okno radiostacji (zostaje w miejscu na ekranie)
const DOLLY := 0.035                   ## najazd 1,0 → 1,035
const DOLLY_S := 50.0                  ## s na przejście w jedną stronę (tam i z powrotem, ease in-out)
const FOG_LOW_K := Vector2(1.6, 1.4)   ## skala kafelka mgły przy ziemi
const FOG_HIGH_K := Vector2(2.4, 2.0)  ## … i między drzewami
const FADE_S := 1.2                    ## przenikanie kadru w żywą scenę
const RENDER_SCALE := [0.6, 0.75, 0.85] ## skala renderu sceny wg jakości (LOW / MEDIUM / HIGH); mgła i noc są miękkie

var _t := 0.0
var _cover := 1.0
var _base := Vector2.ZERO              ## lewy górny róg obrazu przy skali `_cover` (obraz wyśrodkowany)
var _screen := Vector2.ZERO
var _pan: Node2D
var _fog_low: Node2D
var _fog_high: Node2D
var _live: TextureRect                 ## obraz sceny 3D (`menu_forest.gd`), nad kadrem
var _forest: SubViewport
var _active := false                   ## ten ekran pokazuje scenę (liczy się w `set_active` sceny)

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	_pan = Node2D.new()
	add_child(_pan)
	var art := TextureRect.new()
	art.texture = BACKDROP
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS   # przy 720p obraz jest pomniejszony o połowę
	art.size = IMG
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pan.add_child(art)
	_fog_high = _fog_layer(0.44, FOG_HIGH_K, Color(0.62, 0.70, 0.82, 0.07))
	_fog_low = _fog_layer(0.80, FOG_LOW_K, Color(0.62, 0.70, 0.80, 0.10))
	_live = TextureRect.new()
	_live.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_live.stretch_mode = TextureRect.STRETCH_SCALE
	_live.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_live.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_live.modulate.a = 0.0
	_live.visible = false
	add_child(_live)
	_apply()

func _ready() -> void:
	if MenuForest.supported():
		_forest = MenuForest.shared(get_tree())
		_live.texture = _forest.get_texture()
		_live.visible = true
		if bool(_forest.get("shown")):
			_live.modulate.a = 1.0              # lobby po menu: scena już stoi, bez przenikania
		_fit_forest()

func _exit_tree() -> void:
	_set_active(false)

## Pas mgły na wysokości `v` (0..1 kadru): kafelek fog.png powtarzany w poziomie, o kafelek szerszy niż kadr. Kafelki leżą
## nieruchomo w Node2D, który przesuwa _apply (pozycja Node2D nie jest zaokrąglana do piksela jak pozycja kontrolki).
func _fog_layer(v: float, k: Vector2, tint: Color) -> Node2D:
	var holder := Node2D.new()
	holder.position.y = v * IMG.y - FOG.get_height() * k.y * 0.5
	holder.scale = k
	holder.modulate = tint
	var f := TextureRect.new()
	f.texture = FOG
	f.stretch_mode = TextureRect.STRETCH_TILE
	f.mouse_filter = Control.MOUSE_FILTER_IGNORE
	f.size = Vector2(IMG.x / k.x + FOG.get_width() * 2.0, FOG.get_height())
	holder.add_child(f)
	_pan.add_child(holder)
	return holder

## Rozmiar tła dla okna o wymiarach `screen` (px): obraz kryje ekran, nadmiar przycinany po równo z obu stron.
func fit(screen: Vector2) -> void:
	position = Vector2.ZERO
	size = screen
	_screen = screen
	_cover = maxf(screen.x / IMG.x, screen.y / IMG.y)
	_base = (screen - IMG * _cover) * 0.5
	_live.position = Vector2.ZERO
	_live.size = screen
	_fit_forest()
	_apply()

func _fit_forest() -> void:
	if _forest != null and _screen.x > 0.0 and is_visible_in_tree():
		var q := clampi(int(Settings.quality_idx), 0, RENDER_SCALE.size() - 1)
		_forest.call("fit", _screen, float(RENDER_SCALE[q]))

func _set_active(on: bool) -> void:
	if _forest == null or on == _active or not is_instance_valid(_forest):
		return
	_active = on
	_forest.call("set_active", on)
	if on:
		_fit_forest()

func _process(delta: float) -> void:
	var vis := is_visible_in_tree()
	_set_active(vis)
	if not vis:
		return
	if _forest != null and bool(_forest.get("shown")) and _live.modulate.a < 1.0:
		_live.modulate.a = minf(_live.modulate.a + delta / FADE_S, 1.0)
	_pan.visible = _live.modulate.a < 1.0          # kadr pod gotową sceną nie musi się rysować
	if not _pan.visible:
		return
	if Settings.fx_mult() <= 0.0:
		if _t != 0.0:
			_t = 0.0
			_apply()
		return
	_t += delta
	_apply()

## Najazd (skala wokół FOCUS_UV, kadr dalej kryje ekran) i dryf mgły dla bieżącego `_t`.
func _apply() -> void:
	var still := Settings.fx_mult() <= 0.0
	var p := fposmod(_t, DOLLY_S * 2.0) / DOLLY_S
	var d := 0.0 if still else 0.5 - 0.5 * cos(PI * (p if p <= 1.0 else 2.0 - p))
	var s := _cover * (1.0 + DOLLY * d)
	var focus := FOCUS_UV * IMG
	_pan.scale = Vector2(s, s)
	_pan.position = _base + focus * (_cover - s)          # punkt FOCUS_UV stoi w miejscu, obraz rośnie wokół niego
	var fw := float(FOG.get_width())
	_fog_low.position.x = -fposmod(_t * 9.0, fw) * _fog_low.scale.x
	_fog_high.position.x = -fposmod(-_t * 5.0, fw) * _fog_high.scale.x
