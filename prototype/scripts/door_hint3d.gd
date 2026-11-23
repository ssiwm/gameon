extends Node3D
## Drzwi budynków (DESTRUCTION_CONTENT_PLAN.md W0–W1): podpowiedź przy zamkniętych drzwiach — „duch” narzędzia, który w pętli pokazuje, jak je wyważyć:
## maczeta rąbie ościeżnicę (drewno), kilof wbija się w szczelinę i podważa skrzydło (metal), ładunek przykleja się do słupka i mruga
## przed wybuchem (zbrojone). Wygląd celowo nie jak przedmiot gry: bez światła sceny, półprzezroczysty bursztyn z jaśniejszą krawędzią
## i delikatnymi liniami, błysk przy uderzeniu. Po wyważeniu drzwi rozpływa się (`dissolve`) i znika z drzewa. Ruch tylko w płaszczyźnie
## kadru (oś z). Pokazuje się dopiero, gdy lokalny gracz podejdzie (NEAR_M), i gra najwyżej LOOPS pętli; znowu dopiero po odejściu dalej
## niż REARM_M (decyzja autora 2026-11-22). Buduje ją `Building3D.door_hint`, stan drzwi przekazuje widok 3D (`view3d._sync_doors`).
## Od 1.7.666 ten sam duch zastępuje statyczny kilof znaku strefy wydobycia (`mat` = "dig", `view3d._build_dig_sign`): kilof rąbie czoło
## i wyłamuje bryłę urobku; gaśnie, gdy ktoś w strefie kopał (`done`), i wraca po resecie strefy (wipe, punkt kontrolny).

const Level3D := preload("res://scripts/level3d.gd")

const PERIOD := 2.6                         ## s: jedna pętla akcji
const TINT := Color(1.0, 0.72, 0.30)        ## bursztyn podpowiedzi (jak znaczniki celu na HUD-zie)
const FADE_OUT := 0.35                      ## s: rozpływanie po wyważeniu
const NEAR_M := 10.0                        ## m: gracz bliżej drzwi — podpowiedź rusza (decyzja autora 2026-11-22)
const REARM_M := 14.0                       ## m: po odejściu dalej podpowiedź może ruszyć jeszcze raz przy następnym podejściu
const LOOPS := 3                            ## najwyżej tyle pętli na jedno podejście (decyzja autora 2026-11-22)
const DIG_LEVER := 0.22                     ## rad: kilof w czole — trzonek od czoła przy wyłamaniu bryły (mniej niż przy podważaniu drzwi)
const FADE_IN := 0.3                        ## s: pojawienie się i zgaśnięcie po ostatniej pętli
const SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_back, shadows_disabled, fog_disabled;
uniform vec4 tint : source_color;
uniform float fade = 1.0;
uniform float flash = 0.0;
void fragment() {
	float rim = pow(1.0 - clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0), 1.5);
	float scan = 0.82 + 0.18 * sin(FRAGCOORD.y * 0.8 - TIME * 7.0);
	ALBEDO = mix(tint.rgb, vec3(1.0, 0.95, 0.85), clamp(flash, 0.0, 1.0)) * (1.0 + flash * 1.5);
	ALPHA = clamp(((0.42 + 0.58 * rim) * scan + flash * 0.4) * fade, 0.0, 1.0);
}
"""

var mat := "metal"                          ## wood / metal / steel / dig (kilof w czoło strefy wydobycia)
var side := 1.0                             ## strona zewnętrzna drzwi (+1 prawo, −1 lewo)
var tool: Node3D                            ## model narzędzia (dziecko)
var rest := Transform3D()                   ## poza narzędzia wbitego / przyklejonego
var hand := Vector3.ZERO                    ## punkt obrotu zamachu (koniec rękojeści / trzonka)
var tip := Vector3.ZERO                     ## czubek w ościeżnicy (oś dźwigni kilofa)
var done := Callable()                      ## () -> bool: podpowiedź już niepotrzebna (strefa wydobycia ruszona); znika i nie rusza, póki zwraca true

var _sm: ShaderMaterial
var _fade := 1.0
var _dying := false
var _play_t := -1.0                         ## s od początku pokazu; −1 — ukryta
var _armed := true                          ## może ruszyć przy następnym podejściu

static var _shader: Shader

## Wspólny shader ducha: nowy `Shader` na każde drzwi kompilował potok przy każdym pojawieniu (W3, --hitchtest --hitchdoor: ok. 70–230 ms
## po odbudowie drzwi); jeden egzemplarz — widok 3D rozgrzewa go pod planszą (`_warm_destruction("door_*")`).
static func shader() -> Shader:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER
	return _shader

func _ready() -> void:
	visible = false                               # do pierwszego podejścia
	_sm = ShaderMaterial.new()
	_sm.shader = shader()
	_sm.set_shader_parameter("tint", TINT)
	for mi in find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		m.material_override = _sm
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

## Drzwi wyważone: podpowiedź gaśnie z błyskiem i znika (ukryta znika od razu).
func dissolve() -> void:
	_dying = true
	if _play_t < 0.0:
		_fade = 0.0                               # już ukryta (poza zasięgiem albo po pętlach): bez błysku

func _process(delta: float) -> void:
	if _dying:
		_fade -= delta / FADE_OUT
		if _fade <= 0.0:
			queue_free()
			return
	var d := _player_dist()
	if not _dying and done.is_valid() and bool(done.call()):
		_play_t = -1.0                            # ktoś już kopie: bez pokazu (wraca po resecie strefy i odejściu jak po pętlach)
		_armed = false
	elif _play_t < 0.0:
		if _armed and d <= NEAR_M:
			_play_t = 0.0
			_armed = false
	else:
		_play_t += delta
		if _play_t >= float(LOOPS) * PERIOD or d > REARM_M:
			_play_t = -1.0
	if not _armed and _play_t < 0.0 and d > REARM_M:
		_armed = true
	visible = _play_t >= 0.0 or _dying
	if not visible:
		return
	var env := 1.0 if _dying else clampf(_play_t / FADE_IN, 0.0, 1.0) * clampf((float(LOOPS) * PERIOD - _play_t) / FADE_IN, 0.0, 1.0)
	var p := fmod(maxf(_play_t, 0.0), PERIOD)
	var fl := 0.0
	var show := 1.0
	match mat:
		"wood":
			fl = _chop(p)
		"steel":
			var r: Vector2 = _plant(p)
			fl = r.x
			show = r.y
		"dig":
			fl = _dig(p)
		_:
			fl = _pry(p)
	if _dying:
		fl = maxf(fl, _fade)                      # rozpływa się z jasnym błyskiem
	_sm.set_shader_parameter("flash", fl)
	_sm.set_shader_parameter("fade", _fade * show * env)

## Odległość lokalnego gracza od drzwi (m, w płaszczyźnie gry); INF bez gracza.
func _player_dist() -> float:
	for pl in get_tree().get_nodes_in_group("players"):
		if is_instance_valid(pl) and (pl as Node).is_multiplayer_authority() and pl.get("is_bot") != true:   # bot hosta się nie liczy
			var m: Vector3 = Level3D.px_to_m((pl as Node2D).global_position)
			return Vector2(m.x - tip.x, m.y - tip.y).length()
	return INF

## Obrót w płaszczyźnie kadru wokół punktu `at`.
static func _rot(at: Vector3, a: float) -> Transform3D:
	var b := Basis(Vector3.BACK, a)
	return Transform3D(b, at - b * at)

static func _ease_in(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return x * x * x

## Maczeta: zamach w górę od ściany, szybki cios w ościeżnicę, drgnięcie w drewnie. Zwraca błysk.
func _chop(p: float) -> float:
	var up := -2.0 * side                       # ostrze nad głowę
	var a := 0.0
	var fl := 0.0
	if p < 0.75:
		a = up * smoothstep(0.0, 0.75, p)
	elif p < 0.95:
		a = up
	elif p < 1.07:
		a = up * (1.0 - _ease_in((p - 0.95) / 0.12))
	else:
		var k := p - 1.07
		a = 0.035 * side * sin(k * 60.0) * exp(-k * 10.0)   # drży wbita
		fl = exp(-k * 9.0)
	tool.transform = _rot(hand, a) * rest
	return fl

## Kilof: zamach, wbicie obucha w szczelinę skrzydła, podważenie (trzonek odciągnięty jak dźwignia). Zwraca błysk.
func _pry(p: float) -> float:
	var back := -1.25 * side                    # głowica od ściany
	var swing := 0.0
	var lever := 0.0
	var fl := 0.0
	if p < 0.6:
		swing = back * smoothstep(0.0, 0.6, p)
	elif p < 0.75:
		swing = back
	elif p < 0.87:
		swing = back * (1.0 - _ease_in((p - 0.75) / 0.12))
	else:
		fl = exp(-(p - 0.87) * 9.0)
		if p < 1.0:
			lever = 0.0
		elif p < 1.7:
			lever = 0.38 * side * smoothstep(1.0, 1.7, p)
			fl = maxf(fl, 0.35 * smoothstep(1.4, 1.7, p))     # skrzydło puszcza
		elif p < 2.1:
			lever = 0.38 * side
		else:
			lever = 0.38 * side * (1.0 - smoothstep(2.1, 2.5, p))
	tool.transform = _rot(tip, lever) * _rot(hand, swing) * rest
	return fl

## Kilof w czoło strefy wydobycia: zamach, cios obuchem w czoło, drgnięcie, wyłamanie bryły (trzonek odciągnięty od czoła jak dźwignia) i powrót
## do pozy wbitego kilofa. Zwraca błysk.
func _dig(p: float) -> float:
	var back := -1.25 * side                    # głowica od czoła
	var swing := 0.0
	var lever := 0.0
	var fl := 0.0
	if p < 0.6:
		swing = back * smoothstep(0.0, 0.6, p)
	elif p < 0.75:
		swing = back
	elif p < 0.87:
		swing = back * (1.0 - _ease_in((p - 0.75) / 0.12))
	else:
		var k := p - 0.87
		swing = 0.03 * side * sin(k * 60.0) * exp(-k * 10.0)   # drży wbity
		fl = exp(-k * 9.0)
		if p >= 1.25 and p < 1.6:
			lever = DIG_LEVER * side * smoothstep(1.25, 1.6, p)
			fl = maxf(fl, 0.3 * smoothstep(1.45, 1.6, p))      # bryła puszcza
		elif p >= 1.6 and p < 1.8:
			lever = DIG_LEVER * side
		elif p >= 1.8:
			lever = DIG_LEVER * side * (1.0 - smoothstep(1.8, 2.2, p))
	tool.transform = _rot(tip, lever) * _rot(hand, swing) * rest
	return fl

## Ładunek: dosuwa się z zewnątrz do słupka, mruga coraz szybciej, błysk i gaśnie. Zwraca (błysk, widoczność).
func _plant(p: float) -> Vector2:
	var off := 0.0
	var show := 1.0
	var fl := 0.0
	if p < 0.5:
		var k := smoothstep(0.0, 0.5, p)
		off = 0.7 * (1.0 - k)
		show = k
	elif p < 2.0:
		var q := p - 0.5
		fl = 0.6 * exp(-q * 12.0)                 # przyklejony
		var period := lerpf(0.45, 0.12, q / 1.5)  # mruganie zapalnika coraz szybciej
		if fmod(q, period) < period * 0.35:
			fl = maxf(fl, 0.3)
	else:
		var q := p - 2.0
		fl = 0.9 * (1.0 - smoothstep(0.0, 0.6, q))   # błysk wybuchu
		show = 1.0 - smoothstep(0.15, 0.6, q)
	tool.transform = Transform3D(rest.basis, rest.origin + Vector3(side * off, 0.0, 0.0))
	return Vector2(fl, show)
