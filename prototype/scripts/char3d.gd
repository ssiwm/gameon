extends Node2D
## Postać 3D renderowana w czasie rzeczywistym do tekstury (`--char3d`, patrz CHAR3D_SPIKE.md).
##
## Model z rigiem Mixamo (art/char3d/<płeć>_<strój>.glb, tools/prep_char3d.py) żyje w małym SubViewport z kamerą
## ortogonalną patrzącą z boku; wynik wyświetla zwykły Sprite2D (obrys robi shader, oświetlenie 2D robi gra).
## Pozy to czysty kod: nogi i ręce rozwiązuje dwukostkowe IK, więc broń (art/char3d/gun_<klucz>.glb, chwyty w .json)
## leży w dłoniach przy KAŻDYM kącie celowania, animacji, broni i wyglądzie. Przeładowanie, dobycie i cios to ruch broni
## (ten sam co w weapon_view) plus lewa dłoń sięgająca do magazynka. Czyta tylko stan zreplikowany w graczu — poza nic
## nie rozstrzyga w gameplayu, więc każdy peer widzi to samo. Rozgrywka bierze stąd tylko `aim_points`: chwyt i wylot lufy
## z pozy nominalnej (postawa, kąt, broń, model), bez udziału bieżącej klatki animacji.
##
## Układ: model patrzy w +X, kamera stoi na +Z (bliższa jest prawa strona postaci), stopy w y = 0.
## Zwrot w lewo: w widoku 3D model obraca się wokół pionu (`model_yaw`, obrót przodem do kamery w TURN_TIME) — broń zostaje w prawej
## ręce, więc patrząc w lewo postać pokazuje lewy bok; w podglądzie 2D (sprite) to dalej odbicie flip_h.

const CHAR_H_M := 1.8                       ## wysokość postaci odniesienia (m)
const CHAR_H_WP := 22.0                     ## ... w pikselach świata
const WP_PER_M := CHAR_H_WP / CHAR_H_M
## Jakość renderu (pokrętła kosztu na słabszym GPU): pikseli renderu na piksel świata (4 = jak arkusze HD postaci) i MSAA.
## Niska jakość: --char3d-lq (SS 2, bez MSAA) — ok. 3× mniej pikseli do wyrenderowania.
static var ss := 4
static var msaa := true
## Mapa normalnych (drugi przebieg renderu): światła 2D (latarka, flara) dają relief jak na sprite'ach HD. Kosztuje drugi render siatki; wyłączane w niskiej jakości.
static var normals := true
const VIEW_YAW_DEG := 15.0                  ## obrót kamery wokół postaci (widok 3/4): widać pierś, twarz i ekwipunek; 0 = czysty profil
const FRAME_WP := Vector2(44.0, 44.0)       ## ramka w pikselach świata (zapas na broń podniesioną i wyciągniętą)
const CAM_Y := 1.25                         ## wysokość środka ramki (m)
const PRE := "mixamorig_"
const DIR := "res://art/char3d/"
const DEFAULT_CHAR := "male_scav"
const DEFAULT_GUN := "m83"

const Look := preload("res://scripts/look.gd")
const CharClips := preload("res://scripts/char_clips.gd")

## Materiał modelu z paletą kolorów (look.gd, PALETTES): kolor + normalne + ORM z modelu, metaliczność 0 (bez sondy odbić czarna).
const PALETTE_SHADER := """
shader_type spatial;
uniform sampler2D albedo_tex : source_color, hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec4 albedo_mul : source_color = vec4(1.0);   // kolor materiału (części bez tekstury: ekwipunek, czapka z MPFB)
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D orm_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform bool has_normal = false;
uniform bool has_orm = false;
uniform float hue_target = -1.0;          // < 0: bez zmiany barwy
uniform float sat_mul = 1.0;
uniform float val_mul = 1.0;
uniform float damage = 0.0;               // 0..1: ilość krwi na stroju (player.gd, z zdrowia); maska w przestrzeni UV — przyklejona do ciała przy animacji
uniform float blood_seed = 0.0;
varying float wy;                         // wysokość w świecie (m): krew gęstsza na tułowiu i ramionach niż na łydkach
float bh(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}
float bn(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(bh(i), bh(i + vec2(1.0, 0.0)), f.x), mix(bh(i + vec2(0.0, 1.0)), bh(i + vec2(1.0, 1.0)), f.x), f.y);
}
vec3 rgb2hsv(vec3 c) {
	vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	float e = 1.0e-10;
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}
vec3 hsv2rgb(vec3 c) {
	vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
	vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
	return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}
void vertex() {
	wy = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y;
}
void fragment() {
	vec3 c = texture(albedo_tex, UV).rgb * albedo_mul.rgb;
	if (hue_target >= 0.0 || sat_mul != 1.0 || val_mul != 1.0) {
		vec3 h = rgb2hsv(c);
		// skóra (pomarańcz, średnie nasycenie) zostaje; szarości, czerń i biel nie dostają obrotu barwy
		float skin = smoothstep(0.01, 0.03, h.x) * (1.0 - smoothstep(0.085, 0.115, h.x)) * smoothstep(0.15, 0.25, h.y) * (1.0 - smoothstep(0.65, 0.8, h.y)) * smoothstep(0.25, 0.4, h.z);
		float colored = smoothstep(0.12, 0.28, h.y);
		float k = colored * (1.0 - skin);
		float nh = h.x;
		if (hue_target >= 0.0) {
			float dh = fract(h.x - 0.17 + 0.5) - 0.5;      // odległość od barwy oliwkowej: część różnic odcieni zostaje
			nh = fract(hue_target + dh * 0.35);
		}
		vec3 t = vec3(nh, clamp(h.y * sat_mul, 0.0, 1.0), clamp(h.z * val_mul, 0.0, 1.0));
		c = mix(c, hsv2rgb(t), k);
		c *= mix(1.0, val_mul, (1.0 - skin) * (1.0 - colored));
	}
	float wet = 0.0;
	if (damage > 0.001) {
		// plamy krwi: szum w UV (stały na ciele), próg spada z obrażeniami; rdzeń ciemniejszy, brzeg „zaschnięty”, mokry połysk w świetle
		vec2 bp = UV * 9.0 + vec2(blood_seed, blood_seed * 0.63);
		float n = bn(bp) * 0.55 + bn(bp * 2.3 + 5.0) * 0.3 + bn(bp * 5.1 + 11.0) * 0.15;
		float zone = smoothstep(0.15, 1.1, wy);
		float thr = 1.0 - damage * 0.62 - 0.1 * zone;
		float blood = smoothstep(thr, thr + 0.07, n);
		float core = smoothstep(thr + 0.07, thr + 0.2, n);
		vec3 crust = vec3(0.10, 0.012, 0.016);
		vec3 wetc = vec3(0.15, 0.012, 0.018);
		c = mix(c, mix(crust, wetc, core), blood * 0.92);
		wet = blood * core;
	}
	ALBEDO = c;
	if (has_normal) {
		NORMAL_MAP = texture(normal_tex, UV).xyz;
	}
	if (has_orm) {
		vec4 o = texture(orm_tex, UV);
		AO = o.r;
		ROUGHNESS = o.g;
	} else {
		ROUGHNESS = 0.85;
	}
	ROUGHNESS = mix(ROUGHNESS, 0.34, wet);
	METALLIC = 0.0;
}
"""

const OUTLINE_SHADER := """
shader_type canvas_item;
uniform vec4 outline_color : source_color = vec4(0.078, 0.055, 0.094, 1.0);
uniform float width = 2.0;
uniform bool flip_n = false;          // sprite odbity poziomo (flip_h): składowa X normalnych odwrócona, żeby światło padało z właściwej strony
void fragment() {
	vec4 c = texture(TEXTURE, UV);
	vec2 px = TEXTURE_PIXEL_SIZE * width;
	float a = 0.0;
	for (int r = 1; r <= 2; r++) {
		for (int i = 0; i < 8; i++) {
			float ang = float(i) * 0.785398;
			a = max(a, texture(TEXTURE, UV + vec2(cos(ang), sin(ang)) * px * (float(r) * 0.5)).a);
		}
	}
	a = smoothstep(0.1, 0.7, a);
	COLOR = vec4(mix(outline_color.rgb, c.rgb / max(c.a, 0.001), c.a), max(a, c.a));
	vec3 n = texture(NORMAL_TEXTURE, UV).rgb;
	if (flip_n) {
		n.x = 1.0 - n.x;
	}
	NORMAL_MAP = mix(vec3(0.5, 0.5, 1.0), n, c.a);
}
"""

var _vp: SubViewport
var _vpn: SubViewport                        ## drugi przebieg: normalne widokowe (R=+X, G=+Y w górę, B=do kamery, ×0,5+0,5) tego samego świata 3D
var _camn: Camera3D
var _sun: DirectionalLight3D
var _rim: DirectionalLight3D
var _canvas_tex: CanvasTexture
## Podgląd postaci w menu (warsztat, lobby): zawsze pełna jakość, bez mapy normalnych (brak świateł 2D), własny `ss`, obrót kamery.
var preview := false
var preview_ss := 12
var view_yaw := VIEW_YAW_DEG                 ## stopnie; w podglądzie kręci się „na stole obrotowym”
var _damage := 0.0                           ## 0..1 obrażenia (krew w materiale i pochylenie tułowia)
var _blood_seed := 0.0
var _pal_mats: Array = []                    ## ShaderMaterial postaci (paleta kolorów) — uniformy ustawia _apply_palette
var _palette := 0
var _rev := 0
var _last_zoom := 2.0
var _last_h := 1080.0
var _gun_n: Node3D
var _normal_mat: ShaderMaterial
var _cam: Camera3D
var _sprite: Sprite2D
var _notifier: VisibleOnScreenNotifier2D
var _root3d: Node3D
var _char_node: Node
var _char_name := ""
var _sk: Skeleton3D
var _gun: Node3D
var _gun_key := ""
var _hands := 2
var _gun_len := 1.2
var _gun_info := {"rear": Vector3.ZERO, "fore": Vector3(0.4, 0.03, 0.0), "muzzle": Vector3(0.9, 0.08, 0.0)}   ## dane trzymanej broni (gun_info): układ Godota (x, y w górę, z do kamery)
static var _gun_infos := {}                  ## klucz broni → dane z gun_<klucz>.json (raz na sesję)
var _b := {}                                 ## nazwa kości → indeks
var _leg_len := {}                           ## długości [udo, goleń] (m)
var _arm_len := {}                           ## długości [ramię, przedramię] (m)
var _arm_hinge := {}                         ## strona → [oś zgięcia łokcia w układzie kości ramienia, … przedramienia] (z pozy spoczynkowej); brak = ręka prosta w spoczynku
var _hand_rel := {}                          ## strona → orientacja dłoni względem przedramienia w spoczynku (do podziału skrętu nadgarstka)
var _hand := {}                              ## strona → {"fix": Basis, "len": m, "thick": m}: układ anatomiczny dłoni zmierzony z siatki (_measure_hands)
static var _hand_cache := {}                 ## nazwa modelu → to samo (pomiar raz na model)
var _face := 1.0                             ## −1..1: zwrot w trakcie obrotu (1 = w prawo, −1 = w lewo); w połowie postać stoi przodem do kamery
var _cam_c := 1.0                            ## −1..1: po której stronie modelu jest kamera (+1 = +Z, prawy bok); przy obrocie przechodzi płynnie przez 0
var model_yaw := 0.0                         ## rad: obrót modelu wokół pionu w widoku 3D (czyta view3d.gd zamiast odbicia lustrzanego)
var _vis_aim := NAN                          ## rad: kąt broni modelu (goni kąt celowania sprężyną — broń ma bezwładność); NAN = pierwsza klatka
var _vis_vel := 0.0                          ## rad/s
var _last_recoil := 0.0
var _stance := {}                            ## czy kuca → punkty postawy (biodra, kręgosłup, barki) do liczenia barków „nominalnych" (_stance_pts)
var _posed := false                          ## pierwsza poza już policzona (drzewo klipów działa dopiero od pierwszej klatki)
var _origin_x := 0.163                       ## oś ciała (m) — biodra w pozie spoczynkowej
var _ankle_y := 0.077                        ## wysokość kostki na podłożu (m)
var _time := 0.0
var _phase := 0.0
var _on_screen := true

## Wejście od widoku broni (weapon_view.gd), ustawiane co klatkę przed update().
var gun_extra := 0.0                         ## rad — dodatkowy obrót lufy w dół (odrzut, dobycie, przeładowanie, zamach), względem kierunku patrzenia
var gun_kick_px := 0.0                       ## px — cofnięcie broni wzdłuż lufy (odrzut)
var reload_t := -1.0                         ## 0..1 trwającego przeładowania, <0 = brak (lewa dłoń sięga do magazynka)
var swing_t := -1.0                          ## 0..1 trwającego ciosu, <0 = brak
var throw_t := -1.0                          ## 0..1 trwającego rzutu (flara, granat), <0 = brak: prawa ręka zamachem nad głową, broń schowana
var hit_t := -1.0                            ## 0..1 reakcji na trafienie (rekoil tułowia i głowy), <0 = brak (player.gd)
var land_t := -1.0                           ## 0..1 amortyzacji lądowania (ugięcie kolan), <0 = brak (player.gd)
var land_str := 0.6                          ## siła lądowania 0..1 (z prędkości spadania)
var back_run := false                        ## biegnie tyłem względem kierunku celowania: krok w przeciwną stronę, tułów odchylony
var dying := 0.0                             ## 0..1 ostatnie sekundy wykrwawiania: drgawki i zapadanie się w ziemię (player.gd)
var charge_t := 0.0                          ## 0..1 ładowania szyny (widmo1): drżenie, odchylenie tułowia
var cycle_t := -1.0                          ## 0..1 cyklu po strzale (pompka, zamek), <0 = brak (weapon_view.gd)
var recoil_px := 0.0                         ## px odrzutu broni (to samo co gun_kick_px, ale także po strzale poza przeładowaniem): wznos lufy i cofnięcie ciała
var grabbed := false                         ## chwycony przez Pijawkę (player.gd): szamocze się, nogi dyndają nad ziemią
var _grab_w := 0.0                           ## 0..1 waga pozy chwycenia (płynne wejście i wyjście)
var air_vy := 0.0                            ## px/s prędkość pionowa w locie (− w górę): steruje pozą skoku (wyprost, podciągnięte kolana, sięganie do ziemi)
var climb_t := -1.0                          ## 0..1 podciągnięcia przy wskakiwaniu na platformę (player.gd), <0 = brak
var _air_t := 0.0                            ## s w powietrzu (od odbicia)
var sink_m := 0.0                            ## m: o tyle opuszczamy model pod podłoże (czyta view3d.gd)
var _mc := {}                                ## bieżący cios bronią białą (krzywe ruchu), puste = brak ciosu
const AW_STATES := ["idle", "run", "jump", "fall", "crouch", "crouch_walk", "revive"]
## Pozy specyficzne dla broni: promień początku układu broni od barku (m) i opuszczenie względem linii celowania (− = wyżej, na ramieniu), rodzaj przeładowania
## (mag / shell / cell / rail / bolt / pistol), cykl po strzale (pump / bolt), mnożniki wznosu lufy (climb) i cofnięcia ciała (body), odchylenie tułowia (lean, °),
## side — przesunięcie broni w poprzek ciała względem prawego barku (m, − = ku środkowi; domyślnie −0,13), wrist — kąt śródręcza dłoni tylnej względem lufy
## (°, + = knykcie wyżej niż nadgarstek; chwyt pistoletowy 12, szyjka kolby −8, rękojeść broni białej −50), grip_dy — przesunięcie dłoni tylnej wzdłuż
## chwytu (m, − = niżej: rękawica jest większa od pistoletu, więc trzyma go nisko, żeby zamek wystawał nad dłoń), follow — jak GUN_FOLLOW, dla tej broni.
const WEAPON_POSE := {
	"m83": {"reload": "mag", "radial": 0.30, "perp": 0.11, "climb": 1.0, "body": 1.0},
	"sokol6": {"reload": "mag", "radial": 0.31, "perp": 0.11, "climb": 1.0, "body": 1.0},
	"p64": {"reload": "pistol", "follow": 0.8, "radial": 0.56, "perp": 0.16, "side": -0.21, "wrist": -4.0, "grip_dy": -0.04, "climb": 1.6, "body": 0.6},
	"spread12": {"reload": "mag", "radial": 0.30, "perp": 0.11, "climb": 1.2, "body": 1.3},      # od 1.7.313 półautomat na komorze AK z bębnem: chwyt pistoletowy, bez pompki
	"srut8": {"reload": "shell", "cycle": "pump", "radial": 0.28, "perp": 0.10, "climb": 1.4, "body": 1.7, "lean": -2.0, "wrist": -8.0},
	"lr7": {"reload": "cell", "radial": 0.30, "perp": 0.11, "climb": 0.5, "body": 0.5},
	"hkm9": {"reload": "cell", "radial": 0.24, "perp": 0.20, "climb": 0.3, "body": 0.5, "lean": 3.0, "wrist": -8.0},
	"gniew4": {"reload": "shell", "radial": 0.20, "perp": -0.03, "climb": 1.2, "body": 2.2, "lean": -6.0},
	"widmo1": {"reload": "rail", "radial": 0.27, "perp": 0.10, "climb": 1.0, "body": 2.4, "lean": -6.0},
	"ciegno6": {"reload": "bolt", "cycle": "bolt", "radial": 0.31, "perp": 0.10, "climb": 0.8, "body": 1.2, "wrist": -8.0},
	"maczeta": {"wrist": -50.0},
	"kilof": {"wrist": -50.0},
}
const PALM_AT := 0.45                        ## środek dłoni: ułamek długości dłoni od nadgarstka (tam leży chwyt)
const GRIP_HALF := 0.013                     ## pół grubości chwytu / rękojeści (m): o tyle dłoń leży obok jego osi
const GUN_FOLLOW := 0.5                      ## ile ruchu barku względem pozy nominalnej przechodzi na broń (1 = broń sztywno przy barku, 0 = nieruchoma w pozie nominalnej)
const AIM_SPRING := 34.0                     ## 1/s: sztywność sprężyny, którą broń MODELU goni kierunek celowania (rozgrywka celuje od razu)
const MELEE_GUARD := 0.95                    ## rad: uniesienie ostrza w gardzie (broń biała w spoczynku)
const TURN_TIME := 0.16                      ## s: obrót postaci przy zmianie kierunku (przodem do kamery)
const UP_REACH := 0.16                       ## m: o tyle dalej od barku jest broń przy celowaniu pionowo w górę
const CROUCH_DROP := 0.48                    ## m: o tyle niżej są biodra w przysiadzie (poza z kodu i barki nominalne)
const SPINE_AIM := 0.13                      ## ułamek kąta celowania, o który pochyla się każda z trzech kości kręgosłupa
const SPINE_AIM_UP := 0.060                    ## … i dodatkowo przy celowaniu w górę (rośnie z sinusem kąta): tułów odchyla się do tyłu, a głowa
                                             ## odsuwa się od rąk — bez tego przy celowaniu stromo w górę ręce zasłaniały twarz
const BODY_YAW := -22.0                      ## °: tułów zwrócony ku kamerze — w obie strony (znak z `_cam_c`), więc po obrocie w lewo widać pierś,
                                             ## dłonie i broń, a nie plecak. Poza nominalna (rozgrywka) liczy go zawsze jak dla zwrotu w prawo, żeby wylot
                                             ## był lustrzany; różnicę (bark ok. 0,18 m dalej w przód przy zwrocie w lewo) wybierają ręce (GUN_FOLLOW).
const AW_RATE := 13.0                        ## 1/s: tempo mieszania póz bazowych (przejścia ~80 ms)
var _aw := {}                                ## wagi póz bazowych — płynne przejścia zamiast przeskoków
var _down := 0.0                             ## 0..1 postęp upadku (rośnie przy „down”, maleje przy wstawaniu po reanimacji)
## Klipy animacji (char_clips.gd): drzewo daje ruch ciała w stanach, które mają klip (bieg); IK rąk i stóp liczymy na wierzchu.
var clips_on := true                         ## false = same pozy z kodu (porównania w tools/shot_anim3d.gd)
var clips_raw := false                       ## true = klipy bez tłumienia tułowia (ustaw przed setup; tylko do porównań)
var _clips: AnimationTree
var _clip_w := 0.0                           ## 0..1 łączna waga klipów w tej klatce (0 = poza z kodu)
var _clip_k := 0.0                           ## 0..1 udział klipu w stanach, które go mają (1 = cały stan z klipu; maleje przy upadku)
var _kneel_t := 0.0                          ## s od wejścia w stan „revive" (czas klipu klęczenia)
var _clip_arms := 0.0                        ## 0..1 waga stanu, w którym ręce idą z klipu, a broń jest schowana (klęczenie przy rannym)
var _rise_w := 0.0                           ## 0..1 wstawanie: klip „getup" zamiast klipu upadku granego wstecz
var _clip_down := 0.0                        ## 0..1 udział klipu upadku (zastępuje upadek z kodu, gdy klip jest)
var _clip_prog := {}                         ## stan → postęp 0..1 klipów jednorazowych (wejście dla CharClips.drive)
var _clip_knee := {}                         ## strona → kierunek kolana w klipie (biegun IK nogi), pusty wektor = brak
var _clip_bounce := 0.0                      ## m: poprawka pionu bioder zdejmująca część kołysania klipu (CharClips.bounce_fix)
var _clip_ws := {}                           ## stan → waga klipu w tej klatce (wejście dla CharClips.drive)
var _clip_foot := {}                         ## strona → Transform3D stopy z klipu (przestrzeń szkieletu), zanim ruszą ją nakładki

## Wyniki ostatniej klatki, w pikselach świata względem stóp (z uwzględnieniem odbicia) — dla efektów.
var muzzle_px := Vector2.ZERO
var px_flip := 1.0                           ## +1 postać patrzy w prawo, −1 w lewo (znak, z jakim policzono muzzle_px / grip_px)
var grip_px := Vector2.ZERO
var ready_ok := false

## Plik modelu dla kodu wyglądu: np. "male_scav", "female_hazmat" (Look.gender_id + Look.outfit_id; „scavenger” → „scav”).
static func char_name_for(gender: String, outfit: String) -> String:
	return "%s_%s" % [gender, "scav" if outfit == "scavenger" else outfit]

## Niska jakość (--char3d-lq lub słaby sprzęt): mniejsza rozdzielczość renderu, bez MSAA, normalnych, cieni i rim light.
static func set_low_quality(on: bool) -> void:
	ss = 2 if on else 4
	msaa = not on
	normals = not on
	shadows = not on
	rim = not on
	ss_auto = not on
	forced_low = on

## Cienie własne postaci (kierunkowe, mała ramka) i światło kontrujące (rim) — wg poziomu jakości.
static var shadows := true
static var rim := true
static var ss_cap := 8                       ## górna granica `ss` z poziomu jakości
static var forced_low := false               ## --char3d-lq: poziom jakości z ustawień jest ignorowany
static var quality_now := 2
static var quality_rev := 0
## Poziom z ustawienia „Effects quality” (Settings.quality_idx): 0 LOW (ss ≤ 4, bez MSAA / normalnych / cieni / rim),
## 1 MEDIUM (ss ≤ 6, MSAA, normalne, rim), 2 HIGH (ss ≤ 8, + cienie własne).
static func set_quality(q: int) -> void:
	if forced_low:
		return
	q = clampi(q, 0, 2)
	if q == quality_now:
		return
	quality_now = q
	quality_rev += 1                         # żywe postacie dopasują się przy najbliższym apply_view
	ss_cap = [4, 6, 8][q]
	msaa = q >= 1
	normals = q >= 1
	rim = q >= 1
	shadows = q >= 2

## Czy `ss` ma nadążać za zoomem kamery i rozmiarem okna (wyłącza je tryb niskiej jakości).
static var ss_auto := true

## Ile pikseli renderu na piksel świata daje ostry obraz przy danym zoomie kamery i wysokości okna (baza 640×360).
static func ss_for_view(zoom: float, win_h: float) -> int:
	return clampi(int(ceil(zoom * win_h / 360.0)), 3, ss_cap)

static func available() -> bool:
	return DisplayServer.get_name() != "headless" and ResourceLoader.exists(DIR + DEFAULT_CHAR + ".glb")

var _ss_now := 0

## Dopasowuje rozdzielczość renderu do widoku: zoom kamery × rozmiar okna. Woła gracz przy starcie, zmianie zoomu i rozmiaru okna.
func apply_view(zoom: float, win_h: float) -> void:
	_last_zoom = zoom
	_last_h = win_h
	if preview:
		return
	if _vp != null and _rev != quality_rev:
		_rev = quality_rev
		apply_quality()                                        # woła apply_view ponownie z nowym limitem ss
		return
	if not ss_auto or _vp == null:
		return
	var n := ss_for_view(zoom, win_h)
	if n == _ss_now:
		return
	_ss_now = n
	ss = n                                                # nowe postacie startują od razu w dobrej jakości
	_vp.size = Vector2i(int(FRAME_WP.x) * n, int(FRAME_WP.y) * n)
	if _vpn != null:
		_vpn.size = _vp.size
	_sprite.scale = Vector2.ONE / float(n)
	(_sprite.material as ShaderMaterial).set_shader_parameter("width", 0.5 * n)

func setup(char_name := DEFAULT_CHAR, gun_key := DEFAULT_GUN) -> bool:
	_ss_now = _q_ss()
	_vp = SubViewport.new()
	_vp.name = "Vp"
	_vp.size = Vector2i(int(FRAME_WP.x) * _ss_now, int(FRAME_WP.y) * _ss_now)
	_vp.transparent_bg = true
	_vp.own_world_3d = true
	_vp.msaa_3d = Viewport.MSAA_2X if _q_msaa() else Viewport.MSAA_DISABLED
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_vp)
	_root3d = Node3D.new()
	_vp.add_child(_root3d)
	_cam = Camera3D.new()
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.keep_aspect = Camera3D.KEEP_HEIGHT
	_cam.size = FRAME_WP.y / WP_PER_M
	_cam.near = 0.5
	_cam.far = 20.0
	_cam.cull_mask = 1
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.64, 0.72)
	env.ambient_light_energy = 0.7
	_cam.environment = env
	_root3d.add_child(_cam)
	_sun = DirectionalLight3D.new()
	_sun.basis = Basis.looking_at(Vector3(-0.35, -0.75, -0.55), Vector3.UP)
	_sun.light_energy = 1.05
	_sun.light_color = Color(1.0, 0.96, 0.9)
	_sun.shadow_enabled = _q_shadows()
	_sun.shadow_bias = 0.03
	_sun.shadow_normal_bias = 1.0
	_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	_sun.directional_shadow_max_distance = 10.0
	_root3d.add_child(_sun)
	_rim = DirectionalLight3D.new()                           # kontra zza postaci i z góry: chłodny obrys sylwetki odcina ją od tła
	_rim.basis = Basis.looking_at(Vector3(0.15, -0.35, 0.93), Vector3.UP)
	_rim.light_energy = 0.55
	_rim.light_color = Color(0.75, 0.85, 1.0)
	_rim.visible = _q_rim()
	_root3d.add_child(_rim)
	var fill := DirectionalLight3D.new()
	fill.basis = Basis.looking_at(Vector3(0.7, -0.2, -0.4), Vector3.UP)
	fill.light_energy = 0.28
	fill.light_color = Color(0.6, 0.7, 1.0)
	_root3d.add_child(fill)

	_sprite = Sprite2D.new()
	_sprite.name = "Body3D"
	_build_normal_pass()                                     # zawsze zbudowany; poziom jakości tylko go włącza / wyłącza (apply_quality)
	_canvas_tex = CanvasTexture.new()
	_canvas_tex.diffuse_texture = _vp.get_texture()
	_canvas_tex.normal_texture = _vpn.get_texture() if _q_normals() else null
	_sprite.texture = _canvas_tex
	_vpn.render_target_update_mode = SubViewport.UPDATE_ALWAYS if _q_normals() else SubViewport.UPDATE_DISABLED
	_sprite.scale = Vector2.ONE / float(_ss_now)
	_sprite.position = Vector2(0.0, -CAM_Y * WP_PER_M)
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	var sh := Shader.new()
	sh.code = OUTLINE_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("width", 0.5 * _ss_now)      # obrys 0,5 piksela świata niezależnie od ss
	_sprite.material = mat
	add_child(_sprite)
	# poza ekranem nie renderujemy viewportu (koszt rośnie z liczbą postaci, a zdalni gracze bywają daleko)
	_notifier = VisibleOnScreenNotifier2D.new()
	_notifier.rect = Rect2(-FRAME_WP.x * 0.5, -CAM_Y * WP_PER_M - FRAME_WP.y * 0.5, FRAME_WP.x, FRAME_WP.y)
	_notifier.screen_entered.connect(func(): _set_on_screen(true))
	_notifier.screen_exited.connect(func(): _set_on_screen(false))
	add_child(_notifier)

	if not set_look(char_name):
		return false
	set_gun(gun_key)
	ready_ok = true
	return true

func _q_msaa() -> bool:
	return true if preview else msaa

func _q_normals() -> bool:
	return false if preview else normals

func _q_shadows() -> bool:
	return true if preview else shadows

func _q_rim() -> bool:
	return true if preview else rim

func _q_ss() -> int:
	return preview_ss if preview else ss

## Obrót kamery wokół postaci (stopnie); w grze stały VIEW_YAW_DEG, w podglądzie ciągły.
func set_view_yaw(deg: float) -> void:
	view_yaw = deg
	if _cam != null:
		_place_cameras()

func _set_on_screen(v: bool) -> void:
	_on_screen = v
	var mode := SubViewport.UPDATE_ALWAYS if v else SubViewport.UPDATE_DISABLED
	_vp.render_target_update_mode = mode
	if _vpn != null:
		_vpn.render_target_update_mode = mode if _q_normals() else SubViewport.UPDATE_DISABLED

## Przełącza elementy zależne od poziomu jakości na działającej postaci (MSAA, mapa normalnych dla świateł 2D, cienie, rim) i
## przelicza rozdzielczość renderu z nowym limitem `ss`.
func apply_quality() -> void:
	if _vp == null:
		return
	if preview:
		return                                                 # podgląd ma stałą, pełną jakość
	var m := Viewport.MSAA_2X if msaa else Viewport.MSAA_DISABLED
	_vp.msaa_3d = m
	if _vpn != null:
		_vpn.msaa_3d = m
		_vpn.render_target_update_mode = SubViewport.UPDATE_ALWAYS if (normals and _on_screen) else SubViewport.UPDATE_DISABLED
	_canvas_tex.normal_texture = _vpn.get_texture() if (normals and _vpn != null) else null
	_sun.shadow_enabled = shadows
	_rim.visible = rim
	_ss_now = 0
	apply_view(_last_zoom, _last_h)

## Drugi SubViewport z tym samym światem 3D i kamerą na warstwie 2: widzi tylko kopie siatek z materiałem wypisującym normalne.
## Kopie współdzielą szkielet z oryginałem, więc poza liczymy raz.
func _build_normal_pass() -> void:
	_vpn = SubViewport.new()
	_vpn.name = "VpN"
	_vpn.size = _vp.size
	_vpn.transparent_bg = true
	_vpn.msaa_3d = _vp.msaa_3d
	_vpn.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_vpn)
	_vpn.world_3d = _vp.find_world_3d()
	_camn = Camera3D.new()
	_camn.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camn.keep_aspect = Camera3D.KEEP_HEIGHT
	_camn.size = _cam.size
	_camn.near = _cam.near
	_camn.far = _cam.far
	_camn.cull_mask = 2
	_vpn.add_child(_camn)
	var sh := Shader.new()
	sh.code = "shader_type spatial;
render_mode unshaded, cull_back;
uniform sampler2D nm : hint_normal, filter_linear_mipmap, repeat_enable;
uniform bool has_nm = false;
uniform bool to_linear = false;         // Forward+: obraz 3D jest kodowany do sRGB na wyjściu — kodujemy odwrotnie, żeby w teksturze zostały surowe normalne
void fragment() {
	vec3 n = NORMAL;
	if (has_nm) {
		// mapa normalnych z modelu (tangent space) → normalne widokowe: relief widzą światła 2D (latarka, flara)
		vec3 t = texture(nm, UV).xyz * 2.0 - 1.0;
		n = normalize(TANGENT * t.x + BINORMAL * t.y + NORMAL * t.z);
	}
	vec3 e = n * 0.5 + vec3(0.5);
	ALBEDO = to_linear ? mix(e / 12.92, pow((e + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), e)) : e;
}
"
	_normal_mat = ShaderMaterial.new()
	_normal_mat.shader = sh
	_normal_mat.set_shader_parameter("to_linear", RenderingServer.get_current_rendering_method() != "gl_compatibility")

## Materiał normalnych dla siatki: wspólny, a gdy model ma mapę normalnych — kopia ze wskazaną teksturą.
func _normal_material_for(mi: MeshInstance3D) -> Material:
	if mi.mesh == null or mi.mesh.get_surface_count() == 0:
		return _normal_mat
	var src := mi.mesh.surface_get_material(0)
	if src is BaseMaterial3D and (src as BaseMaterial3D).normal_texture != null:
		var m := _normal_mat.duplicate() as ShaderMaterial
		m.set_shader_parameter("nm", (src as BaseMaterial3D).normal_texture)
		m.set_shader_parameter("has_nm", true)
		return m
	return _normal_mat

## Materiały modelu pod światła gry i paletę kolorów: shader z kolorem, normalnymi, roughness i AO z modelu, bez metaliczności
## (bez sondy odbić metal byłby czarny). Obiekty bez StandardMaterial3D zostają, jak były.
func _prepare_materials(root: Node) -> void:
	_pal_mats.clear()
	var sh := Shader.new()
	sh.code = PALETTE_SHADER
	# karty włosów, brwi i rzęs (w GLB przycinanie alfa): ten sam shader z odrzucaniem przezroczystych tekseli, obie strony karty
	var sh_cut := Shader.new()
	sh_cut.code = PALETTE_SHADER.replace("shader_type spatial;", "shader_type spatial;\nrender_mode cull_disabled;") \
			.replace("\tALBEDO = c;", "\tALBEDO = c;\n\tALPHA = texture(albedo_tex, UV).a;\n\tALPHA_SCISSOR_THRESHOLD = 0.5;")
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(i)
			if m is StandardMaterial3D:
				var src := m as StandardMaterial3D
				var sm := ShaderMaterial.new()
				sm.shader = sh_cut if src.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR else sh
				sm.set_shader_parameter("albedo_tex", src.albedo_texture)
				sm.set_shader_parameter("albedo_mul", src.albedo_color)
				if src.normal_texture != null:
					sm.set_shader_parameter("normal_tex", src.normal_texture)
					sm.set_shader_parameter("has_normal", true)
				var orm: Texture2D = src.roughness_texture if src.roughness_texture != null else src.ao_texture
				if orm != null:
					sm.set_shader_parameter("orm_tex", orm)
					sm.set_shader_parameter("has_orm", true)
				mi.set_surface_override_material(i, sm)
				_pal_mats.append(sm)
	_apply_palette()
	_apply_damage()

## Paleta kolorów stroju (Look.palette_of): obrót barwy / nasycenie / jasność dla nasyconych pikseli nie-skórnych.
func set_palette(p: int) -> void:
	if p == _palette:
		return
	_palette = p
	_apply_palette()

## Krew na stroju (player.gd): d 0..1 — od lekkich plam do przesiąknięcia; seed rozmieszcza plamy inaczej u każdego gracza.
func set_damage(d: float, seed: float) -> void:
	_damage = clampf(d, 0.0, 1.0)
	_blood_seed = seed
	_apply_damage()

func _apply_damage() -> void:
	for m in _pal_mats:
		var sm := m as ShaderMaterial
		sm.set_shader_parameter("damage", _damage)
		sm.set_shader_parameter("blood_seed", _blood_seed)

func _apply_palette() -> void:
	var d: Dictionary = Look.PALETTES[clampi(_palette, 0, Look.PALETTES.size() - 1)]
	for m in _pal_mats:
		var sm := m as ShaderMaterial
		sm.set_shader_parameter("hue_target", float(d["hue"]))
		sm.set_shader_parameter("sat_mul", float(d["sat"]))
		sm.set_shader_parameter("val_mul", float(d["val"]))

## Kopie siatek sceny na warstwie 2 z materiałem normalnych. skinned: kopie dzielą szkielet z oryginałem (są jego dziećmi).
func _normal_clones(root: Node, skinned: bool) -> void:
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		var c := MeshInstance3D.new()
		c.mesh = mi.mesh
		c.layers = 2
		c.material_override = _normal_material_for(mi)
		c.transform = mi.transform
		mi.add_sibling(c)
		if skinned and mi.skin != null:
			c.skin = mi.skin
			c.skeleton = c.get_path_to(mi.get_parent())


## Zestaw modeli: "mpfb" = art/char3d/mpfb/ (realistyczne, MPFB2, tools/char_mpfb.py — domyślny), "tripo" = art/char3d/ (stylizowane
## modele Tripo sprzed 1.7.220, --charset=tripo). Brak modelu w zestawie → art/char3d/.
static var charset := "mpfb"

## Wymiana modelu postaci (wygląd z warsztatu, replikowany `player.look`). Zwraca false, gdy brak pliku.
func set_look(char_name: String) -> bool:
	if char_name == _char_name and _sk != null:
		return true
	var path := DIR + char_name + ".glb"
	if charset != "" and charset != "tripo" and ResourceLoader.exists(DIR + charset + "/" + char_name + ".glb"):
		path = DIR + charset + "/" + char_name + ".glb"
	if not ResourceLoader.exists(path):
		return false
	var scene: Node = (load(path) as PackedScene).instantiate()
	var sk: Skeleton3D = scene.find_child("Skeleton3D", true, false)
	if sk == null:
		scene.free()
		return false
	if _char_node != null:
		_char_node.queue_free()
	_char_node = scene
	_char_name = char_name
	_sk = sk
	_prepare_materials(scene)
	_root3d.add_child(scene)
	_b.clear()
	for n in ["Hips", "Spine", "Spine1", "Spine2", "Neck", "Head", "LeftUpLeg", "LeftLeg", "LeftFoot", "RightUpLeg", "RightLeg", "RightFoot",
			"LeftShoulder", "LeftArm", "LeftForeArm", "LeftHand", "RightShoulder", "RightArm", "RightForeArm", "RightHand"]:
		_b[n] = _sk.find_bone(PRE + n)
	_arm_hinge.clear()
	for side in ["Left", "Right"]:
		_leg_len[side] = [_rest_dist(side + "UpLeg", side + "Leg"), _rest_dist(side + "Leg", side + "Foot")]
		_arm_len[side] = [_rest_dist(side + "Arm", side + "ForeArm"), _rest_dist(side + "ForeArm", side + "Hand")]
		# oś zgięcia łokcia: w spoczynku ręka jest lekko ugięta — normalna tej płaszczyzny, zapisana w układach obu kości, mówi, w którą stronę zgina się łokieć
		var ga := _sk.get_bone_global_rest(_b[side + "Arm"])
		var gf := _sk.get_bone_global_rest(_b[side + "ForeArm"])
		var gh := _sk.get_bone_global_rest(_b[side + "Hand"])
		var hinge := (gf.origin - ga.origin).cross(gh.origin - gf.origin)
		if hinge.length() > 0.08 * float(_arm_len[side][0]) * float(_arm_len[side][1]):           # zgięcie w spoczynku ≥ ok. 5°
			hinge = hinge.normalized()
			_arm_hinge[side] = [ga.basis.orthonormalized().inverse() * hinge, gf.basis.orthonormalized().inverse() * hinge]
		_hand_rel[side] = gf.basis.orthonormalized().inverse() * gh.basis.orthonormalized()
	_stance.clear()
	_posed = false
	_measure_hands(scene)
	_clips = CharClips.build(_sk, char_name, clips_raw)
	if _clips != null:
		_sk.get_parent().add_child(_clips)
	_clip_w = 0.0
	_origin_x = _sk.get_bone_global_rest(_b["Hips"]).origin.x
	_ankle_y = _sk.get_bone_global_rest(_b["RightFoot"]).origin.y
	_place_cameras()
	if _camn != null:
		_normal_clones(scene, true)
	return true

## Kamery (kolor i normalne) krążą wokół postaci o VIEW_YAW_DEG: widok 3/4 bez zmian w pozach IK i w broni.
func _place_cameras() -> void:
	var y := deg_to_rad(view_yaw)
	var centre := Vector3(_origin_x, CAM_Y, 0.0)
	var pos := centre + Vector3(sin(y), 0.0, cos(y)) * 6.0
	var xf := Transform3D(Basis(Vector3.UP, y), pos)
	_cam.transform = xf
	if _camn != null:
		_camn.transform = xf

## Wymiana broni (klucz z weapon_def: m83, p64, maczeta…). Brak modelu → karabin M-83.
func set_gun(key: String) -> void:
	if key == _gun_key and _gun != null:
		return
	var path := DIR + "gun_%s.glb" % key
	if not ResourceLoader.exists(path):
		key = DEFAULT_GUN
		path = DIR + "gun_%s.glb" % key
		if key == _gun_key and _gun != null:
			return
	if _gun != null:
		_gun.queue_free()
	if _gun_n != null:
		_gun_n.queue_free()
		_gun_n = null
	_gun = (load(path) as PackedScene).instantiate()
	_gun.visible = false                                     # do pierwszej pozy (update ustawia transformację i widoczność) — bez błysku w zerze świata
	_root3d.add_child(_gun)
	_tune_gun_materials(_gun)
	if _camn != null:                                        # kopia broni na warstwie 2 (osobny egzemplarz sceny, ta sama transformacja)
		_gun_n = (load(path) as PackedScene).instantiate()
		_gun_n.visible = false
		_root3d.add_child(_gun_n)
		for mi in _gun_n.find_children("*", "MeshInstance3D", true, false):
			(mi as MeshInstance3D).layers = 2
			(mi as MeshInstance3D).material_override = _normal_mat
	_gun_key = key
	_gun_info = gun_info(key)
	_hands = int(_gun_info["hands"])
	_gun_len = float(_gun_info["length"])

## Materiały broni z GLB (albedo + normalne + ORM + opcjonalnie emisja): pełna metaliczność z tekstury — stal odbija „niebo odbić" warstwy graczy
## (view3d.gd, `_actor_reflection_sky`) i światła sceny; reszta modeli ma metaliczność wyzerowaną w shaderach. Emisja (cewki, kontrolki) wzmocniona
## dla bloomu.
func _tune_gun_materials(root: Node) -> void:
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(i)
			if m is StandardMaterial3D:
				var sm := m as StandardMaterial3D
				sm.metallic = 1.0
				sm.metallic_specular = 0.5
				if sm.emission_enabled:
					sm.emission_energy_multiplier = 1.8

## Dane broni z `gun_<klucz>.json` w układzie Godota (x wzdłuż lufy, y w górę, z ku prawej stronie postaci), raz na sesję: rear = początek układu modelu,
## grip = środek chwytu (dłoń tylna), hold = spód łoża (dłoń przednia; hold_v = chwyt przedni pionowy), fore = stary punkt dłoni przedniej, muzzle = wylot.
static func gun_info(key: String) -> Dictionary:
	if _gun_infos.has(key):
		return _gun_infos[key]
	var o := {"rear": Vector3.ZERO, "fore": Vector3(0.4, 0.03, 0.0), "muzzle": Vector3(0.9, 0.08, 0.0), "hands": 2, "length": 1.2, "hold_v": false}
	var path := DIR + "gun_%s.json" % key
	if FileAccess.file_exists(path):
		var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
		for k in ["rear", "fore", "muzzle", "grip", "hold"]:
			if d.has(k):
				var a: Array = d[k]
				o[k] = Vector3(float(a[0]), float(a[2]), -float(a[1]))      # Blender (x, y, z) → Godot (x, z, −y)
		o["hands"] = int(d.get("hands", 2))
		o["length"] = float(d.get("length", 1.2))
		o["hold_v"] = bool(d.get("hold_v", false))
	if not o.has("grip"):                                         # stary plik bez punktów chwytu: przybliżenie z punktów nadgarstków
		o["grip"] = (o["rear"] as Vector3) + Vector3(0.0, 0.06, 0.0)
	if not o.has("hold"):
		o["hold"] = (o["fore"] as Vector3) + Vector3(0.0, 0.09, 0.0)
	_gun_infos[key] = o
	return o

func _rest_dist(a: String, b: String) -> float:
	return _sk.get_bone_global_rest(_sk.find_bone(PRE + a)).origin.distance_to(_sk.get_bone_global_rest(_sk.find_bone(PRE + b)).origin)

# ---------------------------------------------------------------- narzędzia kostne

func _gp(i: int) -> Transform3D:
	return _sk.get_bone_global_pose(i)

func _set_global_basis(i: int, gb: Basis) -> void:
	var p := _sk.get_bone_parent(i)
	var pb := _gp(p).basis if p >= 0 else Basis.IDENTITY
	_sk.set_bone_pose_rotation(i, (pb.inverse() * gb).orthonormalized().get_rotation_quaternion())

## Przesuwa kość o wektor w przestrzeni szkieletu (świata modelu). Osie lokalne kości Mixamo są obrócone (w biodrach „góra" to lokalne Z),
## więc przesunięcie w pozie trzeba przeliczyć przez bazę rodzica — samo dodanie wektora do lokalnej pozycji ruszało biodra w bok.
## Dodaje do bieżącej pozy (po `reset_bone_poses` to spoczynek, z klipem — poza klipu); wołać raz na kość w klatce.
func _move_global(i: int, delta: Vector3) -> void:
	var p := _sk.get_bone_parent(i)
	var pb := _gp(p).basis if p >= 0 else Basis.IDENTITY
	_sk.set_bone_pose_position(i, _sk.get_bone_pose_position(i) + pb.inverse() * delta)

## Obraca kość (i całe jej poddrzewo) wokół jej własnego początku o kąt wokół osi świata.
func _rot_world(i: int, axis: Vector3, ang: float) -> void:
	_set_global_basis(i, Basis(axis, ang) * _gp(i).basis)

## Kość i kieruje się na punkt target (jej dziecko child leży na osi kości).
func _point_bone(i: int, child: int, target: Vector3) -> void:
	var g := _gp(i)
	var from := (_gp(child).origin - g.origin).normalized()
	var to := (target - g.origin).normalized()
	if from.dot(to) > 0.99999:
		return
	_set_global_basis(i, Basis(Quaternion(from, to)) * g.basis)

## Dwukostkowe IK: staw środkowy tak, by koniec sięgał celu; pole = kierunek wygięcia (łokieć / kolano).
func _two_bone(a: int, m: int, e: int, la: float, lb: float, target: Vector3, pole: Vector3) -> void:
	var s := _gp(a).origin
	var d := target - s
	var dist := clampf(d.length(), absf(la - lb) + 0.001, (la + lb) * 0.999)
	var dn := d.normalized()
	var x := (la * la - lb * lb + dist * dist) / (2.0 * dist)
	var h := sqrt(maxf(la * la - x * x, 0.0))
	var pv := pole - dn * pole.dot(dn)
	pv = pv.normalized() if pv.length() > 0.0001 else Vector3.UP
	var mid := s + dn * x + pv * h
	_point_bone(a, m, mid)
	_point_bone(m, e, s + dn * dist)

## IK ręki: jak `_two_bone`, ale ramię i przedramię są jeszcze obracane wokół własnej osi tak, żeby łokieć zginał się w swojej anatomicznej osi
## (z pozy spoczynkowej). Bez tego obrót wokół osi kości jest przypadkowy (najkrótszy łuk od poprzedniej pozy) i siatka łokcia łamie się w bok.
func _arm_ik(side: String, target: Vector3, pole: Vector3) -> void:
	var a: int = _b[side + "Arm"]
	var m: int = _b[side + "ForeArm"]
	var e: int = _b[side + "Hand"]
	var la: float = _arm_len[side][0]
	var lb: float = _arm_len[side][1]
	var s := _gp(a).origin
	var d := target - s
	var dist := clampf(d.length(), absf(la - lb) + 0.001, (la + lb) * 0.999)
	var dn := d.normalized()
	var x := (la * la - lb * lb + dist * dist) / (2.0 * dist)
	var h := sqrt(maxf(la * la - x * x, 0.0))
	var pv := pole - dn * pole.dot(dn)
	pv = pv.normalized() if pv.length() > 0.0001 else Vector3.UP
	var mid := s + dn * x + pv * h
	var tip := s + dn * dist
	var hl: Array = _arm_hinge.get(side, [])
	var bend := (mid - s).cross(tip - mid)
	var roll := not hl.is_empty() and bend.length() > 0.02 * la * lb
	_point_bone(a, m, mid)
	if roll:
		_roll_to(a, (mid - s).normalized(), hl[0], bend)
	_point_bone(m, e, tip)
	if roll:
		_roll_to(m, (tip - mid).normalized(), hl[1], bend)

## Obraca kość wokół jej osi tak, żeby kierunek `local_ref` (w układzie kości) wskazywał `want` (rzut na płaszczyznę prostopadłą do osi).
func _roll_to(i: int, axis: Vector3, local_ref: Vector3, want: Vector3) -> void:
	var g := _gp(i).basis
	var cur := g.orthonormalized() * local_ref
	cur -= axis * cur.dot(axis)
	want -= axis * want.dot(axis)
	if cur.length() < 0.01 or want.length() < 0.0001:
		return
	_set_global_basis(i, Basis(axis, cur.normalized().signed_angle_to(want.normalized(), axis)) * g)

## Ustawia orientację dłoni (w przestrzeni szkieletu) i oddaje część skrętu nadgarstka przedramieniu — model nie ma kości skrętu, więc cały skręt
## w jednym stawie zwijał rękaw jak cukierek. w < 1 miesza orientację z tą, którą dłoń ma sama z siebie (przedłużenie przedramienia).
func _set_hand(side: String, gb: Basis, w := 1.0, share := 0.55) -> void:
	var f: int = _b[side + "ForeArm"]
	var hnd: int = _b[side + "Hand"]
	var gf := _gp(f).basis.orthonormalized()
	var follow: Basis = gf * (_hand_rel[side] as Basis)              # dłoń sztywno za przedramieniem, jak w spoczynku
	gb = gb.orthonormalized()
	if w < 1.0:
		gb = follow.slerp(gb, w)
	var axis := (_gp(hnd).origin - _gp(f).origin).normalized()
	var q := (gb * follow.inverse()).get_rotation_quaternion()
	var tw := wrapf(2.0 * atan2(Vector3(q.x, q.y, q.z).dot(axis), q.w), -PI, PI)
	_set_global_basis(f, Basis(axis, clampf(tw * share, -1.5, 1.5)) * _gp(f).basis)
	_set_global_basis(hnd, gb)

## Obojczyki wracają do pozy spoczynkowej: klipy z biblioteki cofają prawy bark o kilkanaście centymetrów (ręce zwisają tam swobodnie), a od barku
## liczymy położenie broni — karabin lądował przez to na środku piersi, pod brodą. Gdy ręce prowadzi IK, obojczykiem rusza tylko `_reach_clavicle`.
func _rest_clavicles() -> void:
	for side in ["Left", "Right"]:
		var c: int = _b[side + "Shoulder"]
		if c >= 0:
			_sk.set_bone_pose_rotation(c, _sk.get_bone_rest(c).basis.get_rotation_quaternion())

## Obojczyk podąża za ręką: bark przesuwa się ku celowi dłoni o ułamek `w` kąta (najwyżej `max_deg`). Wołać przed IK ręki.
func _reach_clavicle(side: String, target: Vector3, w: float, max_deg := 16.0) -> void:
	var c: int = _b[side + "Shoulder"]
	if c < 0:
		return
	var o := _gp(c).origin
	var cur := (_gp(_b[side + "Arm"]).origin - o).normalized()
	var to := (target - o).normalized()
	var axis := cur.cross(to)
	if axis.length() < 0.001:
		return
	_rot_world(c, axis.normalized(), minf(cur.angle_to(to) * w, deg_to_rad(max_deg)))

## Układ anatomiczny dłoni z siatki modelu: kości Tripo mają przypadkowe osie (inne w każdym modelu i w każdej dłoni), więc kierunek palców i grzbiet dłoni
## bierzemy z wierzchołków przypisanych do kości dłoni — palce: od nadgarstka do środka ciężkości, grzbiet: najcieńszy wymiar bryły (dłoń jest płaska),
## po tej stronie, przy której kciuk wypada z przodu (w pozie A / T kciuki patrzą w przód). fix = orientacja kości względem tego układu.
func _measure_hands(scene: Node) -> void:
	if _hand_cache.has(_char_name):
		_hand = _hand_cache[_char_name]
		return
	var out := {}
	for side in ["Left", "Right"]:
		var hb: int = _b[side + "Hand"]
		var rest := _sk.get_bone_global_rest(hb)
		var wrist := rest.origin
		var pts := PackedVector3Array()
		for n in scene.find_children("*", "MeshInstance3D", true, false):
			var mi := n as MeshInstance3D
			if mi.skin == null or mi.mesh == null or mi.layers == 2:
				continue
			var bind := -1
			for j in mi.skin.get_bind_count():
				var bn := String(mi.skin.get_bind_name(j))
				if (bn != "" and bn == _sk.get_bone_name(hb)) or (bn == "" and mi.skin.get_bind_bone(j) == hb):
					bind = j
			if bind < 0:
				continue
			var xf := _xf_under(_sk, scene).affine_inverse() * _xf_under(mi, scene)
			for si in mi.mesh.get_surface_count():
				var arr := mi.mesh.surface_get_arrays(si)
				var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
				if arr[Mesh.ARRAY_BONES] == null or vs.is_empty():
					continue
				var bs: PackedInt32Array = arr[Mesh.ARRAY_BONES]
				var ws: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
				var per := bs.size() / vs.size()
				for v in vs.size():
					var wsum := 0.0
					for k in per:
						if bs[v * per + k] == bind:
							wsum += ws[v * per + k]
					if wsum > 0.5:
						pts.append(xf * vs[v])
		var fwd := (wrist - _sk.get_bone_global_rest(_b[side + "ForeArm"]).origin).normalized()      # zapas: dłoń jako przedłużenie przedramienia
		var back := Vector3.UP
		var length := 0.18
		var thick := 0.03
		if pts.size() >= 12:
			var c := Vector3.ZERO
			for q in pts:
				c += q
			c /= float(pts.size())
			var thin := _thin_axis(pts, c)
			var f := (c - wrist) - thin * (c - wrist).dot(thin)
			if f.length() > 0.01:
				fwd = f.normalized()
				back = thin
				var lo := 0.0
				var hi := 0.0
				length = 0.0
				for q in pts:
					length = maxf(length, (q - wrist).dot(fwd))
					lo = minf(lo, (q - c).dot(thin))
					hi = maxf(hi, (q - c).dot(thin))
				thick = (hi - lo) * 0.3
		back = (back - fwd * back.dot(fwd)).normalized()
		var thumb := back.cross(fwd) if side == "Right" else fwd.cross(back)
		if thumb.x < 0.0:
			back = -back
		out[side] = {"fix": Basis(fwd, back, fwd.cross(back)).inverse() * rest.basis.orthonormalized(), "len": length, "thick": thick, "n": pts.size(), "f": fwd, "b": back}
	_hand_cache[_char_name] = out
	_hand = out

## Transformacja węzła względem przodka `top` (bez drzewa sceny — model bywa mierzony, zanim do niego trafi).
static func _xf_under(n: Node, top: Node) -> Transform3D:
	var xf := Transform3D.IDENTITY
	while n != null and n != top:
		if n is Node3D:
			xf = (n as Node3D).transform * xf
		n = n.get_parent()
	return xf

## Najcieńszy wymiar chmury punktów (oś o najmniejszej wariancji): dwie największe osie metodą potęgową, trzecia z iloczynu wektorowego.
static func _thin_axis(pts: PackedVector3Array, c: Vector3) -> Vector3:
	var r0 := Vector3.ZERO
	var r1 := Vector3.ZERO
	var r2 := Vector3.ZERO
	for q in pts:
		var d := q - c
		r0 += d * d.x
		r1 += d * d.y
		r2 += d * d.z
	var v1 := Vector3(0.6, 0.5, 0.62).normalized()
	for i in 48:
		v1 = Vector3(r0.dot(v1), r1.dot(v1), r2.dot(v1)).normalized()
	var l1 := v1.dot(Vector3(r0.dot(v1), r1.dot(v1), r2.dot(v1)))
	var v2 := v1.cross(Vector3(0.3, -0.8, 0.52)).normalized()
	for i in 48:
		v2 = Vector3(r0.dot(v2), r1.dot(v2), r2.dot(v2)) - v1 * (l1 * v1.dot(v2))
		v2 = (v2 - v1 * v2.dot(v1)).normalized()
	return v1.cross(v2).normalized()

## Cel dłoni (orientacja kości i pozycja nadgarstka w przestrzeni szkieletu), gdy środek dłoni ma leżeć w punkcie `point` broni: `f` = kierunek palców,
## `back` = strona grzbietu dłoni (oba w układzie broni), `off` = odstęp wnętrza dłoni od punktu (pół grubości tego, co trzyma).
func _hand_target(side: String, gx: Transform3D, point: Vector3, f: Vector3, back: Vector3, off: float) -> Transform3D:
	var hd: Dictionary = _hand[side]
	var fw := (gx.basis * f).normalized()
	var bw := gx.basis * back
	bw = (bw - fw * bw.dot(fw)).normalized()
	return Transform3D(Basis(fw, bw, fw.cross(bw)) * (hd["fix"] as Basis), gx * point - fw * (float(hd["len"]) * PALM_AT) + bw * (float(hd["thick"]) + off))

## Kierunek palców dłoni na chwycie / rękojeści w układzie broni (kąt `wrist` z WEAPON_POSE).
static func _wrist_dir(wp: Dictionary) -> Vector3:
	var a := deg_to_rad(float(wp.get("wrist", 12.0)))
	return Vector3(cos(a), sin(a), 0.0)

## Cel dłoni przedniej w chwycie: pod łożem (wnętrzem do góry, palce owijają łoże od strony kamery), na chwycie pionowym albo — przy pistolecie —
## pod stopką chwytu (podparcie od dołu: dłonie modelu są otwarte, więc złożone bokami wyglądałyby jak do oklasków).
func _left_hold(gx: Transform3D, info: Dictionary, wp: Dictionary) -> Transform3D:
	if String(wp.get("reload", "")) == "pistol":
		return _hand_target("Left", gx, (info["grip"] as Vector3) + Vector3(-0.01, -0.105, 0.0), Vector3(0.42, 0.22, 0.88), Vector3.DOWN, 0.0)
	if bool(info.get("hold_v", false)):
		return _hand_target("Left", gx, info["hold"], _wrist_dir(wp), Vector3.FORWARD, GRIP_HALF)
	return _hand_target("Left", gx, info["hold"], Vector3(0.42, 0.22, 0.88), Vector3.DOWN, 0.0)

## Początek układu broni dla barków sr / sl: na promieniu `radial` od prawego barku wzdłuż kierunku `hd`, opuszczony o `perp`; broń trzymana oburącz jest
## wsuwana ku ciału, dopóki dłoń przednia nie sięga swojego chwytu. Wspólne dla pozy (barki z animacji) i punktów celowania rozgrywki (barki nominalne).
## cam: strona kamery (+1 / −1, `_cam_c`) — celując w dół broń wysuwa się ku niej, żeby nie schować się za tułowiem.
func _gun_origin(sr: Vector3, sl: Vector3, hd: float, gun_b: Basis, radial: float, perp: float, info: Dictionary, wp: Dictionary, two: bool, cam := 1.0) -> Vector3:
	var reach_l: float = (float(_arm_len["Left"][0]) + float(_arm_len["Left"][1])) * 0.97
	var side_z := float(wp.get("side", -0.13))
	var rear := Vector3.ZERO
	for k in 8:
		# celowanie w dół: broń wysuwa się ku kamerze, żeby nie chować się za tułowiem (z=+ to bliższa strona)
		# celowanie w górę: broń odsuwa się od barku, żeby ręce nie zasłaniały twarzy
		var r := radial + UP_REACH * maxf(0.0, sin(hd))
		rear = sr + Vector3(cos(hd), sin(hd), 0.0) * r - Vector3(-sin(hd), cos(hd), 0.0) * perp + Vector3(0.0, 0.0, side_z + 0.28 * maxf(0.0, -sin(hd)))
		if not two or _left_hold(Transform3D(gun_b, rear), info, wp).origin.distance_to(sl) <= reach_l:
			break
		radial -= 0.035
	rear.z += 0.28 * maxf(0.0, -sin(hd)) * (cam - 1.0)        # ku kamerze po drugiej stronie dopiero na końcu: wsunięcie broni nie zależy od strony, więc wylot w obie strony jest lustrzany
	return rear

## Pochylenie jednej kości kręgosłupa za celowaniem (rad): stały ułamek kąta, a w górę jeszcze odchylenie do tyłu.
static func _spine_pitch(theta: float) -> float:
	return theta * SPINE_AIM + theta * SPINE_AIM_UP * maxf(0.0, sin(theta))

## Kąt celowania w górę od poziomu (rad) z kierunku na ekranie (y w dół); lustro załatwia odbicie postaci.
static func _aim_theta(aim: Vector2) -> float:
	var ax := absf(aim.x)
	var theta := atan2(-aim.y, maxf(ax, 0.0001))
	if ax < 0.05:
		theta = PI * 0.5 * signf(-aim.y)
	return clampf(theta, deg_to_rad(-80.0), deg_to_rad(85.0))

## Punkty postawy do pozy nominalnej: biodra, trzy kości kręgosłupa i oba barki tam, gdzie stawia je klip postoju / kucania tego modelu (chwila 0,
## bez nakładek z kodu), a bez klipów — w pozie spoczynkowej. Liczone raz na model i postawę; poza szkieletu po pomiarze wraca na miejsce.
func _stance_pts(crouching: bool) -> Dictionary:
	if _stance.has(crouching):
		return _stance[crouching]
	var st := "crouch" if crouching else "idle"
	var clip := _clips != null and clips_on and CharClips.enabled and CharClips.has(st)
	if clip and not _posed:
		clip = false                                              # przed pierwszą klatką drzewo klipów jeszcze nie liczy — tymczasem poza spoczynkowa (bez zapamiętania)
	var keep: Array = []
	if clip:
		for i in _sk.get_bone_count():
			keep.append([_sk.get_bone_pose_position(i), _sk.get_bone_pose_rotation(i)])
		_sk.reset_bone_poses()
		CharClips.drive(_clips, {st: 1.0}, 0.0, 0.0, {})
		_rest_clavicles()
	var o := {"clip": clip, "S": []}
	for n in ["Hips", "Spine", "Spine1", "Spine2", "RightArm", "LeftArm"]:
		var q := _gp(_b[n]).origin if clip else _sk.get_bone_global_rest(_b[n]).origin
		if n.begins_with("Spine"):
			(o["S"] as Array).append(q)
		else:
			o[n] = q
	if clip:
		for i in _sk.get_bone_count():
			_sk.set_bone_pose_position(i, keep[i][0])
			_sk.set_bone_pose_rotation(i, keep[i][1])
	if clip or _posed or _clips == null:
		_stance[crouching] = o
	return o

## Barki (prawy, lewy) w pozie nominalnej: sama postawa (stoi / kuca), pochylenie od broni i celowanie tułowiem — bez kroku, kołysania, odrzutu,
## trafień i lądowań. Te same obroty co w `_pose_body`, policzone na punktach postawy (`_stance_pts`).
## cam: znak zwrotu tułowia ku kamerze (`_cam_c`); rozgrywka liczy zawsze z +1.
func _nominal_shoulders(theta: float, crouching: bool, wp: Dictionary, cam := 1.0) -> Array:
	var sp := _stance_pts(crouching)
	var clip := bool(sp["clip"])
	var st := "crouch" if crouching else "idle"
	# z klipem pochylenie i przysiad niesie klip (z kodu zostaje `drop` z tabeli klipów), bez klipu — poza z kodu
	var lean := deg_to_rad((0.0 if clip else (6.0 if crouching else 4.0)) + float(wp.get("lean", 0.0)))
	var drop := CharClips.param(st, "drop", 0.0) if clip else (CROUCH_DROP if crouching else 0.0)
	var h: Vector3 = sp["Hips"]
	var ss: Array = sp["S"]
	var p: Array = [ss[0], ss[1], ss[2], sp["RightArm"], sp["LeftArm"]]
	var tilt := Basis(Vector3.BACK, -lean)
	for i in 5:
		p[i] = h + Vector3(0.0, -drop, 0.0) + tilt * ((p[i] as Vector3) - h)
	var yaw := Basis(Vector3.UP, deg_to_rad(BODY_YAW) * cam)
	for i in range(1, 5):
		p[i] = (p[0] as Vector3) + yaw * ((p[i] as Vector3) - (p[0] as Vector3))
	var pitch := Basis(Vector3.BACK, _spine_pitch(theta) + lean * 0.12)
	for j in 3:
		for i in range(j + 1, 5):
			p[i] = (p[j] as Vector3) + pitch * ((p[i] as Vector3) - (p[j] as Vector3))
	return [p[3], p[4]]

## Punkty celowania dla ROZGRYWKI: [chwyt, wylot lufy] w pikselach świata względem stóp, dla kierunku celowania `aim` (y w dół), strony `side` (±1),
## postawy i broni `gun_key`. Liczone z pozy nominalnej, więc nie zależą od klatki animacji: bieg, odrzut, trafienie, przeładowanie ani obrót modelu
## nie przesuwają toru pocisków, a każdy peer dostaje ten sam wynik dla tego samego stanu. Strona jest od razu docelowa — obrót modelu
## (TURN_TIME) jest samym widokiem. Do efektów (błysk, wiązka) służą `muzzle_px` / `grip_px`.
func aim_points(aim: Vector2, side: float, crouching: bool, gun_key: String) -> Array:
	if not ResourceLoader.exists(DIR + "gun_%s.glb" % gun_key):
		gun_key = DEFAULT_GUN
	var info := gun_info(gun_key)
	var wp: Dictionary = WEAPON_POSE.get(gun_key, {})
	var theta := _aim_theta(aim)
	var sh := _nominal_shoulders(theta, crouching, wp)
	var gun_b := Basis(Vector3.BACK, theta)
	var two := int(info["hands"]) == 2 or String(wp.get("reload", "")) == "pistol"
	var rear := _gun_origin(sh[0], sh[1], theta, gun_b, float(wp.get("radial", 0.30)), float(wp.get("perp", 0.11)), info, wp, two, -1.0 if side < 0.0 else 1.0)
	var fl := -1.0 if side < 0.0 else 1.0
	return [_to_px_side(rear, fl), _to_px_side(Transform3D(gun_b, rear) * (info["muzzle"] as Vector3), fl)]

# ---------------------------------------------------------------- klatka

## anim: idle | run | jump | fall | crouch | crouch_walk | revive | down. aim: kierunek celowania na ekranie (y w dół).
## speed: |prędkość pozioma| w px/s (tempo kroku). armed=false chowa broń (leżenie).
func update(delta: float, anim: String, facing: float, aim: Vector2, speed := 0.0, armed := true, tint := Color.WHITE) -> void:
	if not ready_ok:
		return
	_time += delta
	_sprite.flip_h = facing < 0.0
	px_flip = -1.0 if _sprite.flip_h else 1.0
	# obrót zamiast lustra: zwrot dochodzi do kierunku patrzenia w TURN_TIME (sinus: rusza i hamuje łagodnie), przez pozę przodem do kamery
	_face = move_toward(_face, px_flip, delta * 2.0 / TURN_TIME) if _posed and delta < 0.1 else px_flip
	_cam_c = sin(PI * 0.5 * _face)
	model_yaw = -PI * 0.5 + PI * 0.5 * _cam_c
	(_sprite.material as ShaderMaterial).set_shader_parameter("flip_n", _sprite.flip_h)
	_sprite.modulate = tint
	if not _on_screen:
		return                                                    # poza ekranem nic nie rysujemy (viewport wyłączony), pozę nadrobi pierwsza klatka po wejściu
	_sk.reset_bone_poses()
	var theta := _aim_theta(aim)
	if hit_t >= 0.0:
		hit_t += delta / 0.30
		if hit_t >= 1.0:
			hit_t = -1.0
	if land_t >= 0.0:
		land_t += delta / 0.34
		if land_t >= 1.0:
			land_t = -1.0
	_grab_w = move_toward(_grab_w, 1.0 if (grabbed and _down < 0.2) else 0.0, delta / 0.18)
	if climb_t >= 0.0:
		climb_t += delta / 0.40
		if climb_t >= 1.0:
			climb_t = -1.0
	_air_t = _air_t + delta if (anim == "jump" or anim == "fall") else 0.0
	var fall_s := 1.0 if (clips_on and CharClips.has("down")) else 0.75      # klip upadku jest dłuższy niż upadek z kodu
	_down = move_toward(_down, 1.0 if anim == "down" else 0.0, delta / (fall_s if anim == "down" else 0.95))
	_rise_w = move_toward(_rise_w, 0.0 if anim == "down" else 1.0, delta / 0.2)
	_mc = {}
	if swing_t >= 0.0 and _down < 0.2:
		_mc = _melee_curve(swing_t, "chop" if _gun_key == "kilof" else "slash")
	sink_m = 0.45 * smoothstep(0.0, 1.0, dying)
	_pose_body(delta, anim, speed, theta)
	if not _posed:
		_posed = true
		_stance.clear()
	var holding := armed and _down < 0.2 and throw_t < 0.0 and _clip_arms < 0.5
	# bezwładność broni: kąt broni modelu goni kąt celowania sprężyną lekko niedotłumioną (obrót o 45° trwa ok. 0,1 s i kończy się drobnym wybiegiem);
	# strzał dociąga broń na linię celowania od razu, żeby błysk wylotowy nie rozjechał się z torem pocisku
	if is_nan(_vis_aim) or not holding or recoil_px > _last_recoil + 0.05 or delta > 0.1:
		_vis_aim = theta
		_vis_vel = 0.0
	else:
		_vis_vel += ((theta - _vis_aim) * AIM_SPRING * AIM_SPRING - _vis_vel * 2.0 * 0.78 * AIM_SPRING) * delta
		_vis_aim += _vis_vel * delta
	_last_recoil = recoil_px
	if armed and _down < 0.2 and _clip_arms < 0.5:
		_rest_clavicles()
	if throw_t >= 0.0 and armed and _down < 0.2:
		_pose_throw(theta)
	elif holding:
		_pose_arms(_vis_aim)
	else:
		_pose_arms_relaxed(_clip_down < 0.5 and _clip_arms < 0.5)   # z klipem upadku albo klęczenia ręce zostają z klipu
	if _gun != null:
		_gun.visible = holding
		if _gun_n != null:
			_gun_n.visible = holding

## Parametry pozy bazowej (przed mieszaniem wagami): pochylenie tułowia (°), zapadnięcie bioder (m), kołysanie (m).
func _body_state(a: String) -> Dictionary:
	var lean := 4.0
	var drop := 0.0
	var bob := 0.0
	var clip := _clip_k if CharClips.has(a) else 0.0              # udział klipu: pochylenie i kołysanie niesie klip, z kodu zostaje reszta
	match a:
		"idle":
			lean = 4.0 + 0.8 * sin(_time * 2.4)
			bob = -0.006 * sin(_time * 2.4)
		"run":
			lean = 13.0
			bob = -0.035 * absf(sin(_phase))
		"jump", "fall":
			var ap := _air_params()
			lean = lerpf(8.0, 2.0, float(ap["fl"])) + 6.0 * float(ap["tk"])       # odbicie: wyprost z lekkim pochyleniem, spadanie: tułów pionowo
			drop = -0.05 * float(ap["tk"]) + 0.05 * float(ap["tuck"])             # wyprost przy odbiciu, w apeksie biodra niżej względem podciągniętych nóg
		"crouch", "revive":                                       # „revive" bez klipu to zwykły przysiad
			lean = 6.0                                                # przysiad: tułów prawie pionowo, kolana do przodu
			drop = CROUCH_DROP                                               # głęboki przysiad: sylwetka ok. 0,65 wysokości stojącej, jak hitbox kucania
		"crouch_walk":
			lean = 6.0
			drop = CROUCH_DROP
			bob = 0.012 * sin(_phase * 2.0)
	if clip > 0.0:
		lean *= 1.0 - clip
		bob *= 1.0 - clip
		drop = lerpf(drop, CharClips.param(a, "drop", 0.0), clip)
	return {"lean": lean, "drop": drop, "bob": bob}

func _pose_body(delta: float, anim: String, speed: float, theta: float) -> void:
	var hips := _b["Hips"] as int
	var key := "idle" if anim == "down" else anim
	if not AW_STATES.has(key):
		key = "idle"
	if _aw.is_empty():
		_aw[key] = 1.0
	var kk := 1.0 - exp(-AW_RATE * delta)
	var sum := 0.0
	for n in AW_STATES:
		_aw[n] = lerpf(float(_aw.get(n, 0.0)), 1.0 if n == key else 0.0, kk)
		sum += float(_aw[n])
	if anim == "run" or anim == "crouch_walk":
		_phase += (-1.0 if back_run else 1.0) * delta * clampf(speed / 95.0, 0.4, 1.4) * TAU * 2.0
	# klipy: drzewo ustawia biodra, tułów, głowę i nogi w stanach, które mają klip; zapamiętujemy stopy i kolana z klipu, zanim nakładki ruszą biodra.
	# Upadek: klip „down" przejmuje całą pozę (postęp = _down, wstawanie gra go wstecz); bez niego udział klipów znika i upadek liczy kod.
	_clip_w = 0.0
	_clip_bounce = 0.0
	_clip_arms = 0.0
	if anim == "revive":
		_kneel_t += delta
	elif float(_aw["revive"]) < 0.01 * sum:
		_kneel_t = 0.0
	var usable := _clips != null and clips_on and CharClips.enabled
	var fall_clip := usable and CharClips.has("down")
	_clip_down = smoothstep(0.0, 0.12, _down) if fall_clip else 0.0
	_clip_k = (1.0 if fall_clip else 1.0 - smoothstep(0.0, 1.0, _down)) if usable else 0.0
	if _clip_k > 0.0:
		_clip_ws.clear()
		for n in AW_STATES:
			var wc := float(_aw[n]) / maxf(sum, 0.0001) * _clip_k * (1.0 - _clip_down)
			if wc > 0.002 and CharClips.has(n):
				_clip_ws[n] = wc
				_clip_w += wc
				if CharClips.param(n, "arms", 0.0) > 0.0:
					_clip_arms += wc
		_clip_prog["revive"] = _kneel_t
		if _clip_down > 0.002:
			# upadek gra klip „down" postępem _down; wstawanie po reanimacji — klip „getup" (bez niego „down" wstecz)
			var w_up := _clip_down * _rise_w if CharClips.has("getup") else 0.0
			if _clip_down - w_up > 0.002:
				_clip_ws["down"] = _clip_down - w_up
				_clip_prog["down"] = _down
			if w_up > 0.002:
				_clip_ws["getup"] = w_up
				_clip_prog["getup"] = 1.0 - _down
			_clip_w += _clip_down
		if _clip_w > 0.0:
			CharClips.drive(_clips, _clip_ws, _phase / TAU, _time, _clip_prog)
			for side in ["Left", "Right"]:
				var cf := _gp(_b[side + "Foot"])
				_clip_foot[side] = cf
				_clip_knee[side] = _gp(_b[side + "Leg"]).origin - (_gp(_b[side + "UpLeg"]).origin + cf.origin) * 0.5
			_clip_bounce = CharClips.bounce_fix(_clips, _clip_ws, _gp(hips).origin.y - _sk.get_bone_global_rest(hips).origin.y)
	# poza bazowa = mieszanka stanów wg wag (faza kroku ciągła, więc bez przeskoków przy zmianie stanu)
	var lean := 0.0
	var drop := 0.0
	var bob := 0.0
	for n in AW_STATES:
		var w := float(_aw[n]) / maxf(sum, 0.0001)
		if w < 0.002:
			continue
		var st := _body_state(n)
		lean += w * float(st["lean"])
		drop += w * float(st["drop"])
		bob += w * float(st["bob"])
	if _clip_down > 0.0:                                          # klip upadku niesie całą pozę: z póz bazowych z kodu nie zostaje nic
		lean *= 1.0 - _clip_down
		drop = drop * (1.0 - _clip_down) + CharClips.param("down", "drop", 0.0) * _clip_down
		bob *= 1.0 - _clip_down
	var w_idle := float(_aw["idle"]) / maxf(sum, 0.0001)
	var w_run := (float(_aw["run"]) + float(_aw["crouch_walk"])) / maxf(sum, 0.0001)
	if back_run:
		lean -= 9.0 * w_run                                           # bieg tyłem: tułów odchylony do tyłu
	var lunge := 0.0
	if not _mc.is_empty():                                        # cios: wypad bioder, pochylenie i ugięcie wg krzywej ruchu
		lunge = float(_mc["step"]) * 0.45
		lean += float(_mc["lean"])
		drop += float(_mc["drop"])
	elif swing_t < 0.0 and _gun_key != "maczeta" and _gun_key != "kilof":
		var wpb: Dictionary = WEAPON_POSE.get(_gun_key, {})
		lean += float(wpb.get("lean", 0.0))                       # postawa zależna od broni (wyrzutnia na ramieniu, szyna z odchyleniem)
		var bk := float(wpb.get("body", 1.0))
		lunge -= minf(recoil_px * 0.004 * bk, 0.14)               # strzał: biodra cofają się, tułów odchyla się
		lean -= minf(recoil_px * 0.30 * bk, 9.0)
		lean -= 5.0 * charge_t                                    # ładowanie szyny: zaparcie się
	lean += 7.0 * clampf((_damage - 0.55) / 0.45, 0.0, 1.0)         # ciężko ranny: tułów zgarbiony do przodu
	var head_hit := 0.0
	if hit_t >= 0.0:                                              # trafienie: rekoil tułowia i szarpnięcie głowy
		var k := sin(PI * minf(hit_t * 1.4, 1.0)) * (1.0 - hit_t)
		lean -= 16.0 * k
		drop += 0.035 * k
		head_hit = 22.0 * k
	if land_t >= 0.0:                                             # lądowanie: amortyzacja kolanami ze sprężynowym odbiciem
		var kl := (sin(PI * land_t) - 0.22 * sin(TAU * land_t) * land_t) * land_str
		drop += 0.24 * kl
		lean += 10.0 * kl
	var jit := Vector3.ZERO
	if _grab_w > 0.001:                                           # chwycony: tułów zgięty, szarpie się na boki, biodra uniesione (nogi dyndają)
		lean += 14.0 * _grab_w
		drop -= 0.10 * _grab_w
		jit = Vector3(0.035 * sin(_time * 17.0) * _grab_w, 0.0, 0.0)
		head_hit += 12.0 * sin(_time * 14.0) * _grab_w
	if climb_t >= 0.0:                                            # podciągnięcie na platformę: pochylenie i ugięcie nad krawędzią
		var cw := sin(PI * climb_t)
		lean += 15.0 * cw
		drop += 0.07 * cw
	# upadek (po zdjęciu zdrowia) i wstawanie po reanimacji: ten sam ruch w drugą stronę
	var stand := 1.0 - smoothstep(0.0, 1.0, _down)
	var e := 0.0 if fall_clip else 1.0 - stand                    # upadek z kodu tylko wtedy, gdy nie ma klipu upadku
	if e > 0.001:
		drop = lerpf(drop, 0.62, e)
		lean = lerpf(lean, 0.0, e)
	if w_idle > 0.01 and e < 0.5 and not CharClips.has("idle"):
		# mikroruch: oddech klatki piersiowej, głowa „szuka” (bez wpływu na broń: tylko kręgosłup i głowa)
		_rot_world(_b["Spine2"], Vector3.BACK, deg_to_rad(0.9 * sin(_time * 1.9)) * w_idle * stand)
		_rot_world(_b["Head"], Vector3.UP, deg_to_rad(2.5 * sin(_time * 0.43) + 1.2 * sin(_time * 1.1)) * w_idle * stand)
	var fall_rot := -PI * 0.5 * pow(e, 1.3)                       # ciało przewraca się wokół bioder (opóźnione względem opadania bioder)
	_move_global(hips, Vector3(lunge, -drop + bob + _clip_bounce, 0.0) + jit)                     # kucając biodra cofnięte za stopy
	_rot_world(hips, Vector3.BACK, -deg_to_rad(lean) + fall_rot)
	if _grab_w > 0.001:
		_rot_world(hips, Vector3.UP, deg_to_rad(7.0) * sin(_time * 11.0) * _grab_w)
	if dying > 0.0:                                               # ostatnie sekundy: drgawki całego ciała, coraz słabsze przy zapadaniu
		var tw := sin(_time * 47.0) * sin(_time * 13.0) * (1.0 - dying * 0.6)
		_rot_world(hips, Vector3.UP, deg_to_rad(5.0) * tw)
		_rot_world(_b["Head"], Vector3.BACK, deg_to_rad(9.0) * sin(_time * 31.0) * (1.0 - dying * 0.5))
		for side in ["Left", "Right"]:
			_rot_world(_b[side + "Arm"], Vector3.BACK, deg_to_rad(14.0) * sin(_time * 38.0 + (0.0 if side == "Left" else 1.7)))
			_rot_world(_b[side + "UpLeg"], Vector3.BACK, deg_to_rad(10.0) * sin(_time * 29.0 + (0.0 if side == "Left" else 2.3)))
	# tułów zwraca się ku kamerze (broń po bliższej stronie) i pochyla się za celem
	var aim_k := stand * (1.0 - _clip_arms)                       # klęczenie przy rannym: tułów nie celuje
	_rot_world(_b["Spine"], Vector3.UP, deg_to_rad(BODY_YAW) * aim_k * _cam_c)
	for n in ["Spine", "Spine1", "Spine2"]:
		_rot_world(_b[n], Vector3.BACK, (_spine_pitch(theta) + deg_to_rad(lean) * 0.12 - gun_extra * 0.06) * aim_k)
	_rot_world(_b["Head"], Vector3.BACK, (theta * 0.2 - deg_to_rad(lean) * 0.5) * aim_k + deg_to_rad(head_hit))
	_pose_legs(e)

## Pomocnicze parametry lotu z prędkości pionowej i czasu w powietrzu: tk — wyprost tuż po odbiciu, tuck — podciągnięte kolana (najmocniej w apeksie),
## ext — nogi sięgają w dół przed lądowaniem, fl — jak szybko spada (0..1).
func _air_params() -> Dictionary:
	var rise := clampf(-air_vy / 275.0, 0.0, 1.0)
	var fl := clampf(air_vy / 380.0, 0.0, 1.0)
	var tk := 1.0 - smoothstep(0.0, 0.16, _air_t)
	var tuck := smoothstep(0.08, 0.40, _air_t) * clampf(1.0 - fl * 1.6, 0.0, 1.0) * (0.55 + 0.45 * (1.0 - rise))
	var ext := smoothstep(0.25, 0.85, fl)
	return {"tk": tk, "tuck": tuck, "ext": ext, "fl": fl}

## Stan nogi (offset kostki względem pozycji spoczynkowej, odchylenie stopy) dla jednej pozy bazowej.
func _leg_state(a: String, side: String) -> Array:
	var sgn := 1.0 if side == "Right" else -1.0
	var off := Vector3.ZERO
	var tilt := 0.0
	var ph := _phase + (0.0 if side == "Right" else PI)
	var own := 1.0 - (_clip_k if CharClips.has(a) else 0.0)        # z klipem tor stopy pochodzi z klipu (_pose_legs), z kodu zostaje reszta
	match a:
		"idle":
			off = Vector3(0.12 * sgn * 0.8, 0.0, 0.0)
		"run":
			var stride := 0.34 * (0.8 if back_run else 1.0)
			off = Vector3(stride * sin(ph), 0.17 * maxf(0.0, cos(ph)), 0.0)
			tilt = deg_to_rad(-14.0) * maxf(0.0, cos(ph))
		"jump", "fall":
			# ciągła poza lotu z prędkości: wyprost przy odbiciu → kolana podciągnięte w apeksie → nogi sięgają w dół przed lądowaniem
			var ap := _air_params()
			var front := sgn > 0.0
			var base := Vector3(0.14 if front else -0.08, 0.14 if front else 0.20, 0.0)
			var tucked := Vector3(0.30 if front else -0.14, 0.34 if front else 0.22, 0.0)
			var reach := Vector3(0.12 if front else -0.10, 0.05, 0.0)
			var launch := Vector3(-0.04 if front else -0.14, 0.0, 0.0)
			off = base.lerp(tucked, float(ap["tuck"])).lerp(reach, float(ap["ext"])).lerp(launch, float(ap["tk"]))
			tilt = deg_to_rad(-14.0) * (1.0 - float(ap["ext"])) + deg_to_rad(12.0) * float(ap["tk"])
		"crouch", "revive":
			off = Vector3(0.10 if sgn > 0 else -0.10, 0.0, 0.0)
		"crouch_walk":
			off = Vector3(0.13 * sin(ph) + (0.06 if sgn > 0 else -0.06), 0.07 * maxf(0.0, cos(ph)), 0.0)
	return [off * own, tilt * own]

func _pose_legs(e: float) -> void:
	var sum := 0.0
	for n in AW_STATES:
		sum += float(_aw.get(n, 0.0))
	for side in ["Left", "Right"]:
		var off := Vector3.ZERO
		var tilt := 0.0
		for n in AW_STATES:
			var w := float(_aw.get(n, 0.0)) / maxf(sum, 0.0001)
			if w < 0.002:
				continue
			var ls := _leg_state(n, side)
			off += w * (ls[0] as Vector3)
			tilt += w * float(ls[1])
		off *= 1.0 - _clip_down
		tilt *= 1.0 - _clip_down
		if _grab_w > 0.001:                                       # chwycony: nogi nad ziemią, kopią naprzemiennie
			var kp := _time * 9.0 + (0.0 if side == "Right" else PI)
			off.y += (0.12 + 0.22 * maxf(0.0, sin(kp))) * _grab_w
			off.x += 0.12 * sin(kp) * _grab_w
		if climb_t >= 0.0:                                        # podciągnięcie: oba kolana wysoko, noga bliższa kamery z przodu
			var cw2 := sin(PI * climb_t)
			off.y += 0.22 * cw2
			off.x += (0.10 if side == "Right" else -0.04) * cw2
		if not _mc.is_empty():                                    # cios: stopa bliższa kamery wysuwa się do przodu, druga zostaje i dociąża
			var st := float(_mc["step"])
			off.x += st if side == "Right" else -0.4 * st
		var foot: int = _b[side + "Foot"]
		var rest_foot := _sk.get_bone_global_rest(foot).origin
		var base := Vector3(_origin_x, _ankle_y, rest_foot.z)
		var target := base + off
		var rest_gb := _sk.get_bone_global_rest(foot).basis
		var pole := Vector3(1.0, 0.0, 0.0)                            # kolano do przodu
		if _clip_w > 0.0:
			# stopa z klipu: jej odchylenie od spoczynku już niesie wagę klipu (drzewo miesza klip z pozą spoczynkową); przy pełnej wadze cel = stopa klipu
			var cf: Transform3D = _clip_foot[side]
			target += (cf.origin - rest_foot) + _clip_w * (rest_foot - base)
			rest_gb = cf.basis
			# kolano tam, gdzie w klipie (leżenie na plecach, przyklęk): bez tego IK wyginałoby je zawsze do przodu
			var ck: Vector3 = _clip_knee[side]
			if ck.length() > 0.02:
				pole = pole.lerp(ck.normalized(), _clip_w)
				if pole.length() < 0.05:
					pole = ck
		if e > 0.001:
			# upadek: stopy zostają na ziemi, dopóki biodra opadają (kolana się uginają), potem nogi podążają sztywno za ciałem
			var rigid := _gp(foot).origin
			target = target.lerp(rigid, smoothstep(0.5, 0.9, e))
		_two_bone(_b[side + "UpLeg"], _b[side + "Leg"], foot, _leg_len[side][0], _leg_len[side][1], target, pole)
		# stopa płasko (z lekkim obrotem czubka); przy upadku obraca się razem z ciałem
		var flat := Basis(Vector3.BACK, tilt) * rest_gb
		if e > 0.001:
			flat = _gp(foot).basis.slerp(flat, 1.0 - smoothstep(0.3, 0.8, e))
		_set_global_basis(foot, flat)

## Broń wokół barku: dłoń tylna obejmuje chwyt (grzbietem do kamery, palce wzdłuż broni), przednia podchodzi pod łoże (broń dwuręczna), sięga po
## magazynek przy przeładowaniu, przy pistolecie dokłada się do chwytu, a przy broni białej zwisa. Gdy łoże jest za daleko, broń jest wsuwana ku ciału.
## Ustawia też `muzzle_px` / `grip_px` — punkty MODELU dla efektów; rozgrywka liczy swoje z `aim_points`.
func _pose_arms(theta: float) -> void:
	var sr := _gp(_b["RightArm"]).origin
	var sl := _gp(_b["LeftArm"]).origin
	var swinging := not _mc.is_empty()
	var wp: Dictionary = WEAPON_POSE.get(_gun_key, {})
	var wpa: Dictionary = {} if swinging else wp
	var pistol := String(wp.get("reload", "")) == "pistol"
	# broń biała w spoczynku: garda — ostrze uniesione, dłoń przed piersią; cios wychodzi z gardy i do niej wraca (bez gardy ostrze sterczało poziomo spod brody)
	var guard := 0.0
	if _hands == 1 and not pistol:
		guard = 1.0 - smoothstep(0.0, 0.14, swing_t) + smoothstep(0.8, 1.0, swing_t) if swinging else 1.0
	var aim_t := theta - (float(_mc["ang"]) if swinging else gun_extra) + MELEE_GUARD * guard
	if not swinging:
		if reload_t >= 0.0 and wpa.has("reload"):
			aim_t = theta - _reload_tilt(String(wpa["reload"]), clampf(reload_t, 0.0, 1.0))   # pochylenie broni wg rodzaju przeładowania (zamiast jednej sinusoidy)
		aim_t += clampf(recoil_px * 0.012 * float(wpa.get("climb", 1.0)), 0.0, 0.18)       # wznos lufy po strzale
	var gun_b := Basis(Vector3.BACK, aim_t)
	var radial := lerpf(float(_mc["rad"]) if swinging else float(wpa.get("radial", 0.30)), 0.25, guard)
	var perp := lerpf(0.11 if swinging else float(wpa.get("perp", 0.11)), 0.30, guard)
	var two := (_hands == 2 or pistol) and not swinging
	var hd := lerpf(aim_t, theta, guard) if swinging else theta    # przy ciosie dłoń wędruje po łuku wokół barku (razem z ostrzem)
	# broń palna trzyma się pozy nominalnej (tej, z której rozgrywka liczy wylot), a ruch barku z animacji — krok, kołysanie, odrzut ciała, trafienie —
	# przechodzi na nią tylko w części: ciało pracuje pod bronią, ręce to wybierają, a lufa zostaje przy torze pocisku
	var anchor := sr
	var anchor_l := sl
	if _hands == 2 or pistol:
		var wsum := 0.0
		for n in AW_STATES:
			wsum += float(_aw.get(n, 0.0))
		var wc := (float(_aw.get("crouch", 0.0)) + float(_aw.get("crouch_walk", 0.0))) / maxf(wsum, 0.0001)
		var base: Array = _nominal_shoulders(theta, false, wp)             # barki, z których rozgrywka liczy wylot (zwrot jak w prawo)
		var now: Array = _nominal_shoulders(theta, false, wp, _cam_c)      # barki nominalne przy obecnym zwrocie tułowia
		if wc > 0.001:
			var bc := _nominal_shoulders(theta, true, wp)
			var nc := _nominal_shoulders(theta, true, wp, _cam_c)
			for k in 2:
				base[k] = (base[k] as Vector3).lerp(bc[k], wc)
				now[k] = (now[k] as Vector3).lerp(nc[k], wc)
		# stałe przesunięcie barków od zwrotu tułowia wybierają ręce (broń zostaje przy wylocie rozgrywki); z ruchu animacji broń bierze część
		var fol := float(wp.get("follow", GUN_FOLLOW))
		anchor = (base[0] as Vector3) + (sr - (now[0] as Vector3)) * fol
		anchor_l = (base[1] as Vector3) + (sl - (now[1] as Vector3)) * fol
	var rear := _gun_origin(anchor, anchor_l, hd, gun_b, radial, perp, _gun_info, wpa, two, _cam_c)
	rear -= gun_b.x * (gun_kick_px / WP_PER_M * 0.6)
	if charge_t > 0.0:                                            # ładowanie szyny: drżenie trzymanej broni
		rear += Vector3(randf() - 0.5, randf() - 0.5, 0.0) * 0.018 * charge_t
	var gx := Transform3D(gun_b, rear)
	if _gun != null:
		_gun.transform = gx
		if _gun_n != null:
			_gun_n.transform = gx
	var rh := _hand_target("Right", gx, (_gun_info["grip"] as Vector3) + Vector3(0.0, float(wp.get("grip_dy", 0.0)), 0.0), _wrist_dir(wp), Vector3.BACK, GRIP_HALF)
	_reach_clavicle("Right", rh.origin, 0.22)
	_arm_ik("Right", rh.origin, Vector3(-0.35, -1.0, 0.55))
	_set_hand("Right", rh.basis)
	if swinging or _gun_key == "kilof":
		_pose_left_melee(gx, "chop" if _gun_key == "kilof" else "slash")
	elif two:
		var lh := _left_hold(gx, _gun_info, wp)
		var keep := 1.0                                           # ile orientacji chwytu zostaje dłoni (w drodze po magazynek dłoń idzie za przedramieniem)
		var reach_l: float = float(_arm_len["Left"][0]) + float(_arm_len["Left"][1])
		if climb_t >= 0.0 and not pistol:                         # podciągnięcie: wolna ręka podpiera się o krawędź platformy
			var cw := sin(PI * climb_t)
			lh.origin = lh.origin.lerp(sl + Vector3(0.20, -reach_l * 0.97, 0.08), cw)
			keep = 1.0 - cw
		elif reload_t >= 0.0:
			var u := clampf(reload_t, 0.0, 1.0)
			keep = 1.0 - 0.85 * sin(PI * u)
			if pistol:
				# pistolet: lewa dłoń schodzi po magazynek do pasa, wsuwa go od dołu w chwyt i wraca do chwytu oburącz
				var belt := sl + Vector3(-0.06, -reach_l * 0.95, 0.04)
				var well := gx * ((_gun_info["grip"] as Vector3) + Vector3(-0.02, -0.14, -0.04))
				if u < 0.35:
					lh.origin = lh.origin.lerp(belt, smoothstep(0.0, 0.35, u))
				elif u < 0.75:
					lh.origin = belt.lerp(well, smoothstep(0.35, 0.75, u))
				else:
					lh.origin = well.lerp(lh.origin, smoothstep(0.75, 1.0, u))
			else:                                                 # przeładowanie wg rodzaju broni: środek lewej dłoni po torze (magazynek, naboje, ogniwo, zamek)
				var palm := _left_path(String(wpa.get("reload", "mag")), u, _gun_info["hold"] as Vector3)
				lh.origin += gx * palm - gx * (_gun_info["hold"] as Vector3)
		elif cycle_t >= 0.0 and String(wpa.get("cycle", "")) != "":   # cykl po strzale: pompka (dłoń po łożu tam i z powrotem) / zamek
			if String(wpa["cycle"]) == "pump":
				lh.origin += gun_b.x * (-0.17 * sin(clampf((cycle_t - 0.12) / 0.6, 0.0, 1.0) * PI))
			else:
				lh.origin += gx * _left_path("bolt", clampf(cycle_t / 0.9, 0.0, 1.0), _gun_info["hold"] as Vector3) - gx * (_gun_info["hold"] as Vector3)
		_reach_clavicle("Left", lh.origin, 0.22)
		_arm_ik("Left", lh.origin, Vector3(-0.25, -1.0, -0.4))
		_set_hand("Left", lh.basis, keep)
	else:
		_pose_left_relaxed()
	muzzle_px = _to_px(gx * (_gun_info["muzzle"] as Vector3))
	grip_px = _to_px(rear)

## Rzut: prawa ręka zamach z tyłu nad głową → wyprost w przód i w dół (zwolnienie ok. 60% czasu), lewa ręka swobodnie.
func _pose_throw(theta: float) -> void:
	var t := clampf(throw_t, 0.0, 1.0)
	var ang := lerpf(deg_to_rad(160.0), deg_to_rad(-15.0) + theta * 0.6, ease(t, 0.7))
	var sr := _gp(_b["RightArm"]).origin
	var reach: float = (_arm_len["Right"][0] + _arm_len["Right"][1]) * 0.92
	var target := sr + Vector3(cos(ang), sin(ang), 0.0) * reach + Vector3(0.0, 0.0, 0.06)
	_arm_ik("Right", target, Vector3(-0.3, -0.6, 0.6))
	_pose_left_relaxed()
	muzzle_px = _to_px(target)
	grip_px = muzzle_px

## Pochylenie broni (rad, + = lufa w dół względem celowania) w trakcie przeładowania: lewa ręka bywa zasłonięta tułowiem, więc rodzaj przeładowania
## widać głównie po ruchu samej broni. mag — opuszcza się, szarpnięcie przy wsunięciu magazynka i klepnięcie zamka; shell — nachylona, kołysze się
## przy każdym naboju; cell / rail — lufa w górę (ogniwo od góry); bolt — lekko w dół, odciągnięcie zamka; pistol — przechylony ku drugiej ręce.
func _reload_tilt(kind: String, u: float) -> float:
	var env := smoothstep(0.0, 0.18, u) * (1.0 - smoothstep(0.82, 1.0, u))
	match kind:
		"shell":
			return 0.40 * env + 0.11 * sin(TAU * 3.0 * u) * env
		"cell":
			return -0.30 * env + 0.05 * sin(TAU * 2.0 * u) * env
		"rail":
			return -0.42 * env + 0.04 * sin(TAU * 7.0 * u) * env
		"bolt":
			return 0.22 * env - 0.10 * sin(PI * clampf((u - 0.45) / 0.3, 0.0, 1.0)) * env
		"pistol":
			return 0.55 * sin(PI * u)
		_:
			var jolt := 0.10 * sin(PI * clampf((u - 0.64) / 0.12, 0.0, 1.0))
			var slap := -0.09 * sin(PI * clampf((u - 0.84) / 0.08, 0.0, 1.0))
			return 0.55 * env + jolt + slap

## Tor środka lewej dłoni przy przeładowaniu w układzie broni (względem początku układu modelu); u ∈ 0..1 to postęp przeładowania, fore_l = punkt chwytu łoża.
## mag — wysuń magazynek, weź nowy z pasa, wsuń, przeładuj zamek; shell — kilka razy: nabój z pasa do gniazda; cell — ogniwo z góry; rail — jak cell, wolniej;
## bolt — odciągnięcie i dosunięcie zamka. Pozycje zależne od długości broni.
func _left_path(kind: String, u: float, fore_l: Vector3) -> Vector3:
	var L := _gun_len
	var P: Array = []
	match kind:
		"shell":
			var v := fposmod(u * 3.0, 1.0)                            # trzy ładowania
			P = [[0.0, fore_l], [0.25, Vector3(-0.04, -0.50, 0.0)], [0.55, Vector3(L * 0.16, -0.02, 0.0)], [0.72, Vector3(L * 0.16, -0.02, 0.0)], [1.0, fore_l]]
			return _path_eval(P, v)
		"cell", "rail":
			P = [[0.0, fore_l], [0.18, Vector3(L * 0.08, 0.14, 0.0)], [0.38, Vector3(L * 0.08, 0.36, 0.0)], [0.55, Vector3(-0.10, -0.55, 0.0)],
				[0.72, Vector3(L * 0.08, 0.32, 0.0)], [0.86, Vector3(L * 0.08, 0.10, 0.0)], [1.0, fore_l]]
		"bolt":
			P = [[0.0, fore_l], [0.25, Vector3(L * 0.16, 0.07, 0.0)], [0.45, Vector3(L * 0.16, 0.07, 0.0)], [0.6, Vector3(L * 0.04, 0.07, 0.0)],
				[0.8, Vector3(L * 0.16, 0.07, 0.0)], [1.0, fore_l]]
		_:
			P = [[0.0, fore_l], [0.18, Vector3(L * 0.10, -0.22, 0.0)], [0.34, Vector3(L * 0.10, -0.46, 0.0)], [0.48, Vector3(-0.08, -0.60, 0.0)],
				[0.64, Vector3(L * 0.10, -0.30, 0.0)], [0.74, Vector3(L * 0.10, -0.12, 0.0)], [0.84, Vector3(L * 0.14, 0.05, 0.0)], [1.0, fore_l]]
	for i in range(1, P.size() - 1):                              # punkty pośrednie opisywały nadgarstek dłoni sięgającej w górę — środek dłoni leży 0,1 m wyżej
		P[i][1] = (P[i][1] as Vector3) + Vector3(0.0, 0.1, 0.0)
	return _path_eval(P, u)

func _path_eval(P: Array, u: float) -> Vector3:
	for i in range(P.size() - 1):
		var a: Array = P[i]
		var b: Array = P[i + 1]
		if u <= float(b[0]):
			var t := (u - float(a[0])) / maxf(float(b[0]) - float(a[0]), 0.0001)
			return (a[1] as Vector3).lerp(b[1], t * t * (3.0 - 2.0 * t))
	return P[P.size() - 1][1]

## Cios bronią białą: krzywe ruchu (kąt zamachu względem celowania w rad, + = ostrze w dół; promień ręki od barku w m; pochylenie tułowia w °,
## zapadnięcie bioder w m; krok w m). Trafienie liczy gra w 45% czasu ciosu (`MELEE_HIT_AT`), więc uderzenie jest w u = 0,45.
## slash (maczeta): zamach do tyłu i w górę, cięcie przez łuk z wyprostem ręki, wybieg; chop (kilof): wzniesienie nad głowę, rąbnięcie, przytrzymanie, powrót.
func _melee_curve(u: float, style: String) -> Dictionary:
	var K: Dictionary
	if style == "chop":
		K = {
			"ang": [[0.0, 0.0], [0.28, -2.05], [0.45, 1.05], [0.62, 1.25], [1.0, 0.0]],
			"rad": [[0.0, 0.30], [0.28, 0.15], [0.45, 0.40], [1.0, 0.30]],
			"lean": [[0.0, 0.0], [0.28, -12.0], [0.45, 30.0], [0.65, 24.0], [1.0, 0.0]],
			"drop": [[0.0, 0.0], [0.28, -0.04], [0.45, 0.16], [0.7, 0.10], [1.0, 0.0]],
			"step": [[0.0, 0.0], [0.28, 0.04], [0.45, 0.28], [0.75, 0.20], [1.0, 0.0]],
		}
	else:
		K = {
			"ang": [[0.0, 0.0], [0.18, -1.15], [0.45, 0.50], [0.62, 0.95], [1.0, 0.0]],
			"rad": [[0.0, 0.30], [0.18, 0.18], [0.45, 0.42], [0.7, 0.34], [1.0, 0.30]],
			"lean": [[0.0, 0.0], [0.18, -6.0], [0.45, 20.0], [0.65, 13.0], [1.0, 0.0]],
			"drop": [[0.0, 0.0], [0.18, -0.01], [0.45, 0.07], [0.7, 0.04], [1.0, 0.0]],
			"step": [[0.0, 0.0], [0.18, 0.0], [0.45, 0.22], [0.75, 0.14], [1.0, 0.0]],
		}
	var o := {"style": style}
	for k in K:
		o[k] = _keyframes(K[k], u)
	return o

## Interpolacja między kluczami [[u, v], …]: przyspieszenie do klatki trafienia (u = 0,45), po niej wyhamowanie — cios „uderza", a nie płynie.
func _keyframes(keys: Array, u: float) -> float:
	if u <= float(keys[0][0]):
		return float(keys[0][1])
	for i in range(keys.size() - 1):
		var a: Array = keys[i]
		var b: Array = keys[i + 1]
		if u <= float(b[0]):
			var t := (u - float(a[0])) / maxf(float(b[0]) - float(a[0]), 0.0001)
			if is_equal_approx(float(b[0]), 0.45):
				t = t * t                                      # rozpęd do uderzenia
			elif is_equal_approx(float(a[0]), 0.45):
				t = 1.0 - (1.0 - t) * (1.0 - t)                # wybieg po uderzeniu
			else:
				t = t * t * (3.0 - 2.0 * t)
			return lerpf(float(a[1]), float(b[1]), t)
	return float(keys[keys.size() - 1][1])

## Druga ręka przy ciosie: kilof — na trzonku (chwyt oburącz), maczeta — przeciwwaga: zamach w przeciwną stronę.
func _pose_left_melee(gx: Transform3D, style: String) -> void:
	if style == "chop":
		var lh := _hand_target("Left", gx, (_gun_info["grip"] as Vector3) + Vector3(0.2, 0.0, 0.0), _wrist_dir(WEAPON_POSE.get(_gun_key, {})), Vector3.FORWARD, GRIP_HALF)
		_arm_ik("Left", lh.origin, Vector3(-0.25, -1.0, -0.4))
		_set_hand("Left", lh.basis)
		return
	var sl := _gp(_b["LeftArm"]).origin
	var reach: float = float(_arm_len["Left"][0]) + float(_arm_len["Left"][1])
	var counter := float(_mc["ang"])                           # ostrze w dół → lewa ręka odchodzi w tył i w górę
	_arm_ik("Left", sl + Vector3(-0.10 - 0.16 * clampf(counter, 0.0, 1.0), -reach * 0.78 + 0.20 * clampf(counter, 0.0, 1.0), 0.05), Vector3(-0.25, -1.0, -0.4))

func _pose_left_relaxed() -> void:
	var sl := _gp(_b["LeftArm"]).origin
	var reach: float = _arm_len["Left"][0] + _arm_len["Left"][1]
	var tgt := sl + Vector3(0.12, -reach * 0.9, 0.05)
	if climb_t >= 0.0:                                                # podciągnięcie: ręka wyciągnięta w dół i w przód, na krawędź
		tgt = tgt.lerp(sl + Vector3(0.22, -reach * 0.98, 0.08), sin(PI * climb_t))
	_arm_ik("Left", tgt, Vector3(-0.3, -1.0, -0.5))

func _pose_arms_relaxed(both: bool) -> void:
	muzzle_px = Vector2(0.0, -10.0)
	grip_px = muzzle_px
	if both and not _b.is_empty():
		var sr := _gp(_b["RightArm"]).origin
		var reach: float = _arm_len["Right"][0] + _arm_len["Right"][1]
		_arm_ik("Right", sr + Vector3(0.10, -reach * 0.9, -0.03), Vector3(-0.3, -1.0, 0.5))
		_pose_left_relaxed()

## Punkt 3D (m, układ modelu) → piksele świata względem stóp, tak jak widać go w widoku 3D: aktor stoi w pozycji gracza i jest obrócony
## o `model_yaw` (kamera patrzy wzdłuż −Z, więc liczy się tylko składowa x po obrocie).
func _to_px(p: Vector3) -> Vector2:
	return Vector2((p.x * cos(model_yaw) + p.z * sin(model_yaw)) * WP_PER_M, -p.y * WP_PER_M)

## To samo dla postaci zwróconej na stałe w stronę `fl` (±1) — punkty celowania rozgrywki.
func _to_px_side(p: Vector3, fl: float) -> Vector2:
	return Vector2(fl * p.x * WP_PER_M, -p.y * WP_PER_M)
