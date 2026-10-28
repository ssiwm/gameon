extends Control
const Controller := preload("res://scripts/weapon_controller.gd")
## Wspólny panel siedmiu stanowisk: broń i części, konserwacja, prasa, pirotechnika, pracownia, tokarka oraz szafki.
## Lista broni odpowiada operacjom stanowiska; szczegóły porównują bieżący montaż z podglądem i pokazują pracę drużyny.
## Odblokowania i złom są wspólne, montaż prywatny; zakupy i dostawy rozstrzyga serwer (scrap.gd).
## Otwiera go workshop.gd ([E] przy ławie). Na czas panelu akcje gry są wycięte z InputMap (Settings.block_game_input), więc panel
## czyta własne akcje menu z rejestru (actions.gd: menu_left/right/up/down, menu_accept, menu_back, menu_tab, menu_slot_1/2 —
## klawiatura i D-pad / A / B / RB). Mysz: kafel wybiera, przycisk kupuje.

const UiTheme := preload("res://scripts/ui_theme.gd")
const Weapons := preload("res://scripts/weapons.gd")
const Codex := preload("res://scripts/codex.gd")
const Parts := preload("res://scripts/parts.gd")
const Throwables := preload("res://scripts/throwables.gd")
const ItemIcon := preload("res://scripts/item_icon.gd")
const PerkIcon := preload("res://scripts/perk_icon.gd")
const Perks := preload("res://scripts/perks.gd")
const GunIcon := preload("res://scripts/gun_icon.gd")
const GunStage := preload("res://scripts/gun_stage.gd")
const GunsmithPanel := preload("res://scripts/gunsmith_panel.gd")
const Look := preload("res://scripts/look.gd")
const Sprites := preload("res://scripts/sprites.gd")
const Char3D := preload("res://scripts/char3d.gd")
const Actions := preload("res://scripts/actions.gd")
const Ammo := preload("res://scripts/ammo.gd")
const WeaponDefinition := preload("res://scripts/weapon_def.gd")
const StationKit := preload("res://scripts/station_kit.gd")
const StationNoise := preload("res://scripts/station_noise.gd")
const VuMeter := preload("res://scripts/vu_meter.gd")
const HubProp := preload("res://scripts/hub_prop.gd")
const Weather := preload("res://scripts/weather.gd")
const SupplyArt := preload("res://scripts/station_supply_art.gd")
const NotePaletteRef := preload("res://scripts/note_palette.gd")
const ServiceArt := preload("res://scripts/station_service_art.gd")

const GOLD := Color(0.95, 0.8, 0.4)
const COLS := 2
const TILE_W := 150.0
const TILE_H := 46.0
const DETAIL_W := 270.0
## Dodatkowe pola zmieniane przez części, poza podstawową kartą. Jednostki symulacji: 16 px = 1 m.
const PART_METRICS := {
	"ammo_per_shot": ["Ammo per shot", "%d", 1.0], "arc_deg": ["Swing half arc", "%.1f°", 1.0],
	"arm_dist": ["Arming distance", "%.2f m", 1.0 / 16.0], "auto": ["Automatic fire", "bool", 1.0],
	"blast_damage": ["Blast damage", "%.1f", 1.0], "blast_radius": ["Blast radius", "%.2f m", 1.0 / 16.0],
	"charge_time": ["Charge time", "%.2f s", 1.0], "cluster": ["Cluster bomblets", "%d", 1.0],
	"execute_frac": ["Finisher threshold", "%.0f%%", 100.0], "falloff_start": ["Damage falloff starts", "%.2f m", 1.0 / 16.0],
	"flash_light": ["Flash light", "%.2f", 1.0], "flash_size": ["Flash radius", "%.2f m", 1.0 / 16.0],
	"homing": ["Tracking turn rate", "%.1f°/s", 180.0 / PI], "homing_cone": ["Acquisition cone", "%.1f°", 1.0],
	"homing_range": ["Acquisition range", "%.2f m", 1.0 / 16.0], "ignite": ["Burn duration", "%.2f s", 1.0],
	"knock": ["Impact push speed", "%.2f m/s", 1.0 / 16.0], "patch_every": ["Fire patch interval", "%.2f s", 1.0],
	"patch_life": ["Fire patch duration", "%.2f s", 1.0], "pull": ["Pull speed", "%.2f m/s", 1.0 / 16.0],
	"shake": ["Camera shake", "%.2f", 1.0], "speed": ["Projectile speed", "%.2f m/s", 1.0 / 16.0],
	"stun": ["Stun duration", "%.2f s", 1.0], "suppressor": ["Suppressor fitted", "bool", 1.0],
	"wall_pierce": ["Wall penetration", "%.2f m", 1.0 / 16.0],
}
## Karta prasy: modyfikatory naboju (ammo.gd) jako porównanie z nabojem zwykłym — [etykieta, kierunek (1: więcej = lepiej), zapis dodawania].
const AMMO_FIELDS := {
	"damage": ["Damage", 1, "num"], "speed": ["Bullet speed", 1, "num"], "pen": ["Penetration", 1, "num"], "armor_pen": ["Armour bypass", 1, "pct"],
	"falloff_start": ["Full-damage range", 1, "m"], "cam_kick": ["Recoil", -1, "num"], "wear": ["Gun wear", -1, "num"], "ignite": ["Sets on fire", 1, "s"],
	"knock": ["Knock-back", 1, "num"], "stun": ["Stun", 1, "s"], "crit_mult": ["Headshot bonus", 1, "num"],
}
## Dźwięk udanej operacji przy stanowisku (obok potwierdzenia UI): [nagranie, liczba wariantów; 0 = jedno bez numeru].
const STATION_SOUNDS := {"bench": ["mech_mag_in", 3], "service": ["mech_bolt_fwd", 3], "press": ["reload_shell", 3], "pyro": ["item_pickup", 0],
	"lab": ["reload_cell", 2], "lathe": ["mech_bolt_back", 2], "locker": ["item_pickup", 0]}
const FUSE_NAMES := ["SHORT", "MID", "LONG"]                 ## „MEDIUM” ma już tłumaczenie żeńskie (jakość efektów) — zapalnik jest męski
## Pracownia i tokarka: droga części broni specjalnej od próbek do montażu.
const LAB_STEPS := ["SAMPLES", "RESEARCH", "SCHEMATIC", "LATHE", "BENCH"]
## Gniazdo nazwane inaczej niż wspólne SLOT_NAMES, bo jego części siedzą gdzie indziej (PELLET-8: ładownica na komorze w gnieździe „stock”).
const SLOT_LABELS := {"srut8:stock": "Carrier"}
## Kolejność siatki: bronie od początku, potem do kupienia za złom, na końcu zablokowane do późniejszych stref.
const LIST := [Weapons.M83, Weapons.SPREAD12, Weapons.P64, Weapons.LR7, Weapons.HKM9, Weapons.SRUT8, Weapons.GNIEW4, Weapons.WIDMO1, Weapons.SOKOL6, Weapons.CIEGNO6, Weapons.MACZETA, Weapons.KILOF]

## Moneta złomu (8×8).
class Coin extends Control:
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(8, 8)
	func _draw() -> void:
		var gold := Color(0.95, 0.78, 0.32)
		var dark := Color(0.5, 0.36, 0.1)
		if UiTheme.hd_on():
			draw_circle(Vector2(4, 4), 4.0, dark)
			draw_circle(Vector2(4, 4), 3.2, gold)
			draw_arc(Vector2(4, 4), 2.1, 0.0, TAU, 20, dark, 0.8, true)
			draw_arc(Vector2(4, 4), 2.9, PI * 1.1, PI * 1.6, 8, Color(1, 0.95, 0.7), 0.9, true)
			return
		draw_rect(Rect2(2, 0, 4, 8), dark)
		draw_rect(Rect2(0, 2, 8, 4), dark)
		draw_rect(Rect2(2, 1, 4, 6), gold)
		draw_rect(Rect2(1, 2, 6, 4), gold)
		draw_rect(Rect2(3, 2, 2, 4), dark)

## Trzy kwadraciki poziomu ulepszeń.
class TierBar extends Control:
	var level := 0                ## odblokowane części broni
	var total := 3                ## wszystkie części broni (parts.gd)
	var maxed := false
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(26, 7)
	func _draw() -> void:
		for i in total:
			var r := Rect2(float(i) * 9.0, 0, 7, 7)
			if i < level:
				var fc := Color(0.45, 1.0, 0.55) if maxed else Color(1.0, 0.72, 0.28)
				if UiTheme.hd_on():
					UiTheme.pill(self, r, fc, true)
				else:
					draw_rect(r, fc)
			elif UiTheme.hd_on():
				UiTheme.pill(self, r, Color(UiTheme.BONE_DIM, 0.8), false)
			else:
				draw_rect(r, Color(UiTheme.BONE_DIM, 0.8), false, 1.0)

## Pasek na papierowej karcie (stan broni, zużycie części): ślad, wypełnienie i opcjonalna kreska granicy (np. do ilu czyszczenie przywróci stan).
class PaperBar extends Control:
	var frac := 0.0
	var cap := -1.0
	var col := UiTheme.INK
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(60, 6)
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), UiTheme.PAPER_SEL)
		draw_rect(Rect2(0, 0, roundf(size.x * clampf(frac, 0.0, 1.0)), size.y), col)
		if cap >= 0.0:
			var x := clampf(size.x * cap, 1.0, size.x - 1.0)
			draw_rect(Rect2(x - 0.75, -2.0, 1.5, size.y + 4.0), UiTheme.INK_COST)

## Kropka „nowe” (perk właśnie odblokowany, część, której gracz jeszcze nie oglądał) — kolor lampy z ciemnym obrysem.
class NewDot extends Control:
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(7, 7)
		size = Vector2(7, 7)
	func _draw() -> void:
		draw_circle(Vector2(3.5, 3.5), 3.5, Color(0, 0, 0, 0.6))
		draw_circle(Vector2(3.5, 3.5), 2.6, UiTheme.ACCENT)

## Wspólny kafel stanowisk (bronie, zaopatrzenie, perki, wygląd): miniatura po lewej, nazwa, jedna linia stanu (albo cena z monetą)
## i najwyżej jeden wskaźnik z kropek przy prawej krawędzi — zawsze z podpisem w linii stanu albo z podpowiedzią.
class CardTile extends Button:
	var icon_node: Control
	var name_label: Label
	var state_label: Label
	var coin: Coin
	var price_label: Label
	var bar: Control
	var _new_dot: NewDot
	func _init() -> void:
		focus_mode = Control.FOCUS_NONE
		toggle_mode = false
		custom_minimum_size = Vector2(150.0, 46.0)
	var lit := false
	var box_normal: StyleBox              ## własne tło kafla (pudełko na półce, przegroda skrzyni); null — kafel stanowiska
	var box_lit: StyleBox
	## Światło jako kursor (STATION_CARDS_PLAN.md §5): wybrany kafel stoi w snopie lampy, reszta jest przygaszona — miniatura ciemnieje,
	## nazwa i cena zostają czytelne. Bez pomarańczowej ramki.
	func set_lit(on: bool) -> void:
		lit = on
		var sbox: StyleBox = (box_lit if on else box_normal) if box_normal != null else UiTheme.tile_box("selected" if on else "normal")
		for st in ["normal", "pressed", "focus"]:
			add_theme_stylebox_override(st, sbox)
		if icon_node != null:
			icon_node.self_modulate = Color.WHITE if on else Color(0.6, 0.58, 0.55)
		queue_redraw()
	func _draw() -> void:
		if lit:
			draw_texture_rect(UiTheme.lamp_pool(), Rect2(Vector2(-size.x * 0.12, -size.y * 0.55), Vector2(size.x * 0.75, size.y * 1.9)), false)
	## Kropka „nowe” w prawym górnym rogu kafla.
	func set_new(on: bool) -> void:
		if on and _new_dot == null:
			_new_dot = NewDot.new()
			_new_dot.position = Vector2(custom_minimum_size.x - 11.0, 4.0)
			add_child(_new_dot)
		if _new_dot != null:
			_new_dot.visible = on
	## Kropki wskaźnika przy prawej krawędzi, w linii stanu (szerokość z liczby kropek).
	func place_bar() -> void:
		if bar == null:
			return
		var n := int(bar.get("maxn")) if bar.get("maxn") != null else int(bar.get("total"))
		var w := maxf(7.0, float(n) * 9.0 - 2.0)
		bar.custom_minimum_size.x = w
		bar.position = Vector2(custom_minimum_size.x - 6.0 - w, custom_minimum_size.y - 19.0)

## Kafel broni w siatce stanowiska: stan zależny od stanowiska (stan techniczny, ostrze, części) albo miejsce zakupu.
class Tile extends CardTile:
	var weapon := 0
	var marks: ServiceMarks

## Stół konserwacji, kafel broni: dwie ikonki części eksploatacyjnych przy prawej krawędzi — lufa (rura z wylotem) i sprężyny (zygzak).
## Stan 0 — ukryta, 1 — do wymiany (złoto), 2 — pilna (czerwień). Same wymiany: stan czyszczenia mówi linia STAN.
class ServiceMarks extends Control:
	var barrel := 0
	var springs := 0
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(30, 9)
		size = custom_minimum_size
	func _col(state: int) -> Color:
		return UiTheme.DANGER if state >= 2 else Color(0.95, 0.8, 0.4)          # złoto jak GOLD panelu
	func _draw() -> void:
		if barrel > 0:
			var c := _col(barrel)
			draw_rect(Rect2(0, 3, 11, 3), c)                          # rura lufy
			draw_rect(Rect2(10, 2, 2, 5), c)                          # wylot
		if springs > 0:
			var c2 := _col(springs)
			var pts := PackedVector2Array()
			for i in 7:
				pts.append(Vector2(17.0 + i * 2.0, 1.0 if i % 2 == 0 else 8.0))
			draw_polyline(pts, c2, 1.5)

## Kropki zapasu drużyny: `have` wypełnionych z `maxn` (jak kwadraciki poziomu ulepszeń broni).
class StockBar extends Control:
	var have := 0
	var maxn := 3
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(36, 7)
	func _draw() -> void:
		for i in maxn:
			var r := Rect2(float(i) * 9.0, 0, 7, 7)
			if i < have:
				var fc := Color(0.45, 1.0, 0.55) if have >= maxn else Color(1.0, 0.72, 0.28)
				if UiTheme.hd_on():
					UiTheme.pill(self, r, fc, true)
				else:
					draw_rect(r, fc)
			elif UiTheme.hd_on():
				UiTheme.pill(self, r, Color(UiTheme.BONE_DIM, 0.8), false)
			else:
				draw_rect(r, Color(UiTheme.BONE_DIM, 0.8), false, 1.0)

## Pasek poziomu profilu: wypełnienie = postęp XP w bieżącym poziomie.
class LevelBar extends Control:
	var frac := 0.0
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(0, 7)
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
	func _draw() -> void:
		if UiTheme.hd_on():
			UiTheme.pill(self, Rect2(Vector2.ZERO, size), Color(0.04, 0.05, 0.07, 0.9), true)
			if frac > 0.0:
				UiTheme.pill(self, Rect2(1, 1, maxf(size.y - 2.0, (size.x - 2.0) * frac), size.y - 2.0), Color(0.55, 0.8, 1.0), true)
			UiTheme.pill(self, Rect2(Vector2.ZERO, size), Color(UiTheme.BONE_DIM, 0.8), false)
			return
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.04, 0.05, 0.07, 0.9))
		draw_rect(Rect2(Vector2.ZERO, size), Color(UiTheme.BONE_DIM, 0.8), false, 1.0)
		draw_rect(Rect2(1, 1, maxf(0.0, (size.x - 2.0) * frac), size.y - 2.0), Color(0.55, 0.8, 1.0))

## Kafel perku w siatce: miniatura + nazwa + stan (poziom odblokowania / założony / dostępny).
## Podgląd postaci z arkusza HD (256×384 na klatkę): animowany (bieg/idle) w kafelku i w szczegółach zakładki LOOK. Arkusz ładowany leniwie (z mipmapami).
class LookView extends Control:
	var code := 0
	var anim := "idle"
	var _t := 0.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS

	func set_code(c: int) -> void:
		if c != code:
			code = c
			queue_redraw()

	func _process(delta: float) -> void:
		if is_visible_in_tree():
			_t += delta
			queue_redraw()

	func _draw() -> void:
		var sheet := Look.sheet(code)
		if not Sprites.has(sheet):
			return
		var man: Dictionary = Sprites.manifest()["sheets"][sheet]
		var an: Dictionary = man["anims"].get(anim, man["anims"]["idle"])
		var fr: Array = man["frame"]
		var frame := int(_t * float(an["fps"])) % maxi(1, int(an["frames"]))
		var tex := Sprites.mip_texture(Sprites.DIR + sheet + ".png")
		if tex == null:
			return
		var s := minf(size.x / float(fr[0]), size.y / float(fr[1]))
		var w := Vector2(float(fr[0]), float(fr[1])) * s
		draw_texture_rect_region(tex, Rect2(Vector2((size.x - w.x) * 0.5, size.y - w.y), w), Rect2(frame * fr[0], int(an["row"]) * fr[1], fr[0], fr[1]))

## Podgląd postaci 3D na żywo (gdy gra używa modeli 3D): ten sam render co w misji, ale w pełnej jakości (MSAA, cienie, rim, `ss` do 16)
## i na stole obrotowym — widać plecak, kieszenie, szwy i twarz. Z zakładką LOOK w warsztacie i (później) z lobby.
class Look3DView extends Control:
	var code := 0
	var _c3d: Node2D
	var _holder: Node2D
	var _t := 0.0
	var _name := ""

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		clip_contents = true
		custom_minimum_size = Vector2(0, 190)

	func _ready() -> void:
		_holder = Node2D.new()
		add_child(_holder)
		resized.connect(_layout)
		_layout()

	## Postać (22 j. świata) zajmuje ~92% wysokości kontrolki; `ss` renderu dobrany do rozmiaru na ekranie (tekstura ≥ 1 px na piksel).
	func _layout() -> void:
		if _holder == null:
			return
		var k := size.y * 0.92 / 22.0
		_holder.scale = Vector2(k, k)
		_holder.position = Vector2(size.x * 0.5, size.y * 0.97)

	func _want_ss() -> int:
		var px_per_unit := get_global_transform().get_scale().x * float(get_window().size.y) / 360.0
		var k := size.y * 0.92 / 22.0
		return clampi(int(ceil(k * px_per_unit)), 6, 16)

	func set_code(c: int) -> void:
		code = c
		var nm := Char3D.char_name_for(Look.gender_id(c), Look.outfit_id(c))
		if _c3d == null:
			_c3d = Char3D.new()
			_c3d.preview = true
			_c3d.preview_ss = _want_ss()
			_holder.add_child(_c3d)
			if not _c3d.setup(nm):
				_c3d.queue_free()
				_c3d = null
				return
			_name = nm
		elif nm != _name:
			_c3d.set_look(nm)
			_name = nm
		_c3d.set_palette(Look.palette_of(c))

	func _process(delta: float) -> void:
		if _c3d == null or not is_visible_in_tree():
			return
		_t += delta
		_c3d.set_view_yaw(fmod(_t * 28.0, 360.0))
		_c3d.update(delta, "idle", 1.0, Vector2(1.0, 0.0), 0.0, true, Color.WHITE)

## Kafel stroju (wyższy — postać na całą wysokość).
## Miniatura stroju z renderu modelu 3D (tools/bake_look_portraits.gd → art/portraits/look_<płeć>_<strój>.png), stopami na dole kafla.
class LookPortrait extends Control:
	var tex: Texture2D
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	func set_code(c: int) -> void:
		var path := "res://art/portraits/look_%s_%s.png" % [Look.gender_id(c), Look.outfit_id(c)]
		tex = load(path) as Texture2D if ResourceLoader.exists(path) else null
		queue_redraw()
	func _draw() -> void:
		if tex == null:
			return
		var ts := tex.get_size()
		var s := minf(size.x / ts.x, size.y / ts.y)
		var w := ts * s
		draw_texture_rect(tex, Rect2(Vector2((size.x - w.x) * 0.5, size.y - w.y), w), false)

## Kafel stroju (wyższy — postać na całą wysokość).
class LookTile extends CardTile:
	var code := 0
	var view: Control

## Kafel perku: stan (założony / dostępny / poziom odblokowania).
class PerkTile extends CardTile:
	var perk := ""

## Kafel zaopatrzenia: cena z monetą w linii stanu, kropki = zapas drużyny.
class SupplyTile extends CardTile:
	var kind := ""

var _open := false
var _page := 0                        ## 0 = ARMS (bronie i ulepszenia), 1 = SUPPLIES (granaty, miny, narzędzia), 2 = PERKS, 3 = LOOK
var _mode := "bench"                  ## „bench" — ława (ARMS, SUPPLIES), „locker" — szafki osobiste (PERKS, LOOK); od 1.7.349, WORKSHOP_PLAN.md W1
## „service" — stół konserwacji (od 1.7.350, W2): zakładka ARMS bez części i zestawów, tylko czyszczenie i części eksploatacyjne broni
## „press" — prasa elaboracyjna (od 1.7.354, W4): zakładka SUPPLIES z samą amunicją specjalną, zamówienia zamiast zakupu (Scrap.request_order)
## „pyro" — stół pirotechniczny (od 1.7.355, W4b): granaty, miny, ładunki i naboje 40 mm, klawisze 1 / 2 zmieniają zapalnik (ustawienie drużyny)
## „lab" — pracownia elektroniki i próbek (od 1.7.357, W6a): zakładka ARMS z samymi częściami broni specjalnych do zbadania (Scrap.request_research)
## „lathe" — tokarka i szlifierka (od 1.7.358, W6b): części broni specjalnych ze schematów (Scrap.request_machining) i ostrzenie broni białej
const MODE_PAGES := {"bench": [0, 1], "locker": [2, 3], "service": [0], "press": [1], "pyro": [1], "lab": [0], "lathe": [0]}
const MODE_GROUP := {"bench": "workshop", "locker": "locker_station", "service": "service_bench", "press": "press_bench", "pyro": "pyro_bench", "lab": "lab_bench",
	"lathe": "lathe_bench"}      ## grupa stanowiska: panel zamyka się, gdy gracz od niego odejdzie
const SERVICE_IDS := ["clean", "barrel", "springs"]
var _title: Label
var _sup_sel := 0
var _arms_body: HBoxContainer
var _sup_body: HBoxContainer
var _sup_tiles: Array = []            ## kafle zaopatrzenia (SupplyTile) — kolejność = _supply_kinds()
var _sup_grid: GridContainer          ## ława: siatka narzędzi
var _sup_left: VBoxContainer          ## lewa kolumna zaopatrzenia (siatka / regał / skrzynia)
var _shelves: VBoxContainer           ## prasa: regał, półka na kaliber
var _notch: Control                   ## prasa: ząbek etykiety partii pod wybranym pudełkiem
var _crate: PanelContainer            ## stół pirotechniczny: skrzynia z przegrodami
var _crate_grid: GridContainer
var _lid: PanelContainer              ## ramka karty zaopatrzenia (wieko skrzyni przy pirotechnice)
var _sup_paper: PanelContainer
var _dies: PanelContainer             ## prasa: matryce — miejsca na partie
var _dies_list: VBoxContainer
var _s_main: VBoxContainer            ## karta zaopatrzenia: kolumna główna
var _s_side: VBoxContainer            ## karta zaopatrzenia: druga kolumna (prasa — porównanie i hałas)
var _s_blast: Control                 ## pirotechnika: schemat działania w skali
var _s_cord: Control                  ## pirotechnika: lont o długości czasu zapalnika
var _s_icon: ItemIcon
var _s_title: Label
var _s_tag: Label
var _s_stats: GridContainer
var _s_text: Label
var _s_action: Button
var _sup_note: Label                  ## podpowiedź pod siatką zaopatrzenia ławy: gdzie kupić granaty, miny i amunicję
var _s_fuse: VBoxContainer            ## stół pirotechniczny: przełącznik krótki / średni / długi zapalnik (ustawienie drużyny)
var _s_cmp: VBoxContainer             ## prasa: porównanie naboju z nabojem zwykłym
var _s_queue: VBoxContainer           ## prasa: miejsca na partie (Scrap.PRESS_SLOTS)
var _page_btns: Array[Button] = []
var _look_body: HBoxContainer
var _look_sel := 0
var _look_pal := 0                          ## wybrana paleta kolorów (Look.PALETTES) w zakładce LOOK
var _pal_row: HBoxContainer
var _pal_btns: Array = []
var _look_tiles: Array = []
var _l_view: Control                  ## LookView (arkusz 2D)
var _l_view3: Control                 ## Look3DView (model 3D na żywo) — tworzony przy pierwszym użyciu
var _l_box: VBoxContainer
var _l_title: Label
var _l_tag: Label
var _l_text: Label
var _l_action: Button
var _perk_body: HBoxContainer
var _perk_sel := 0
var _perk_slot := 0
var _perk_tiles: Array = []
var _slot_chips: Array = []           ## [{root, icon, name, sub}] dla dwóch slotów
var _lvl_label: Label
var _lvl_bar: LevelBar
var _xp_label: Label
var _p_icon: PerkIcon
var _p_title: Label
var _p_tag: Label
var _p_stats: GridContainer
var _p_text: Label
var _p_action: Button
var _remembered: Dictionary = {}      ## osobny wybór broni dla każdego stanowiska
var _claiming := false
var _sel := 0
var _opt := 0                         ## kursor części w szczegółach broni (indeks w `_options`): klawisze 1 / 2 albo kliknięcie wiersza
var _clean_w := -1                    ## broń czyszczona teraz przy ławie (-1 — żadna); od 1.7.347 czyszczenie kosztuje czas, nie złom
var _clean_t := 0.0                   ## s od początku czyszczenia
var _clean_total := 0.0               ## s potrzebne na całe czyszczenie (Profile.clean_time w chwili startu)
var _prev_mouse := Input.MOUSE_MODE_VISIBLE
var _card: PanelContainer
var _wallet: Label
var _tiles: Array = []
var _svc_todo: Label                  ## stół konserwacji: co zrobić z każdą bronią (lewa kolumna pod kaflami)
var _svc_note: Control                ## kartka (SCRAWL) z listą do zrobienia, przypięta taśmą
var _arms_paper: PanelContainer       ## karta szczegółów broni (na stole konserwacji bez papieru — przyrządy na blacie)
var _gauges := {}                     ## stół konserwacji: przyrządy „clean” / „barrel” / „springs” (ServiceArt.Gauge)
var _hold_clean := false              ## czyszczenie trzymane klawiszem: puszczenie przerywa
var _perk_paper: PanelContainer       ## szafka: strona książeczki (SCRAWL) z opisem perka
var _book_stamps: Control             ## szafka: pieczątki poziomów w książeczce
var _book_photo: Control              ## szafka: zdjęcie przyklejone taśmą (portret założonego wyglądu)
var _p_vu: HBoxContainer              ## szafka: VU perka zmieniającego hałas (krzyk)
var _p_vu_meter: VuMeter
var _p_vu_text: Label
var _d_stage: Control                 ## ława 3D: wybrana broń z częściami, część spod kursora świeci i wysuwa się z gniazda (gun_stage.gd)
var _d_title: Label
var _d_tag: Label
var _d_panel: VBoxContainer           ## karta stanowiska: konserwacja — paski stanu i zużycia, pracownia / tokarka — droga części
var _d_stats: GridContainer
var _d_tiers: VBoxContainer
var _d_text: Label
var _action: Button
var _msg: Label
var _hint: RichTextLabel              ## taśma z klawiszami pod kartą (StationKit.tape_text)
var _plate: StationKit.StationPlate   ## tabliczka znamionowa stanowiska w nagłówku (tytuł `_title` w środku)
var _drum: StationKit.DrumCounter     ## licznik złomu z bębnami (`_wallet` zostaje jako ukryta etykieta z kwotą)
var _papers: Array = []               ## karty papierowe (PanelContainer) — pieczątka trafia na widoczną
var _s_vu: HBoxContainer              ## karta zaopatrzenia: VU-metr hałasu z podpisem (§5a)
var _s_vu_meter: VuMeter
var _s_vu_text: Label
var _knock_prev := 0.0                ## d7: poprzednia wartość knock_flash (zbocze = stuknięcie)
var _edge_flash: ColorRect            ## czerwony błysk od strony drzwi D-7
var _knock_label: Label               ## napis dźwięku z kierunkiem (nakładka poza układem karty)
var _msg_t := 0.0
var _bank_shown := -1                 ## kwota w portfelu na ekranie (odlicza do Scrap.bank po zakupie)
var _wallet_tween: Tween
var _workbench: GunsmithPanel
var _legacy_stage: GunStage
var _shade: ColorRect
var _bench_slot := ""
var _session := 0
var _selection_revision := 0
var _pending_part: Dictionary = {}
var _buying := -1

func _ready() -> void:
	add_to_group("workshop_ui")
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shade = ColorRect.new()
	_shade.color = Color(0.015, 0.018, 0.014, 0.65)
	_shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_shade.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_shade)
	_card = PanelContainer.new()
	_card.add_theme_stylebox_override("panel", UiTheme.station_box())
	_card.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_card)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 6)
	_card.add_child(root)
	# nagłówek: tytuł, portfel
	var head := HBoxContainer.new()
	_title = UiTheme.heading("WORKSHOP", 16, UiTheme.TEXT)
	_plate = StationKit.StationPlate.new(_title)
	head.add_child(_plate)
	var fill := Control.new()
	fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(fill)
	for pi in 4:
		var pb := Button.new()                                 # zakładki ARMS / SUPPLIES / PERKS / LOOK (Tab przełącza)
		pb.text = ["ARMS", "SUPPLIES", "PERKS", "LOOK"][pi]
		pb.toggle_mode = true
		pb.focus_mode = Control.FOCUS_NONE
		pb.add_theme_font_size_override("font_size", 9)
		pb.pressed.connect(_set_page.bind(pi))
		head.add_child(pb)
		_page_btns.append(pb)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(10, 0)
	head.add_child(gap)
	_wallet = UiTheme.label("", 11, GOLD, HORIZONTAL_ALIGNMENT_RIGHT)       # kwota w tekście (ukryta): licznik bębnowy pokazuje ją cyframi
	_wallet.visible = false
	head.add_child(_wallet)
	_drum = StationKit.DrumCounter.new()
	_drum.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_drum)
	root.add_child(head)
	root.add_child(_rule())
	# korpus: siatka broni | szczegóły
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	root.add_child(_scroll_body(body))
	_arms_body = body
	_sup_body = _build_supplies()
	root.add_child(_scroll_body(_sup_body))
	_sup_body.get_parent().visible = false
	_sup_body.visible = false
	_perk_body = _build_perks()
	root.add_child(_scroll_body(_perk_body))
	_perk_body.get_parent().visible = false
	_perk_body.visible = false
	_look_body = _build_look()
	root.add_child(_scroll_body(_look_body))
	_look_body.get_parent().visible = false
	_look_body.visible = false
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 10)
	body.add_child(left)
	var grid := GridContainer.new()
	grid.columns = COLS
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	left.add_child(grid)
	for i in LIST.size():
		var t := _make_tile(int(LIST[i]), i)
		grid.add_child(t)
		_tiles.append(t)
	_svc_todo = UiTheme.label("", 9, UiTheme.MUTED)                   # stół konserwacji: lista „do zrobienia” pod kaflami (puste miejsce przy kilku broniach)
	_svc_todo.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_svc_todo.custom_minimum_size.x = COLS * TILE_W - 24.0
	_svc_todo.visible = false
	var scrawl := NotePaletteRef.palette(NotePaletteRef.Note.SCRAWL)
	_svc_todo.add_theme_font_override("font", UiTheme.note_font(NotePaletteRef.Note.SCRAWL))   # kartka odręczna (ST-02): Caveat, atrament kartki
	_svc_todo.add_theme_font_size_override("font_size", UiTheme.note_size(NotePaletteRef.Note.SCRAWL, 10))
	_svc_todo.add_theme_color_override("font_color", scrawl["ink"])
	_svc_todo.add_theme_constant_override("outline_size", 0)
	_svc_note = ServiceArt.Scrawl.new()
	_svc_note.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_svc_note.visible = false
	_svc_note.add_child(_svc_todo)
	left.add_child(_svc_note)
	_arms_paper = _paper(_build_detail())
	body.add_child(_arms_paper)
	_legacy_stage = _d_stage as GunStage
	_workbench = GunsmithPanel.new()
	_workbench.custom_minimum_size = Vector2(606, 240)
	root.add_child(_workbench)
	_workbench.visible = false
	_workbench.weapon_selected.connect(_select)
	_workbench.slot_selected.connect(_pick_slot)
	_workbench.option_selected.connect(_pick_opt)
	_workbench.inspect_requested.connect(_inspect)
	_workbench.save_requested.connect(_save_current_preset)
	# Główna akcja zawsze pod ręką; przewija się treść, nie przycisk zakupu/montażu/odbioru.
	_action.reparent(root)
	_s_action.reparent(root)
	_s_action.visible = false
	for extra in [_p_action, _l_action]:
		extra.reparent(root)
		extra.visible = false
	root.add_child(_rule())
	_msg = UiTheme.label("", 9, UiTheme.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	root.add_child(_msg)
	var tape := PanelContainer.new()                     # taśma maskująca z klawiszami (§5): nazwy z rejestru akcji, klawisze w ramkach
	tape.add_theme_stylebox_override("panel", StationKit.tape_box())
	tape.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	tape.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(tape)
	_hint = RichTextLabel.new()
	_hint.bbcode_enabled = true
	_hint.fit_content = true
	_hint.scroll_active = false
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.custom_minimum_size.x = 606
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint.add_theme_font_size_override("normal_font_size", 8)
	_hint.add_theme_color_override("default_color", UiTheme.TEXT.darkened(0.08))
	_hint.text = StationKit.tape_text(_controls_hint())
	tape.add_child(_hint)
	_edge_flash = ColorRect.new()                        # pukanie do D-7: czerwony błysk od strony drzwi
	_edge_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_edge_flash.color = Color(UiTheme.DANGER, 0.0)
	add_child(_edge_flash)
	_knock_label = UiTheme.label("", 12, UiTheme.DANGER)
	_knock_label.modulate.a = 0.0
	add_child(_knock_label)
	Scrap.changed.connect(_refresh)
	Scrap.purchase_result.connect(_on_result)
	Scrap.supply_result.connect(_on_supply_result)
	Scrap.part_result.connect(_on_part_result)
	Scrap.service_result.connect(_on_service_result)
	Scrap.order_result.connect(_on_order_result)
	Scrap.research_result.connect(_on_research_result)
	Scrap.machining_result.connect(_on_machining_result)
	Profile.changed.connect(_refresh)
	Arsenal.stock_changed.connect(_refresh)
	multiplayer.server_disconnected.connect(_connection_lost)
	multiplayer.connection_failed.connect(_connection_lost)

## Zakładka SUPPLIES: ten sam układ co ARMS — siatka kafli po lewej (miniatura, nazwa, cena, zapas), szczegóły po prawej.
func _build_supplies() -> HBoxContainer:
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	body.custom_minimum_size = Vector2(0, 6.0 * (TILE_H + 6.0))            # tyle co ARMS — karta nie skacze przy przełączaniu
	var grid := GridContainer.new()
	grid.columns = COLS
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 8)
	left.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	body.add_child(left)
	left.add_child(grid)
	# pusty stan: na ławie zostały same narzędzia — reszta zaopatrzenia ma własne stanowiska
	_sup_note = UiTheme.label("", 8, UiTheme.MUTED)
	_sup_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_sup_note.custom_minimum_size.x = TILE_W * COLS + 6.0
	left.add_child(_sup_note)
	# prasa (ST-03): regał — półka na kaliber, pudełka na deskach; pod regałem etykieta partii z ząbkiem, matryce w kolumnie po prawej
	_shelves = VBoxContainer.new()
	_shelves.add_theme_constant_override("separation", 6)
	left.add_child(_shelves)
	_notch = SupplyArt.Notch.new()
	left.add_child(_notch)
	# stół pirotechniczny (ST-04): skrzynia saperska z magazynu Obiektu 86, przegrody 4 × 2, karta w otwartym wieku po prawej
	_crate = PanelContainer.new()
	_crate.add_theme_stylebox_override("panel", SupplyArt.wood_box(6))
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 5)
	_crate.add_child(cv)
	var stencil := UiTheme.mono(UiTheme.label("ЯЩИК № 4  ·  ВЗРЫВЧАТЫЕ ВЕЩЕСТВА  ·  НЕ БРОСАТЬ", 8, UiTheme.BONE_DIM, HORIZONTAL_ALIGNMENT_CENTER))
	stencil.add_theme_constant_override("outline_size", 0)
	cv.add_child(stencil)                                # napis na krawędzi skrzyni (sprzęt bunkra — cyrylica, D1a)
	_crate_grid = GridContainer.new()
	_crate_grid.columns = 4
	_crate_grid.add_theme_constant_override("h_separation", 5)
	_crate_grid.add_theme_constant_override("v_separation", 5)
	cv.add_child(_crate_grid)
	left.add_child(_crate)
	var rows := {}
	var kinds := _supply_kinds()
	for i in kinds.size():
		var k := String(kinds[i])
		var t := _make_supply_tile(k, i)
		_sup_tiles.append(t)
		if _is_press_kind(k):
			var cal := String(Ammo.from_kind(k)["cal"])
			if not rows.has(cal):
				rows[cal] = _make_shelf(cal)
			(rows[cal] as Control).get_meta("boxes").add_child(t)
		elif _is_pyro_kind(k):
			_crate_grid.add_child(t)
		else:
			grid.add_child(t)
	_sup_grid = grid
	_sup_left = left
	_lid = PanelContainer.new()                          # wieko skrzyni wokół karty (pirotechnika); gdzie indziej bez ramki
	_lid.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_sup_paper = _paper(_build_supply_detail())
	_lid.add_child(_sup_paper)
	body.add_child(_lid)
	_dies = PanelContainer.new()                         # prasa: matryce (miejsca na partie) pionowo po prawej
	_dies.add_theme_stylebox_override("panel", UiTheme.panel_box())
	_dies.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_dies_list = VBoxContainer.new()
	_dies_list.add_theme_constant_override("separation", 6)
	_dies_list.custom_minimum_size.x = 104
	_dies.add_child(_dies_list)
	body.add_child(_dies)
	return body

## Półka regału prasy dla kalibru `cal`: podpis kalibru nad półką, rząd pudełek, deska pod spodem.
func _make_shelf(cal: String) -> Control:
	var shelf := VBoxContainer.new()
	shelf.add_theme_constant_override("separation", 0)
	var cap := UiTheme.mono(UiTheme.label(String(Ammo.CALIBERS.get(cal, {}).get("name", cal)), 8, UiTheme.BONE_DIM))      # kaliber nad półką
	shelf.add_child(cap)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	shelf.add_child(row)
	var boxes := HBoxContainer.new()
	boxes.add_theme_constant_override("separation", 4)
	row.add_child(boxes)
	shelf.add_child(SupplyArt.Plank.new())
	shelf.set_meta("boxes", boxes)
	_shelves.add_child(shelf)
	return shelf

## Układ zakładki zaopatrzenia dla stanowiska: ława — siatka kafli i karta po prawej, prasa — regał, etykieta partii pod regałem
## i matryce po prawej, pirotechnika — skrzynia i karta w wieku. Kafle stoją na stałe w swoim pojemniku (rodzaj należy do jednego stanowiska).
func _arrange_supplies() -> void:
	var press := _mode == "press"
	var pyro := _mode == "pyro"
	_sup_grid.visible = not (press or pyro)
	_shelves.visible = press
	_notch.visible = press
	_crate.visible = pyro
	_dies.visible = press
	_s_icon.visible = not (press or pyro)                # prasa i skrzynia pokazują przedmiot na regale / w przegrodzie
	_lid.add_theme_stylebox_override("panel", SupplyArt.wood_box(6) if pyro else StyleBoxEmpty.new())
	var body := _sup_left.get_parent()
	if press and _lid.get_parent() != _sup_left:
		_lid.reparent(_sup_left)
	elif not press and _lid.get_parent() != body:
		_lid.reparent(body)
		body.move_child(_lid, 1)
	if press:
		_sup_left.move_child(_lid, _notch.get_index() + 1)
	_s_side.visible = press
	for n in [_s_vu, _s_cmp]:
		var want: Control = _s_side if press else _s_main
		if n.get_parent() != want:
			n.reparent(want)
			if not press:
				_s_main.move_child(n, _s_stats.get_index() + (1 if n == _s_vu else 3))
	_s_text.custom_minimum_size.x = 230.0 if press else DETAIL_W
	_s_main.custom_minimum_size.x = 230.0 if press else DETAIL_W

func _make_supply_tile(kd: String, idx: int) -> SupplyTile:
	if _is_press_kind(kd):
		return _make_box_tile(kd, idx)
	if _is_pyro_kind(kd):
		return _make_bay_tile(kd, idx)
	var data: Dictionary = Throwables.KINDS[kd]
	var t := SupplyTile.new()
	t.kind = kd
	var ic := ItemIcon.new()
	ic.k = 1.0
	ic.set_item(kd, Color.WHITE)
	_dress_tile(t, ic, String(data["name"]))
	_add_price(t)
	var bar := StockBar.new()
	bar.maxn = Throwables.units(kd, int(data["max"]))        # amunicja: w pudełkach
	_add_bar(t, bar)
	t.pressed.connect(_select_supply.bind(idx))
	return t

func _build_supply_detail() -> Control:
	var v := VBoxContainer.new()
	v.custom_minimum_size = Vector2(DETAIL_W, 0)
	v.add_theme_constant_override("separation", 4)
	_s_icon = ItemIcon.new()
	_s_icon.k = 2.0
	_s_icon.custom_minimum_size = Vector2(0, 58)
	v.add_child(_s_icon)
	_s_title = _ink_heading()
	v.add_child(_s_title)
	_s_tag = UiTheme.ink("", 8, UiTheme.INK_MUTED)
	v.add_child(_s_tag)
	_s_stats = GridContainer.new()
	_s_stats.columns = 3
	_s_stats.add_theme_constant_override("h_separation", 10)
	_s_stats.add_theme_constant_override("v_separation", 1)
	v.add_child(_s_stats)
	_s_vu = HBoxContainer.new()                           # VU-metr hałasu (§5a): ta sama skala co w HUD
	_s_vu.add_theme_constant_override("separation", 8)
	v.add_child(_s_vu)
	_s_vu_meter = VuMeter.new()
	_s_vu_meter.custom_minimum_size = Vector2(58, 34)
	_s_vu_meter.ticks = StationNoise.ticks()
	_s_vu.add_child(_s_vu_meter)
	_s_vu_text = UiTheme.ink("", 8)
	_s_vu_text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_s_vu_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_s_vu_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_s_vu.add_child(_s_vu_text)
	for box in ["_s_fuse", "_s_cmp", "_s_queue"]:
		var c := VBoxContainer.new()
		c.add_theme_constant_override("separation", 3)
		v.add_child(c)
		set(box, c)
	_s_blast = SupplyArt.BlastDiagram.new()               # pirotechnika: schemat działania w skali (za zapalnikiem)
	v.add_child(_s_blast)
	v.move_child(_s_blast, _s_fuse.get_index() + 1)
	v.add_child(_paper_rule())
	_s_text = UiTheme.ink("", 8)
	_s_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_s_text.custom_minimum_size = Vector2(DETAIL_W, 0)
	v.add_child(_s_text)
	_s_action = Button.new()
	_s_action.focus_mode = Control.FOCUS_NONE
	_s_action.add_theme_font_size_override("font_size", 10)
	_s_action.pressed.connect(_buy_selected_supply)
	v.add_child(_s_action)
	_s_main = v
	var cols := HBoxContainer.new()                       # druga kolumna tylko na etykiecie partii (prasa): porównanie i hałas
	cols.add_theme_constant_override("separation", 14)
	cols.add_child(v)
	_s_side = VBoxContainer.new()
	_s_side.add_theme_constant_override("separation", 6)
	_s_side.custom_minimum_size.x = 196
	_s_side.visible = false
	cols.add_child(_s_side)
	return cols

## Rodzaj z prasy (amunicja specjalna bez 40 mm) / ze stołu pirotechnicznego (granaty, miny, ładunki, 40 mm) — jak `_sup_in_mode`.
func _is_press_kind(k: String) -> bool:
	return Throwables.is_ammo(k) and String(Ammo.from_kind(k).get("cal", "")) != "40mm"

func _is_pyro_kind(k: String) -> bool:
	var m := String(Throwables.KINDS[k]["mode"])
	return m == "throw" or m == "place" or (Throwables.is_ammo(k) and not _is_press_kind(k))

## Prasa (ST-03): pudełko na półce regału — nazwa na etykiecie pudełka, pasek oznaczenia czubka, okienka z pudełkami przy sobie,
## cena na krawędzi półki. Wybór = światło lampy (bez ramki).
func _make_box_tile(kd: String, idx: int) -> SupplyTile:
	var data: Dictionary = Throwables.KINDS[kd]
	var t := SupplyTile.new()
	t.kind = kd
	t.custom_minimum_size = Vector2(86, 74)
	var face := SupplyArt.BoxFace.new()
	face.title = String(data["name"])
	face.stock_max = Throwables.units(kd, int(data["max"]))
	face.set_item(kd, Color.WHITE)
	_dress_tile(t, face, String(data["name"]))
	face.position = Vector2(4, 2)
	face.size = Vector2(78, 54)
	t.name_label.visible = false                         # nazwa jest na etykiecie pudełka
	t.state_label.visible = false
	_add_price(t)
	t.coin.position = Vector2(8, 60)
	t.price_label.position = Vector2(20, 57)
	var bar := StockBar.new()                            # zapas: okienka na pudełku (wskaźnik kafla ukryty, zostaje dla kodu odświeżania)
	bar.maxn = face.stock_max
	_add_bar(t, bar)
	bar.visible = false
	t.box_normal = StyleBoxEmpty.new()
	var lit := StyleBoxFlat.new()
	lit.bg_color = Color(1.0, 0.8, 0.45, 0.07)
	lit.border_color = UiTheme.LAMP_LINE
	lit.border_width_bottom = 2
	t.box_lit = lit
	for st in ["normal", "hover", "pressed", "disabled", "focus"]:
		t.add_theme_stylebox_override(st, t.box_normal if st != "hover" else lit)
	t.pressed.connect(_select_supply.bind(idx))
	return t

## Stół pirotechniczny (ST-04): przegroda skrzyni saperskiej — render przedmiotu pod lampą, licznik „przy sobie / maks.” w rogu,
## nazwa i cena na pasku jak napis na przegrodzie.
func _make_bay_tile(kd: String, idx: int) -> SupplyTile:
	var data: Dictionary = Throwables.KINDS[kd]
	var t := SupplyTile.new()
	t.kind = kd
	t.custom_minimum_size = Vector2(98, 96)
	var ic := ItemIcon.new()
	ic.plate = false
	ic.set_item(kd, Color.WHITE)
	_dress_tile(t, ic, String(data["name"]))
	ic.position = Vector2(8, 14)
	ic.size = Vector2(82, 56)
	var strip := ColorRect.new()
	strip.color = SupplyArt.LABEL_PAPER
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strip.position = Vector2(4, 74)
	strip.size = Vector2(90, 18)
	t.add_child(strip)
	t.move_child(strip, 0)
	t.name_label.position = Vector2(8, 75)
	t.name_label.add_theme_font_size_override("font_size", 9)
	t.state_label.position = Vector2(70, 2)              # „1/4” w rogu przegrody
	_add_price(t)
	t.coin.visible = false
	t.price_label.position = Vector2(66, 76)
	t.price_label.add_theme_font_size_override("font_size", 9)
	var bar := StockBar.new()
	bar.maxn = Throwables.units(kd, int(data["max"]))
	_add_bar(t, bar)
	bar.visible = false
	t.box_normal = SupplyArt.bay_box()
	var lit := SupplyArt.bay_box()
	lit.bg_color = Color("2a2216")
	lit.border_color = UiTheme.ACCENT.darkened(0.35)
	t.box_lit = lit
	for st in ["normal", "hover", "pressed", "disabled", "focus"]:
		t.add_theme_stylebox_override(st, t.box_normal if st != "hover" else lit)
	t.pressed.connect(_select_supply.bind(idx))
	return t

## Zakładka LOOK: siatka 2 × 3 (kolumny: mężczyzna / kobieta, wiersze: stroje) z animowanymi podglądami i szczegóły z przyciskiem Equip.
## Kod wyglądu kafla i = wiersz (strój) × 2 + kolumna (płeć). Stroje odblokowuje poziom profilu (Look.UNLOCK_LEVEL); wygląd jest tylko kosmetyką.
func _look_code(i: int) -> int:
	return Look.code(i % COLS, i / COLS)

func _build_look() -> HBoxContainer:
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	body.custom_minimum_size = Vector2(0, 6.0 * (TILE_H + 6.0))
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 6)
	left.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	body.add_child(left)
	var grid := GridContainer.new()
	grid.columns = COLS
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	left.add_child(grid)
	# kolumny siatki to płeć — ta sama nazwa stroju stoi w obu, więc kolumny mają podpis
	var heads := HBoxContainer.new()
	heads.add_theme_constant_override("separation", 6)
	for g in Look.GENDERS:
		var hl := UiTheme.label(tr(String(g).capitalize()).to_upper(), 8, UiTheme.MUTED, HORIZONTAL_ALIGNMENT_CENTER)
		hl.custom_minimum_size.x = TILE_W
		heads.add_child(hl)
	left.add_child(heads)
	left.move_child(heads, grid.get_index())
	for i in Look.GENDERS.size() * Look.OUTFITS.size():
		var t := LookTile.new()
		t.code = _look_code(i)
		t.custom_minimum_size = Vector2(TILE_W, TILE_H * 1.5)
		var portrait := "res://art/portraits/look_%s_%s.png" % [Look.gender_id(t.code), Look.outfit_id(t.code)]
		t.view = LookPortrait.new() if ResourceLoader.exists(portrait) else LookView.new()       # render 3D jak duży podgląd; bez niego stary arkusz
		t.view.call("set_code", t.code)
		_dress_tile(t, t.view, Look.display_name(t.code))
		t.pressed.connect(_select_look.bind(i))
		grid.add_child(t)
		_look_tiles.append(t)
	var v := VBoxContainer.new()
	v.custom_minimum_size = Vector2(DETAIL_W, 0)
	v.add_theme_constant_override("separation", 4)
	var lv := LookView.new()                              # podgląd 2D z arkusza; model 3D na żywo dochodzi w _refresh_look (Sprites.char3d bywa ustawione później)
	lv.anim = "run"
	lv.custom_minimum_size = Vector2(0, 150)
	_l_view = lv
	_l_box = v
	v.add_child(_l_view)
	_l_title = _ink_heading()
	v.add_child(_l_title)
	_l_tag = UiTheme.ink("", 8, UiTheme.INK_MUTED)
	v.add_child(_l_tag)
	_pal_row = HBoxContainer.new()                       # paleta kolorów stroju: tylko dla modeli 3D
	_pal_row.add_theme_constant_override("separation", 5)
	_pal_row.add_child(UiTheme.ink(tr("COLOR"), 8, UiTheme.INK_MUTED))
	for pi in Look.PALETTES.size():
		var pb := Button.new()
		pb.focus_mode = Control.FOCUS_NONE
		pb.custom_minimum_size = Vector2(20, 14)
		pb.tooltip_text = Look.palette_name(pi)
		pb.pressed.connect(_select_palette.bind(pi))
		_pal_row.add_child(pb)
		_pal_btns.append(pb)
	_pal_row.visible = false
	v.add_child(_pal_row)
	v.add_child(_paper_rule())
	_l_text = UiTheme.ink("", 8)
	_l_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_l_text.custom_minimum_size = Vector2(DETAIL_W, 0)
	v.add_child(_l_text)
	_l_action = Button.new()
	_l_action.focus_mode = Control.FOCUS_NONE
	_l_action.add_theme_font_size_override("font_size", 10)
	_l_action.pressed.connect(_act_look)
	v.add_child(_l_action)
	body.add_child(_paper(v))
	return body

func _select_palette(pi: int) -> void:
	_look_pal = pi
	Audio.play("ui_click", Audio.BUS_UI, -14.0)
	_refresh()

func _select_look(i: int) -> void:
	_look_sel = i
	Audio.play("ui_click", Audio.BUS_UI, -14.0)
	_refresh()

func _act_look() -> void:
	var c := Look.with_palette(_look_code(_look_sel), _look_pal)
	if Profile.look == c:
		_say(tr("Already wearing %s.") % Look.display_name(c), UiTheme.MUTED)
	elif Profile.set_look(c):
		_success_fx()
		_say(tr("%s (%s) equipped.") % [Look.display_name(c), tr(Look.gender_id(c).capitalize())], UiTheme.OK)
	else:
		_say(tr("Unlocks at level %d.") % Look.unlock_level(c), UiTheme.DANGER)

func _refresh_look() -> void:
	var lvl := Profile.level()
	var use3d := Sprites.char3d and Char3D.available()
	if use3d and _l_view3 == null:
		_l_view3 = Look3DView.new()
		_l_box.add_child(_l_view3)
		_l_box.move_child(_l_view3, _l_view.get_index())
	_l_view.visible = not use3d
	if _l_view3 != null:
		_l_view3.visible = use3d
	_pal_row.visible = use3d
	var vw: Control = _l_view3 if use3d else _l_view
	for i in _look_tiles.size():
		var t := _look_tiles[i] as LookTile
		var sel := i == _look_sel
		t.set_lit(sel)
		var ok := Look.is_unlocked(t.code, lvl)
		t.view.modulate = Color.WHITE if ok else Color(0.35, 0.4, 0.45)
		t.name_label.add_theme_color_override("font_color", UiTheme.ACCENT if sel else UiTheme.TEXT)
		var worn := Look.base(Profile.look) == t.code
		t.state_label.text = (tr("EQUIPPED") if worn else tr("AVAILABLE")) if ok else tr("LV %d") % Look.unlock_level(t.code)
		t.state_label.add_theme_color_override("font_color", UiTheme.OK if worn else (UiTheme.MUTED if ok else UiTheme.DANGER))
	for pi in _pal_btns.size():
		var pb := _pal_btns[pi] as Button
		var d: Dictionary = Look.PALETTES[pi]
		var pbox := StyleBoxFlat.new()
		pbox.bg_color = (d["swatch"] as Color) if lvl >= int(d["level"]) else (d["swatch"] as Color).darkened(0.65)
		pbox.border_color = UiTheme.INK if pi == _look_pal else Color(UiTheme.PAPER_EDGE, 0.8)
		pbox.set_border_width_all(2 if pi == _look_pal else 1)
		for st in ["normal", "hover", "pressed", "focus", "disabled"]:
			pb.add_theme_stylebox_override(st, pbox)
		var locked := lvl < int(d["level"])
		pb.text = str(int(d["level"])) if locked else ""                  # zablokowany kolor: numer poziomu na próbce (nie tylko ciemniejszy odcień)
		pb.add_theme_font_size_override("font_size", 7)
		for fc in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			pb.add_theme_color_override(fc, UiTheme.TEXT)
		pb.tooltip_text = Look.palette_name(pi) + ((" · " + tr("Locked — level %d") % int(d["level"])) if locked else "")
	var c := Look.with_palette(_look_code(_look_sel), _look_pal)
	vw.call("set_code", c)
	vw.modulate = Color.WHITE if Look.is_unlocked(c, lvl) else Color(0.35, 0.4, 0.45)
	_l_title.text = Look.display_name(c)
	_l_tag.text = tr("%s  ·  unlocks at level %d") % [tr(Look.gender_id(c).capitalize()).to_upper(), Look.unlock_level(c)]
	_l_text.text = tr(String(Look.OUTFIT_TEXT[Look.outfit_id(c)])) + "\n\n" + tr("Cosmetic only — other players see your look too.")
	_l_action.disabled = false
	_l_action.text = tr("Wearing") if Profile.look == c else (tr("Equip") if Look.is_unlocked(c, lvl) else tr("Locked — level %d") % Look.unlock_level(c))
	_act_state(_l_action, "ready" if Profile.look != c and Look.is_unlocked(c, lvl) else "wait", 0)      # założony albo zablokowany — ciemna dźwignia

## Zakładka PERKS: ten sam układ co ARMS i SUPPLIES — po lewej pasek poziomu, siatka kafli i dwa sloty, po prawej szczegóły wybranego perku.
func _build_perks() -> HBoxContainer:
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	body.custom_minimum_size = Vector2(0, 6.0 * (TILE_H + 6.0))
	# drzwi szafki osobistej (ST-07): blacha w zieleni munduru, szczeliny, na drzwiach zdjęcie, książeczka, naszywki perków i rzepy slotów
	var door := PanelContainer.new()
	door.add_theme_stylebox_override("panel", ServiceArt.locker_door())
	door.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	body.add_child(door)
	var vents := ServiceArt.Vents.new()
	door.add_child(vents)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 6)
	left.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	door.add_child(left)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	left.add_child(top)
	var photo := PanelContainer.new()                      # zdjęcie przyklejone taśmą: portret założonego wyglądu
	var pb := StyleBoxFlat.new()
	pb.bg_color = Color("1a1c17")
	pb.border_color = Color("8a8574")
	pb.set_border_width_all(2)
	pb.border_width_bottom = 6
	photo.add_theme_stylebox_override("panel", pb)
	photo.rotation_degrees = 2.5
	var lp := LookPortrait.new()
	lp.custom_minimum_size = Vector2(40, 52)
	photo.add_child(lp)
	_book_photo = lp
	top.add_child(photo)
	var book := ServiceArt.Scrawl.new()                     # książeczka wojskowa (SCRAWL): poziom, XP, pieczątki poziomów
	book.stains = false
	book.rotation_degrees = 0.0
	book.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(book)
	var bv := VBoxContainer.new()
	bv.add_theme_constant_override("separation", 1)
	book.add_child(bv)
	var bcap := UiTheme.ink(tr("SERVICE RECORD"), 7, UiTheme.INK_MUTED)
	bv.add_child(bcap)
	var lv := HBoxContainer.new()
	lv.add_theme_constant_override("separation", 6)
	_lvl_label = UiTheme.heading("LV 1", 12, UiTheme.INK)
	_lvl_label.add_theme_constant_override("outline_size", 0)
	lv.add_child(_lvl_label)
	_lvl_bar = LevelBar.new()
	_lvl_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	lv.add_child(_lvl_bar)
	_xp_label = UiTheme.ink("", 9, UiTheme.INK, HORIZONTAL_ALIGNMENT_RIGHT)
	lv.add_child(_xp_label)
	bv.add_child(lv)
	_book_stamps = ServiceArt.LevelStamps.new()
	bv.add_child(_book_stamps)
	var grid := GridContainer.new()
	grid.columns = COLS
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	left.add_child(grid)
	for i in Perks.ORDER.size():
		var t := _make_perk_tile(String(Perks.ORDER[i]), i)
		grid.add_child(t)
		_perk_tiles.append(t)
	var slots := HBoxContainer.new()
	slots.add_theme_constant_override("separation", 6)
	left.add_child(slots)
	for si in 2:
		slots.add_child(_make_slot_chip(si))
	_perk_paper = _paper(_build_perk_detail())             # strona książeczki: kartka odręczna (SCRAWL)
	var pp := UiTheme.paper_box()
	pp.bg_color = NotePaletteRef.palette(NotePaletteRef.Note.SCRAWL)["bg"]
	pp.border_color = NotePaletteRef.palette(NotePaletteRef.Note.SCRAWL)["edge"]
	_perk_paper.add_theme_stylebox_override("panel", pp)
	body.add_child(_perk_paper)
	return body

func _make_perk_tile(id: String, idx: int) -> PerkTile:
	var t := PerkTile.new()
	t.perk = id
	var ic := PerkIcon.new()
	ic.k = 1.0
	ic.set_perk(id, Color.WHITE)
	_dress_tile(t, ic, Perks.display_name(id))
	var col: Color = Perks.PERKS[id]["color"]              # naszywka: tkanina w kolorze perka z obszyciem
	t.box_normal = ServiceArt.patch_box(col, false)
	t.box_lit = ServiceArt.patch_box(col, true)
	for st in ["normal", "hover", "pressed", "disabled", "focus"]:
		t.add_theme_stylebox_override(st, t.box_lit if st == "hover" else t.box_normal)
	var stitch := ServiceArt.Stitch.new()
	stitch.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stitch.color = Color(col, 0.45)
	t.add_child(stitch)
	t.set_meta("stitch", stitch)
	t.pressed.connect(_select_perk.bind(idx))
	return t

## Slot perka (0–1) pod siatką: miniatura założonego perka, nazwa albo „empty” / poziom odblokowania. Klik albo klawisz 1 / 2 wybiera slot docelowy.
func _make_slot_chip(si: int) -> Control:
	var root := PanelContainer.new()
	root.custom_minimum_size = Vector2(150, 40)
	root.add_theme_stylebox_override("panel", UiTheme.tile_box("normal"))
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(ServiceArt.Velcro.new())               # slot = pasek rzepu na drzwiach (naszywka perka przypina się do niego)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	root.add_child(h)
	var ic := PerkIcon.new()
	ic.k = 1.0
	ic.custom_minimum_size = Vector2(40, 30)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(ic)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(col)
	var cap := UiTheme.label("SLOT %d  [%d]" % [si + 1, si + 1], 8, UiTheme.MUTED)
	col.add_child(cap)
	var nm := UiTheme.label("", 9, UiTheme.TEXT)
	col.add_child(nm)
	root.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			_perk_slot = si
			_refresh())
	_slot_chips.append({"root": root, "icon": ic, "name": nm})
	return root

func _build_perk_detail() -> Control:
	var v := VBoxContainer.new()
	v.custom_minimum_size = Vector2(DETAIL_W, 0)
	v.add_theme_constant_override("separation", 4)
	_p_icon = PerkIcon.new()
	_p_icon.k = 2.0
	_p_icon.custom_minimum_size = Vector2(0, 58)
	v.add_child(_p_icon)
	_p_title = _ink_heading()
	v.add_child(_p_title)
	_p_tag = UiTheme.ink("", 8, UiTheme.INK_MUTED)
	v.add_child(_p_tag)
	_p_stats = GridContainer.new()
	_p_stats.columns = 3
	_p_stats.add_theme_constant_override("h_separation", 10)
	_p_stats.add_theme_constant_override("v_separation", 1)
	v.add_child(_p_stats)
	_p_vu = HBoxContainer.new()
	_p_vu.add_theme_constant_override("separation", 8)
	v.add_child(_p_vu)
	_p_vu_meter = VuMeter.new()
	_p_vu_meter.custom_minimum_size = Vector2(58, 34)
	_p_vu_meter.ticks = StationNoise.ticks()
	_p_vu.add_child(_p_vu_meter)
	_p_vu_text = UiTheme.ink("", 8)
	_p_vu_text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_p_vu.add_child(_p_vu_text)
	v.add_child(_paper_rule())
	_p_text = UiTheme.ink("", 8)
	_p_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_p_text.custom_minimum_size = Vector2(DETAIL_W, 0)
	v.add_child(_p_text)
	_p_action = Button.new()
	_p_action.focus_mode = Control.FOCUS_NONE
	_p_action.add_theme_font_size_override("font_size", 10)
	_p_action.pressed.connect(_act_perk)
	v.add_child(_p_action)
	return v

func _select_perk(i: int) -> void:
	if i != _perk_sel:
		Audio.play("ui_click", Audio.BUS_UI, -14.0)
	_perk_sel = i
	_refresh()

## Które sloty zajmuje perk: indeks slotu albo -1.
func _perk_slot_of(id: String) -> int:
	return Profile.equipped.find(id)

## Akcja na wybranym perku: zdejmij (jeśli założony) albo załóż w wybranym slocie.
func _act_perk() -> void:
	var id := String(Perks.ORDER[_perk_sel])
	var have := _perk_slot_of(id)
	if have >= 0:
		Profile.unequip(have)
		_say(tr("%s removed.") % Perks.display_name(id), UiTheme.MUTED)
		Audio.play("ui_click", Audio.BUS_UI, -10.0)
		return
	if not Profile.is_unlocked(id):
		_say(tr("Reach level %d to unlock %s.") % [Perks.unlock_level(id), Perks.display_name(id)], UiTheme.MUTED)
		return
	if _perk_slot >= Profile.slots():
		_say(tr("Slot %d unlocks at level %d.") % [_perk_slot + 1, int(Profile.SLOT_LEVELS[_perk_slot])], UiTheme.MUTED)
		return
	if Profile.equip(_perk_slot, id):
		_say(tr("%s equipped in slot %d.") % [Perks.display_name(id), _perk_slot + 1], UiTheme.OK)
		_success_fx()

func _refresh_perks() -> void:
	var lp := Profile.level_progress()
	_lvl_label.text = "LV %d" % Profile.level()
	_lvl_bar.frac = clampf(float(lp[0]) / maxf(1.0, float(lp[1])), 0.0, 1.0)
	_lvl_bar.queue_redraw()
	_xp_label.text = "%d / %d XP" % [int(lp[0]), int(lp[1])]
	(_book_stamps as ServiceArt.LevelStamps).level = Profile.level()
	_book_stamps.queue_redraw()
	(_book_photo as LookPortrait).set_code(Look.base(Profile.look))
	if _perk_slot >= maxi(1, Profile.slots()):
		_perk_slot = 0
	Profile.mark_seen("perk:" + String(Perks.ORDER[_perk_sel]))       # perk pod kursorem jest obejrzany — kropka „nowe” gaśnie
	for i in _perk_tiles.size():
		var t := _perk_tiles[i] as PerkTile
		var id := t.perk
		var sel := i == _perk_sel
		t.set_lit(sel)
		var unlocked := Profile.is_unlocked(id)
		var at := _perk_slot_of(id)
		t.set_new(Profile.is_new("perk:" + id))
		(t.icon_node as PerkIcon).set_perk(id, Color.WHITE if unlocked else Color(0.45, 0.5, 0.55))
		var sti := t.get_meta("stitch") as ServiceArt.Stitch
		sti.foil = not unlocked                              # zablokowany perk w folii
		sti.queue_redraw()
		t.name_label.add_theme_color_override("font_color", UiTheme.ACCENT if sel else (UiTheme.TEXT if unlocked else UiTheme.MUTED))
		if at >= 0:
			t.state_label.text = tr("EQUIPPED  ·  SLOT %d") % (at + 1)
			t.state_label.add_theme_color_override("font_color", UiTheme.OK)
		elif unlocked:
			t.state_label.text = "AVAILABLE"
			t.state_label.add_theme_color_override("font_color", UiTheme.MUTED)
		else:
			t.state_label.text = "LV %d" % Perks.unlock_level(id)
			t.state_label.add_theme_color_override("font_color", GOLD if Profile.level() + 1 >= Perks.unlock_level(id) else UiTheme.DANGER)
	for si in _slot_chips.size():
		var c: Dictionary = _slot_chips[si]
		var open := si < Profile.slots()
		var eq := String(Profile.equipped[si])
		var chosen := si == _perk_slot
		var vb := StyleBoxFlat.new()                             # rzep: wybrany slot w świetle lampy
		vb.bg_color = Color(0, 0, 0, 0)
		vb.border_color = UiTheme.LAMP_LINE if chosen else Color("15170f")
		vb.set_border_width_all(2 if chosen else 1)
		vb.set_content_margin_all(4)
		(c["root"] as PanelContainer).add_theme_stylebox_override("panel", vb)
		if not open:
			(c["icon"] as PerkIcon).set_perk(String(Perks.ORDER[0]), Color(0.25, 0.28, 0.32, 0.6))
			(c["name"] as Label).text = "LV %d" % int(Profile.SLOT_LEVELS[si])
			(c["name"] as Label).add_theme_color_override("font_color", UiTheme.DANGER)
		elif eq == "":
			(c["icon"] as PerkIcon).set_perk(String(Perks.ORDER[0]), Color(0.25, 0.28, 0.32, 0.6))
			(c["name"] as Label).text = "empty"
			(c["name"] as Label).add_theme_color_override("font_color", UiTheme.MUTED)
		else:
			(c["icon"] as PerkIcon).set_perk(eq, Color.WHITE)
			(c["name"] as Label).text = Perks.display_name(eq)
			(c["name"] as Label).add_theme_color_override("font_color", UiTheme.TEXT)
	var id2 := String(Perks.ORDER[_perk_sel])
	var d: Dictionary = Perks.PERKS[id2]
	var unlocked2 := Profile.is_unlocked(id2)
	var at2 := _perk_slot_of(id2)
	_p_icon.set_perk(id2, Color.WHITE if unlocked2 else Color(0.55, 0.6, 0.65))
	_p_title.text = tr(String(d["name"])).to_upper()
	_p_tag.text = tr("Perk  ·  unlocks at level %d") % int(d["level"])
	for ch in _p_stats.get_children():
		_p_stats.remove_child(ch)
		ch.free()
	var status := tr("Equipped — slot %d") % (at2 + 1) if at2 >= 0 else (tr("Available") if unlocked2 else tr("Locked — reach level %d") % int(d["level"]))
	var prows: Array = [["Status", status], ["Slots", tr("%d of 2 open") % Profile.slots()]]
	var pp: Dictionary = d.get("params", {})
	if pp.has("run_noise_mult"):                           # bieg nie przebija wygaszania Uwagi (§5a) — mnożnik w wierszu, bez VU
		prows.append(["Running", UiTheme.num_text("▼ ×%.1f  (%.2f / s)" % [float(pp["run_noise_mult"]), NoiseMgr.N_RUN_PER_SEC * float(pp["run_noise_mult"])])])
	_p_vu.visible = pp.has("scream_cap")
	if _p_vu.visible:                                      # krzyk to jedno zdarzenie: poziom po krzyku od ciszy, cień = bez perka
		_p_vu_meter.value = float(pp["scream_cap"]) / 100.0
		_p_vu_meter.ghost = NoiseMgr.N_SCREAM / 100.0
		_p_vu_meter.fill = UiTheme.OK
		_p_vu_text.text = tr("Scream: %d%% → %d%% noise") % [int(NoiseMgr.N_SCREAM), int(pp["scream_cap"])]
	for r in prows:
		_p_stats.add_child(UiTheme.ink(tr(String(r[0])), 9, UiTheme.INK_MUTED))
		_p_stats.add_child(UiTheme.ink(String(r[1]), 9, UiTheme.INK_GAIN if at2 >= 0 and String(r[0]) == "Status" else UiTheme.INK))
		_p_stats.add_child(Control.new())
	_p_text.text = String(d["desc"])
	if at2 >= 0:
		_p_action.text = tr("Remove from slot %d") % (at2 + 1)
		_p_action.disabled = false
	elif not unlocked2:
		_p_action.text = tr("Locked  ·  reach level %d") % int(d["level"])
		_p_action.disabled = true
	elif _perk_slot >= Profile.slots():
		_p_action.text = tr("Slot %d unlocks at level %d") % [_perk_slot + 1, int(Profile.SLOT_LEVELS[_perk_slot])]
		_p_action.disabled = true
	else:
		_p_action.text = tr("Equip in slot %d") % (_perk_slot + 1)
		_p_action.disabled = false

func _select_supply(i: int) -> void:
	if i != _sup_sel:
		Audio.play("ui_click", Audio.BUS_UI, -14.0)
	_sup_sel = i
	_refresh()

func _buy_selected_supply() -> void:
	var k := String(_supply_kinds()[_sup_sel])
	if int(Scrap.deliveries.get(k, 0)) > 0:
		_claiming = true
		Scrap.request_claim(k)
	elif Throwables.is_ammo(k):
		_claiming = false
		Scrap.request_order(k)                                   # amunicja: zamówienie w prasie (gotowe po misji)
	else:
		Scrap.request_buy_supply(k)

## Indeksy kafli zaopatrzenia (w _supply_kinds) widoczne w tym trybie: ława — przedmioty, prasa — amunicja specjalna.
func _sup_list() -> Array:
	var out: Array = []
	var kinds := _supply_kinds()
	for i in kinds.size():
		if _sup_in_mode(String(kinds[i])):
			out.append(i)
	return out

## Czy rodzaj `k` należy do stanowiska: prasa — amunicja specjalna bez 40 mm, pirotechnika — granaty, miny, ładunki i 40 mm, ława — narzędzia.
func _sup_in_mode(k: String) -> bool:
	var m := String(Throwables.KINDS[k]["mode"])
	var forty := Throwables.is_ammo(k) and String(Ammo.from_kind(k).get("cal", "")) == "40mm"
	match _mode:
		"press":
			return Throwables.is_ammo(k) and not forty
		"pyro":
			return m == "throw" or m == "place" or forty
		_:
			return m == "use"

## VU-metr hałasu na karcie zaopatrzenia (STATION_CARDS_PLAN.md §5a): przedmiot rzucany / ładunek — poziom po jednym od ciszy i ile naraz
## do niepokoju; amunicja zmieniająca hałas — poziom po magazynku pierwszej broni tego kalibru (cień = nabój zwykły); reszta bez VU.
func _fill_noise(k: String) -> void:
	_s_vu.visible = false
	var uneasy := float(NoiseMgr.UNEASY_THRESHOLD)
	var item := StationNoise.item_noise(k)
	if item > 0.0:
		_s_vu.visible = true
		_s_vu_meter.visible = true
		_s_vu_meter.value = item / 100.0
		_s_vu_meter.ghost = -1.0
		_s_vu_meter.fill = UiTheme.ACCENT if item * 2.0 >= uneasy else UiTheme.TEXT
		var n := StationNoise.count_to(item, uneasy)
		_s_vu_text.text = UiTheme.num_text(tr("+%s%% noise per item") % ("%.0f" % item if item >= 1.0 else "%.1f" % item)) + "
" + tr("%d at once = unease") % n
		return
	var ct := Ammo.from_kind(k)
	if ct.is_empty() or String(ct["cal"]) == "40mm":
		return
	var w := -1
	for id in LIST:
		if String(Weapons.base_def(int(id)).caliber) == String(ct["cal"]):
			w = int(id)
			break
	if w < 0:
		return
	var wc := _local_wc()
	var fit: int = wc.fit_of(w) if wc != null else 0
	var plain: RefCounted = Weapons.def_build(w, Weapons.build_of(0, fit))
	var with: RefCounted = Weapons.def_build(w, Weapons.build_of(int(ct["t"]), fit))
	var a := StationNoise.mag_level(plain)
	var b := StationNoise.mag_level(with)
	if absf(a - b) < 0.5:
		_s_vu_text.text = tr("Shot noise unchanged.")         # VU tylko przy naboju, który zmienia hałas (§6 ST-03)
		_s_vu.visible = true
		_s_vu_meter.visible = false
		return
	_s_vu.visible = true
	_s_vu_meter.visible = true
	_s_vu_meter.value = b / 100.0
	_s_vu_meter.ghost = a / 100.0
	_s_vu_meter.fill = UiTheme.OK if b < a else UiTheme.DANGER
	_s_vu_text.text = tr("One %s magazine: %d%% → %d%% noise") % [String(plain.name), roundi(a), roundi(b)]

## Stół pirotechniczny: schemat działania przedmiotu w skali z sylwetką kolegi (granat i ładunek ranią drużynę, mina nie) — z danych przedmiotu.
func _fill_blast(k: String) -> void:
	var d: Dictionary = Throwables.KINDS[k]
	var b := _s_blast as SupplyArt.BlastDiagram
	b.visible = _mode == "pyro" and k in ["frag", "charge", "mine", "phos", "smoke"]
	if not b.visible:
		return
	b.kind = k
	match k:
		"frag", "charge":
			b.lines = [UiTheme.num_text(tr("%s m · %d damage") % ["%.0f" % (float(d["radius"]) / SupplyArt.PX_PER_M), int(d["damage"])]),
				tr("squad mate: hurt"), tr("safe")]
		"mine":
			b.lines = [UiTheme.num_text(tr("%s m · %d damage · %d° cone") % ["%.0f" % (float(d["range"]) / SupplyArt.PX_PER_M), int(d["damage"]), roundi(2.0 * float(d["half_deg"]))]),
				tr("squad mate: spared"), tr("safe")]
		"phos":
			b.lines = [tr("fire field · %d s") % int(d["field_life"])]
		"smoke":
			b.lines = [tr("cloud · %d s · blocks sight, not sound") % int(d["cloud_life"])]
	b.queue_redraw()

## Stół pirotechniczny: krótszy (−1) albo dłuższy (+1) zapalnik zaznaczonego przedmiotu — dla całej drużyny (serwer).
func _step_fuse(d: int) -> void:
	var k := String(_supply_kinds()[_sup_sel])
	var opts: Array = Throwables.FUSES.get(k, []) as Array
	if opts.is_empty():
		return
	_set_fuse(k, clampi(Scrap.fuse_index(k) + d, 0, opts.size() - 1))

## Zapalnik `k` na pozycję `ni` (przełącznik na karcie albo klawisze 1 / 2) — ustawienie drużyny rozstrzyga serwer.
func _set_fuse(k: String, ni: int) -> void:
	var opts: Array = Throwables.FUSES.get(k, []) as Array
	if ni < 0 or ni >= opts.size() or ni == Scrap.fuse_index(k):
		return
	Scrap.request_fuse(k, ni)
	Audio.play("ui_click", Audio.BUS_UI, -10.0, 1.2)
	_say(tr("%s fuse: %.1f s — for the whole squad.") % [tr(String(Throwables.KINDS[k]["name"])), float(opts[ni])], UiTheme.OK)
	_refresh()

## Stół pirotechniczny: trzy pozycje zapalnika jako przełącznik (zamiast „1,8 s (2 z 3) · 1 / 2 zmień”), z dopiskiem, że to ustawienie drużyny.
func _fill_fuse(k: String) -> void:
	_clear_children(_s_fuse)
	_s_fuse.visible = _mode == "pyro" and Throwables.FUSES.has(k)
	if not _s_fuse.visible:
		return
	_s_fuse.add_child(UiTheme.ink(tr("FUSE  ·  %s / %s") % [_menu_key("menu_slot_1", Actions.pad_mode), _menu_key("menu_slot_2", Actions.pad_mode)], 7, UiTheme.INK_MUTED))
	# pokrętło zapalnika (ST-04): tarcza z pozycjami, obok lista pozycji z czasem; klawisze pozycji obracają pokrętło
	var dial_row := HBoxContainer.new()
	dial_row.add_theme_constant_override("separation", 10)
	_s_fuse.add_child(dial_row)
	var opts: Array = Throwables.FUSES[k]
	var dial := SupplyArt.FuseDial.new()
	dial.count = opts.size()
	dial.index = Scrap.fuse_index(k)
	dial.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	dial_row.add_child(dial)
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dial_row.add_child(row)
	for i in opts.size():
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.text = "%s   %s" % [tr(FUSE_NAMES[mini(i, FUSE_NAMES.size() - 1)]), UiTheme.num_text("%.1f s" % float(opts[i]))]
		b.add_theme_font_size_override("font_size", 8)
		b.add_theme_constant_override("outline_size", 0)
		for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			b.add_theme_color_override(c, UiTheme.INK if i == Scrap.fuse_index(k) else UiTheme.INK_MUTED)
		for st in ["normal", "hover", "pressed", "focus"]:
			var box := StyleBoxFlat.new()
			var sel := i == Scrap.fuse_index(k)
			box.bg_color = UiTheme.PAPER_SEL if sel else (Color(UiTheme.PAPER_SEL, 0.5) if st == "hover" else Color(0, 0, 0, 0))
			box.border_color = UiTheme.INK if sel else UiTheme.PAPER_EDGE
			box.set_border_width_all(2 if sel else 1)
			box.set_content_margin_all(3)
			b.add_theme_stylebox_override(st, box)
		b.pressed.connect(_set_fuse.bind(k, i))
		row.add_child(b)
	var cord := SupplyArt.FuseCord.new()                 # lont: długość = czas zapalnika (pełna szerokość = najdłuższa pozycja)
	cord.seconds = float(opts[Scrap.fuse_index(k)])
	cord.max_s = float(opts.back())
	_s_fuse.add_child(cord)
	var note := UiTheme.ink(tr("Squad setting: everyone's %s uses this fuse.") % tr(String(Throwables.KINDS[k]["name"])), 7, UiTheme.INK_MUTED)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size.x = DETAIL_W
	_s_fuse.add_child(note)

## Prasa: co nabój zmienia względem zwykłego tego kalibru (modyfikatory ammo.gd) — wartość i ocena słowem, kolor tylko ją wzmacnia.
func _fill_ammo_cmp(k: String) -> void:
	_clear_children(_s_cmp)
	var rows := _ammo_rows(k)
	_s_cmp.visible = not rows.is_empty()
	if rows.is_empty():
		return
	_s_cmp.add_child(UiTheme.ink(tr("VS. STANDARD ROUND"), 7, UiTheme.INK_MUTED))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 1)
	_s_cmp.add_child(grid)
	for r in rows:
		var kind := int(r[2])
		var col := UiTheme.INK_GAIN if kind > 0 else (UiTheme.INK_COST if kind < 0 else UiTheme.INK)
		grid.add_child(UiTheme.ink(tr(String(r[0])), 9, UiTheme.INK_MUTED))
		if _mode == "press":
			# etykieta partii (ST-03): pasek od zera — zysk w prawo, koszt w lewo — i wartość ze znakiem ▲▼ (kolor tylko wzmacnia)
			var bar := SupplyArt.CmpBar.new()
			bar.value = float(kind) * (float(r[3]) if r.size() > 3 else 0.3)
			bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			grid.add_child(bar)
			grid.add_child(UiTheme.ink(("▲ " if kind > 0 else ("▼ " if kind < 0 else "")) + UiTheme.num_text(String(r[1])), 9, col))
			continue
		grid.add_child(UiTheme.ink(UiTheme.num_text(String(r[1])), 9, col))
		grid.add_child(UiTheme.ink((tr("Gain") if kind > 0 else (tr("Trade-off") if kind < 0 else "")).to_lower(), 7, col))

## Wiersze porównania naboju `k` z nabojem zwykłym: [etykieta, zmiana, ocena −1 / 0 / 1]. Granaty 40 mm to inny ładunek, nie wariant — bez porównania.
func _ammo_rows(k: String) -> Array:
	var ct := Ammo.from_kind(k)
	if ct.is_empty() or String(ct["cal"]) == "40mm":
		return []
	var t := Ammo.type_of(String(ct["cal"]), int(ct["t"]))
	var out: Array = []
	if bool(t.get("slug", false)):
		out.append(["Pellets", tr("one heavy slug"), 0])
	if bool(t.get("subsonic", false)):
		out.append(["Bullet crack", tr("none — quieter"), 1])
	for m in t.get("mods", []):
		var f := String(m[0])
		if not AMMO_FIELDS.has(f):
			continue
		var spec: Array = AMMO_FIELDS[f]
		var v := float(m[2])
		var text := ""
		var sgn := 0.0
		match String(m[1]):
			"mul":
				text = "%+d%%" % roundi((v - 1.0) * 100.0)
				sgn = v - 1.0
			"add":
				match String(spec[2]):
					"pct":
						text = "+%d%%" % roundi(v * 100.0)
					"s":
						text = tr("+%.1f s") % v
					"m":
						text = "+%.1f m" % (v / 16.0)
					_:
						text = "%+.1f" % v
				sgn = v
			"set":
				text = tr("none") if f == "crit_mult" and v <= 1.0 else "%.1f" % v
				sgn = -1.0 if f == "crit_mult" else 1.0
		out.append([String(spec[0]), text, int(signf(sgn) * float(spec[1])), clampf(absf(sgn) if String(m[1]) != "set" else 0.5, 0.1, 1.0)])
	return out

## Prasa: miejsca na partie — zajęte z nazwą naboju, wolne puste (dawniej wiersz „1 z 3 partii”).
func _fill_press_queue() -> void:
	_clear_children(_s_queue)
	_s_queue.visible = false                             # od E2 partie stoją na matrycach w kolumnie po prawej (_fill_dies)
	_fill_dies()

## Prasa (ST-03): matryce pionowo po prawej — zajęta pokazuje nabój i „po udanej misji”, wolna jest pusta.
func _fill_dies() -> void:
	_clear_children(_dies_list)
	if _mode != "press":
		return
	_dies_list.add_child(UiTheme.mono(UiTheme.label(tr("DIES"), 8, UiTheme.MUTED)))
	for i in Scrap.PRESS_SLOTS:
		var filled := i < Scrap.orders.size()
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var die := SupplyArt.FuseDial.new()                  # matryca: okrągłe gniazdo, zajęte ze wskazówką w kolorze lampy
		die.count = 1
		die.index = 0
		die.custom_minimum_size = Vector2(26, 26)
		die.modulate = Color.WHITE if filled else Color(0.5, 0.5, 0.5)
		die.set_meta("filled", filled)
		row.add_child(die)
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", -2)
		col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		col.add_child(UiTheme.label(String(Throwables.KINDS[String(Scrap.orders[i])]["name"]) if filled else tr("free"), 9, UiTheme.TEXT if filled else UiTheme.MUTED))
		col.add_child(UiTheme.label(tr("after a successful mission") if filled else "—", 7, UiTheme.MUTED))
		row.add_child(col)
		_dies_list.add_child(row)

## Portfel odlicza do nowej kwoty (zakup, zamówienie, odbiór) zamiast skakać i krótko przygasa na czerwono przy wydatku — widać, ile kosztowało.
func _tick_wallet() -> void:
	var target := Scrap.bank
	if _bank_shown < 0 or Settings.reduce_fx:
		_bank_shown = target
		_wallet.text = "%d" % target
		_drum.shown = float(target)
		return
	if target == _bank_shown and (_wallet_tween == null or not _wallet_tween.is_running()):
		return
	if _wallet_tween != null and _wallet_tween.is_running():
		if _wallet_tween.get_meta("to", -1) == target:
			return
		_wallet_tween.kill()
	var from := _bank_shown
	_wallet_tween = create_tween()
	_wallet_tween.set_meta("to", target)
	_wallet_tween.tween_method(func(v: float) -> void:
		_bank_shown = int(round(v))
		_drum.shown = v                                     # bębny obracają się płynnie jak w liczniku mechanicznym
		_wallet.text = "%d" % _bank_shown, float(from), float(target), 0.7).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)

## Udana operacja: potwierdzenie UI, dźwięk stanowiska (magazynek na ławie, łuski przy prasie, ogniwo w pracowni…) i krótki błysk wybranego kafla.
func _success_fx(vol_db := -4.0) -> void:
	Audio.play("ui_confirm", Audio.BUS_UI, vol_db)
	var snd: Array = STATION_SOUNDS.get(_mode, [])
	if not snd.is_empty():
		if int(snd[1]) > 0:
			Audio.play_variant(String(snd[0]), int(snd[1]), Audio.BUS_UI, vol_db - 2.0)
		else:
			Audio.play(String(snd[0]), Audio.BUS_UI, vol_db - 2.0)
	_stamp()
	if Settings.reduce_fx:
		return
	var tile: Control = null
	match _page:
		0:
			tile = _tiles[_sel] if not (_mode == "bench") else null      # ława 3D ma własną animację montażu
		1:
			tile = _sup_tiles[_sup_sel]
		2:
			tile = _perk_tiles[_perk_sel]
		3:
			tile = _look_tiles[_look_sel]
	if tile == null or not tile.is_visible_in_tree():
		return
	tile.modulate = Color(1.55, 1.4, 0.95)
	create_tween().tween_property(tile, "modulate", Color.WHITE, 0.35)

func _clear_children(node: Node) -> void:
	for c in node.get_children():
		node.remove_child(c)
		c.queue_free()

## Cena kafla: przedmiot — sklep ławy, amunicja — partia w prasie.
func _sup_price(k: String) -> int:
	return Scrap.press_price(k) if Throwables.is_ammo(k) else Throwables.price_of(k)

func _on_order_result(kind: String, ok: bool, reason: String) -> void:
	if not _open:
		return
	var nm := String(Throwables.KINDS[kind]["name"]) if Throwables.is_valid(kind) else kind
	match reason:
		"station":
			_say(tr("Approach the correct station in the hideout."), UiTheme.MUTED)
		"repeat":
			_say(tr("Please wait before repeating this action."), UiTheme.MUTED)
		"serviced":
			_say(tr("This part was already replaced during this visit."), UiTheme.MUTED)
		"ok":
			_say(tr("%s collected. Remaining delivery: %d rounds.") % [nm, int(Scrap.deliveries.get(kind, 0))] if _claiming else tr("%s ordered — ready after the next mission (%d / %d batches in the press).") % [nm, Scrap.orders.size(), Scrap.PRESS_SLOTS], UiTheme.OK)
			_success_fx()
		"poor":
			_drum.broke()
			_say(tr("Not enough scrap (%d needed).") % Scrap.press_price(kind), UiTheme.DANGER)
		"busy":
			_say(tr("The press is full — %d batches per mission.") % Scrap.PRESS_SLOTS, UiTheme.MUTED)
		"full":
			_say(tr("The squad cannot carry more %s.") % nm, UiTheme.MUTED)
		"off":
			_say("No scrap in this mode.", UiTheme.MUTED)
		_:
			_say("Cannot do that.", UiTheme.DANGER)
	_refresh()

## Rodzaje do kupienia (z ceną) w kolejności karuzeli: przedmioty, potem amunicja specjalna.
func _supply_kinds() -> Array:
	var out: Array = []
	for k in Throwables.SHOP_ORDER:
		if Throwables.price_of(String(k)) > 0:
			out.append(k)
	return out

func _set_page(p: int) -> void:
	if p == _page:
		_page_btns[p].set_pressed_no_signal(true)
		return
	_page = p
	Audio.play("ui_click", Audio.BUS_UI, -12.0, 1.1)
	_refresh()

## Długie porównania i kolejki pozostają dostępne także w bazowej rozdzielczości 640×360.
func _scroll_body(body: Control) -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(TILE_W * COLS + DETAIL_W + 50.0, 250.0)        # +14: marginesy papierowej karty
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(body)
	return scroll

func _make_tile(w: int, idx: int) -> Tile:
	var t := Tile.new()
	t.weapon = w
	var ic := GunIcon.new()
	var d: RefCounted = Weapons.base_def(w)
	ic.plate = true
	ic.k = 0.3
	ic.set_gun(int(d.gun_row), d.tracer_color, Color.WHITE)
	_dress_tile(t, ic, String(d.name))
	_add_bar(t, TierBar.new())
	t.pressed.connect(_select.bind(idx))
	return t

## Wspólna ramka kafla: style stanów, miniatura w polu po lewej, nazwa i (pusta) linia stanu. Wysoki kafel (wygląd) — obie linie wyśrodkowane.
func _dress_tile(t: CardTile, icon: Control, title: String) -> void:
	for st in ["normal", "hover", "pressed", "disabled", "focus"]:
		t.add_theme_stylebox_override(st, UiTheme.tile_box("hover" if st == "hover" else "normal"))
	icon.position = Vector2(4, 5)
	icon.size = Vector2(54, t.custom_minimum_size.y - 10.0)
	t.add_child(icon)
	t.icon_node = icon
	var mid := (t.custom_minimum_size.y - TILE_H) * 0.5
	t.name_label = UiTheme.label(title, 10, UiTheme.TEXT)
	t.name_label.position = Vector2(64, 6.0 + mid)
	t.add_child(t.name_label)
	t.state_label = UiTheme.label("", 8, UiTheme.MUTED)
	t.state_label.position = Vector2(64, 25.0 + mid)
	t.add_child(t.state_label)

## Cena z monetą w linii stanu (zaopatrzenie).
func _add_price(t: CardTile) -> void:
	t.coin = Coin.new()
	t.coin.position = Vector2(64, 26)
	t.add_child(t.coin)
	t.price_label = UiTheme.label("", 10, GOLD)
	t.price_label.position = Vector2(76, 23)
	t.add_child(t.price_label)

## Jedyny wskaźnik kafla: kropki przy prawej krawędzi.
func _add_bar(t: CardTile, bar: Control) -> void:
	t.bar = bar
	t.add_child(bar)
	t.place_bar()

func _build_detail() -> Control:
	var v := VBoxContainer.new()
	v.custom_minimum_size = Vector2(DETAIL_W, 0)
	v.add_theme_constant_override("separation", 4)
	_d_stage = GunStage.new()
	_d_stage.custom_minimum_size = Vector2(0, 76)
	v.add_child(_d_stage)
	_d_title = _ink_heading()
	v.add_child(_d_title)
	_d_tag = UiTheme.ink("", 8, UiTheme.INK_MUTED)
	v.add_child(_d_tag)
	_d_panel = VBoxContainer.new()
	_d_panel.add_theme_constant_override("separation", 3)
	v.add_child(_d_panel)
	_d_stats = GridContainer.new()
	_d_stats.columns = 4                                  # parametr | teraz | → po zmianie | korzyść / kompromis
	_d_stats.add_theme_constant_override("h_separation", 10)
	_d_stats.add_theme_constant_override("v_separation", 1)
	v.add_child(_d_stats)
	v.add_child(_paper_rule())
	_d_tiers = VBoxContainer.new()
	_d_tiers.add_theme_constant_override("separation", 1)
	v.add_child(_d_tiers)
	_d_text = UiTheme.ink("", 8)
	_d_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_d_text.custom_minimum_size = Vector2(DETAIL_W, 0)
	v.add_child(_d_text)
	_action = Button.new()
	_action.focus_mode = Control.FOCUS_NONE
	_action.add_theme_font_size_override("font_size", 10)
	_action.add_theme_color_override("font_disabled_color", UiTheme.BONE_DIM)     # wyłączona akcja niesie podpowiedź („wybierz gniazdo”)
	_action.pressed.connect(_act)
	v.add_child(_action)
	return v

# ---------------------------------------------------------------- otwieranie

func is_open() -> bool:
	return _open

## `mode`: „bench" — ława warsztatu (bronie, części, zaopatrzenie), „locker" — szafki osobiste (perki, wygląd). Zakładki spoza trybu są ukryte.
func open(mode := "bench") -> void:
	if _open:
		return
	_open = true
	visible = true
	_mode = mode if MODE_PAGES.has(mode) else "bench"
	_session += 1
	_bench_slot = ""
	_title.text = {"locker": tr("LOCKER"), "service": tr("MAINTENANCE"), "press": tr("RELOADING PRESS"), "pyro": tr("PYROTECHNICS"), "lab": tr("LAB"), "lathe": tr("LATHE")}.get(_mode, tr("WORKSHOP"))
	_plate.set_station(_mode)
	_arrange_supplies()
	for pi in _page_btns.size():
		(_page_btns[pi] as Button).visible = (MODE_PAGES[_mode] as Array).has(pi) and (MODE_PAGES[_mode] as Array).size() > 1
	_msg.text = ""
	_hint.text = StationKit.tape_text(_controls_hint())
	_sel = _initial_selection()
	_opt = _first_part_opt()
	_bank_shown = -1                                       # po otwarciu portfel od razu pokazuje stan, odlicza dopiero zmianę
	_page = int((MODE_PAGES[_mode] as Array)[0])
	var allowed := _sup_list()
	if not allowed.has(_sup_sel) and not allowed.is_empty():
		_sup_sel = int(allowed[0])
	Settings.block_game_input(true)
	_prev_mouse = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE            # w grze celownik zastępuje kursor; panel potrzebuje myszy
	Audio.play("ui_click", Audio.BUS_UI, -10.0)
	_refresh()

func close() -> void:
	if not _open:
		return
	_remembered[_mode] = _sel
	_session += 1
	_workbench.stage.cancel_mount()
	_workbench.stage.set_rendering(false)
	_legacy_stage.set_rendering(false)
	_stop_clean()
	_open = false
	visible = false
	Settings.block_game_input(false)
	Input.mouse_mode = _prev_mouse
	Audio.play("ui_click", Audio.BUS_UI, -10.0)

func _process(delta: float) -> void:
	if not _open:
		return
	_msg_t = maxf(0.0, _msg_t - delta)
	if _msg_t <= 0.0:
		_msg.text = ""
	# panel zamyka się, gdy gracz odejdzie od ławy / zginie / misja się zmieni (przerwane czyszczenie trzeba zacząć od nowa)
	var wk := get_tree().get_first_node_in_group(String(MODE_GROUP[_mode]))
	if wk == null or not wk.local_in_range or not NoiseMgr.safe_zone:
		close()
		return
	tick_clean(delta)
	_hub_events()
	var hud := get_parent() as Control
	if hud != null:
		size = hud.size
	# Ława 3D ma stałą skalę ×1,4; pozostałe stanowiska dostają tyle samo, ile zmieści szerokość ekranu (dawniej ×1 — drobny tekst
	# w ~46% szerokości ekranu). Wysokość przewijanej treści liczona już w jednostkach skali, żeby karta nie wyszła poza ekran.
	var immersive := _mode == "bench" and _page == 0
	var card_scale := 1.4 if immersive else clampf((size.x - 48.0) / maxf(1.0, _card.get_combined_minimum_size().x), 1.0, 1.4)
	for body in [_arms_body, _sup_body, _perk_body, _look_body]:
		(body.get_parent() as ScrollContainer).custom_minimum_size.y = clampf(size.y / card_scale - 156.0, 150.0, 400.0)      # 156: nagłówek z tabliczką, dźwignia, komunikat, taśma, odstępy
	var overhead := maxf(118.0, _card.size.y - _workbench.size.y)
	_workbench.custom_minimum_size = Vector2(clampf(size.x / card_scale - 34.0, 606.0, 1050.0), clampf(size.y / card_scale - overhead - 14.0, 190.0, 620.0))
	_card.scale = Vector2.ONE * card_scale
	# Kontener sam się nie kurczy: po wyższej stronie (zaopatrzenie, inne stanowisko) karta ławy ×1,4 wychodziła poza ekran.
	if not _card.size.is_equal_approx(_card.get_combined_minimum_size()):
		_card.reset_size()
	_card.position = ((size - _card.size * card_scale) * 0.5).round()

## Zdarzenia Kryjówki na karcie (STATION_CARDS_PLAN.md §5): w burzy karta przygasa razem z lampą generatora; stuknięcie zza D-7 — papiery
## drgają, czerwony błysk od strony drzwi i napis dźwięku z kierunkiem. „Reduce effects” wyłącza migotanie, drganie i błysk (napis zostaje).
func _hub_events() -> void:
	var fx := Settings.fx_mult() > 0.0
	var dim := 1.0
	if fx and Weather.forecast == "storm":
		dim = lerpf(0.6, 1.0, clampf((HubProp.generator_light(float(Time.get_ticks_msec()) * 0.001, true) - 0.15) / 0.55, 0.0, 1.0))
	_card.modulate = Color(dim, dim, dim)
	var d7: Node2D = null
	for n in get_tree().get_nodes_in_group("hub_props"):
		if String(n.get("kind")) == "d7":
			d7 = n as Node2D
			break
	if d7 == null:
		return
	var k := float(d7.get("knock_flash"))
	if k >= 0.95 and _knock_prev < 0.95:
		_on_knock(d7)
	_knock_prev = k

func _on_knock(d7: Node2D) -> void:
	var me: Node2D = null
	for p in get_tree().get_nodes_in_group("players"):
		if not p.is_bot and p.is_multiplayer_authority():
			me = p
	var left := me != null and d7.global_position.x < me.global_position.x
	# napis dźwięku po stronie drzwi, nad kartą — nie zmienia układu karty (wiersz komunikatów zostaje dla wyników operacji)
	_knock_label.text = ("◀  " if left else "") + tr("Knocking behind D-7") + ("" if left else "  ▶")
	_knock_label.reset_size()
	var cr := _card.get_global_rect()
	_knock_label.position = Vector2(cr.position.x + 8.0 if left else cr.end.x - _knock_label.size.x - 8.0, maxf(2.0, cr.position.y - _knock_label.size.y - 2.0))
	_knock_label.modulate.a = 1.0
	var kt := create_tween()
	kt.tween_interval(1.4)
	kt.tween_property(_knock_label, "modulate:a", 0.0, 0.6)
	if Settings.fx_mult() <= 0.0:
		return
	_edge_flash.size = Vector2(size.x * 0.16, size.y)
	_edge_flash.position = Vector2(0.0 if left else size.x - _edge_flash.size.x, 0.0)
	_edge_flash.color = Color(UiTheme.DANGER, 0.22)
	create_tween().tween_property(_edge_flash, "color:a", 0.0, 0.9)
	for p in _papers:
		var pc := p as Control
		if not pc.is_visible_in_tree():
			continue
		pc.pivot_offset = pc.size * Vector2(0.5, 0.0)
		var tw := create_tween()
		for r in [0.9, -0.6, 0.35, 0.0]:
			tw.tween_property(pc, "rotation_degrees", r * (-1.0 if left else 1.0), 0.07)

func _exit_tree() -> void:
	if _open:
		Settings.block_game_input(false)
		Input.mouse_mode = _prev_mouse

# ---------------------------------------------------------------- sterowanie

## Linia sterowania pod panelem: klawisze z rejestru akcji, a gdy jest pad — jego przyciski.
func _controls_hint() -> String:
	var pad := Actions.pad_mode
	var nav := StationKit.KEY_OPEN + ("D-PAD" if pad else Actions.cluster(["menu_up", "menu_left", "menu_down", "menu_right"]).to_upper()) + StationKit.KEY_CLOSE
	if _mode == "bench" and _page == 0:
		return tr("%s weapon · %s slot · %s / %s part · %s fit · %s inspect · %s tabs · %s close") % [
			_cap("menu_up", pad) + "/" + _cap("menu_down", pad), _cap("menu_left", pad) + "/" + _cap("menu_right", pad),
			_cap("menu_slot_1", pad), _cap("menu_slot_2", pad), _cap("menu_accept", pad), _cap("menu_inspect", pad),
			_cap("menu_tab", pad), _cap("menu_back", pad)]
	if _mode == "lathe":
		return tr("%s select   ·   %s / %s job   ·   %s machine / sharpen   ·   %s close   ·   or click") % [
			nav, _cap("menu_slot_1", pad), _cap("menu_slot_2", pad), _cap("menu_accept", pad), _cap("menu_back", pad)]
	if _mode == "lab":
		return tr("%s select   ·   %s / %s part   ·   %s research   ·   %s close   ·   or click") % [
			nav, _cap("menu_slot_1", pad), _cap("menu_slot_2", pad), _cap("menu_accept", pad), _cap("menu_back", pad)]
	if _mode == "press":
		return tr("%s select   ·   %s order a batch   ·   %s close   ·   or click") % [nav, _cap("menu_accept", pad), _cap("menu_back", pad)]
	if _mode == "pyro":
		return tr("%s select   ·   %s / %s fuse   ·   %s buy / order   ·   %s close   ·   or click") % [
			nav, _cap("menu_slot_1", pad), _cap("menu_slot_2", pad), _cap("menu_accept", pad), _cap("menu_back", pad)]
	if _mode == "service":
		return tr("%s gun   ·   %s instrument   ·   %s hold: clean / replace   ·   %s close   ·   or click") % [
			_cap("menu_up", pad) + " " + _cap("menu_down", pad), _cap("menu_left", pad) + " " + _cap("menu_right", pad), _cap("menu_accept", pad), _cap("menu_back", pad)]
	if _mode == "locker" and _page == 3:
		return tr("%s select   ·   %s wear   ·   %s perks / look   ·   %s close   ·   or click") % [
			nav, _cap("menu_accept", pad), _cap("menu_tab", pad), _cap("menu_back", pad)]
	if _mode == "bench" and _page == 1:
		return tr("%s select   ·   %s buy   ·   %s arms / supplies   ·   %s close   ·   or click") % [
			nav, _cap("menu_accept", pad), _cap("menu_tab", pad), _cap("menu_back", pad)]
	if _mode == "locker":
		return tr("%s select   ·   %s / %s perk slot   ·   %s equip   ·   %s perks / look   ·   %s close   ·   or click") % [
			nav, _cap("menu_slot_1", pad), _cap("menu_slot_2", pad), _cap("menu_accept", pad), _cap("menu_tab", pad), _cap("menu_back", pad)]
	return tr("%s select   ·   %s / %s part   ·   %s buy / fit   ·   %s save set   ·   %s arms / supplies   ·   %s close   ·   or click") % [
		nav, _cap("menu_slot_1", pad), _cap("menu_slot_2", pad), _cap("menu_accept", pad), _cap("menu_alt", pad), _cap("menu_tab", pad), _cap("menu_back", pad)]

## Nazwa klawisza oznaczona dla taśmy sterowania (StationKit.tape_text rysuje ją w ramce klawisza).
func _cap(id: String, pad: bool) -> String:
	return StationKit.KEY_OPEN + _menu_key(id, pad) + StationKit.KEY_CLOSE

func _menu_key(id: String, pad: bool) -> String:
	return Actions.text(id, true, Actions.DEV_PAD if pad else Actions.DEV_KEY).to_upper()

## Krok zaznaczenia z akcji menu (strzałki / WASD / D-pad): ±1 w poziomie, ±COLS w pionie, 0 = to nie nawigacja.
func _nav_step(event: InputEvent) -> int:
	if event.is_action_pressed("menu_left"):
		return -1
	if event.is_action_pressed("menu_right"):
		return 1
	if event.is_action_pressed("menu_up"):
		return -COLS
	if event.is_action_pressed("menu_down"):
		return COLS
	return 0

## Następny kafel w kierunku kroku `step` (±1 poziomo, ±COLS pionowo) wg położenia na ekranie: regał prasy ma półki różnej długości,
## skrzynia 4 przegrody w rzędzie, siatka ławy 2 kolumny — światło idzie za fokusem tak, jak kafle stoją. -1, gdy w tę stronę nic nie ma.
func _spatial_step(tiles: Array, vis: Array, cur: int, step: int) -> int:
	if vis.is_empty() or not vis.has(cur):
		return int(vis[0]) if not vis.is_empty() else -1
	var horiz := absi(step) == 1
	var c := (tiles[cur] as Control).get_global_rect().get_center()
	var best := -1
	var best_d := INF
	for i in vis:
		if int(i) == cur:
			continue
		var p := (tiles[int(i)] as Control).get_global_rect().get_center()
		var d := p - c
		var along := d.x if horiz else d.y
		var across := d.y if horiz else d.x
		if signf(along) != signf(float(step)) or absf(along) < 4.0:
			continue
		if horiz and absf(across) > 8.0:
			continue                                       # w poziomie tylko ten sam rząd (półka, rząd przegród)
		var score := absf(along) + absf(across) * 3.0
		if score < best_d:
			best_d = score
			best = int(i)
	if best < 0 and horiz:
		var at := vis.find(cur) + signi(step)                 # koniec rzędu: dalej po kolejności (następna półka)
		best = int(vis[at]) if at >= 0 and at < vis.size() else -1
	return best

func _input(event: InputEvent) -> void:
	if _open and _hold_clean and (event is InputEventKey or event is InputEventJoypadButton) and event.is_action_released("menu_accept"):
		_hold_clean = false
		if _clean_w >= 0:                                  # czynność w czasie trzymana klawiszem: puszczenie przerywa (ST-02)
			_stop_clean()
			_say(tr("Interrupted — hold to finish."), UiTheme.MUTED)
			_refresh()
		get_viewport().set_input_as_handled()
		return
	if not _open or not (event is InputEventKey or event is InputEventJoypadButton) or not event.is_pressed() or event.is_echo():
		return
	if event.is_action_pressed("menu_tab") or event.is_action_pressed("menu_tab_prev"):
		var pages: Array = MODE_PAGES[_mode]
		_set_page(int(pages[posmod(pages.find(_page) + (1 if event.is_action_pressed("menu_tab") else -1), pages.size())]))
		get_viewport().set_input_as_handled()
		return
	var step := _nav_step(event)
	var accept := event.is_action_pressed("menu_accept")
	var back := event.is_action_pressed("menu_back")
	if _mode == "bench" and _page == 0:
		if event.is_action_pressed("menu_up") or event.is_action_pressed("menu_down"):
			_move(-1 if event.is_action_pressed("menu_up") else 1)
		elif event.is_action_pressed("menu_left") or event.is_action_pressed("menu_right"):
			_move_slot(-1 if event.is_action_pressed("menu_left") else 1)
		elif event.is_action_pressed("menu_slot_1") or event.is_action_pressed("menu_slot_2"):
			_move_opt(-1 if event.is_action_pressed("menu_slot_1") else 1)
		elif event.is_action_pressed("menu_inspect"):
			_inspect()
		elif event.is_action_pressed("menu_details"):
			_workbench._toggle_details()
		elif event.is_action_pressed("menu_alt"):
			_save_current_preset()
		elif accept:
			_act()
		elif back:
			close()
	elif _page == 3:
		if step != 0 and _look_sel + step >= 0 and _look_sel + step < Look.GENDERS.size() * Look.OUTFITS.size():
			_look_sel += step
			Audio.play("ui_click", Audio.BUS_UI, -14.0)
			_refresh()
		elif accept:
			_act_look()
		elif back:
			close()
	elif _page == 2:
		if step != 0 and _perk_sel + step >= 0 and _perk_sel + step < Perks.ORDER.size():
			_perk_sel += step
			Audio.play("ui_click", Audio.BUS_UI, -14.0)
			_refresh()
		elif event.is_action_pressed("menu_slot_1") or event.is_action_pressed("menu_slot_2"):
			_perk_slot = 0 if event.is_action_pressed("menu_slot_1") else 1
			Audio.play("ui_click", Audio.BUS_UI, -14.0)
			_refresh()
		elif accept:
			_act_perk()
		elif back:
			close()
	elif _page == 1:
		var nxt := _spatial_step(_sup_tiles, _sup_list(), _sup_sel, step) if step != 0 else -1
		if nxt >= 0:
			_sup_sel = nxt
			Audio.play("ui_click", Audio.BUS_UI, -14.0)
			_refresh()
		elif _mode == "pyro" and (event.is_action_pressed("menu_slot_1") or event.is_action_pressed("menu_slot_2")):
			_step_fuse(-1 if event.is_action_pressed("menu_slot_1") else 1)
		elif accept:
			_buy_selected_supply()
		elif back:
			close()
	elif _mode == "service" and step != 0:
		# stół konserwacji (ST-02): w górę / w dół — broń, w lewo / w prawo — przyrząd
		if absi(step) == 1:
			_move_opt(step)
		else:
			_move(signi(step))
	elif step != 0:
		_move(step)
	elif event.is_action_pressed("menu_slot_1") or event.is_action_pressed("menu_slot_2"):
		_move_opt(-1 if event.is_action_pressed("menu_slot_1") else 1)
	elif event.is_action_pressed("menu_alt"):
		_save_preset()
	elif accept:
		var ops2 := _options(int(LIST[_sel]))
		var timed := _opt >= 0 and _opt < ops2.size() and String(ops2[_opt]["slot"]) == "service" and String(ops2[_opt]["id"]) in ["clean", "sharpen"]
		_act()
		_hold_clean = timed and _clean_w >= 0
	elif back:
		close()
	get_viewport().set_input_as_handled()

## Opcje części broni `w` w kolejności gniazd: [{slot, id}] — id "" to element fabryczny gniazda. Na końcu „SERVICE / clean”: czyszczenie
## broni przy ławie (etap 4a GUNSMITH_PLAN — stan techniczny), gdy broń jest kupiona, strzela i niezawodność nie jest wyłączona.
func _options(w: int) -> Array:
	var key := String(Weapons.def(w).key)
	var out: Array = []
	if _mode == "lathe":
		if Scrap.is_unlocked(w) and Weapons.def(w).is_melee() and Settings.reliability_mult() > 0.0:
			out.append({"slot": "service", "id": "sharpen"})        # szlifierka: ostrze broni białej
		elif key in Scrap.LAB_WEAPONS:
			for s in Parts.slots_of(key):
				for p in Parts.in_slot(key, String(s)):
					out.append({"slot": s, "id": String(p["id"])})
		return out
	if _mode == "lab":
		if key in Scrap.LAB_WEAPONS:
			for s in Parts.slots_of(key):
				for p in Parts.in_slot(key, String(s)):
					out.append({"slot": s, "id": String(p["id"])})
		return out
	if _mode == "service":
		var d := Weapons.def(w)
		if Scrap.is_unlocked(w) and not d.is_melee() and Settings.reliability_mult() > 0.0:
			out.append({"slot": "service", "id": "clean"})
			if d.can_jam():                                      # broń na naboje: lufa i sprężyny (energetyczna ma swoje usterki — WeaponDef.fault)
				out.append({"slot": "service", "id": "barrel"})
				out.append({"slot": "service", "id": "springs"})
		return out
	for s in Parts.slots_of(key):
		out.append({"slot": s, "id": ""})
		for p in Parts.in_slot(key, String(s)):
			out.append({"slot": s, "id": String(p["id"])})
	if Scrap.is_unlocked(w) and not Parts.slots_of(key).is_empty():
		for i in Profile.PRESETS:
			out.append({"slot": "preset", "id": str(i)})       # zestawy części gracza (WORKSHOP_PLAN.md U6)
	return out

func _move_opt(d: int) -> void:
	if _mode == "bench":
		var ops := _options(int(LIST[_sel]))
		var indices: Array = []
		for i in ops.size():
			if String(ops[i]["slot"]) == _bench_slot:
				indices.append(i)
		if not indices.is_empty():
			_pick_opt(int(indices[posmod(indices.find(_opt) + d, indices.size())]))
		return
	var n := _options(int(LIST[_sel])).size()
	if n == 0:
		return
	_opt = posmod(_opt + d, n)
	Audio.play("ui_click", Audio.BUS_UI, -14.0)
	_refresh()
	_reveal_option()

func _pick_opt(i: int) -> void:
	var ops := _options(int(LIST[_sel]))
	if i < 0 or i >= ops.size():
		return
	if i != _opt:
		Audio.play("ui_click", Audio.BUS_UI, -14.0)
	_opt = i
	_selection_revision += 1
	if _mode == "bench":
		_bench_slot = String(ops[i]["slot"])
		_workbench.stage.cancel_mount()
	_refresh()
	_reveal_option()

## Nawigacja klawiszami/padem nie zostawia wybranej operacji poza przewijanym kadrem.
func _reveal_option() -> void:
	call_deferred("_reveal_current_option")

func _reveal_current_option() -> void:
	if not _open or _page != 0 or _mode == "bench":
		return
	var buttons := _d_tiers.get_children().filter(func(c: Node) -> bool: return c is Button)
	if _opt >= 0 and _opt < buttons.size():
		_ensure_arm_option_visible.call_deferred(buttons[_opt])

## Przebudowa części może odłączyć przycisk przed odroczonym przewinięciem fokusu.
func _ensure_arm_option_visible(button: Control) -> void:
	if not is_instance_valid(button) or not is_instance_valid(_arms_body):
		return
	var scroll := _arms_body.get_parent() as ScrollContainer
	if scroll != null and scroll.is_ancestor_of(button):
		scroll.ensure_control_visible(button)

func _move(d: int) -> void:
	var choices := _arms_list()
	var pos := choices.find(_sel)
	var next := pos + d
	if next < 0 or next >= choices.size():
		return
	var n := int(choices[next])
	if n < 0 or n >= LIST.size():
		return
	_stop_clean()
	_sel = n
	_selection_revision += 1
	_bench_slot = ""
	(_arms_body.get_parent() as ScrollContainer).scroll_vertical = 0
	_opt = _first_part_opt()
	Audio.play("ui_click", Audio.BUS_UI, -14.0)
	_refresh()

func _select(i: int) -> void:
	if not _arms_list().has(i):
		return
	if i != _sel:
		Audio.play("ui_click", Audio.BUS_UI, -14.0)
		_stop_clean()
		_sel = i
		_selection_revision += 1
		_bench_slot = ""
		(_arms_body.get_parent() as ScrollContainer).scroll_vertical = 0
		_opt = _first_part_opt()
	_refresh()

## Kursor na pierwszej części (nie na elemencie fabrycznym) — po wyborze broni widać od razu, co można kupić.
## Siatka i nawigacja korzystają z tej samej listy rzeczywistych opcji stanowiska.
func _arms_list() -> Array:
	var out: Array = []
	for i in LIST.size():
		var w := int(LIST[i])
		if _mode == "bench" or _mode == "locker" or not _options(w).is_empty():
			out.append(i)
	return out

func _initial_selection() -> int:
	var choices := _arms_list()
	if choices.is_empty():
		return 0
	var jobs: Array = Scrap.lathe if _mode == "lathe" else (Scrap.research if _mode == "lab" else [])
	if _mode == "lathe" and jobs.is_empty():
		jobs = Scrap.schematics.keys()
	for id in jobs:
		var w := Weapons.index_of(String(Parts.get_part(String(id)).get("weapon", "")))
		var i := LIST.find(w)
		if choices.has(i):
			return i
	var remembered := int(_remembered.get(_mode, -1))
	if choices.has(remembered):
		return remembered
	var controller := _local_wc()
	if controller != null:
		var i := LIST.find(controller.cur().id)
		if choices.has(i):
			return i
	for i in choices:
		if Scrap.is_unlocked(int(LIST[int(i)])):
			return int(i)
	return int(choices[0])

## Stan wspólnej pracy, także gdy panel pokazuje inną broń.
func _queue_summary(skip_batches := false) -> String:
	var lines: Array[String] = []
	for entry in [[tr("Research"), Scrap.research], [tr("Machining"), Scrap.lathe]]:
		for id in entry[1]:
			lines.append(tr("%s: %s — after a successful mission") % [String(entry[0]), tr(String(Parts.get_part(String(id)).get("name", id)))])
	for id in Scrap.schematics:
		if not Scrap.lathe.has(id):
			lines.append(tr("Schematic: %s — take to the lathe") % tr(String(Parts.get_part(String(id)).get("name", id))))
	for kind in ([] if skip_batches else Scrap.orders):          # prasa pokazuje partie w swoich miejscach (_fill_press_queue)
		lines.append(tr("Batch: %s — after a successful mission") % tr(String(Throwables.KINDS[String(kind)]["name"])))
	for kind in Scrap.deliveries:
		var station := tr("PYROTECHNICS") if Scrap.supply_station(String(kind)) == "pyro_bench" else tr("RELOADING PRESS")
		lines.append(tr("Ready: %s · %d rounds — collect at %s") % [tr(String(Throwables.KINDS[String(kind)]["name"])), int(Scrap.deliveries[kind]), station])
	return "\n".join(lines)

func _slot_label(key: String, slot: String) -> String:
	return tr(String(SLOT_LABELS.get("%s:%s" % [key, slot], Parts.SLOT_NAMES[slot])))

## Te same dane broni dla obu kolumn; porównanie nie zakłada naboju standardowego.
func _comparison_rows(d: RefCounted) -> Array:
	var rows: Array = Codex._weapon_stats(d)
	for row in rows:
		match String(row[0]):
			"Magazine":
				row[1] = "%d%s" % [d.mag, "+1" if d.chamber else ""]
			"Damage":
				if d.kind == WeaponDefinition.Kind.LAUNCHER:
					row[1] = tr("%d blast") % int(d.blast_damage)
				elif d.pellets > 1:
					row[1] = tr("%d × %d pellets") % [int(d.damage), d.pellets]
				elif d.is_continuous():
					row[1] = tr("%d / tick") % int(d.damage)
			"Fire rate":
				if d.is_continuous():
					row[1] = tr("continuous")
				elif d.kind == WeaponDefinition.Kind.RAIL:
					row[1] = tr("%.1f s charge") % d.charge_time
			"Reload":
				if d.reload_per_round:
					row[1] = tr("%.2f s / round") % d.reload_time
			"Noise":
				if d.n_max <= 0.0:
					row[1] = tr("silent")
		row[0] = tr(String(row[0]))
	if d.uses_ammo():
		rows.append([tr("Shared reserve"), "∞" if d.infinite else "%d" % Arsenal.get_reserve(d.id, d.ammo)])
	rows.append([tr("Draw"), tr("%.2f s") % d.draw_time])
	if not d.is_melee():
		rows.append([tr("Spread"), "±%.2f°" % d.jitter_deg + (" / ±%.2f°" % d.spread_deg if d.pellets > 1 else "")])
		rows.append([tr("Bloom"), "+%.2f° / %.2f°" % [d.bloom_per_shot, d.bloom_max]])
		rows.append([tr("Recoil"), "%.2f / %.2f" % [d.cam_kick, d.recoil]])
		rows.append([tr("Penetration"), _penetration_text(d)])
		rows.append([tr("Armour bypass"), "%d%%" % int(d.armor_pen * 100.0)])
		rows.append([tr("Heating"), "%.1f%% / %.1f%%" % [d.barrel_heat * 100.0, d.heat_gain * 100.0]])
	var fields := {}
	for part in Parts.of(String(d.key)):
		for modifier in part.get("mods", []):
			fields[String(modifier[0])] = true
	for field in PART_METRICS:
		if not fields.has(field):
			continue
		var spec: Array = PART_METRICS[field]
		var value := float(d.get(field))
		var text := (tr("Yes") if value != 0 else tr("No")) if spec[1] == "bool" else String(spec[1]) % (value * float(spec[2]))
		rows.append([tr(String(spec[0])), text])
	return rows

## Przebicie zrozumiale: energia kuli w przeszkodach (skrzynia, ciało) i dodatkowe cele promienia, szyny, bełtu (dawniej „0,00 / 1”).
func _penetration_text(d: RefCounted) -> String:
	var parts: Array = []
	if d.pen > 0.0:
		parts.append(tr("%.1f obstacles") % d.pen)
	if d.pierce > 0:
		parts.append(tr_n("+%d target", "+%d targets", d.pierce) % d.pierce)          # formy mnogie: translations/plural.csv
	return " · ".join(parts) if not parts.is_empty() else "—"

## Wiersz z paskiem na papierowej karcie: etykieta, pasek, napis wartości.
func _paper_bar(label: String, frac: float, value: String, col: Color, cap := -1.0) -> void:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	var l := UiTheme.ink(label, 9, UiTheme.INK_MUTED)
	l.custom_minimum_size.x = 84
	h.add_child(l)
	var bar := PaperBar.new()
	bar.custom_minimum_size.x = 90
	bar.frac = frac
	bar.cap = cap
	bar.col = col
	h.add_child(bar)
	var v := UiTheme.ink(UiTheme.num_text(value), 9, col, HORIZONTAL_ALIGNMENT_RIGHT)
	v.custom_minimum_size.x = 100
	h.add_child(v)
	_d_panel.add_child(h)

## Zalecenie stołu konserwacji dla broni `w`: jedna rzecz do zrobienia teraz, od najpilniejszej (od 1.7.413 — panel podawał same liczby).
## {level, id, text, short}: level 2 — pilne (broń się zacina albo czyszczenie nie wyprowadzi jej ponad próg zacięć, lufa ≥ SERVICE_URGENT),
## 1 — warto (część od progu wymiany), 0 — drobiazg (brud), -1 — nic do roboty; `id` — wiersz SERVICE, na który trafia kursor. {} — broń biała.
func _service_advice(w: int) -> Dictionary:
	var base: RefCounted = Weapons.base_def(w)
	var key := String(base.key)
	if base.is_melee():
		return {}
	var cond := Profile.condition(key)
	var cap := Profile.clean_cap(key)
	var ct := Profile.clean_time(key)
	var bw := Profile.part_wear(key, "barrel")
	var spread := int(round(Controller.BARREL_SPREAD * pow(bw / 100.0, 2.0) * 100.0))
	var jams: bool = base.can_jam()
	var springs := jams and Profile.service_due(key, "springs")
	var barrel := jams and Profile.service_due(key, "barrel")
	if springs and cap < Controller.JAM_FROM:
		return {"level": 2, "id": "springs", "short": tr("replace springs"),
			"text": tr("Replace the springs: cleaning only reaches %d%% — below %d%% the gun jams.") % [int(cap), int(Controller.JAM_FROM)]}
	if jams and cond < Controller.JAM_FROM and ct > 0.0:
		return {"level": 2, "id": "clean", "short": tr("clean (%d%%)") % int(cond),
			"text": tr("Clean it (%d s): at %d%% the gun jams.") % [ceili(ct), int(cond)]}
	if barrel and bw >= Profile.SERVICE_URGENT:
		return {"level": 2, "id": "barrel", "short": tr("replace barrel"), "text": tr("Replace the barrel: shots spread %d%% wider.") % spread}
	if springs:
		return {"level": 1, "id": "springs", "short": tr("replace springs"), "text": tr("Replace the springs: cleaning only reaches %d%%.") % int(cap)}
	if barrel:
		return {"level": 1, "id": "barrel", "short": tr("replace barrel"), "text": tr("Replace the barrel: shots spread %d%% wider.") % spread}
	if ct > 0.0:
		return {"level": 0, "id": "clean", "short": tr("clean (%d%%)") % int(cond), "text": tr("Clean it when you can (%d s) — condition %d%%.") % [ceili(ct), int(cond)]}
	return {"level": -1, "id": "clean", "short": "", "text": tr("In good order — nothing to do.")}

## Kolor zalecenia na papierze: pilne — koszt, warto — cena, drobiazg — atrament, nic — zysk.
static func _advice_ink(level: int) -> Color:
	return [UiTheme.INK_GAIN, UiTheme.INK, UiTheme.INK_PRICE, UiTheme.INK_COST][clampi(level + 1, 0, 3)]

## Lewa kolumna stołu konserwacji: co zrobić z całym ekwipunkiem — jedna linia na broń, która czegoś potrzebuje (pilne pierwsze).
func _refresh_service_todo() -> void:
	_svc_todo.visible = _mode == "service" and _page == 0
	_svc_note.visible = _svc_todo.visible
	if not _svc_todo.visible:
		return
	var rows: Array = []
	for i in _arms_list():
		var w := int(LIST[int(i)])
		if not Scrap.is_unlocked(w):
			continue
		var adv := _service_advice(w)
		if not adv.is_empty() and int(adv["level"]) >= 0:
			rows.append([int(adv["level"]), "%s — %s" % [String(Weapons.base_def(w).name), String(adv["short"])]])
	rows.sort_custom(func(a: Array, b: Array) -> bool: return int(a[0]) > int(b[0]))
	var lines: Array[String] = [tr("To do:")]
	for r in rows:
		lines.append(("! " if int(r[0]) >= 2 else "· ") + String(r[1]))
	if rows.is_empty():
		lines.append(tr("All guns in good order."))
	_svc_todo.text = "\n".join(lines)

## Kolor zużycia części eksploatacyjnej: zwykły poniżej progu wymiany, cena od Profile.SERVICE_DUE, koszt (pilne) od SERVICE_URGENT.
func _wear_ink(wear: float) -> Color:
	return UiTheme.INK_COST if wear >= Profile.SERVICE_URGENT else (UiTheme.INK_PRICE if wear >= Profile.SERVICE_DUE else UiTheme.INK)

## Stół konserwacji: stan broni, zużycie lufy i sprężyn ze skutkami (rozrzut, granica czyszczenia), szansa zacięcia i czas czyszczenia.
## Kreska na paskach zużycia = próg, od którego część da się wymienić.
func _fill_service_panel(base: RefCounted, cur: RefCounted) -> void:
	var key := String(base.key)
	if base.is_melee():
		var edge := Profile.edge_of(key)
		_paper_bar(tr("Edge"), edge / 100.0, "%d%%" % int(edge), UiTheme.INK_GAIN if edge >= 95.0 else UiTheme.INK)
		return
	var adv := _service_advice(int(LIST[_sel]))
	if not adv.is_empty():
		var lv := int(adv["level"])
		var al := UiTheme.ink(String(adv["text"]), 10, [UiTheme.OK, UiTheme.TEXT, UiTheme.ACCENT, UiTheme.DANGER][clampi(lv + 1, 0, 3)] if _mode == "service" else _advice_ink(lv))
		al.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		al.custom_minimum_size.x = DETAIL_W
		_d_panel.add_child(al)
	var cond := Profile.condition(key)
	var cap := Profile.clean_cap(key)
	var bw := Profile.part_wear(key, "barrel")
	var spread := int(round(Controller.BARREL_SPREAD * pow(bw / 100.0, 2.0) * 100.0))
	var sw := Profile.part_wear(key, "springs")
	# trzy przyrządy z manometrem (ST-02): czyszczenie — stan, czerwona strefa zacięć poniżej JAM_FROM, kropka lampy na limicie sprężyn,
	# cień wskazówki = dokąd dojdzie czyszczenie; lufa i sprężyny — zużycie ze strefą wymiany i pilną, cień = po wymianie
	var ops := _options(int(LIST[_sel]))
	var cur_id := String(ops[_opt]["id"]) if _opt >= 0 and _opt < ops.size() else ""
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_d_panel.add_child(row)
	_gauges.clear()
	var due := Profile.SERVICE_DUE / 100.0
	var urgent := Profile.SERVICE_URGENT / 100.0
	var ctime := Profile.clean_time(key)
	var specs := [
		["clean", tr("CLEANING"), tr("%d s") % ceili(ctime) if ctime > 0.0 else "—", cond / 100.0, cap / 100.0 if cond < cap - 0.5 else -1.0, cap / 100.0 if cap < 99.5 else -1.0,
			[[0.0, Controller.JAM_FROM / 100.0, Color(UiTheme.DANGER, 0.75)]],
			(tr("condition %d%% → %d%%") % [int(cond), int(cap)] if cond < cap - 0.5 else tr("condition %d%%") % int(cond)) + (" · " + tr("jams") if cond < Controller.JAM_FROM else "")],
		["barrel", tr("BARREL"), "%d" % int(Scrap.SERVICE_COST["barrel"]), bw / 100.0, 0.0 if Profile.service_due(key, "barrel") else -1.0, -1.0,
			[[due, urgent, Color(UiTheme.ACCENT, 0.6)], [urgent, 1.0, Color(UiTheme.DANGER, 0.75)]], tr("wear %d%% · spread +%d%%") % [int(bw), spread]],
		["springs", tr("SPRINGS"), "%d" % int(Scrap.SERVICE_COST["springs"]), sw / 100.0, 0.0 if Profile.service_due(key, "springs") else -1.0, -1.0,
			[[due, urgent, Color(UiTheme.ACCENT, 0.6)], [urgent, 1.0, Color(UiTheme.DANGER, 0.75)]], tr("wear %d%% · cleans to %d%%") % [int(sw), int(cap)]],
	]
	for s in specs:
		var g := ServiceArt.Gauge.new()
		g.job = String(s[0])
		g.title.text = String(s[1])
		g.right.text = String(s[2])
		g.dial.value = float(s[3])
		g.dial.ghost = float(s[4])
		g.dial.mark = float(s[5])
		g.dial.zones = s[6]
		g.sub.text = UiTheme.num_text(String(s[7]))
		g.set_lit(cur_id == g.job)
		var oi := ops.find({"slot": "service", "id": g.job})
		g.gui_input.connect(func(ev: InputEvent) -> void:
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT and oi >= 0:
				_pick_opt(oi))
		row.add_child(g)
		_gauges[g.job] = g
	var wc := _local_wc()
	var jam: float = wc.jam_chance(cur) if wc != null else 0.0
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 1)
	var deck := _mode == "service"                         # na blacie stołu konserwacji kolory blatu, nie atramentu
	grid.add_child(UiTheme.ink(tr("Jam chance"), 9, UiTheme.MUTED if deck else UiTheme.INK_MUTED))
	grid.add_child(UiTheme.ink(tr("none") if jam <= 0.0 else tr("1 in %d shots") % maxi(1, roundi(1.0 / jam)), 9,
		(UiTheme.DANGER if jam > 0.0 else UiTheme.OK) if deck else (UiTheme.INK_COST if jam > 0.0 else UiTheme.INK_GAIN)))
	_d_panel.add_child(grid)                              # czas czyszczenia stoi w wierszu „Czyszczenie” i na przycisku — nie trzeci raz tutaj

## Stół konserwacji (ST-02): karta znika — rozłożona broń na płótnie i przyrządy stoją na ciemnym blacie, napisy w kolorach blatu,
## lista części zastąpiona wyborem przyrządu (strzałki w lewo / w prawo albo klik). Pozostałe stanowiska: karta na papierze.
func _service_skin(on: bool) -> void:
	if _arms_paper.get_meta("service", false) == on:
		return
	_arms_paper.set_meta("service", on)
	var deck := StyleBoxFlat.new()
	deck.bg_color = Color(0, 0, 0, 0)
	deck.set_content_margin_all(2)
	_arms_paper.add_theme_stylebox_override("panel", deck if on else UiTheme.paper_box())
	_d_title.add_theme_color_override("font_color", UiTheme.TEXT if on else UiTheme.INK)
	_d_tag.add_theme_color_override("font_color", UiTheme.MUTED if on else UiTheme.INK_MUTED)
	_d_text.add_theme_color_override("font_color", UiTheme.MUTED if on else UiTheme.INK)
	_d_tiers.visible = not on
	_d_stage.modulate = Color(0.78, 0.76, 0.72) if on else Color.WHITE       # płótno z rozłożoną bronią przyciemnione — światło na przyrządach

## Pracownia / tokarka: droga części broni specjalnej PRÓBKI › BADANIE › SCHEMAT › TOKARKA › ŁAWA — zrobione kroki zielone, bieżący z paskiem,
## pod spodem jedno zdanie, co dalej (dawniej trzeba było to wyczytać z nawiasów przy częściach).
func _fill_lab_chain(key: String, slot: String, id: String) -> void:
	if id == "" or not Scrap.is_lab_part(id):
		return
	var rc := Scrap.research_cost(id)
	var step := 0
	var busy := false
	var note := ""
	if Scrap.has_part(id):
		step = 5 if Profile.fitted(key, slot) == id else 4
		note = tr("Fitted to your gun.") if step == 5 else tr("Part made — fit it at the workshop bench.")
	elif Scrap.lathe.has(id):
		step = 3
		busy = true
		note = tr("On the lathe — ready after a successful mission.")
	elif Scrap.schematics.has(id):
		step = 3
		note = tr("Schematic ready — make the part on the lathe.")
	elif Scrap.research.has(id):
		step = 1
		busy = true
		note = tr("Being researched — ready after a successful mission.")
	elif Scrap.samples >= rc.x:
		step = 1
		note = tr("You have %s — enough to research it at the lab.") % _samples_text(Scrap.samples)
	else:
		note = tr("Research needs %s, you have %d. Elites, bosses and side goals drop samples.") % [_samples_text(rc.x), Scrap.samples]
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 3)
	for i in LAB_STEPS.size():
		if i > 0:
			row.add_child(UiTheme.ink("›", 8, UiTheme.INK_MUTED))
		var done := i < step
		var cell := PanelContainer.new()
		var box := StyleBoxFlat.new()
		box.bg_color = UiTheme.PAPER_SEL if i == step else Color(0, 0, 0, 0)
		box.set_content_margin_all(1)
		box.content_margin_left = 3
		box.content_margin_right = 3
		cell.add_theme_stylebox_override("panel", box)
		cell.add_child(UiTheme.ink(tr(LAB_STEPS[i]) + ("…" if busy and i == step else ""), 8, UiTheme.INK_GAIN if done else (UiTheme.INK if i == step else UiTheme.INK_MUTED)))
		row.add_child(cell)
	_d_panel.add_child(row)
	var l := UiTheme.ink(note, 8)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = DETAIL_W
	_d_panel.add_child(l)

func _first_part_opt() -> int:
	if _mode == "bench":
		return -1
	var ops := _options(int(LIST[_sel]))
	if _mode == "service":                                # stół konserwacji: kursor od razu na tym, co zalecane
		var adv := _service_advice(int(LIST[_sel]))
		for i in ops.size():
			if not adv.is_empty() and String(ops[i]["id"]) == String(adv["id"]):
				return i
	for i in ops.size():
		if String(ops[i]["id"]) != "":
			return i
	return 0

## Akcja na wybranej broni: kup broń (zablokowana), a odblokowanej — kup część pod kursorem, zamontuj ją albo wróć do fabrycznej.
func _act() -> void:
	if not _pending_part.is_empty() or _buying >= 0:
		return
	var w: int = LIST[_sel]
	if not Scrap.is_unlocked(w):
		if _mode in ["service", "lab", "lathe"]:
			_say(tr("Buy it at the workshop bench first."), UiTheme.MUTED)
		else:
			_buying = w
			Scrap.request_buy(w)
		return
	var ops := _options(w)
	if ops.is_empty():
		return
	if _mode == "bench" and _opt < 0:
		return
	var o: Dictionary = ops[clampi(_opt, 0, ops.size() - 1)]
	var key := String(Weapons.def(w).key)
	var id := String(o["id"])
	if String(o["slot"]) == "preset":
		var pi := int(o["id"])
		if Profile.preset(key, pi).is_empty():
			_save_preset()
		elif Profile.is_preset_fitted(key, pi):
			_say(tr("Set %d is already fitted.") % (pi + 1), UiTheme.MUTED)
		else:
			var before := Profile.fit_code(w)
			var skipped := Profile.load_preset(key, pi)
			_success_fx(-6.0)
			_say((tr("Fitted set %d.") % (pi + 1)) if skipped == 0 else (tr("Fitted set %d — %d parts the squad no longer has stay as they were.") % [pi + 1, skipped]),
				UiTheme.OK if skipped == 0 else UiTheme.MUTED)
			_present_committed(w, before)
		return
	if String(o["slot"]) == "service" and id in Profile.WEAR_PARTS:
		if not Profile.service_due(key, id):
			_say(tr("Still serviceable — replace from %d%% wear.") % int(Profile.SERVICE_DUE), UiTheme.MUTED)
		else:
			Scrap.request_service(w, id)
		return
	if String(o["slot"]) == "service":
		if _clean_w == w:
			_stop_clean()
			_say(tr("Cleaning stopped."), UiTheme.MUTED)
			_refresh()
		elif id == "sharpen" and Profile.sharpen_time(key) <= 0.0:
			_say(tr("Already sharp."), UiTheme.MUTED)
		elif id != "sharpen" and Profile.clean_time(key) <= 0.0:
			_say(tr("Already clean."), UiTheme.MUTED)
		else:
			_start_clean(w)
		return
	if _mode == "lathe" and String(o["slot"]) != "service":
		if Scrap.has_part(id):
			_say(tr("Already made — fit it at the workshop bench."), UiTheme.MUTED)
		elif Scrap.lathe.has(id):
			_say(tr("On the lathe — ready after the next mission."), UiTheme.MUTED)
		elif Scrap.schematics.has(id):
			Scrap.request_machining(id)
		else:
			_say(tr("No schematic — research it at the lab first."), UiTheme.MUTED)
		return
	if _mode == "lab":
		if Scrap.schematics.has(id) or Scrap.lathe.has(id):
			_say(tr("Already researched — make it on the lathe downstairs."), UiTheme.MUTED)
			return
		if Scrap.has_part(id):
			_say(tr("Already known — fit it at the workshop bench."), UiTheme.MUTED)
		elif Scrap.research.has(id):
			_say(tr("Being researched — ready after the next mission."), UiTheme.MUTED)
		else:
			Scrap.request_research(id)
		return
	if id != "" and not Scrap.has_part(id):
		if Scrap.is_lab_part(id) and not Scrap.found.has(id):
			_say(tr("Special-weapon parts are researched at the lab upstairs."), UiTheme.MUTED)
		else:
			_pending_part = {"id": id, "w": w, "fit": Profile.fit_code(w), "session": _session, "revision": _selection_revision}
			_refresh()
			Scrap.request_part(id)
	elif Profile.fitted(key, String(o["slot"])) != id:
		var before := Profile.fit_code(w)
		Profile.set_fit(key, String(o["slot"]), id)
		_success_fx(-6.0)
		_say(tr("Fitted: %s.") % (tr(Parts.get_part(id)["name"]) if id != "" else tr("factory part")), UiTheme.OK)
		_present_committed(w, before)

func _on_result(w: int, ok: bool, reason: String) -> void:
	if _buying == w:
		_buying = -1
	if not _open:
		return
	var name := String(Weapons.def(w).name)
	match reason:
		"station":
			_say(tr("Approach the correct station in the hideout."), UiTheme.MUTED)
		"repeat":
			_say(tr("Please wait before repeating this action."), UiTheme.MUTED)
		"serviced":
			_say(tr("This part was already replaced during this visit."), UiTheme.MUTED)
		"ok":
			_say(tr("%s unlocked — take it from the rack.") % name, UiTheme.OK)
			_success_fx()
		"poor":
			_drum.broke()
			_say(tr("Not enough scrap (%d needed).") % Scrap.price_of(w), UiTheme.DANGER)
		"owned":
			_say(tr("%s is already unlocked.") % name, UiTheme.MUTED)
		"later":
			_say("Not available yet — a later zone.", UiTheme.MUTED)
		"reward":
			_say("Defeat the Leech to unlock it.", UiTheme.MUTED)
		_:
			_say("Cannot do that.", UiTheme.DANGER)
	_refresh()

## Zestaw pod kursorem: zapisuje bieżący montaż broni (nadpisuje). Poza wierszem zestawu nic nie robi.
func _save_preset() -> void:
	if _page != 0:
		return
	var w: int = LIST[_sel]
	var ops := _options(w)
	if ops.is_empty():
		return
	var o: Dictionary = ops[clampi(_opt, 0, ops.size() - 1)]
	if String(o["slot"]) != "preset":
		return
	Profile.save_preset(String(Weapons.def(w).key), int(o["id"]))
	_success_fx(-6.0)
	_say(tr("Current fit saved as set %d.") % (int(o["id"]) + 1), UiTheme.OK)
	_refresh()

## „1 próbka” / „3 próbki” (badania kosztują 1–3 próbki).
func _samples_text(n: int) -> String:
	return tr("1 sample") if n == 1 else tr("%d samples") % n

## Kontroler broni lokalnego gracza (masa ekwipunku w nagłówku ławy) albo null.
func _local_wc() -> Node:
	for p in get_tree().get_nodes_in_group("players"):
		if not p.is_bot and p.is_multiplayer_authority():
			return p.weapons
	return null

## Krótki opis zestawu: nazwy części (bez fabrycznych), „factory", gdy same fabryczne, „—" dla pustego.
func _preset_summary(key: String, i: int) -> String:
	var p := Profile.preset(key, i)
	if p.is_empty():
		return "—"
	var names: Array = []
	for s in Parts.slots_of(key):
		var id := String(p.get(s, ""))
		if id != "":
			names.append(tr(String(Parts.get_part(id)["name"])))
	var txt := ", ".join(names) if not names.is_empty() else tr("factory")
	return txt if txt.length() <= 30 else txt.substr(0, 29) + "…"

## Czyszczenie przy ławie (stan siedzi w profilu gracza, więc serwer nie bierze udziału): trwa Profile.clean_time, panel musi zostać
## otwarty, a gracz przy ławie — odejście, zmiana broni albo ponowne [E] przerywa i trzeba zacząć od nowa.
func _start_clean(w: int) -> void:
	_clean_w = w
	_clean_t = 0.0
	var melee := Weapons.def(w).is_melee()
	_clean_total = Profile.sharpen_time(String(Weapons.def(w).key)) if melee else Profile.clean_time(String(Weapons.def(w).key))
	Audio.play_variant("reload_bolt", 1, Audio.BUS_UI, -8.0, 0.85)
	_say((tr("Sharpening the %s…") if melee else tr("Stripping the %s…")) % String(Weapons.def(w).name), UiTheme.TEXT)
	_refresh()

func _stop_clean() -> void:
	_clean_w = -1
	_clean_t = 0.0

## Klatka czyszczenia (z `_process`; testy wołają ją ręcznie).
func tick_clean(delta: float) -> void:
	if _clean_w < 0:
		return
	_clean_t += delta
	var ck := String(Weapons.def(_clean_w).key)
	var melee := Weapons.def(_clean_w).is_melee()
	if _clean_t < _clean_total:
		_action.text = (tr("Sharpening…  %d%%  (again to stop)") if melee else tr("Cleaning…  %d%%  (again to stop)")) % int(100.0 * _clean_t / _clean_total)
		if String(_action.get_meta("st", "")) != "busy":
			_act_state(_action, "busy", 0)
			_dress_action(_action)
		if not melee:
			var c0 := Profile.condition(ck)                 # brud schodzi z broni w trakcie (ława 3D)
			(_d_stage as GunStage).set_dirt(1.0 - lerpf(c0, Profile.clean_cap(ck), _clean_t / _clean_total) / 100.0)
			if _gauges.has("clean") and is_instance_valid(_gauges["clean"]):            # przyrząd czyszczenia: wskazówka idzie do limitu
				(_gauges["clean"] as ServiceArt.Gauge).dial.value = lerpf(c0, Profile.clean_cap(ck), _clean_t / _clean_total) / 100.0
		return
	var w := _clean_w
	_stop_clean()
	if melee:
		Profile.sharpen(ck)                                 # szlifierka (W6b)
		_stamp()
		_say(tr("%s sharpened — edge 100%%.") % String(Weapons.def(w).name), UiTheme.OK)
		Audio.play_variant("reload_bolt", 1, Audio.BUS_UI, -6.0, 1.3)
		_refresh()
		return
	Profile.clean(ck)
	_stamp()
	_say(tr("%s stripped and cleaned — condition %d%%.") % [String(Weapons.def(w).name), int(Profile.condition(ck))], UiTheme.OK)
	Audio.play_variant("reload_bolt", 1, Audio.BUS_UI, -6.0, 1.0)
	_refresh()

func _on_machining_result(id: String, ok: bool, reason: String) -> void:
	if not _open:
		return
	var nm := tr(String(Parts.get_part(id).get("name", id)))
	match reason:
		"station":
			_say(tr("Approach the correct station in the hideout."), UiTheme.MUTED)
		"repeat":
			_say(tr("Please wait before repeating this action."), UiTheme.MUTED)
		"serviced":
			_say(tr("This part was already replaced during this visit."), UiTheme.MUTED)
		"ok":
			_say(tr("%s on the lathe — ready after the next mission.") % nm, UiTheme.OK)
			_success_fx()
		"poor":
			_drum.broke()
			_say(tr("Not enough scrap (%d needed).") % Scrap.machine_price(id), UiTheme.DANGER)
		"busy":
			_say(tr("The lathe is busy — %d job per mission.") % Scrap.LATHE_SLOTS, UiTheme.MUTED)
		"noschem":
			_say(tr("No schematic — research it at the lab first."), UiTheme.MUTED)
		"owned":
			_say(tr("Already made."), UiTheme.MUTED)
		"off":
			_say("No scrap in this mode.", UiTheme.MUTED)
		_:
			_say("Cannot do that.", UiTheme.DANGER)
	_refresh()

func _on_service_result(w: int, part: String, ok: bool, reason: String) -> void:
	if not _open:
		return
	match reason:
		"station":
			_say(tr("Approach the correct station in the hideout."), UiTheme.MUTED)
		"repeat":
			_say(tr("Please wait before repeating this action."), UiTheme.MUTED)
		"serviced":
			_say(tr("This part was already replaced during this visit."), UiTheme.MUTED)
		"early":
			_say(tr("Still serviceable — replace from %d%% wear.") % int(Profile.SERVICE_DUE), UiTheme.MUTED)
		"ok":
			_say((tr("New barrel in the %s.") if part == "barrel" else tr("New springs in the %s.")) % String(Weapons.def(w).name), UiTheme.OK)
			Audio.play_variant("reload_bolt", 1, Audio.BUS_UI, -6.0, 1.1)
		"poor":
			_drum.broke()
			_say(tr("Not enough scrap (%d needed).") % int(Scrap.SERVICE_COST.get(part, 0)), UiTheme.DANGER)
		_:
			_say("Cannot do that.", UiTheme.DANGER)
	_refresh()

func _on_research_result(id: String, ok: bool, reason: String) -> void:
	if not _open:
		return
	var nm := tr(String(Parts.get_part(id).get("name", id)))
	var cost := Scrap.research_cost(id)
	match reason:
		"station":
			_say(tr("Approach the correct station in the hideout."), UiTheme.MUTED)
		"repeat":
			_say(tr("Please wait before repeating this action."), UiTheme.MUTED)
		"serviced":
			_say(tr("This part was already replaced during this visit."), UiTheme.MUTED)
		"ok":
			_say(tr("%s: research started — ready after the next mission.") % nm, UiTheme.OK)
			_success_fx()
		"samples":
			_say(tr("Not enough samples (%d needed) — elites and bosses drop them.") % cost.x, UiTheme.DANGER)
		"poor":
			_drum.broke()
			_say(tr("Not enough scrap (%d needed).") % cost.y, UiTheme.DANGER)
		"busy":
			_say(tr("The lab is busy — %d project per mission.") % Scrap.LAB_SLOTS, UiTheme.MUTED)
		"locked":
			_say(tr("Buy the gun at the workshop bench first."), UiTheme.MUTED)
		"owned":
			_say(tr("Already known."), UiTheme.MUTED)
		"off":
			_say("No scrap in this mode.", UiTheme.MUTED)
		_:
			_say("Cannot do that.", UiTheme.DANGER)
	_refresh()

func _on_part_result(id: String, ok: bool, reason: String) -> void:
	var context: Dictionary = _pending_part.duplicate() if String(_pending_part.get("id", "")) == id else {}
	if not context.is_empty():
		_pending_part.clear()
	if not _open:
		return
	var nm := tr(String(Parts.get_part(id).get("name", id)))
	match reason:
		"station":
			_say(tr("Approach the correct station in the hideout."), UiTheme.MUTED)
		"repeat":
			_say(tr("Please wait before repeating this action."), UiTheme.MUTED)
		"serviced":
			_say(tr("This part was already replaced during this visit."), UiTheme.MUTED)
		"ok":
			_say(tr("%s unlocked for the squad and fitted to your gun.") % nm, UiTheme.OK)
			_success_fx()
		"poor":
			_drum.broke()
			_say(tr("Not enough scrap (%d needed).") % Scrap.part_cost(id), UiTheme.DANGER)
		"owned":
			_say(tr("The squad already has %s.") % nm, UiTheme.MUTED)
		"locked":
			_say("Unlock the weapon first.", UiTheme.MUTED)
		_:
			_say("Cannot do that.", UiTheme.DANGER)
	if ok and not context.is_empty() and int(context["session"]) == _session and int(context["revision"]) == _selection_revision and int(LIST[_sel]) == int(context["w"]):
		_present_committed(int(context["w"]), int(context["fit"]))
	else:
		_refresh()

func _say(text: String, col: Color) -> void:
	_msg.text = text
	_msg.add_theme_color_override("font_color", col)
	_msg_t = 3.0

# ---------------------------------------------------------------- odświeżanie

func _refresh() -> void:
	_refresh_body()
	if _open:
		for b in [_action, _s_action, _p_action, _l_action]:
			_dress_action(b)

func _refresh_body() -> void:
	if not _open:
		return
	_tick_wallet()
	for pi in _page_btns.size():
		_page_btns[pi].set_pressed_no_signal(pi == _page)
	var immersive := _mode == "bench" and _page == 0
	_workbench.visible = immersive
	_shade.visible = true                              # każde stanowisko przygasza scenę jak ława — uwaga na panelu
	_d_stage = _workbench.stage if immersive else _legacy_stage
	_legacy_stage.set_rendering(_page == 0 and not immersive)
	_workbench.stage.set_rendering(immersive)
	_hint.text = StationKit.tape_text(_controls_hint())
	_card.add_theme_stylebox_override("panel", UiTheme.panel_box() if immersive else UiTheme.station_box())
	_arms_body.visible = _page == 0 and not immersive
	_sup_body.visible = _page == 1
	_perk_body.visible = _page == 2
	_look_body.visible = _page == 3
	_action.visible = _page == 0
	_s_action.visible = _page == 1
	_p_action.visible = _page == 2
	_l_action.visible = _page == 3
	for body in [_arms_body, _sup_body, _perk_body, _look_body]:
		body.get_parent().visible = body.visible
	if _page == 3:
		_refresh_look()
		_card.reset_size()
		return
	if _page == 2:
		_refresh_perks()
		_card.reset_size()
		return
	if _page == 1:
		_refresh_supplies()
		_card.reset_size()
		return
	var arms := _arms_list()
	if not arms.is_empty() and not arms.has(_sel):
		_sel = _initial_selection()
	for i in _tiles.size():
		(_tiles[i] as Tile).visible = arms.has(i)
		_refresh_tile(_tiles[i] as Tile, i == _sel)
	_refresh_service_todo()
	_refresh_detail(int(LIST[_sel]))

func _refresh_supplies() -> void:
	var kinds := _supply_kinds()
	for i in _sup_tiles.size():
		var t := _sup_tiles[i] as SupplyTile
		var sel := i == _sup_sel
		t.set_lit(sel)
		var k := String(kinds[i])
		t.visible = _sup_in_mode(k)
		var have := Arsenal.get_throwable(k)
		var price := _sup_price(k)
		t.price_label.text = ("%d" % price) + (("  +%d" % Scrap.ordered(k)) if Scrap.ordered(k) > 0 else "")
		(t.icon_node as ItemIcon).set_item(k, Color.WHITE if have > 0 or Scrap.bank >= price else Color(0.6, 0.64, 0.68))
		t.name_label.add_theme_color_override("font_color", UiTheme.ACCENT if sel else UiTheme.TEXT)
		t.price_label.add_theme_color_override("font_color", GOLD if Scrap.bank >= price else UiTheme.DANGER)
		t.bar.have = Throwables.units(k, have)
		t.bar.queue_redraw()
		if t.icon_node is SupplyArt.BoxFace:                 # pudełko na półce: okienka = pudełka przy sobie, cena na desce
			(t.icon_node as SupplyArt.BoxFace).stock = t.bar.have
			t.icon_node.queue_redraw()
		elif _is_pyro_kind(k):                               # przegroda skrzyni: napis atramentem na pasku, licznik w rogu
			t.name_label.add_theme_color_override("font_color", UiTheme.INK)
			t.name_label.add_theme_constant_override("outline_size", 0)
			t.price_label.add_theme_color_override("font_color", UiTheme.INK_PRICE if Scrap.bank >= price else UiTheme.INK_COST)
			t.price_label.add_theme_constant_override("outline_size", 0)
			t.state_label.text = "%d/%d" % [Throwables.units(k, have), t.bar.maxn]
			t.state_label.add_theme_color_override("font_color", UiTheme.TEXT if have > 0 else UiTheme.MUTED)
		t.tooltip_text = tr("The squad carries %d of %d.") % [have, int(Throwables.KINDS[k]["max"])]
	_sup_note.text = tr("Grenades, mines and 40 mm rounds are at the pyrotechnics table, special ammo at the reloading press.") if _mode == "bench" else ""
	_sup_note.visible = _sup_note.text != ""
	var k2 := String(kinds[_sup_sel])
	var d: Dictionary = Throwables.KINDS[k2]
	var have2 := Arsenal.get_throwable(k2)
	var maxn := int(d["max"])
	_s_icon.set_item(k2, Color.WHITE)
	_s_title.text = String(d["name"])
	var mode: String = {"throw": "Throwable", "place": "Placed", "use": "Tool", "ammo": "Ammunition"}[String(d["mode"])]
	_s_tag.text = "%s  ·  %s" % [tr(String(d["full"])), tr(mode)]
	if Throwables.is_ammo(k2):
		_s_title.text = tr(String(d["full"]))               # pełna nazwa naboju zamiast skrótu z kafla („7.62 HOT” → „7.62×39 ładunek wzmocniony”)
		_s_tag.text = "%s  ·  %s" % [String(d["name"]), tr(mode)]
	for ch in _s_stats.get_children():
		_s_stats.remove_child(ch)
		ch.free()
	var rows: Array = [["Carried", "%d / %d" % [have2, maxn]], ["Issued free", tr("%d per mission") % int(d["issue"]) if int(d["issue"]) > 0 else "—"]]
	if Throwables.is_ammo(k2):
		var ct := Ammo.from_kind(k2)
		var users: Array = []
		for wd in Weapons.defs():
			if String(wd.caliber) == String(ct.get("cal", "")):
				users.append(String(wd.name))
		rows = [["Carried", tr("%d / %d rounds") % [have2, maxn]], ["Box", tr("%d rounds") % Throwables.box_of(k2)], ["Fits", ", ".join(users)]]
	elif (d.has("noise") or k2 in ["frag", "charge"]) and _mode != "pyro":
		rows.append(["Noise", Codex.noise_text(k2)])                       # przy stole pirotechnicznym hałas pokazuje VU-metr
	if Throwables.FUSES.has(k2) and _mode != "pyro":
		rows.append(["Fuse", "%.1f s" % Scrap.fuse_of(k2)])              # przy stole pirotechnicznym zapalnik ma własny przełącznik
	for r in rows:
		_s_stats.add_child(UiTheme.ink(tr(String(r[0])), 9, UiTheme.INK_MUTED))
		_s_stats.add_child(UiTheme.ink(UiTheme.num_text(tr(String(r[1]))), 9))
		_s_stats.add_child(Control.new())
	_fill_noise(k2)
	_fill_fuse(k2)
	_fill_blast(k2)
	_fill_ammo_cmp(k2)
	_notch.target = _sup_tiles[_sup_sel]
	_fill_press_queue()
	_s_text.text = tr(String(d["note"]))
	var summary := _queue_summary(_mode == "press")
	if summary != "":
		_s_text.text += "\n\n" + summary
	if Throwables.is_ammo(k2):
		_s_text.text += "\n" + tr("[%s] in the field picks the ammo type for the next magazine.") % Actions.key("ammo_type")
	var price2 := _sup_price(k2)
	var queued := Scrap.ordered(k2) * Throwables.box_of(k2) + int(Scrap.deliveries.get(k2, 0))
	_act_state(_s_action, "", 0)
	_s_action.disabled = have2 + queued >= maxn or not Scrap.enabled()
	if not Scrap.enabled():
		_s_action.text = "No scrap in this mode"
	elif int(Scrap.deliveries.get(k2, 0)) > 0:
		_s_action.disabled = have2 >= maxn
		_s_action.text = tr("Collect ready delivery · %d rounds") % int(Scrap.deliveries[k2])
		_act_state(_s_action, "collect", 0)
	elif have2 + queued >= maxn:
		_s_action.text = "The squad is carrying the maximum"
	elif Throwables.is_ammo(k2) and Scrap.orders.size() >= Scrap.PRESS_SLOTS:
		_s_action.text = tr("The press is full — %d batches per mission") % Scrap.PRESS_SLOTS
	elif Throwables.is_ammo(k2):
		_s_action.text = tr("Order a batch  ·  %d scrap  ·  ready after the mission") % price2
		_act_state(_s_action, "ready", price2)
	else:
		_s_action.text = (tr("Buy a box  ·  %d scrap") % price2) if Throwables.is_ammo(k2) else (tr("Buy +1  ·  %d scrap") % price2)
		_act_state(_s_action, "ready", price2)

func _on_supply_result(kind: String, ok: bool, reason: String) -> void:
	if not _open:
		return
	var nm := String(Throwables.KINDS[kind]["name"]) if Throwables.is_valid(kind) else kind
	match reason:
		"station":
			_say(tr("Approach the correct station in the hideout."), UiTheme.MUTED)
		"repeat":
			_say(tr("Please wait before repeating this action."), UiTheme.MUTED)
		"serviced":
			_say(tr("This part was already replaced during this visit."), UiTheme.MUTED)
		"ok":
			_say(tr("%s bought — the squad now carries %d.") % [nm, Arsenal.get_throwable(kind)], UiTheme.OK)
			_success_fx()
		"poor":
			_drum.broke()
			_say(tr("Not enough scrap (%d needed).") % Throwables.price_of(kind), UiTheme.DANGER)
		"full":
			_say(tr("The squad cannot carry more %s.") % nm, UiTheme.MUTED)
		"off":
			_say("No scrap in this mode.", UiTheme.MUTED)
		_:
			_say("Cannot do that.", UiTheme.DANGER)
	_refresh()

func _refresh_tile(t: Tile, selected: bool) -> void:
	var w := t.weapon
	t.set_lit(selected)
	var unlocked := Scrap.is_unlocked(w)
	var later := Scrap.is_later(w)
	(t.icon_node as GunIcon).set_gun(int(Weapons.base_def(w).gun_row), Weapons.base_def(w).tracer_color, Color.WHITE if unlocked else Color(0.45, 0.5, 0.55))
	t.name_label.add_theme_color_override("font_color", UiTheme.ACCENT if selected else (UiTheme.TEXT if unlocked else UiTheme.MUTED))
	t.bar.visible = false
	if t.marks != null:
		t.marks.visible = false                       # ikonki wymian tylko na stole konserwacji (włącza je gałąź „service” niżej)
	t.state_label.add_theme_color_override("font_color", UiTheme.MUTED)
	# Kafle są tylko na stanowiskach pomocniczych (ława ma własny stojak): broń kupuje się wyłącznie przy ławie, więc bez ceny.
	# Linia stanu mówi to, co liczy się PRZY TYM stanowisku: stół konserwacji — stan, szlifierka — ostrze, reszta — odblokowane części.
	if unlocked:
		var key := String(Weapons.def(w).key)
		var melee: bool = Weapons.base_def(w).is_melee()
		var total := Parts.of(key).size()
		var owned := Scrap.parts_owned(w)
		t.tooltip_text = tr("Unlocked parts: %d / %d. Equipment is chosen separately.") % [owned, total]
		if _mode == "service" and not melee:
			var cond := Profile.condition(key)
			t.state_label.text = (tr("Condition %d%%") % int(cond)).to_upper()
			t.state_label.add_theme_color_override("font_color", UiTheme.DANGER if cond < 70.0 else (GOLD if cond < 95.0 else UiTheme.OK))
			t.tooltip_text = tr("Below 70% a gun starts to jam.")
			# ikonki części do wymiany (lufa, sprężyny) w miejscu kropek części — na stole konserwacji kropek nie ma
			var tile := t as Tile
			if tile != null:
				if tile.marks == null:
					tile.marks = ServiceMarks.new()
					tile.marks.position = Vector2(TILE_W - 6.0 - tile.marks.size.x, TILE_H - 19.0)
					tile.add_child(tile.marks)
				for pid in Profile.WEAR_PARTS:
					var pw := Profile.part_wear(key, String(pid))
					var st := 0 if not (Weapons.def(w).can_jam() and Profile.service_due(key, String(pid))) else (2 if pw >= Profile.SERVICE_URGENT else 1)
					tile.marks.set(String(pid), st)
				tile.marks.visible = true
				tile.marks.queue_redraw()
		elif _mode == "lathe" and melee:
			t.state_label.text = (tr("Edge %d%%") % int(Profile.edge_of(key))).to_upper()
		else:
			t.state_label.text = tr("PARTS") if total > 0 else ""
			t.bar.visible = total > 0
			t.bar.set("level", owned)
			t.bar.set("total", total)
			t.bar.set("maxed", owned >= total)
			t.place_bar()
			t.bar.queue_redraw()
	elif later:
		t.state_label.text = tr("BOSS REWARD") if Scrap.is_gated(w) else tr("LATER ZONE")
	else:
		t.state_label.text = tr("BUY AT THE BENCH")

func _refresh_detail(w: int) -> void:
	_service_skin(_mode == "service")
	_action.disabled = false
	_act_state(_action, "", 0)
	var base: RefCounted = Weapons.base_def(w)
	var key := String(base.key)
	var unlocked := Scrap.is_unlocked(w)
	var ops := _options(w)
	_opt = clampi(_opt, -1 if _mode == "bench" else 0, maxi(ops.size() - 1, 0))
	var mine := Profile.fit_code(w)
	var controller := _local_wc()
	var ammo_type: int = controller.ammo_of(w) if controller != null else 0
	var cur: RefCounted = Weapons.def_build(w, Weapons.build_of(ammo_type, mine))
	# podgląd: broń z częścią spod kursora zamontowaną w jej gnieździe (reszta jak teraz)
	var preview: RefCounted = null
	var o: Dictionary = ops[_opt] if not ops.is_empty() and _opt >= 0 else {}
	if _mode == "bench" and not o.is_empty():
		_bench_slot = String(o["slot"])
	if unlocked and not o.is_empty() and String(o["id"]) != "" and not String(o["slot"]) in ["preset", "service"]:
		Profile.mark_seen("part:" + String(o["id"]))          # część pod kursorem jest obejrzana — kropka „nowe” gaśnie
	var pv_code := mine
	if unlocked and not o.is_empty():
		var choice := {}
		for s in Parts.slots_of(key):
			choice[s] = Profile.fitted(key, String(s))
		if String(o["slot"]) == "preset":                      # zestaw: cała broń z tym zestawem (części, których drużyna nie ma, zostają jak są)
			var pset := Profile.preset(key, int(o["id"]))
			for s in pset:
				if String(pset[s]) == "" or Scrap.has_part(String(pset[s])):
					choice[s] = String(pset[s])
		else:
			choice[String(o["slot"])] = String(o["id"])
		pv_code = Parts.encode(key, choice)
		if pv_code != mine:
			preview = Weapons.def_build(w, Weapons.build_of(ammo_type, pv_code))
	# na ławie broń już z częścią spod kursora; ona (albo fabryczny element gniazda) świeci i jest wysunięta
	var hl_part := unlocked and not o.is_empty() and String(o["slot"]) != "preset" and String(o["slot"]) != "service"
	var hl_slot := String(o.get("slot", "")) if hl_part else ("barrel" if unlocked and not o.is_empty() and String(o["id"]) == "barrel" else "")
	(_d_stage as GunStage).show_gun(w, Parts.decode(key, pv_code), String(o.get("id", "")) if hl_part else "", hl_slot, not unlocked)
	(_d_stage as GunStage).set_dirt((1.0 - Profile.condition(key) / 100.0) if unlocked and not base.is_melee() else 0.0)   # brud wg stanu broni (W2)
	(_d_stage as GunStage).set_strip(_clean_w == w)
	_d_title.text = String(base.name)
	var tag := tr(Codex._slot_name(base))
	if unlocked and not Parts.of(key).is_empty():
		tag += tr("  ·  UNLOCKED %d / %d") % [Scrap.parts_owned(w), Parts.of(key).size()]
		tag += tr("  ·  FITTED %d") % Parts.decode(key, mine).size()
	elif not unlocked:
		tag += tr("  ·  LOCKED")
	if unlocked and Profile.kills(key) > 0:
		tag += tr("  ·  KILLS %d") % Profile.kills(key)                    # historia broni (etap 5b)
	if unlocked:
		# wprawa (etap 5a): stopień i punkty do następnego
		var ml := Profile.mastery_level(key)
		var mp := Profile.mastery_points(key)
		if ml < Profile.MASTERY_XP.size() - 1:
			tag += tr("  ·  MASTERY %s  (%d / %d)") % [["0", "I", "II", "III", "IV", "V"][ml], mp, int(Profile.MASTERY_XP[ml + 1])]
		else:
			tag += tr("  ·  MASTERY %s") % ["0", "I", "II", "III", "IV", "V"][ml]
	if _mode == "lab":
		tag += tr("  ·  SAMPLES %d") % Scrap.samples + ((tr(" (+%d this mission)") % Scrap.samples_loot) if Scrap.samples_loot > 0 else "")
	if _mode == "bench" and Settings.realistic_handling:
		var lp := _local_wc()
		if lp != null:
			var km: float = lp.kit_mass()
			tag += UiTheme.num_text(tr("  ·  KIT %.1f kg  (run noise %+d%%)") % [km, int(round((lp.mass_noise_mult() - 1.0) * 100.0))])   # masa ekwipunku (W5)
	if cur.uses_ammo() and Ammo.name_of(String(cur.caliber), ammo_type) != "":         # ogniwo LR-7 nie ma nazwy naboju
		tag += tr("  ·  AMMO %s") % Ammo.name_of(String(cur.caliber), ammo_type)
	_d_tag.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_d_tag.custom_minimum_size.x = DETAIL_W
	_d_tag.text = tag
	var jobs := _queue_summary()
	if jobs != "":
		_d_tag.text += "\n" + jobs
	# statystyki: broń, jaką masz teraz, i ta sama z częścią spod kursora (złote wartości — zmiany względem bieżącego montażu)
	for ch in _d_stats.get_children():
		_d_stats.remove_child(ch)
		ch.free()
	var now_rows: Array = _comparison_rows(cur)
	var next_rows: Array = _comparison_rows(preview) if preview != null else []
	if next_rows.is_empty():
		next_rows = now_rows.duplicate(true)
	if controller != null and (controller.loadout.has(w) or controller.melee_id == w):
		var km: float = controller.kit_mass()
		var next_mass: float = km + (preview.mass - cur.mass if preview != null else 0.0)
		now_rows.append([tr("Kit mass"), tr("%.2f kg") % km])
		next_rows.append([tr("Kit mass"), tr("%.2f kg") % next_mass])
		var speed: float = clampf(1.0 - Controller.MASS_SPEED * (next_mass - Controller.mass_ref()), Controller.MASS_SPEED_RANGE.x, Controller.MASS_SPEED_RANGE.y) if Settings.realistic_handling else 1.0
		var noise: float = clampf(1.0 + Controller.MASS_NOISE * (next_mass - Controller.mass_ref()), Controller.MASS_NOISE_RANGE.x, Controller.MASS_NOISE_RANGE.y) if Settings.realistic_handling else 1.0
		now_rows.append([tr("Run speed / noise"), "%+.1f%% / %+.1f%%" % [(controller.mass_speed_mult() - 1.0) * 100.0, (controller.mass_noise_mult() - 1.0) * 100.0]])
		next_rows.append([tr("Run speed / noise"), "%+.1f%% / %+.1f%%" % [(speed - 1.0) * 100.0, (noise - 1.0) * 100.0]])
	for i in now_rows.size():
		var r: Array = now_rows[i]
		# Podgląd części/zestawu zaczyna od rzeczywistych zmian. Pełna karta jest widoczna bez zmiany montażu.
		if preview != null and i < next_rows.size() and String(next_rows[i][1]) == String(r[1]):
			continue
		_d_stats.add_child(UiTheme.ink(String(r[0]), 9, UiTheme.INK_MUTED))
		_d_stats.add_child(UiTheme.ink(UiTheme.num_text(String(r[1])), 9))
		# zmiana: nowa wartość i słowna ocena („korzyść” / „kompromis”) — kolor tylko ją wzmacnia. Strzałka „→” nie ocenia: więcej
		# nie zawsze znaczy lepiej (masa, grzanie), więc ↑ / ↓ myliłyby kierunek liczby z oceną.
		var nv := ""
		var verdict := ""
		var kind := 0
		if i < next_rows.size() and String(next_rows[i][1]) != String(r[1]):
			kind = _change_kind(String(r[0]), cur, preview) if preview != null else 0
			nv = "→ %s" % String(next_rows[i][1])
			verdict = tr("Gain") if kind > 0 else (tr("Trade-off") if kind < 0 else "")
		var col := UiTheme.INK_GAIN if kind > 0 else (UiTheme.INK_COST if kind < 0 else UiTheme.INK)
		_d_stats.add_child(UiTheme.ink(UiTheme.num_text(nv), 9, col))
		_d_stats.add_child(UiTheme.ink(verdict.to_lower(), 7, col))
	_clear_children(_d_panel)
	if unlocked and (_mode == "service" or (_mode == "lathe" and base.is_melee())):          # szlifierka: pasek ostrza
		_clear_children(_d_stats)                         # przy czyszczeniu liczy się stan i zużycie, nie 22 parametry balistyczne
		_fill_service_panel(base, cur)
	elif (_mode == "lab" or _mode == "lathe") and not o.is_empty() and String(o["slot"]) != "service":
		_fill_lab_chain(key, String(o["slot"]), String(o["id"]))
	# części w gniazdach: nagłówek gniazda, element fabryczny i części (zamontowana — zielona, odblokowana — atrament, do kupienia — z ceną)
	for ch in _d_tiers.get_children():
		_d_tiers.remove_child(ch)
		ch.queue_free()                  # wiersz może właśnie obsługiwać swoje kliknięcie (_pick_opt) — natychmiastowe free() jest wtedy błędem
	var last_slot := ""
	for i in ops.size():
		var op: Dictionary = ops[i]
		var slot := String(op["slot"])
		if slot != last_slot:
			last_slot = slot
			var head_txt := tr("Service") if slot == "service" else (tr("Sets") if slot == "preset" else _slot_label(String(Weapons.def(int(LIST[_sel])).key), slot))
			_d_tiers.add_child(UiTheme.ink(head_txt.to_upper(), 7, UiTheme.INK_MUTED))
		if slot == "preset":
			var pi := int(op["id"])
			var pfit := Profile.is_preset_fitted(key, pi)
			_tier_row(i, tr("Set %d  ·  %s") % [pi + 1, _preset_summary(key, pi)],
				tr("empty") if Profile.preset(key, pi).is_empty() else (tr("fitted") if pfit else tr("saved")), UiTheme.INK_GAIN if pfit else UiTheme.INK)
			continue
		if slot == "service":
			var cc := Profile.clean_time(key)
			var sid := String(op["id"])
			var pw := Profile.part_wear(key, sid) if sid != "clean" else 0.0
			var due := (cc > 0.0) if sid == "clean" else Profile.service_due(key, sid)
			var cap := Profile.clean_cap(key)
			if sid == "sharpen":
				var st := Profile.sharpen_time(key)
				_tier_row(i, tr("Sharpen  ·  edge %d%%") % int(Profile.edge_of(key)), tr("%d s") % ceili(st) if st > 0.0 else tr("sharp"), UiTheme.INK_COST if st > 0.0 else UiTheme.INK_GAIN)
			elif sid == "clean":
				var ctxt := (tr("Clean  ·  condition %d%%") % int(Profile.condition(key))) if cap >= 99.5 else (tr("Clean  ·  condition %d%% (max %d%%)") % [int(Profile.condition(key)), int(cap)])
				_tier_row(i, ctxt, tr("%d s") % ceili(cc) if cc > 0.0 else tr("clean"), UiTheme.INK_COST if due else UiTheme.INK_GAIN)
			else:
				var pname := tr("Barrel") if sid == "barrel" else tr("Springs")
				# poniżej progu bez ceny (nie da się wymienić), od progu cena, od SERVICE_URGENT cena w kolorze kosztu
				var ptail := tr("%d scrap") % int(Scrap.SERVICE_COST[sid]) if due else (tr("like new") if pw < 0.5 else tr("from %d%%") % int(Profile.SERVICE_DUE))
				var pcol := (UiTheme.INK_COST if pw >= Profile.SERVICE_URGENT else UiTheme.INK_PRICE) if due else (UiTheme.INK_GAIN if pw < 0.5 else UiTheme.INK_MUTED)
				_tier_row(i, tr("%s  ·  worn %d%%") % [pname, int(pw)], ptail, pcol)
			continue
		var id := String(op["id"])
		var fitted := Profile.fitted(key, slot) == id
		var owned := id == "" or Scrap.has_part(id)
		var nm := tr("Factory") if id == "" else tr(String(Parts.get_part(id)["name"]))
		var tail := tr("fitted") if fitted else ("" if id == "" else (tr("owned") if owned else (tr("found — extract") if Scrap.found.has(id) else tr("%d scrap") % Scrap.part_cost(id))))
		if id != "" and not owned and not Scrap.found.has(id) and Scrap.is_lab_part(id):
			var rc := Scrap.research_cost(id)
			if Scrap.lathe.has(id):
				tail = tr("on the lathe")
			elif Scrap.schematics.has(id):
				tail = (tr("%d scrap") % Scrap.machine_price(id)) if _mode == "lathe" else tr("schematic")
			elif Scrap.research.has(id):
				tail = tr("researching")
			elif _mode == "lab":
				tail = tr("%s · %d scrap") % [_samples_text(rc.x), rc.y]
			else:
				tail = tr("no schematic") if _mode == "lathe" else tr("lab")
		elif (_mode == "lab" or _mode == "lathe") and owned:
			tail = tr("known") if _mode == "lab" else tr("made")
		_tier_row(i, nm, tail, UiTheme.INK_GAIN if fitted else (UiTheme.INK if owned else UiTheme.INK_PRICE))
	var notes: Array = Codex.WEAPON_TEXT.get(key, ["", ""])
	var desc := Actions.fmt(tr(String(notes[0])))
	if unlocked and not o.is_empty() and String(o["slot"]) == "preset":
		desc = tr("Your saved sets of parts for this gun (only yours — the squad shares the unlocks, not the build). %s fits the set, %s saves your current fit over it.") % [
			_menu_key("menu_accept", Actions.pad_mode), _menu_key("menu_alt", Actions.pad_mode)]
	elif unlocked and not o.is_empty() and String(o["slot"]) == "service" and String(o["id"]) == "barrel":
		desc = tr("Every shot wears the bore, a hot one three times faster; a worn barrel spreads wider (up to +60%%). Replace from %d%% wear for %d scrap.") % [int(Profile.SERVICE_DUE), int(Scrap.SERVICE_COST["barrel"])]
	elif unlocked and not o.is_empty() and String(o["slot"]) == "service" and String(o["id"]) == "sharpen":
		desc = tr("Every swing dulls the edge a little. A dull blade hurts less — down to %d%% damage when fully blunt. Sharpening costs no scrap, only time at the grinder.") % int(Profile.EDGE_MIN * 100.0)
	elif unlocked and not o.is_empty() and String(o["slot"]) == "service" and String(o["id"]) == "springs":
		desc = tr("Springs tire with every shot; tired ones keep cleaning from restoring the gun fully (100 − half the wear). Replace from %d%% wear for %d scrap.") % [int(Profile.SERVICE_DUE), int(Scrap.SERVICE_COST["springs"])]
	elif unlocked and not o.is_empty() and String(o["slot"]) == "service":
		desc = tr("Strip and clean the gun: no scrap, only time — the dirtier, the longer. Every shot fouls it (faster hot or suppressed); below 70% it starts to jam.")
	elif unlocked and not o.is_empty() and String(o["id"]) != "":
		desc = tr(String(Parts.get_part(String(o["id"]))["desc"]))
	elif unlocked and not o.is_empty():
		desc = tr("Factory part: no gain, no cost.")
	_d_text.text = desc
	# przycisk akcji
	if not unlocked and Scrap.is_later(w):
		_action.text = "Reward for the Leech" if Scrap.is_gated(w) else "Available in a later zone"
		_act_state(_action, "wait", 0)
	elif not unlocked:
		_action.text = tr("Buy it at the workshop bench") if _mode in ["service", "lab", "lathe"] else tr("Buy  ·  %d scrap") % Scrap.price_of(w)
		_act_state(_action, "wait" if _mode in ["service", "lab", "lathe"] else "ready", 0 if _mode in ["service", "lab", "lathe"] else Scrap.price_of(w))
	elif o.is_empty():
		_action.text = tr("Nothing to service") if _mode == "service" else (tr("Nothing to research — not a special weapon") if _mode == "lab" else (tr("Nothing for the lathe") if _mode == "lathe" else "No parts for this weapon"))
		_act_state(_action, "wait", 0)
	elif String(o["slot"]) == "preset":
		var api := int(o["id"])
		if Profile.preset(key, api).is_empty():
			_action.text = tr("Save current fit as set %d") % (api + 1)
		elif Profile.is_preset_fitted(key, api):
			_action.text = tr("Set %d fitted  ·  %s overwrite") % [api + 1, _menu_key("menu_alt", Actions.pad_mode)]
		else:
			_action.text = tr("Fit set %d  ·  %s overwrite") % [api + 1, _menu_key("menu_alt", Actions.pad_mode)]
	elif String(o["slot"]) == "service" and String(o["id"]) == "sharpen":
		var stime := Profile.sharpen_time(key)
		if _clean_w == w:
			_action.text = tr("Sharpening…  %d%%  (again to stop)") % int(100.0 * _clean_t / maxf(0.01, _clean_total))
			_act_state(_action, "busy", 0)
		else:
			_action.text = tr("Sharpen  ·  %d s") % ceili(stime) if stime > 0.0 else tr("Already sharp")
			_act_state(_action, "wait" if stime <= 0.0 else "ready", 0)
	elif String(o["slot"]) == "service" and String(o["id"]) in Profile.WEAR_PARTS:
		# skutek wymiany w liczbach (lufa: rozrzut, sprężyny: granica czyszczenia); poniżej progu przycisk wygaszony z progiem
		var sid2 := String(o["id"])
		var pw2 := Profile.part_wear(key, sid2)
		if not Profile.service_due(key, sid2):
			_action.text = tr("Like new") if pw2 < 0.5 else tr("Still serviceable  ·  replace from %d%% wear") % int(Profile.SERVICE_DUE)
			_act_state(_action, "wait", 0)
			_action.disabled = true
		elif sid2 == "barrel":
			_action.text = tr("Replace barrel  ·  %d scrap  ·  spread +%d%% → +0%%") % [int(Scrap.SERVICE_COST[sid2]), int(round(Controller.BARREL_SPREAD * pow(pw2 / 100.0, 2.0) * 100.0))]
			_act_state(_action, "ready", int(Scrap.SERVICE_COST[sid2]))
		else:
			_action.text = tr("Replace springs  ·  %d scrap  ·  cleans to %d%% → 100%%") % [int(Scrap.SERVICE_COST[sid2]), int(Profile.clean_cap(key))]
			_act_state(_action, "ready", int(Scrap.SERVICE_COST[sid2]))
	elif String(o["slot"]) == "service":
		var ctime := Profile.clean_time(key)
		if _clean_w == w:
			_action.text = tr("Cleaning…  %d%%  (again to stop)") % int(100.0 * _clean_t / maxf(0.01, _clean_total))
			_act_state(_action, "busy", 0)
		else:
			_action.text = tr("Clean  ·  %d s") % ceili(ctime) if ctime > 0.0 else tr("Already clean")
			_act_state(_action, "wait" if ctime <= 0.0 else "ready", 0)
	else:
		var id2 := String(o["id"])
		if _mode == "lathe":
			if Scrap.has_part(id2):
				_action.text = tr("Made  ·  fit it at the bench")
				_act_state(_action, "wait", 0)
			elif Scrap.lathe.has(id2):
				_action.text = tr("On the lathe  ·  ready after the mission")
				_act_state(_action, "busy", 0)
			elif not Scrap.schematics.has(id2):
				_action.text = tr("No schematic  ·  research it at the lab")
				_act_state(_action, "wait", 0)
			elif Scrap.lathe.size() >= Scrap.LATHE_SLOTS:
				_action.text = tr("The lathe is busy  ·  1 job per mission")
				_act_state(_action, "busy", 0)
			else:
				_action.text = tr("Machine  ·  %d scrap  ·  ready after the mission") % Scrap.machine_price(id2)
				_act_state(_action, "ready", Scrap.machine_price(id2))
		elif _mode == "lab":
			var rc2 := Scrap.research_cost(id2)
			if Scrap.schematics.has(id2) or Scrap.lathe.has(id2):
				_action.text = tr("Researched  ·  make it on the lathe")
				_act_state(_action, "wait", 0)
			elif Scrap.has_part(id2):
				_action.text = tr("Known  ·  fit it at the bench")
				_act_state(_action, "wait", 0)
			elif Scrap.research.has(id2):
				_action.text = tr("Researching  ·  ready after the mission")
				_act_state(_action, "busy", 0)
			elif Scrap.research.size() >= Scrap.LAB_SLOTS:
				_action.text = tr("The lab is busy  ·  1 project per mission")
				_act_state(_action, "busy", 0)
			else:
				_action.text = tr("Research  ·  %s  ·  %d scrap") % [_samples_text(rc2.x), rc2.y]
				_act_state(_action, "ready", rc2.y)
		elif id2 != "" and not Scrap.has_part(id2) and Scrap.is_lab_part(id2) and not Scrap.found.has(id2):
			_action.text = tr("Research it at the lab")
			_act_state(_action, "wait", 0)
		elif id2 != "" and not Scrap.has_part(id2):
			_action.text = tr("Buy part  ·  %d scrap") % Scrap.part_cost(id2)
			_act_state(_action, "ready", Scrap.part_cost(id2))
		elif Profile.fitted(key, String(o["slot"])) == id2:
			_action.text = "Fitted"
			_act_state(_action, "wait", 0)
		else:
			_action.text = "Fit to my gun" if id2 != "" else "Fit the factory part"
	if _mode == "bench":
		_present_bench(w, cur, preview, now_rows, next_rows, ops, o)
	_card.reset_size()

## Jawne oględziny nie oznaczają wyboru fabrycznego elementu do montażu.
func _connection_lost() -> void:
	_pending_part.clear()
	_buying = -1
	if _open:
		close()

func _inspect() -> void:
	_opt = -1
	_selection_revision += 1
	_workbench.stage.cancel_mount()
	_refresh()

func _bench_slots() -> Array:
	var slots: Array = Parts.slots_of(String(Weapons.def(int(LIST[_sel])).key)).duplicate()
	if Scrap.is_unlocked(int(LIST[_sel])) and not slots.is_empty():
		slots.append("preset")
	return slots

func _pick_slot(slot: String) -> void:
	if not _bench_slots().has(slot):
		return
	var w := int(LIST[_sel])
	var key := String(Weapons.def(w).key)
	var ops := _options(w)
	var fitted := Profile.fitted(key, slot)
	for i in ops.size():
		if String(ops[i]["slot"]) == slot and (slot == "preset" or String(ops[i]["id"]) == fitted):
			_pick_opt(i)
			return

func _move_slot(direction: int) -> void:
	var slots := _bench_slots()
	if slots.is_empty():
		return
	_pick_slot(String(slots[posmod(slots.find(_bench_slot) + direction, slots.size())]))

func _save_current_preset() -> void:
	if not _pending_part.is_empty() or _buying >= 0:
		return
	if _bench_slot != "preset":
		_pick_slot("preset")
		_say(tr("Choose a set, then save your current fit."), UiTheme.TEXT)
		return
	_save_preset()

func _present_committed(w: int, before: int) -> void:
	var key := String(Weapons.def(w).key)
	var after := Profile.fit_code(w)
	if _mode == "bench" and _page == 0 and int(LIST[_sel]) == w:
		_opt = -1
		_refresh()
		if before != after:
			_workbench.stage.animate_mount(w, Parts.decode(key, before), Parts.decode(key, after))
	else:
		_refresh()

func _present_bench(w: int, cur: RefCounted, preview: RefCounted, now_rows: Array, next_rows: Array, ops: Array, selected: Dictionary) -> void:
	var key := String(cur.key)
	var unlocked := Scrap.is_unlocked(w)
	var slots: Array = []
	for slot in _bench_slots():
		var fitted := Profile.fitted(key, String(slot))
		var name := tr("Sets") if slot == "preset" else _slot_label(key, String(slot))
		var short_name: String = name if SLOT_LABELS.has("%s:%s" % [key, slot]) else {"stock": tr("Grip") if cur.is_melee() else tr("Stock"), "optic": tr("Sight"), "preset": tr("Sets")}.get(slot, name)
		slots.append({"id": slot, "name": name, "short": short_name,
			"fitted": tr("Factory") if fitted == "" else tr(String(Parts.get_part(fitted)["name"]))})
	if _bench_slot == "" and not slots.is_empty():
		_bench_slot = String(slots[0]["id"])
	var records: Array = []
	for i in ops.size():
		var op: Dictionary = ops[i]
		if String(op["slot"]) != _bench_slot:
			continue
		var id := String(op["id"])
		var name := tr("Factory") if id == "" else tr(String(Parts.get_part(id).get("name", id)))
		var fitted := Profile.fitted(key, String(op["slot"])) == id
		var status := tr("fitted") if fitted else (tr("owned") if id == "" or Scrap.has_part(id) else tr("%d scrap") % Scrap.part_cost(id))
		if String(op["slot"]) == "preset":
			name = tr("Set %d") % (int(id) + 1)
			fitted = Profile.is_preset_fitted(key, int(id))
			status = tr("empty") if Profile.preset(key, int(id)).is_empty() else (tr("fitted") if fitted else tr("saved"))
		elif id != "" and not Scrap.has_part(id):
			if Scrap.found.has(id):
				status = tr("found — extract")
			elif Scrap.is_lab_part(id):
				status = tr("on the lathe") if Scrap.lathe.has(id) else (tr("schematic") if Scrap.schematics.has(id) else (tr("researching") if Scrap.research.has(id) else tr("lab")))
		var delta := _part_delta(w, cur, String(op["slot"]), id) if String(op["slot"]) != "preset" and not fitted else []
		records.append({"index": i, "name": name, "status": status, "fitted": fitted,
			"new": id != "" and String(op["slot"]) != "preset" and Profile.is_new("part:" + id), "delta": delta})
	var weapons: Array = []
	var wc := _local_wc()
	for i in LIST.size():
		var wid := int(LIST[i])
		var definition: RefCounted = Weapons.base_def(wid)
		var carried: bool = wc != null and (wc.loadout.has(wid) or wc.melee_id == wid)
		var status := tr("Carried") if carried else (tr("Unlocked") if Scrap.is_unlocked(wid) else (tr("Boss reward") if Scrap.is_gated(wid) else (tr("Later zone") if Scrap.is_later(wid) else tr("%d scrap") % Scrap.price_of(wid))))
		var fresh := Parts.of(String(definition.key)).any(func(pp: Dictionary) -> bool: return Profile.is_new("part:" + String(pp["id"])))
		weapons.append({"index": i, "name": String(definition.name), "row": int(definition.gun_row), "color": definition.tracer_color,
			"status": status, "carried": carried, "selected": i == _sel, "new": fresh})
	var rows: Array = []
	for i in now_rows.size():
		rows.append([now_rows[i][0], now_rows[i][1], next_rows[i][1] if i < next_rows.size() else now_rows[i][1],
			_change_kind(String(now_rows[i][0]), cur, preview) if preview != null else 0])
	var part_name := ""
	var id := String(selected.get("id", ""))
	if not selected.is_empty():
		part_name = tr("Set %d") % (int(id) + 1) if String(selected["slot"]) == "preset" else (tr("Factory") if id == "" else tr(String(Parts.get_part(id).get("name", id))))
	var pending := not _pending_part.is_empty() or _buying >= 0
	_action.disabled = pending or (unlocked and selected.is_empty()) or (not unlocked and (Scrap.is_later(w) or Scrap.bank < Scrap.price_of(w)))
	if pending:
		_action.text = tr("Waiting for confirmation…")
		_act_state(_action, "busy", 0)
	elif unlocked and selected.is_empty():
		_action.text = tr("Inspecting · choose a slot or a part")
	elif unlocked and String(selected.get("slot", "")) != "preset":
		if id != "" and not Scrap.has_part(id):
			if Scrap.found.has(id):
				_action.text = tr("Found · extract to unlock")
				_action.disabled = true
			elif Scrap.is_lab_part(id):
				_action.text = tr("Research and make it at the lab / lathe")
				_action.disabled = true
			else:
				_action.text = tr("Unlock & fit · %d scrap") % Scrap.part_cost(id)
				_act_state(_action, "ready", Scrap.part_cost(id))
				_action.disabled = Scrap.bank < Scrap.part_cost(id)
		else:
			_action.disabled = Profile.fitted(key, String(selected["slot"])) == id
	var meta := tr("Condition %d%%") % int(Profile.condition(key)) if not cur.is_melee() else tr("Edge %d%%") % int(Profile.edge_of(key))
	var kills := Profile.kills(key)
	meta += " · " + tr("Mastery %s") % ["0", "I", "II", "III", "IV", "V"][Profile.mastery_level(key)] + " · " + tr_n("%d kill", "%d kills", kills) % kills
	var ammo_name := Ammo.name_of(String(cur.caliber), wc.ammo_of(w) if wc != null else 0) if cur.uses_ammo() else ""
	if ammo_name != "":
		meta += "\n" + tr(ammo_name)
	var description := _d_text.text
	if id != "" and String(selected.get("slot", "")) != "preset" and not GunStage.GunModel.has_model(id):
		description += "\n" + tr("Internal modification · compare its effects on the card.")
	_workbench.present({"name": String(cur.name), "meta": meta, "tag": _d_tag.text, "preview": preview != null,
		"pending": pending, "part_name": part_name, "option": _opt, "unlocked": unlocked, "slot": _bench_slot,
		"weapons": weapons, "slots": slots, "options": records, "rows": rows, "description": description, "melee": cur.is_melee()})

## Główne zmiany po zamontowaniu części `id` w gnieździe `slot` broni `w` (kafel części na ławie): do dwóch wierszy [parametr, nowa wartość,
## ocena −1 / 0 / 1] — pierwsza korzyść i pierwszy kompromis (albo zmiana bez oceny); [] — bez zmian w liczbach (część o samym opisie).
func _part_delta(w: int, cur: RefCounted, slot: String, id: String) -> Array:
	var key := String(cur.key)
	var choice := {}
	for s in Parts.slots_of(key):
		choice[s] = Profile.fitted(key, String(s))
	choice[slot] = id
	var wc := _local_wc()
	var ammo_type: int = wc.ammo_of(w) if wc != null else 0
	var after: RefCounted = Weapons.def_build(w, Weapons.build_of(ammo_type, Parts.encode(key, choice)))
	var before_rows := _comparison_rows(cur)
	var after_rows := _comparison_rows(after)
	var gain: Array = []
	var cost: Array = []
	var neutral: Array = []
	for i in mini(before_rows.size(), after_rows.size()):
		if String(before_rows[i][1]) == String(after_rows[i][1]):
			continue
		var kind := _change_kind(String(before_rows[i][0]), cur, after)
		var row := [String(before_rows[i][0]), UiTheme.num_text(String(after_rows[i][1])), kind]
		if kind > 0 and gain.is_empty():
			gain = row
		elif kind < 0 and cost.is_empty():
			cost = row
		elif kind == 0 and neutral.is_empty():
			neutral = row
	var out: Array = []
	for r in [gain, cost]:
		if not r.is_empty():
			out.append(r)
	if out.is_empty() and not neutral.is_empty():
		out.append(neutral)
	return out

## Kolor jest pomocniczy: korzyści i kompromisy mają również podpis. Mieszane zmiany pozostają neutralne.
func _change_kind(metric: String, before: RefCounted, after: RefCounted) -> int:
	for field in PART_METRICS:
		if metric == tr(String(PART_METRICS[field][0])):
			if field == "auto":
				return 0 # tryb ognia jest wyborem sposobu użycia
			var direction := -1.0 if Parts.LOWER_IS_BETTER.has(field) or field == "ammo_per_shot" else 1.0
			return int(signf((float(after.get(field)) - float(before.get(field))) * direction))
	if metric == tr("Damage"):
		var old_damage: float = before.blast_damage if before.kind == WeaponDefinition.Kind.LAUNCHER else before.damage * before.pellets
		var new_damage: float = after.blast_damage if after.kind == WeaponDefinition.Kind.LAUNCHER else after.damage * after.pellets
		return int(signf(new_damage - old_damage))
	var fields := {tr("Damage"): ["damage", 1], tr("Magazine"): ["mag", 1], tr("Noise"): ["n_max", -1],
		tr("Mass"): ["mass", -1], tr("Kit mass"): ["mass", -1], tr("Run speed / noise"): ["mass", -1],
		tr("Draw"): ["draw_time", -1], tr("Armour bypass"): ["armor_pen", 1]}
	if fields.has(metric):
		var spec: Array = fields[metric]
		return int(signf((float(after.get(spec[0])) - float(before.get(spec[0]))) * float(spec[1])))
	if metric == tr("Range") or metric == tr("Reach"):
		return int(signf(after.range_m() - before.range_m()))
	if metric == tr("Fire rate") or metric == tr("Swing rate"):
		return int(signf(after.rpm() - before.rpm()))
	if metric == tr("Reload"):
		return int(signf(before.full_reload_time() - after.full_reload_time()))
	if metric == tr("DPS"):
		return int(signf(after.dps() - before.dps()))
	var pairs := {tr("Spread"): ["jitter_deg", "spread_deg", -1], tr("Bloom"): ["bloom_per_shot", "bloom_max", -1],
		tr("Recoil"): ["cam_kick", "recoil", -1], tr("Penetration"): ["pen", "pierce", 1], tr("Heating"): ["barrel_heat", "heat_gain", -1]}
	if pairs.has(metric):
		var spec: Array = pairs[metric]
		var a := signf((float(after.get(spec[0])) - float(before.get(spec[0]))) * float(spec[2]))
		var b := signf((float(after.get(spec[1])) - float(before.get(spec[1]))) * float(spec[2]))
		return int(signf(a + b)) if a * b >= 0 else 0
	return 0

## Kolumna szczegółów na papierze (jak karta ławy): marginesy karty, napisy atramentem (UiTheme.ink).
## Stan dźwigni akcji (StationKit.action_boxes): `st` "ready" / "wait" / "busy" / "collect" ("" — z `disabled`), `price` > złomu = brak złomu.
func _act_state(b: Button, st: String, price: int) -> void:
	b.set_meta("st", st)
	b.set_meta("price", price)

func _dress_action(b: Button) -> void:
	var st := String(b.get_meta("st", ""))
	if st == "":
		st = "wait" if b.disabled else "ready"
	if st == "busy":
		st = "wait"
	if st == "ready" and (b.disabled or (int(b.get_meta("price", 0)) > Scrap.bank and Scrap.enabled())):
		st = "broke" if int(b.get_meta("price", 0)) > Scrap.bank else "wait"
	if String(b.get_meta("dressed", "")) == st:
		return
	b.set_meta("dressed", st)
	var boxes := StationKit.action_boxes(st)
	for k in ["normal", "hover", "pressed", "disabled", "focus"]:
		b.add_theme_stylebox_override(k, boxes[k])
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_disabled_color"]:
		b.add_theme_color_override(c, boxes["fg"])
	b.add_theme_constant_override("outline_size", 0)

func _paper(inner: Control) -> PanelContainer:
	var paper := PanelContainer.new()
	paper.add_theme_stylebox_override("panel", UiTheme.paper_box())
	paper.add_child(inner)
	var stamp := StationKit.Stamp.new()                  # pieczątka skutku akcji (nakładka, nie zmienia układu)
	paper.add_child(stamp)
	paper.set_meta("stamp", stamp)
	_papers.append(paper)
	return paper

## Pieczątka na widocznej karcie po udanej operacji stanowiska (ZAMÓWIONO, WYDANO, ZBADANO…).
func _stamp() -> void:
	for p in _papers:
		var pc := p as PanelContainer
		if pc.is_visible_in_tree():
			(pc.get_meta("stamp") as StationKit.Stamp).play(tr(String(StationKit.STAMPS.get(_mode, "DONE"))))
			return

func _paper_rule() -> ColorRect:
	var r := ColorRect.new()
	r.color = UiTheme.PAPER_EDGE
	r.custom_minimum_size = Vector2(0, 1)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r

## Tytuł karty na papierze: krój nagłówków, atrament, bez obrysu.
func _ink_heading() -> Label:
	var l := UiTheme.heading("", 16, UiTheme.INK)
	l.add_theme_constant_override("outline_size", 0)
	return l

## Wiersz listy części / czynności na papierze. Zaznaczony ma ciemniejszy pasek i znacznik „»” (nie tylko inny kolor), stan w nawiasie.
func _tier_row(i: int, text: String, tail: String, col: Color) -> void:
	var sel := i == _opt
	var b := Button.new()
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_size_override("font_size", 8)
	b.add_theme_constant_override("outline_size", 0)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(c, col)
	b.text = ("%s %s   [%s]" % ["»" if sel else " ", text, tail]) if tail != "" else ("%s %s" % ["»" if sel else " ", text])
	b.custom_minimum_size = Vector2(DETAIL_W, 0)
	for st in ["normal", "hover", "pressed", "focus"]:
		var sb: StyleBox = StyleBoxEmpty.new()
		if sel or st == "hover":
			var band := StyleBoxFlat.new()
			band.bg_color = UiTheme.PAPER_SEL if sel else Color(UiTheme.PAPER_SEL, 0.55)
			sb = band
		sb.content_margin_top = 1.0                         # wiersz bez marginesów przycisku — lista części mieści się w karcie
		sb.content_margin_bottom = 1.0
		sb.content_margin_left = 2.0
		b.add_theme_stylebox_override(st, sb)
	b.pressed.connect(_pick_opt.bind(i))
	_d_tiers.add_child(b)

func _rule() -> ColorRect:
	var r := ColorRect.new()
	r.color = UiTheme.LINE2
	r.custom_minimum_size = Vector2(0, 1)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r
