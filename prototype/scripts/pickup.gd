extends Node2D
## Przedmiot na ziemi: apteczka (+1 HP), skrzynka z amunicją albo broń.
## Spawn, podniesienie i usunięcie idą przez level.gd (RPC ze stałą nazwą),
## więc istnieje identycznie na każdym peerze. Podniesienie rozstrzyga serwer.
##
##   health  dotknięcie leczy rannego (bot ustępuje człowiekowi)
##   ammo    dotknięcie dodaje `rounds` naboi do WSPÓLNEGO zapasu drużyny — o ile
##           ktoś z ludzi nosi tę broń i zapas nie jest pełny (nic się nie marnuje)
##   cache   skrzynia z mapy: dodaje amunicję do WSZYSTKICH broni głównych noszonych przez drużynę
##   scrap   złom (rounds = wartość): dotknięcie przez dowolnego żywego gracza dodaje do łupu misji (scrap.gd)
##   tag     nieśmiertelnik (misja 1.1): dotknięcie przez dowolnego żywego gracza zalicza cel główny (mission.on_tag_taken)
##   stash   ukryta skrytka (cel poboczny misji 1.1): jak złom (rounds = wartość), a do tego zalicza skrytkę w misji (mission.on_stash_found)
##   flares  skrzynka z flarami (arena Pijawki): +rounds flar do wspólnej puli (NoiseMgr.add_flare), o ile pula nie jest pełna
##   weapon  nie podnosi się samo: gracz naciska E (wymiana broni to decyzja, a nie
##           wypadek); serwer sprawdza odległość i przyznaje (level.gd)

const Sprites := preload("res://scripts/sprites.gd")
const Lights := preload("res://scripts/lights.gd")
const Weapons := preload("res://scripts/weapons.gd")
const Throwables := preload("res://scripts/throwables.gd")
const ItemsHd := preload("res://scripts/items_hd.gd")

const HEAL := 1
const PICK_R := 12.0
const HURT_RESERVE_R := 120.0     ## ranny w tym promieniu ma pierwszeństwo przed kumulowaniem serc
const WEAPON_R := 26.0            ## zasięg „E” po broń
const FALL_G := 700.0

const GLOW := {
	"health": Color(0.4, 1.0, 0.5),
	"ammo": Color(1.0, 0.78, 0.3),
	"weapon": Color(0.5, 0.85, 1.0),
	"cache": Color(1.0, 0.78, 0.3),
	"scrap": Color(0.95, 0.8, 0.4),
	"tag": Color(0.6, 0.85, 1.0),
	"stash": Color(0.95, 0.75, 0.35),
	"flares": Color(1.0, 0.45, 0.22),
	"supply": Color(0.7, 0.85, 0.6),
}

var kind := "health"
var arg := 0                      ## ammo/weapon: id broni
var rounds := 0                   ## ammo: ile naboi
var static_display := false       ## broń na stojaku (kryjówka): stoi w miejscu — bez podskoku przy spawnie i bez bujania

var _vel := Vector2.ZERO
var _floor_y := 0.0
var _landed := false
var _t := 0.0
var _spr: Array = []
var _glow: Lights.GameLight
## Grafika HD (Sprites.newitem): korzeń z bujaniem, sprite oświetlany, kopia „unshaded" (widać w ciemności) i nakładka (plakietka, kłódka).
var _hd: Node2D
var _hd_over: Node2D
var _hd_gun := ""
var _hd_gun_rect := Rect2()
static var _bbox := {}            ## wiersz arkusza broni → prostokąt nieprzezroczystych pikseli w klatce (do wyśrodkowania na stojaku)

func _ready() -> void:
	add_to_group("pickups")
	z_index = 0 if static_display else 2          # broń na stojaku wisi ZA graczem (gracz ma z_index 0 i jest później w drzewie); łup na ziemi na wierzchu
	# bez filtrowania liniowego: sprite broni 24×9 px rozmywał się przy skalowaniu okna
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if kind == "weapon":
		# tekstury broni wczytujemy przed pierwszym _draw (wczytanie w trakcie rysowania daje biały prostokąt)
		Sprites.texture(Sprites.DIR + "guns.png")
		Sprites.texture(Sprites.DIR + "guns_glow.png")
	_setup_hd()
	if _hd == null and kind == "health" and Sprites.has("objects"):
		_spr = Sprites.attach(self, "objects")
		Sprites.play(_spr, "medkit", false)
	if kind != "health" and _hd == null:
		material = Lights.unshaded()          # skrzynkę i broń widać w ciemności
		modulate = Color(0.88, 0.88, 0.88)
	# poświata — przedmiot widać w ciemności, ale nie oświetla okolicy
	_glow = Lights.make_light(Lights.radial(), 0.9 if kind == "stash" else 1.6, GLOW.get(kind, Color.WHITE), 0.6, false)      # skrytka świeci słabo — trzeba ją znaleźć
	_glow.position = Vector2(0, -8)
	add_child(_glow)
	if static_display:
		Scrap.changed.connect(queue_redraw)     # zakup w warsztacie odblokowuje stojak
		_landed = true                  # wisi na stojaku: bez spadania i bujania
		_vel = Vector2.ZERO
		_floor_y = global_position.y
	else:
		# podskok deterministyczny z nazwy węzła (ta sama u wszystkich peerów) — przedmiot ląduje w tym samym miejscu u każdego
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(String(name))
		_vel = Vector2(rng.randf_range(-40.0, 40.0), -170.0)
		_unstick()
		_floor_y = _find_floor(global_position)
	queue_redraw()

## Przedmiot nie może zaczynać w bryle (np. wróg zginął przy ścianie): wypychamy go w bok na najbliższe wolne miejsce.
func _unstick() -> void:
	var space := get_world_2d().direct_space_state
	for step in range(0, 40):
		for sgn in [1.0, -1.0]:
			var pt := global_position + Vector2(sgn * float(step) * 2.0, -6.0)
			var q := PhysicsPointQueryParameters2D.new()
			q.position = pt
			q.collision_mask = 1
			if space.intersect_point(q, 1).is_empty():
				global_position.x += sgn * float(step) * 2.0
				return

func _find_floor(from: Vector2) -> float:
	var q := PhysicsRayQueryParameters2D.create(from + Vector2(0, -6), from + Vector2(0, 200), 1 | 16)
	var hit := get_world_2d().direct_space_state.intersect_ray(q)
	return hit["position"].y if not hit.is_empty() else from.y

func _physics_process(delta: float) -> void:
	_t += delta
	if not _landed:
		# podskok i opad na podłogę (bez ciała fizycznego — to tylko znacznik)
		_vel.y += FALL_G * delta
		var from := global_position
		var next := from + _vel * delta
		var space := get_world_2d().direct_space_state
		# ściana na drodze w poziomie: zatrzymaj się przed nią (wcześniej przedmiot wpadał w skałę i był nie do podniesienia)
		if absf(_vel.x) > 0.01:
			var hq := PhysicsRayQueryParameters2D.create(from + Vector2(0, -6), Vector2(next.x + signf(_vel.x) * 3.0, from.y - 6.0), 1)
			var hh := space.intersect_ray(hq)
			if not hh.is_empty():
				next.x = from.x
				_vel.x = 0.0
		# podłoga pod nowym punktem (przy dryfie bywa inna niż pod punktem startu)
		if _vel.y > 0.0:
			var fq := PhysicsRayQueryParameters2D.create(Vector2(next.x, from.y - 4.0), Vector2(next.x, next.y + 1.0), 1 | 16)
			var fh := space.intersect_ray(fq)
			if not fh.is_empty():
				global_position = Vector2(roundf(next.x), fh["position"].y)         # lądowanie na pełnym pikselu
				_landed = true
			else:
				global_position = next
		else:
			global_position = next
	var bob := 0.0 if (not _landed or static_display) else sin(_t * 3.0) * 1.5 - 1.5
	if _hd != null:
		_hd.position.y = roundf(bob) if static_display else bob
	elif not _spr.is_empty():
		(_spr[0] as Node2D).position.y = bob
		if _spr[1] != null:
			(_spr[1] as Node2D).position.y = bob
			(_spr[1] as CanvasItem).modulate.a = 0.6 + 0.4 * sin(_t * 4.0)
	elif kind != "health":
		queue_redraw()
	if _glow != null:
		_glow.energy = 0.5 + 0.2 * sin(_t * 4.0)
	if _landed and NoiseMgr.is_server():
		_try_pickup()

# ---------------------------------------------------------------- rysowanie (ammo / broń)

# ---------------------------------------------------------------- grafika HD

## Nazwa przedmiotu HD (art/items/) dla rodzaju albo "" (broń ma własny tor: sprite broni HD).
func _hd_name() -> String:
	match kind:
		"health": return "medkit"
		"flares": return "flare_box"
		"supply": return "supply"
		"stash": return "stash"
		"tag": return "tag"
		"scrap": return "scrap_pile"
		"cache": return "cache"
		"ammo": return "ammo"
	return ""

## Skala sprite'a względem modelu (rozmiar w świecie dobrany tak, by przedmiot był czytelny, ale nie większy od gracza).
func _hd_scale() -> float:
	match kind:
		"health": return 0.7
		"flares": return 0.8
		"supply": return 0.8
		"stash": return 0.75
		"cache": return 0.8
		"ammo": return 0.9
		"scrap": return 0.8 if rounds >= 6 else 0.55
	return 1.0

func _setup_hd() -> void:
	var gun_key := ""
	if kind == "weapon" and Sprites.newgun:
		gun_key = String(Weapons.def(arg).key)
		if Sprites.gun_hd(gun_key) == null:
			return
	var nm := _hd_name()
	if gun_key == "" and (not Sprites.newitem or nm == "" or not ItemsHd.has(nm)):
		return
	_hd = Node2D.new()
	add_child(_hd)
	if gun_key != "":
		_hd_gun = gun_key
		_hd_gun_rect = Sprites.gun_hd_rect(gun_key)
		# znacznik położenia broni: model na stojaku / na ziemi, kłódkę i tabliczkę z ceną stawia widok 3D (view3d.gd: _sync_guns)
		var sp := Node2D.new()
		sp.name = "GunMark"
		sp.position = Vector2(0.0, _shelf_y() if static_display else -4.0)
		_hd.add_child(sp)
		return
	var sc := _hd_scale()
	var main := ItemsHd.make(nm, _hd, sc)
	_hd_main = main
	if kind == "supply" or kind == "ammo":
		_hd_over = Node2D.new()
		_hd_over.draw.connect(_draw_over)
		_hd.add_child(_hd_over)

var _hd_main: ItemsHd.ItemMark

## Wysokość spodu sylwetki broni na stojaku: kołyska HD jest wyższa niż pikselowa.
func _shelf_y() -> float:
	return -9.8 if (Sprites.newitem and ItemsHd.has("rack")) else -7.0

## Nakładka: kolorowa plakietka na skrzynce zaopatrzenia / amunicji (rodzaj zawartości).
func _draw_over() -> void:
	var sc := _hd_scale()
	if kind == "supply":
		var sk := String(Throwables.ORDER[clampi(arg, 0, Throwables.ORDER.size() - 1)])
		var col: Color = Throwables.KINDS[sk]["color"]
		var r := Rect2(-2.8 * sc, -(4.4 + 1.9) * sc, 5.6 * sc, 3.8 * sc)
		_hd_over.draw_rect(r, col.darkened(0.15))
		_hd_over.draw_rect(Rect2(r.position + Vector2(0.5, 0.5) * sc, Vector2(r.size.x - 1.0 * sc, 0.5 * sc)), Color(1, 1, 1, 0.45))
		_hd_over.draw_rect(Rect2(r.get_center() - Vector2(0.9, 0.9) * sc, Vector2(1.8, 1.8) * sc), Color(1, 1, 1, 0.75))
	elif kind == "ammo":
		var col2: Color = Weapons.def(arg).tracer_color.lerp(Color(0.85, 0.68, 0.3), 0.4)
		var r2 := Rect2(-2.8 * sc, -(3.2 + 1.3) * sc, 5.6 * sc, 2.6 * sc)
		_hd_over.draw_rect(r2, col2)
		_hd_over.draw_rect(Rect2(r2.position, Vector2(r2.size.x, 0.4 * sc)), Color(1, 1, 1, 0.35))

## Prostokąt nieprzezroczystych pikseli broni `row` w jej klatce (px arkusza); liczony raz i zapamiętany.
static func _content_box(tex: Texture2D, row: int, tfs: Vector2) -> Rect2i:
	if _bbox.has(row):
		return _bbox[row]
	var img := tex.get_image()
	var fw := int(tfs.x)
	var fh := int(tfs.y)
	var x0 := fw
	var x1 := -1
	var y0 := fh
	var y1 := -1
	for y in fh:
		for x in fw:
			if img.get_pixel(x, row * fh + y).a > 0.1:
				x0 = mini(x0, x)
				x1 = maxi(x1, x)
				y0 = mini(y0, y)
				y1 = maxi(y1, y)
	var box := Rect2i(x0, y0, x1 - x0 + 1, y1 - y0 + 1) if x1 >= 0 else Rect2i()
	_bbox[row] = box
	return box

# ---------------------------------------------------------------- podnoszenie (serwer)

func _try_pickup() -> void:
	match kind:
		"health":
			_try_health()
		"ammo":
			_try_ammo()
		"cache":
			_try_cache()
		"scrap":
			_try_scrap()
		"tag":
			_try_tag()
		"stash":
			_try_stash()
		"flares":
			_try_flares()
		"supply":
			_try_supply()

## Złom zbiera każdy żywy gracz (też bot) — wspólny łup drużyny.
func _try_scrap() -> void:
	for p in get_tree().get_nodes_in_group("players"):
		if p.dead or not _near(p):
			continue
		Scrap.add_loot(rounds)
		var lvl := _level()
		if lvl != null:
			lvl.take_item(String(name))
		return

## Skrzynka z flarami: bierze ją człowiek, gdy pula flar nie jest pełna (nic się nie marnuje, jak z amunicją).
func _try_flares() -> void:
	if NoiseMgr.flares >= NoiseMgr.FLARE_MAX:
		return
	for pl in get_tree().get_nodes_in_group("players"):
		if pl.dead or pl.is_bot or not _near(pl):
			continue
		NoiseMgr.add_flare(maxi(1, rounds))
		var lvl := _level()
		if lvl != null:
			lvl.take_item(String(name))
		return

## Skrzynka zaopatrzenia (arg = indeks w Throwables.ORDER): bierze ją człowiek, gdy zapas tego rodzaju nie jest pełny.
func _try_supply() -> void:
	var kind_s := String(Throwables.ORDER[clampi(arg, 0, Throwables.ORDER.size() - 1)])
	if Arsenal.get_throwable(kind_s) >= int(Throwables.KINDS[kind_s]["max"]):
		return
	for pl in get_tree().get_nodes_in_group("players"):
		if pl.dead or pl.is_bot or not _near(pl):
			continue
		Arsenal.add_throwable(kind_s, 1)
		Audio.play("ammo_pickup", Audio.BUS_UI, -8.0)
		var lvl := _level()
		if lvl != null:
			lvl.take_item(String(name))
		return

## Skrytkę zbiera każdy żywy gracz: złom do łupu i zaliczenie celu pobocznego misji.
func _try_stash() -> void:
	for pl in get_tree().get_nodes_in_group("players"):
		if pl.dead or not _near(pl):
			continue
		Scrap.add_loot(rounds)
		var mis := get_tree().get_first_node_in_group("mission")
		if mis != null:
			mis.on_stash_found()
		var lvl := _level()
		if lvl != null:
			lvl.take_item(String(name))
		return

## Nieśmiertelnik zbiera każdy żywy gracz (też bot): cel drużyny, nie pojedynczego gracza.
func _try_tag() -> void:
	for p in get_tree().get_nodes_in_group("players"):
		if p.dead or not _near(p):
			continue
		var mis := get_tree().get_first_node_in_group("mission")
		if mis != null:
			mis.on_tag_taken()
		var lvl := _level()
		if lvl != null:
			lvl.take_item(String(name))
		return

func _near(p: Node2D) -> bool:
	return (p.global_position + Vector2(0, -8)).distance_to(global_position + Vector2(0, -6)) <= PICK_R + 6.0

func _level() -> Node:
	return get_tree().get_first_node_in_group("level")

## Apteczka leczy rannego; pełne serca można kumulować ponad MAX_HP (do STACK_HP), ale
## dopiero gdy w pobliżu nikt nie potrzebuje leczenia. Bot nie zabiera apteczki, gdy obok
## jest ranny człowiek — ludzie mają pierwszeństwo.
func _try_health() -> void:
	var hurt_human_near := false
	for p in get_tree().get_nodes_in_group("players"):
		if not p.is_bot and not p.dead and p.hp < p.max_hp() and p.global_position.distance_to(global_position) < 80.0:
			hurt_human_near = true
	for p in get_tree().get_nodes_in_group("players"):
		if p.dead or p.hp >= p.stack_hp():
			continue
		if p.is_bot and hurt_human_near:
			continue
		if p.hp >= p.max_hp() and _hurt_teammate_near(p):
			continue
		if _near(p):
			p.deliver_heal(HEAL)
			_level().take_item(name)
			return

## Czy ktoś inny (żywy) obok apteczki ma mniej niż MAX_HP — wtedy zostaje dla niego.
func _hurt_teammate_near(who: Node2D) -> bool:
	for p in get_tree().get_nodes_in_group("players"):
		if p != who and not p.dead and p.hp < p.max_hp() and p.global_position.distance_to(global_position) < HURT_RESERVE_R:
			return true
	return false

## Amunicja: bierze ją każdy człowiek w zasięgu, ale tylko jeśli ktoś z ludzi nosi
## tę broń (P-64 ma nieskończoną amunicję — jej skrzynek nie ma) i zapas nie jest pełny.
func _try_ammo() -> void:
	if Arsenal.is_full(arg):
		return
	var carried := false
	var near_human := false
	for p in get_tree().get_nodes_in_group("players"):
		if p.is_bot or p.dead:
			continue
		if p.carries(arg):
			carried = true
		if _near(p):
			near_human = true
	if carried and near_human:
		var got := Arsenal.add_reserve(arg, rounds)
		if got > 0:
			_level().take_item(name)

## Skrzynia z mapy: uzupełnia zapas każdej broni głównej, którą drużyna nosi; zostaje,
## dopóki cokolwiek się mieści (nic się nie marnuje).
func _try_cache() -> void:
	var near := false
	var carried := {}
	for p in get_tree().get_nodes_in_group("players"):
		if p.is_bot or p.dead:
			continue
		if _near(p):
			near = true
		for w in p.kit_primaries():
			carried[w] = true
	if not near:
		return
	var added := 0
	for w in carried:
		added += Arsenal.add_reserve(w, maxi(1, int(Weapons.def(w).pickup_rounds * 0.6)))
	if added > 0:
		NoiseMgr.add_flare()          # skrzynia z mapy zawiera też flarę
		_level().take_item(name)

## Broń leży na ziemi i czeka na E — czy ten gracz stoi dość blisko?
func in_reach(p: Node2D) -> bool:
	return (p.global_position + Vector2(0, -8)).distance_to(global_position + Vector2(0, -6)) <= WEAPON_R
