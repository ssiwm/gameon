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
var _glow: PointLight2D
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
	if kind == "health" and Sprites.has("objects"):
		_spr = Sprites.attach(self, "objects")
		Sprites.play(_spr, "medkit", false)
	if kind != "health":
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
	if not _spr.is_empty():
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

func _draw() -> void:
	if kind == "health":
		return
	var bob := 0.0 if (not _landed or static_display) else sin(_t * 3.0) * 1.5 - 1.5
	var c: Color = GLOW.get(kind, Color.WHITE)
	if kind == "flares":
		# skrzynka z flarami: trzy czerwone tuby z jasnymi paskami w drewnianej ramce
		draw_rect(Rect2(-7, -8 + bob, 14, 8), Color(0.18, 0.13, 0.09))
		draw_rect(Rect2(-6, -7 + bob, 12, 6), Color(0.3, 0.22, 0.14))
		for i in 3:
			var fx := -4.0 + float(i) * 4.0
			draw_rect(Rect2(fx, -11 + bob, 2, 7), Color(0.75, 0.16, 0.12))
			draw_rect(Rect2(fx, -9 + bob, 2, 1), Color(0.95, 0.85, 0.55))
			draw_rect(Rect2(fx, -12 + bob, 2, 1), Color(1.0, 0.6, 0.3))
	elif kind == "stash":
		# zakopany worek: brązowy, ściągnięty rzemieniem, ze złotym połyskiem (widać go tylko z bliska)
		var gl2 := 0.5 + 0.5 * sin(_t * 2.6)
		draw_rect(Rect2(-6, -9 + bob, 12, 9), Color(0.14, 0.1, 0.06))
		draw_rect(Rect2(-5, -8 + bob, 10, 8), Color(0.42, 0.3, 0.17))
		draw_rect(Rect2(-5, -8 + bob, 10, 2), Color(0.55, 0.4, 0.22))
		draw_rect(Rect2(-3, -10 + bob, 6, 3), Color(0.35, 0.25, 0.14))
		draw_rect(Rect2(-4, -7 + bob, 8, 1), Color(0.2, 0.14, 0.08))
		draw_rect(Rect2(1, -5 + bob, 3, 2), Color(0.95, 0.78, 0.32, 0.5 + 0.5 * gl2))
		draw_rect(Rect2(-5, -12 + bob, 1, 1), Color(1.0, 0.9, 0.6, gl2))
	elif kind == "tag":
		# nieśmiertelnik: dwie blaszki na łańcuszku, błysk (widać go w ciemności)
		var gl := 0.6 + 0.4 * sin(_t * 5.0)
		draw_arc(Vector2(0, -9 + bob), 4.0, 0.2, PI - 0.2, 8, Color(0.55, 0.57, 0.62), 1.0)
		draw_rect(Rect2(-4, -7 + bob, 4, 6), Color(0.62, 0.66, 0.72))
		draw_rect(Rect2(-4, -7 + bob, 4, 1), Color(0.85, 0.9, 0.95))
		draw_rect(Rect2(0, -6 + bob, 4, 6), Color(0.5, 0.54, 0.6))
		draw_rect(Rect2(-3, -5 + bob, 2, 1), Color(0.2, 0.22, 0.26))
		draw_circle(Vector2(0, -6 + bob), 5.0, Color(0.6, 0.85, 1.0, 0.12 * gl))
	elif kind == "scrap":
		# kupka złomu: blachy, trybik i śruba (większa wartość = większa kupka)
		var big := rounds >= 6
		draw_rect(Rect2(-5, -3 + bob, 10, 3), Color(0.32, 0.33, 0.37))
		draw_rect(Rect2(-5, -3 + bob, 10, 1), Color(0.55, 0.57, 0.62))
		draw_rect(Rect2(-3, -6 + bob, 5, 3), Color(0.42, 0.3, 0.2))
		draw_rect(Rect2(1, -5 + bob, 3, 2), Color(0.5, 0.52, 0.56))
		if big:
			draw_rect(Rect2(-6, -9 + bob, 4, 3), Color(0.3, 0.31, 0.35))
			draw_circle(Vector2(3, -8 + bob), 2.2, Color(0.6, 0.48, 0.2))
			draw_circle(Vector2(3, -8 + bob), 0.9, Color(0.15, 0.15, 0.16))
		draw_rect(Rect2(-5, -1 + bob, 10, 1), Color(0.95, 0.8, 0.4, 0.5))
	elif kind == "cache":
		# skrzynia z zapasem: większa, z pasami i mosiężnymi okuciami
		draw_rect(Rect2(-8, -11 + bob, 16, 10), Color(0.26, 0.28, 0.19))
		draw_rect(Rect2(-8, -11 + bob, 16, 2), Color(0.4, 0.43, 0.3))
		draw_rect(Rect2(-8, -6 + bob, 16, 1), Color(0.85, 0.68, 0.3))
		draw_rect(Rect2(-1, -11 + bob, 2, 10), Color(0.85, 0.68, 0.3, 0.7))
		draw_rect(Rect2(-8, -2 + bob, 16, 1), Color(0.12, 0.13, 0.09))
	elif kind == "ammo":
		# skrzynka z amunicją: oliwkowe pudło z mosiężnym paskiem w kolorze rodzaju broni
		draw_rect(Rect2(-5, -8 + bob, 10, 7), Color(0.28, 0.3, 0.2))
		draw_rect(Rect2(-5, -8 + bob, 10, 1), Color(0.4, 0.42, 0.3))
		draw_rect(Rect2(-4, -5 + bob, 8, 2), Weapons.def(arg).tracer_color.lerp(Color(0.85, 0.68, 0.3), 0.4))
		draw_rect(Rect2(-5, -2 + bob, 10, 1), Color(0.14, 0.15, 0.1))
	else:
		# broń: sylwetka z arkusza guns.png nad ciemną skrzynką-podstawką
		# pozycje na CAŁYCH pikselach — ułamki rozmywają pixel-art
		var ibob := roundf(bob)
		if not static_display:                                           # na stojaku podstawką jest kołyska stojaka
			draw_rect(Rect2(-8, -4 + ibob, 16, 3), Color(0.12, 0.13, 0.16))
			draw_rect(Rect2(-8, -4 + ibob, 16, 1), c.darkened(0.4))
		var tex := Sprites.texture(Sprites.DIR + "guns.png")
		if tex != null and Sprites.has("guns"):
			var tfs := Sprites.frame_size("guns")                       # rozmiar klatki w pikselach arkusza
			var fs := tfs * Sprites.scale_of("guns")                     # rozmiar w świecie (arkusz ma 2× gęstość)
			var row := int(Weapons.def(arg).gun_row)
			var dst := Rect2(roundf(-fs.x * 0.5), -4.0 - fs.y + ibob, fs.x, fs.y)
			if static_display:
				# sylwetka nie leży w środku klatki (chwyt, lufa) — na stojaku wyśrodkowujemy ją po zawartości, a spód stawiamy na półce
				var box := _content_box(tex, row, tfs)
				if box.size.x > 0:
					var sc := Sprites.scale_of("guns")
					dst = Rect2(roundf(-(float(box.position.x) + float(box.size.x) * 0.5) * sc), roundf(-7.0 - float(box.end.y) * sc), fs.x, fs.y)
			var src := Rect2(0, row * tfs.y, tfs.x, tfs.y)
			# ciemny kontur 1 px — sylwetka czytelna na jasnym i ciemnym tle
			for o: Vector2 in [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1)]:
				draw_texture_rect_region(tex, Rect2(dst.position + o, dst.size), src, Color(0, 0, 0, 0.85))
			var locked := static_display and not Scrap.is_unlocked(arg)
			draw_texture_rect_region(tex, dst, src, Color(0.32, 0.33, 0.4) if locked else Color.WHITE)
			var glow_tex := Sprites.texture(Sprites.DIR + "guns_glow.png")
			if glow_tex != null and not locked:
				draw_texture_rect_region(glow_tex, dst, src)
			if locked:
				_draw_lock(dst)
		else:
			draw_rect(Rect2(-6, -7 + bob, 12, 3), c)

## Zablokowany stojak: kłódka nad bronią i cena (albo „SOON") na tabliczce stojaka.
func _draw_lock(dst: Rect2) -> void:
	var cx := roundf(dst.position.x + dst.size.x * 0.5)
	var cy := roundf(dst.position.y + dst.size.y * 0.5) - 4.0
	draw_arc(Vector2(cx, cy - 3.0), 2.6, PI, TAU, 8, Color(0.75, 0.75, 0.8), 1.0)
	draw_rect(Rect2(cx - 3.5, cy - 3.0, 7, 6), Color(0.15, 0.15, 0.18))
	draw_rect(Rect2(cx - 2.5, cy - 2.0, 5, 4), Color(0.85, 0.7, 0.3))
	draw_rect(Rect2(cx - 0.5, cy - 0.5, 1, 2), Color(0.15, 0.15, 0.18))
	var price := Scrap.price_of(arg)
	var label := "%d" % price if price > 0 else "SOON"
	draw_string(ThemeDB.fallback_font, Vector2(-12, -2), label, HORIZONTAL_ALIGNMENT_CENTER, 24.0, 6, Color(0.12, 0.09, 0.06))

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
		if not p.is_bot and not p.dead and p.hp < p.MAX_HP and p.global_position.distance_to(global_position) < 80.0:
			hurt_human_near = true
	for p in get_tree().get_nodes_in_group("players"):
		if p.dead or p.hp >= p.STACK_HP:
			continue
		if p.is_bot and hurt_human_near:
			continue
		if p.hp >= p.MAX_HP and _hurt_teammate_near(p):
			continue
		if _near(p):
			p.deliver_heal(HEAL)
			_level().take_item(name)
			return

## Czy ktoś inny (żywy) obok apteczki ma mniej niż MAX_HP — wtedy zostaje dla niego.
func _hurt_teammate_near(who: Node2D) -> bool:
	for p in get_tree().get_nodes_in_group("players"):
		if p != who and not p.dead and p.hp < p.MAX_HP and p.global_position.distance_to(global_position) < HURT_RESERVE_R:
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
