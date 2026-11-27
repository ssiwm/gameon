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
const SupplyArt := preload("res://scripts/station_supply_art.gd")
const NotePaletteRef := preload("res://scripts/note_palette.gd")
const SupplyView := preload("res://scripts/stations/supply_view.gd")
const ServiceView := preload("res://scripts/stations/service_view.gd")
const LabView := preload("res://scripts/stations/lab_view.gd")
const LockerView := preload("res://scripts/stations/locker_view.gd")
const CardFx := preload("res://scripts/stations/card_fx.gd")
const BenchView := preload("res://scripts/stations/bench_view.gd")
const ServiceArt := preload("res://scripts/station_service_art.gd")
const LabArt := preload("res://scripts/station_lab_art.gd")

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
	"wall_pierce": ["Wall penetration", "%.2f m", 1.0 / 16.0], "wear": ["Gun wear", "×%.2f", 1.0],
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

## Kontrolki kart (stations/station_widgets.gd) — aliasy, żeby panel, widoki i testy pisały `Tile`, `ui.Tile` jak dawniej.
const Widgets := preload("res://scripts/stations/station_widgets.gd")
const Coin := Widgets.Coin
const TierBar := Widgets.TierBar
const PaperBar := Widgets.PaperBar
const NewDot := Widgets.NewDot
const CardTile := Widgets.CardTile
const Tile := Widgets.Tile
const ServiceMarks := Widgets.ServiceMarks
const StockBar := Widgets.StockBar
const LevelBar := Widgets.LevelBar
const LookView := Widgets.LookView
const Look3DView := Widgets.Look3DView
const LookPortrait := Widgets.LookPortrait
const LookTile := Widgets.LookTile
const PerkTile := Widgets.PerkTile
const SupplyTile := Widgets.SupplyTile
const StationScrim := Widgets.StationScrim

var _open := false
var _page := 0                        ## 0 = ARMS (bronie i ulepszenia), 1 = SUPPLIES (granaty, miny, narzędzia), 2 = PERKS, 3 = LOOK
var _mode := "bench"                  ## „bench" — ława (ARMS, SUPPLIES), „locker" — szafki osobiste (PERKS, LOOK); od 1.7.349, WORKSHOP_PLAN.md W1
## „service" — stół konserwacji (od 1.7.350, W2): zakładka ARMS bez części i zestawów, tylko czyszczenie i części eksploatacyjne broni
## „press" — prasa elaboracyjna (od 1.7.354, W4): zakładka SUPPLIES z samą amunicją specjalną, zamówienia zamiast zakupu (Scrap.request_order)
## „pyro" — stół pirotechniczny (od 1.7.355, W4b): granaty, miny, ładunki i naboje 40 mm, klawisze 1 / 2 zmieniają zapalnik (ustawienie drużyny)
## „lab" — pracownia elektroniki i próbek (od 1.7.357, W6a): zakładka ARMS z samymi częściami broni specjalnych do zbadania (Scrap.request_research)
## „lathe" — tokarka i szlifierka (od 1.7.358, W6b): części broni specjalnych ze schematów (Scrap.request_machining) i ostrzenie broni białej
const FIRST_PICK := "m83_drum75"        ## pierwszy zakup na ławie: po udanej 1.1 stać na niego, a M-83 ma każdy nowy gracz
const MODE_PAGES := {"bench": [0, 1], "locker": [2, 3], "service": [0], "press": [1], "pyro": [1], "lab": [0], "lathe": [0]}
const MODE_GROUP := {"bench": "workshop", "locker": "locker_station", "service": "service_bench", "press": "press_bench", "pyro": "pyro_bench", "lab": "lab_bench",
	"lathe": "lathe_bench"}      ## grupa stanowiska: panel wiąże się przy otwarciu z jego węzłem i zamyka na `left_range` (station.gd)
var _station: Node2D                 ## stanowisko otwartego panelu (station.gd); jego `left_range` zamyka panel
var _open_ms := 0                    ## R5: chwila otwarcia panelu (Time.get_ticks_msec) — czas przy stanowisku do dziennika sesji
var _first_act_ms := -1              ## R5: chwila pierwszej akcji (zakup, montaż, zamówienie, czyszczenie, perk, wygląd); -1 — jeszcze żadnej
var _reach_check := false            ## pierwsza klatka po otwarciu: sprawdzić, czy gracz w ogóle stoi w zasięgu stanowiska
const SERVICE_IDS := ["clean", "barrel", "springs"]
const CARD_MAX_W := 0.64               ## R1.4: karta przy stanowisku z ujęciem zajmuje najwyżej tyle szerokości ekranu (reszta — stół)
const CARD_EDGE := 24.0                ## odstęp karty z boku od krawędzi ekranu
const StationShot := preload("res://scripts/station_shot.gd")
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
var _arms_left: VBoxContainer         ## lewa kolumna zakładki broni (kafle, kartka, rulony schematów, szlifierka)
var _arms_side: VBoxContainer         ## prawa kolumna pracowni / tokarki (słoje i odczyt / zlecenie)
var _arms_detail: VBoxContainer       ## zawartość karty broni (kolejność: akta, scena, tytuł…)
var _cork: Control                    ## pracownia: tablica korkowa z łańcuchem kroków
var _dossier_head: Label              ## pracownia: nagłówek akt Obiektu 86
var _redacted: Control                ## pracownia: linia akt z zaczernieniami
var _jars: Control                    ## pracownia: słoje z próbkami (D2a)
var _jars_cap: Label
var _lab_board: PanelContainer        ## pracownia: tablica PROJEKTY pod kaflami (miejsca badań, schematy, co zostało na każdą broń)
var _lab_board_cap: Label
var _lab_board_rows: VBoxContainer
var _lab_tall := 0.0                  ## pracownia: największa wysokość treści od otwarcia panelu (karta nie skacze przy zmianie broni)
var _printout: PanelContainer         ## pracownia: odczyt części na wydruku (PRINTOUT)
var _printout_head: Label
var _blueprint: Control               ## tokarka: rysunek części z drukarki
var _order: Control                   ## tokarka: zlecenie na szpikulcu (SCRAWL)
var _order_box: VBoxContainer
var _order_stamp: Control
var _grinder: PanelContainer          ## tokarka: szlifierka (ostrze broni białej, iskry w trakcie)
var _grinder_text: Label
var _grinder_bar: ColorRect
var _sparks: Control
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
var _shade: StationScrim              ## tło pod kartą: winieta z wolnym pasem na stół albo pełna zasłona (R1.3)
var _bench_slot := ""
var _session := 0
var _selection_revision := 0
var _pending_part: Dictionary = {}
var _buying := -1

var _v_supply = SupplyView.new(self)          # widok stanowiska (stations/supply_view.gd)
var _v_service = ServiceView.new(self)          # widok stanowiska (stations/service_view.gd)
var _v_lab = LabView.new(self)          # widok stanowiska (stations/lab_view.gd)
var _v_locker = LockerView.new(self)          # widok stanowiska (stations/locker_view.gd)
var _v_bench = BenchView.new(self)          # widok stanowiska (stations/bench_view.gd)
var _v_fx = CardFx.new(self)          # efekty karty: portfel, udana operacja, pukanie (stations/card_fx.gd)

func _ready() -> void:
	add_to_group("workshop_ui")
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shade = StationScrim.new()
	_shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
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
	_build_arms(root, body)
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
	Scrap.geode_opened.connect(_on_geode_opened)
	Scrap.machining_result.connect(_on_machining_result)
	Profile.changed.connect(_refresh)
	Arsenal.stock_changed.connect(_refresh)
	multiplayer.server_disconnected.connect(_connection_lost)
	multiplayer.connection_failed.connect(_connection_lost)

# ---------------------------------------------------------------- przekazane do widoków stanowisk (stations/*.gd)
# Te same nazwy, po które sięgają panel, widoki i testy; budowa i wypełnianie kart żyją w widokach (STATION_CARDS_PLAN.md E1, R0 / R0b).

func _build_arms(root: VBoxContainer, body: HBoxContainer) -> void:
	_v_bench._build_arms(root, body)
func _build_supplies() -> HBoxContainer:
	return _v_supply._build_supplies()
func _make_shelf(cal: String) -> Control:
	return _v_supply._make_shelf(cal)
func _arrange_supplies() -> void:
	_v_supply._arrange_supplies()
func _make_supply_tile(kd: String, idx: int) -> SupplyTile:
	return _v_supply._make_supply_tile(kd, idx)
func _build_supply_detail() -> Control:
	return _v_supply._build_supply_detail()
func _is_press_kind(k: String) -> bool:
	return _v_supply._is_press_kind(k)
func _is_pyro_kind(k: String) -> bool:
	return _v_supply._is_pyro_kind(k)
func _make_box_tile(kd: String, idx: int) -> SupplyTile:
	return _v_supply._make_box_tile(kd, idx)
func _make_bay_tile(kd: String, idx: int) -> SupplyTile:
	return _v_supply._make_bay_tile(kd, idx)
func _look_code(i: int) -> int:
	return _v_locker._look_code(i)
func _build_look() -> HBoxContainer:
	return _v_locker._build_look()
func _select_palette(pi: int) -> void:
	_v_locker._select_palette(pi)
func _select_look(i: int) -> void:
	_v_locker._select_look(i)

func _act_look() -> void:
	_note_act()
	_v_locker._act_look()

func _refresh_look() -> void:
	_v_locker._refresh_look()
func _build_perks() -> HBoxContainer:
	return _v_locker._build_perks()
func _make_perk_tile(id: String, idx: int) -> PerkTile:
	return _v_locker._make_perk_tile(id, idx)
func _make_slot_chip(si: int) -> Control:
	return _v_locker._make_slot_chip(si)
func _build_perk_detail() -> Control:
	return _v_locker._build_perk_detail()
func _select_perk(i: int) -> void:
	_v_locker._select_perk(i)
func _perk_slot_of(id: String) -> int:
	return _v_locker._perk_slot_of(id)

func _act_perk() -> void:
	_note_act()
	_v_locker._act_perk()

func _refresh_perks() -> void:
	_v_locker._refresh_perks()

func _select_supply(i: int) -> void:
	if i != _sup_sel:
		Audio.play("ui_click", Audio.BUS_UI, -14.0)
	_sup_sel = i
	_refresh()

# ---------------------------------------------------------------- przekazane do stations/supply_view.gd

func _buy_selected_supply() -> void:
	_v_supply._buy_selected_supply()
func _sup_list() -> Array:
	return _v_supply._sup_list()
func _on_order_result(kind: String, ok: bool, reason: String) -> void:
	_v_supply._on_order_result(kind, ok, reason)
func _on_supply_result(kind: String, ok: bool, reason: String) -> void:
	_v_supply._on_supply_result(kind, ok, reason)
func _fill_noise(k: String) -> void:
	_v_supply._fill_noise(k)
func _fill_blast(k: String) -> void:
	_v_supply._fill_blast(k)
func _step_fuse(d: int) -> void:
	_v_supply._step_fuse(d)
func _set_fuse(k: String, ni: int) -> void:
	_v_supply._set_fuse(k, ni)
func _fill_fuse(k: String) -> void:
	_v_supply._fill_fuse(k)
func _fill_ammo_cmp(k: String) -> void:
	_v_supply._fill_ammo_cmp(k)
func _ammo_rows(k: String) -> Array:
	return _v_supply._ammo_rows(k)
func _fill_press_queue() -> void:
	_v_supply._fill_press_queue()
func _fill_dies() -> void:
	_v_supply._fill_dies()

# ---------------------------------------------------------------- przekazane do stations/card_fx.gd

func _tick_wallet() -> void:
	_v_fx._tick_wallet()
func _success_fx(vol_db := -4.0) -> void:
	_v_fx._success_fx(vol_db)
func _hub_events() -> void:
	_v_fx._hub_events()

func _clear_children(node: Node) -> void:
	for c in node.get_children():
		node.remove_child(c)
		c.queue_free()

## Cena kafla: przedmiot — sklep ławy, amunicja — partia w prasie.
func _sup_price(k: String) -> int:
	return Scrap.press_price(k) if Throwables.is_ammo(k) else Throwables.price_of(k)

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

# ---------------------------------------------------------------- zakładka ARMS (stations/bench_view.gd)

func _make_tile(w: int, idx: int) -> Tile:
	return _v_bench._make_tile(w, idx)
func _dress_tile(t: CardTile, icon: Control, title: String) -> void:
	_v_bench._dress_tile(t, icon, title)
func _add_price(t: CardTile) -> void:
	_v_bench._add_price(t)
func _add_bar(t: CardTile, bar: Control) -> void:
	_v_bench._add_bar(t, bar)
func _build_detail() -> Control:
	return _v_bench._build_detail()
func _options(w: int) -> Array:
	return _v_bench._options(w)
func _queue_summary(skip_batches := false) -> String:
	return _v_bench._queue_summary(skip_batches)
func _slot_label(key: String, slot: String) -> String:
	return _v_bench._slot_label(key, slot)
func _comparison_rows(d: RefCounted) -> Array:
	return _v_bench._comparison_rows(d)
func _paper_bar(label: String, frac: float, value: String, col: Color, cap := -1.0) -> void:
	_v_bench._paper_bar(label, frac, value, col, cap)
func _first_pick() -> String:
	return _v_bench._first_pick()
func _first_part_opt() -> int:
	return _v_bench._first_part_opt()
func _save_preset() -> void:
	_v_bench._save_preset()
func _refresh_tile(t: Tile, selected: bool) -> void:
	_v_bench._refresh_tile(t, selected)
func _refresh_detail(w: int) -> void:
	_v_bench._refresh_detail(w)
func _pick_slot(slot: String) -> void:
	_v_bench._pick_slot(slot)
func _move_slot(direction: int) -> void:
	_v_bench._move_slot(direction)
func _save_current_preset() -> void:
	_v_bench._save_current_preset()
func _present_committed(w: int, before: int) -> void:
	_v_bench._present_committed(w, before)
func _act_state(b: Button, st: String, price: int) -> void:
	_v_bench._act_state(b, st, price)
func _dress_action(b: Button) -> void:
	_v_bench._dress_action(b)
func _paper(inner: Control) -> PanelContainer:
	return _v_bench._paper(inner)
func _stamp() -> void:
	_v_bench._stamp()
func _paper_rule() -> ColorRect:
	return _v_bench._paper_rule()
func _ink_heading() -> Label:
	return _v_bench._ink_heading()
func _rule() -> ColorRect:
	return _v_bench._rule()

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
	Scrap.note_station(_mode)                              # dziennik sesji: które stanowiska drużyna naprawdę otwiera (plan układu kryjówki E0)
	_open_ms = Time.get_ticks_msec()
	_first_act_ms = -1
	_session += 1
	_lab_tall = 0.0
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
	_bind_station()
	Settings.block_game_input(true)
	_prev_mouse = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE            # w grze celownik zastępuje kursor; panel potrzebuje myszy
	Audio.play("ui_click", Audio.BUS_UI, -10.0)
	_refresh()
	if _first_pick() != "" and _opt >= 0:
		_say(tr("Good first upgrade: 45 more rounds before you have to reload."), UiTheme.OK)

## Wiąże panel ze stanowiskiem trybu (R0.2, K4): odejście od niego, śmierć albo uśpienie stanowiska wysyła `left_range` i panel się
## zamyka. Gracz poza zasięgiem w pierwszej klatce po otwarciu — panel zamyka się od razu, jak dawniej (`_reach_check`).
func _bind_station() -> void:
	_unbind_station()
	_station = get_tree().get_first_node_in_group(String(MODE_GROUP[_mode])) as Node2D
	if _station == null:
		return
	if _station.has_signal("left_range"):
		_station.connect("left_range", _on_left_range)
	_reach_check = true

func _unbind_station() -> void:
	if _station != null and is_instance_valid(_station) and _station.has_signal("left_range") and _station.is_connected("left_range", _on_left_range):
		_station.disconnect("left_range", _on_left_range)
	_station = null

## Stanowisko, na które patrzy kamera świata (R1, view3d.gd): otwarte stanowisko z ujęciem, poza ławą ARMS na cały ekran; inaczej null.
func focus_station() -> Node2D:
	if not _open or _station == null or not is_instance_valid(_station) or not _station.has_method("focus_frame"):
		return null
	return _station

## Wolny od karty pas ekranu (od–do w ułamku szerokości): tam kamera świata stawia stół. Ława ARMS (karta na cały ekran) — pusty pas.
func focus_band() -> Vector2:
	if not _open or (_mode == "bench" and _page == 0) or size.x <= 0.0:
		return Vector2.ZERO
	var r := Rect2(_card.position, _card.size * _card.scale)
	return Vector2(0.0, clampf(r.position.x / size.x, 0.0, 1.0)) if _card_right() else Vector2(clampf(r.end.x / size.x, 0.0, 1.0), 1.0)

## Strona karty przy stanowisku z ujęciem: z danych stanowiska (`shot.card`: „left” / „right”), domyślnie po prawej.
func _card_right() -> bool:
	if _station == null or not is_instance_valid(_station):
		return true
	return String((_station.get("shot") as Dictionary).get("card", "right")) != "left"

func _on_left_range() -> void:
	close()

func close() -> void:
	if not _open:
		return
	_unbind_station()
	# R5: ile gracz był przy stanowisku i po ilu sekundach zrobił pierwszą rzecz (-1 — nic) — czy zbliżenie kamery (R1) pomaga, czy spowalnia
	Scrap.note_station_end(_mode, (Time.get_ticks_msec() - _open_ms) / 1000.0, (_first_act_ms - _open_ms) / 1000.0 if _first_act_ms >= 0 else -1.0)
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
	# panel zamyka się, gdy gracz odejdzie od stanowiska albo zginie (`left_range`, _bind_station), stanowisko zniknie albo misja się
	# zmieni (przerwane czyszczenie trzeba zacząć od nowa)
	if _station == null or not is_instance_valid(_station) or not NoiseMgr.safe_zone or (_reach_check and not bool(_station.get("local_in_range"))):
		close()
		return
	_reach_check = false
	tick_clean(delta)
	_hub_events()
	var hud := get_parent() as Control
	if hud != null:
		size = hud.size
	# Ława 3D ma stałą skalę ×1,4; pozostałe stanowiska dostają tyle samo, ile zmieści szerokość ekranu (dawniej ×1 — drobny tekst
	# w ~46% szerokości ekranu). Wysokość przewijanej treści liczona już w jednostkach skali, żeby karta nie wyszła poza ekran.
	var immersive := _mode == "bench" and _page == 0
	# R1.4: przy stanowisku z ujęciem na stół karta stoi z boku (CARD_MAX_W szerokości ekranu), a w wolnym pasie kamera świata
	# pokazuje stół (view3d.gd); ława ARMS wypełnia ekran jak dotąd. Skala nie schodzi poniżej ×1 (tekst ≥ 12 px, UI_PLAN.md).
	var aside := not immersive and _station != null and _station.has_method("focus_frame")
	var fit_w := size.x * CARD_MAX_W if aside else size.x - 48.0
	var card_scale := 1.4 if immersive else clampf(fit_w / maxf(1.0, _card.get_combined_minimum_size().x), 1.0, 1.4)
	for body in [_arms_body, _sup_body, _perk_body, _look_body]:
		var tall := clampf(size.y / card_scale - 156.0, 150.0, 400.0)      # 156: nagłówek z tabliczką, dźwignia, komunikat, taśma, odstępy
		if _mode == "lab" and body == _arms_body:
			_lab_tall = maxf(_lab_tall, body.get_combined_minimum_size().y)
			tall = minf(tall, maxf(150.0, _lab_tall))     # pracownia: karta na wysokość treści (dawniej ~1/4 pustego pasa nad przyciskiem)
		(body.get_parent() as ScrollContainer).custom_minimum_size.y = tall
	var overhead := maxf(118.0, _card.size.y - _workbench.size.y)
	_workbench.custom_minimum_size = Vector2(clampf(size.x / card_scale - 34.0, 606.0, 1050.0), clampf(size.y / card_scale - overhead - 14.0, 190.0, 620.0))
	_card.scale = Vector2.ONE * card_scale
	# Kontener sam się nie kurczy: po wyższej stronie (zaopatrzenie, inne stanowisko) karta ławy ×1,4 wychodziła poza ekran.
	if not _card.size.is_equal_approx(_card.get_combined_minimum_size()):
		_card.reset_size()
	var centered := ((size - _card.size * card_scale) * 0.5).round()
	if aside:
		var cw := _card.size.x * card_scale
		centered.x = roundf(size.x - cw - CARD_EDGE) if _card_right() else CARD_EDGE
	_card.position = centered
	_shade.full = not aside or focus_band().y - focus_band().x < StationShot.MIN_BAND
	_shade.card = Rect2(_card.position, _card.size * card_scale)
	_shade.queue_redraw()

func _exit_tree() -> void:
	if _open:
		Settings.block_game_input(false)
		Input.mouse_mode = _prev_mouse

# ---------------------------------------------------------------- sterowanie

## Linia sterowania pod panelem: klawisze z rejestru akcji, a gdy jest pad — jego przyciski. Tekst podaje widok stanowiska (`hint`, R0b).
func _controls_hint() -> String:
	return _hint_view().hint(Actions.pad_mode)

## Widok, który opisuje sterowanie bieżącego stanowiska i zakładki.
func _hint_view() -> RefCounted:
	match _mode:
		"bench":
			return _v_bench if _page == 0 else _v_supply
		"press", "pyro":
			return _v_supply
		"service":
			return _v_service
		"lab", "lathe":
			return _v_lab
		"locker":
			return _v_locker
	return _v_bench

## Klawisze nawigacji (strzałki / WASD albo D-pad) w ramce klawisza taśmy sterowania.
func _nav_cap(pad: bool) -> String:
	return StationKit.KEY_OPEN + ("D-PAD" if pad else Actions.cluster(["menu_up", "menu_left", "menu_down", "menu_right"]).to_upper()) + StationKit.KEY_CLOSE

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

## Następny kafel w kierunku kroku wg położenia na ekranie (StationKit.spatial_step).
func _spatial_step(tiles: Array, vis: Array, cur: int, step: int) -> int:
	return StationKit.spatial_step(tiles, vis, cur, step)

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
	elif _mode == "lab" and event.is_action_pressed("menu_details"):
		_v_lab.crack_geode()                                      # geoda z żyły (DIG_LOOT_PLAN.md K4)
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

# ---------------------------------------------------------------- przekazane do stations/bench_view.gd

func _move_opt(d: int) -> void:
	_v_bench._move_opt(d)
func _pick_opt(i: int) -> void:
	_v_bench._pick_opt(i)
func _move(d: int) -> void:
	_v_bench._move(d)
func _select(i: int) -> void:
	_v_bench._select(i)
func _arms_list() -> Array:
	return _v_bench._arms_list()
func _initial_selection() -> int:
	return _v_bench._initial_selection()
func _act() -> void:
	_v_bench._act()
func _on_result(w: int, ok: bool, reason: String) -> void:
	_v_bench._on_result(w, ok, reason)
func _on_part_result(id: String, ok: bool, reason: String) -> void:
	_v_bench._on_part_result(id, ok, reason)
func _service_advice(w: int) -> Dictionary:
	return _v_service._service_advice(w)

## Kolor zalecenia na papierze: pilne — koszt, warto — cena, drobiazg — atrament, nic — zysk.
static func _advice_ink(level: int) -> Color:
	return [UiTheme.INK_GAIN, UiTheme.INK, UiTheme.INK_PRICE, UiTheme.INK_COST][clampi(level + 1, 0, 3)]

func _refresh_service_todo() -> void:
	_v_service._refresh_service_todo()
func _wear_ink(wear: float) -> Color:
	return _v_service._wear_ink(wear)
func _fill_service_panel(base: RefCounted, cur: RefCounted) -> void:
	_v_service._fill_service_panel(base, cur)
func _build_lab_lathe(left: VBoxContainer, body: HBoxContainer) -> void:
	_v_lab._build_lab_lathe(left, body)
func _dress_lab_lathe(w: int, o: Dictionary) -> void:
	_v_lab._dress_lab_lathe(w, o)
func _dress_lathe(w: int, o: Dictionary, key: String, part: bool) -> void:
	_v_lab._dress_lathe(w, o, key, part)
func _recolor_printout(root: Node) -> void:
	_v_lab._recolor_printout(root)
func _service_skin(on: bool) -> void:
	_v_service._service_skin(on)
func _fill_lab_chain(key: String, slot: String, id: String) -> void:
	_v_lab._fill_lab_chain(key, slot, id)

## Akcja na wybranej broni: kup broń (zablokowana), a odblokowanej — kup część pod kursorem, zamontuj ją albo wróć do fabrycznej.
## Pierwsza akcja w otwartym panelu (R5): zapamiętuje chwilę tylko raz na otwarcie.
func _note_act() -> void:
	if _open and _first_act_ms < 0:
		_first_act_ms = Time.get_ticks_msec()

# ---------------------------------------------------------------- przekazane do stations/lab_view.gd

func _samples_text(n: int) -> String:
	return _v_lab._samples_text(n)
func _on_machining_result(id: String, ok: bool, reason: String) -> void:
	_v_lab._on_machining_result(id, ok, reason)
func _on_research_result(id: String, ok: bool, reason: String) -> void:
	_v_lab._on_research_result(id, ok, reason)
func _on_geode_opened(res: Dictionary) -> void:
	_v_lab._on_geode_opened(res)

## Kontroler broni lokalnego gracza (masa ekwipunku w nagłówku ławy) albo null.
func _local_wc() -> Node:
	for p in get_tree().get_nodes_in_group("players"):
		if not p.is_bot and p.is_multiplayer_authority():
			return p.weapons
	return null

# ---------------------------------------------------------------- przekazane do stations/service_view.gd

func _start_clean(w: int) -> void:
	_v_service._start_clean(w)
func _stop_clean() -> void:
	_v_service._stop_clean()
func tick_clean(delta: float) -> void:
	_v_service.tick_clean(delta)
func _on_service_result(w: int, part: String, ok: bool, reason: String) -> void:
	_v_service._on_service_result(w, part, ok, reason)

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
	_v_supply._refresh_supplies()

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

