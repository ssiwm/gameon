extends RefCounted
## Okno radiostacji w kryjówce (`hub_prop.gd`, rodzaj „window”): przez szybę widać prognozowaną pogodę (clear / rain / storm / fog).
##
## Uwaga z gry 2026-11-18: płaski prostokąt z ukośnymi kreskami wyglądał jak naklejka. Teraz:
##  - głębia: plany za szybą (niebo z chmurami, linia lasu z masztem radiostacji, ogrodzenie) przesuwają się względem ramy z paralaksą,
##    gdy kamera idzie za graczem (warstwa w odległości D za szybą: przesunięcie Δx·D/(L+D), L — odległość kamery od szyby);
##  - deszcz w trzech planach (bliski grubszy i szybszy, daleki drobny), skos od wiatru, krople łapią błysk burzy;
##  - szyba: krople stojące i spływające ze śladem, które załamują obraz za oknem; brud przy ramie; mgła osiada na szkle (zmatowienie);
##  - burza: seria 2–3 rozbłysków co kilka–kilkanaście sekund, czasem widoczny kanał pioruna za lasem, chmury podświetlone od strony uderzenia;
##  - stalowa rama fabrycznego okna ze szprosami, parapet, jedna szybka zabita deską.
## Tylko obraz (warstwa świata, bez cienia); koszt: jeden prostokąt na ekranie.

const PANES := Vector2i(8, 4)              ## szybki w poziomie / pionie (stalowe okno fabryczne)
const BAR_W := 0.035                       ## m: szerokość szprosu
const H := 2.0                             ## m: wysokość przeszklenia
const Y0 := 1.5                            ## m: dolna krawędź przeszklenia nad podłogą
const Z_GLASS := -1.86                     ## m: głębia szyby (ściana tylna na ok. −1,93)
const BOARDED := Vector2i(0, 3)            ## szybka zabita deską (kolumna, wiersz od góry)

const SHADER := """
shader_type spatial;
render_mode unshaded, cull_back, fog_disabled;

uniform int kind = 0;                      // 0 pogodnie, 1 deszcz, 2 burza, 3 mgła
uniform float flash = 0.0;                 // jasność rozbłysku 0..1
uniform float bolt = 0.0;                  // widoczność kanału pioruna 0..1
uniform float bolt_x = 0.3;                // położenie kanału w planie nieba (wysokości okna od środka)
uniform float bolt_seed = 0.0;
uniform vec2 size = vec2(3.9, 2.0);        // m: wymiary przeszklenia
uniform vec2 panes = vec2(8.0, 4.0);
uniform vec3 sky_top : source_color = vec3(0.02, 0.04, 0.09);
uniform vec3 sky_bot : source_color = vec3(0.07, 0.10, 0.16);
uniform vec3 room_col : source_color = vec3(1.0, 0.62, 0.30);   // odblask lampy kryjówki na szkle

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float h1(float n) { return fract(sin(n * 127.1) * 43758.5453); }
float h2(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h2(i), h2(i + vec2(1.0, 0.0)), f.x), mix(h2(i + vec2(0.0, 1.0)), h2(i + vec2(1.0, 1.0)), f.x), f.y);
}
float fbm(vec2 p) {
	float s = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		s += a * vnoise(p);
		p = p * 2.03 + vec2(1.7, 9.2);
		a *= 0.5;
	}
	return s;
}

// Linia lasu: dwa rzędy świerków (trójkątne wierzchołki) na falistym grzbiecie; zwraca wysokość sylwetki w planie.
float treeline(float x) {
	float base = -0.20 + 0.05 * (vnoise(vec2(x * 0.9, 3.0)) - 0.5);
	float c = floor(x * 22.0);
	float f = fract(x * 22.0);
	float tip = 0.035 + 0.075 * h1(c) * h1(c + 7.0);
	float spr = 0.5 + 0.3 * (h1(c + 3.0) - 0.5);
	float t1 = tip * max(0.0, 1.0 - abs(f - spr) * 2.2);
	float c2 = floor(x * 13.0 + 0.37);
	float f2 = fract(x * 13.0 + 0.37);
	float t2 = (0.06 + 0.07 * h1(c2 + 21.0)) * max(0.0, 1.0 - abs(f2 - 0.5) * 2.1) - 0.02;
	return base + max(t1, t2);
}

// Deszcz jednego planu: smugi w kolumnach, skos od wiatru; n — gęstość kolumn, sp — prędkość, th — udział zajętych kolumn.
float rain_layer(vec2 p, float n, float sp, float len, float th, float seed) {
	p.x += p.y * 0.22;
	float cx = p.x * n;
	float cell = floor(cx);
	float h = h1(cell + seed);
	float y = fract(p.y * len + TIME * sp + h * 7.0);
	float streak = smoothstep(0.0, 0.06, y) * smoothstep(0.55, 0.12, y) * step(th, h);
	float w = max(0.07, fwidth(cx) * 0.8);
	streak *= smoothstep(w, 0.0, abs(fract(cx) - 0.5)) * (0.5 + 0.5 * h1(cell + seed + 1.3));
	return streak;
}

void fragment() {
	vec2 q = (UV - 0.5) * size / size.y;     // wysokości okna od środka, y w górę
	q.y = -q.y;
	vec2 qmax = vec2(0.5 * size.x / size.y, 0.5);
	vec3 cam = CAMERA_POSITION_WORLD;
	vec3 node = NODE_POSITION_WORLD;
	float L = max(cam.z - node.z, 0.5);
	float dx = (node.x - cam.x) / size.y * 0.35;          // paralaksa przytłumiona: pełna przesuwała niebo o kilka wysokości okna

	// ---- szyba: krople (deszcz/burza) i ich załamanie, kondensacja (mgła)
	vec2 refr = vec2(0.0);
	float wet = 0.0;
	float spec = 0.0;
	if (kind == 1 || kind == 2) {
		// krople stojące
		for (int s = 0; s < 2; s++) {
			float sc = s == 0 ? 26.0 : 48.0;
			vec2 g = q * sc + vec2(float(s) * 3.1, 0.0);
			vec2 id = floor(g);
			vec2 f = fract(g) - 0.5;
			float hh = h2(id + float(s) * 17.0);
			vec2 ctr = vec2(h2(id + 4.2), h2(id + 9.7)) - 0.5;
			ctr *= 0.5;
			float r = (0.10 + 0.18 * hh) * step(s == 0 ? (kind == 2 ? 0.70 : 0.82) : (kind == 2 ? 0.80 : 0.88), hh);
			vec2 dd = f - ctr;
			float d = length(dd) / max(r, 1e-3);
			float m = smoothstep(1.0, 0.8, d) * step(0.001, r);
			refr += -dd / max(r, 1e-3) * m * (0.035 / sc) * 10.0;
			wet = max(wet, m);
			spec += m * smoothstep(0.3, 0.0, length(dd / max(r, 1e-3) - vec2(-0.35, 0.4))) * 0.35;
		}
		// krople spływające ze śladem
		float cols = 7.0;
		float gx = q.x * cols;
		float cid = floor(gx);
		float hc = h1(cid + 50.0);
		float sp = 0.06 + 0.10 * hc;
		float yy = q.y * 1.1 + TIME * sp + hc * 13.0;
		float rid = floor(yy);
		float fy = fract(yy);
		float hr = h1(cid * 7.0 + rid);
		float xw = (gx - cid - 0.5) + 0.12 * sin(q.y * 9.0 + hc * 6.0) + 0.25 * (hr - 0.5);
		if (hr > (kind == 2 ? 0.2 : 0.45)) {
			vec2 dd = vec2(xw * 0.55 / cols, (fy - 0.25) * 0.9 / 1.1) * 26.0;   // w jednostkach kropli
			float d = length(dd * vec2(1.0, 0.8)) / 0.55;
			float m = smoothstep(1.0, 0.75, d);
			refr += -dd / 0.55 * m * 0.012;
			wet = max(wet, m);
			spec += m * smoothstep(0.4, 0.0, length(dd / 0.55 - vec2(-0.3, 0.45))) * 0.8;
			float tb = abs(xw) < 0.06 && fy > 0.3 ? 1.0 : 0.0;
			wet = max(wet, tb * 0.5 * (1.0 - fy));
			refr.x += tb * 0.004 * sign(xw);
		}
	}
	vec2 p0 = q + refr;

	// ---- plany za szybą
	vec2 qs = p0 + vec2(dx, 0.0);                          // niebo (nieskończoność)
	vec2 qt = p0 + vec2(dx * 80.0 / (L + 80.0), 0.0);      // las ~80 m
	vec2 qm = p0 + vec2(dx * 300.0 / (L + 300.0), 0.0);    // maszt ~300 m
	vec2 qf = p0 + vec2(dx * 5.0 / (L + 5.0), 0.0);        // ogrodzenie ~5 m

	vec3 col = mix(sky_bot, sky_top, smoothstep(-0.25, 0.5, qs.y));
	col += sky_bot * 0.6 * exp(-pow(qs.y + 0.17, 2.0) * 40.0) * (kind == 3 ? 0.3 : 1.0);   // poświata nad horyzontem: las czyta się sylwetką
	float cover = kind == 0 ? 0.30 : (kind == 1 ? 0.70 : (kind == 2 ? 0.85 : 0.6));
	float cl = fbm(vec2(qs.x * 1.7 + TIME * 0.012, qs.y * 4.0 + 0.2));
	float cmask = smoothstep(1.0 - cover - 0.1, 1.0 - cover + 0.25, cl);
	float blx = exp(-pow(qs.x - bolt_x, 2.0) * 2.5);
	if (kind == 0) {
		// gwiazdy i księżyc za rzadkimi chmurami
		vec2 sgp = qs * 60.0;
		vec2 sg = floor(sgp);
		float st = h2(sg);
		vec2 so = vec2(h2(sg + 5.1), h2(sg + 8.3)) * 0.6 + 0.2;
		float sd = length(fract(sgp) - so);
		float spx = max(fwidth(sgp.x) * 0.7, 0.06);
		float tw = 0.6 + 0.4 * sin(TIME * (1.0 + 3.0 * h2(sg + 2.0)) + st * 30.0);
		col += vec3(0.7, 0.78, 1.0) * step(0.985, st) * smoothstep(spx, 0.0, sd) * tw * (0.25 + 0.5 * h2(sg + 1.7)) * smoothstep(-0.1, 0.25, qs.y);
		float dm = length(qs - vec2(0.45, 0.28));
		col += vec3(0.85, 0.88, 0.95) * smoothstep(0.034, 0.03, dm) * 0.9;
		col += vec3(0.30, 0.38, 0.55) * exp(-dm * 9.0) * 0.18;
		vec3 ccol = sky_top * 1.3 + vec3(0.06, 0.07, 0.09) * exp(-dm * 3.0);
		col = mix(col, ccol, cmask * 0.75);
	} else if (kind == 1 || kind == 2) {
		vec3 ccol = mix(sky_bot * 0.9, sky_top * 1.4, cl);
		col = mix(col, ccol, cmask);
		col += vec3(0.62, 0.68, 0.88) * flash * 0.6 * (0.15 + 0.85 * cl * cl) * (0.3 + 0.7 * blx);
		if (kind == 2 && bolt > 0.0) {
			float yb = qs.y;
			float bx = bolt_x + (vnoise(vec2(yb * 7.0, bolt_seed)) - 0.5) * 0.16 + (vnoise(vec2(yb * 31.0, bolt_seed + 3.0)) - 0.5) * 0.035;
			float d = abs(qs.x - bx);
			float core = smoothstep(0.006 + fwidth(qs.x), 0.0, d) * smoothstep(0.55, 0.35, yb);
			col += vec3(0.85, 0.9, 1.0) * (core * 1.4 + exp(-d * 55.0) * 0.35) * bolt;
		}
	} else {
		col = mix(col, vec3(0.034, 0.042, 0.05), 0.6);
	}

	// maszt radiostacji z lampą (zgasza go mgła i deszcz)
	float vis_far = kind == 3 ? 0.25 : (kind == 2 ? 0.7 : (kind == 1 ? 0.8 : 1.0));
	{
		float mx = 0.62;
		float top = 0.18;
		float wdt = max(mix(0.012, 0.004, smoothstep(-0.2, top, qm.y)), fwidth(qm.x) * 0.6);
		float lat = smoothstep(wdt, wdt * 0.5, abs(qm.x - mx)) * step(qm.y, top);
		vec3 mcol = mix(col, vec3(0.008, 0.01, 0.014), vis_far);
		col = mix(col, mcol, lat);
		float blink = step(0.5, fract(TIME * 0.5));
		float dl = length(qm - vec2(mx, top + 0.006));
		col += vec3(1.0, 0.12, 0.05) * blink * (smoothstep(0.007, 0.003, dl) * 1.2 * vis_far + exp(-dl * (kind == 3 ? 28.0 : 60.0)) * 0.18);
	}

	// las
	float ty = treeline(qt.x);
	float aa = fwidth(qt.y) * 1.5;
	float tmask = smoothstep(ty + aa, ty - aa, qt.y);
	vec3 tcol = mix(vec3(0.006, 0.009, 0.014), col, kind == 3 ? 0.75 : (kind == 2 || kind == 1 ? 0.12 : 0.08));
	tcol += vec3(0.25, 0.28, 0.35) * flash * 0.08;
	col = mix(col, tcol, tmask);
	// pole przed lasem: mokre odbija niebo
	float ground = smoothstep(-0.25, -0.30, qt.y);
	vec3 gcol = mix(vec3(0.012, 0.014, 0.016), sky_bot * 0.5, (kind == 1 || kind == 2) ? 0.6 : 0.2);
	gcol += vec3(0.5, 0.55, 0.7) * flash * 0.12;
	col = mix(col, gcol, ground * tmask);

	// mgła: ławice w kilku planach
	if (kind == 3) {
		for (int i = 0; i < 3; i++) {
			float D = i == 0 ? 60.0 : (i == 1 ? 18.0 : 6.0);
			vec2 pf = p0 + vec2(dx * D / (L + D), 0.0);
			float n = fbm(vec2(pf.x * (1.2 + float(i)) + TIME * (0.015 + 0.01 * float(i)), pf.y * 3.0 + float(i) * 4.0));
			float dens = smoothstep(0.3, 0.75, n) * (0.55 - 0.12 * float(i)) * smoothstep(0.55, -0.2, pf.y);
			col = mix(col, vec3(0.04, 0.047, 0.055), dens);
		}
	}

	// ogrodzenie z drutem kolczastym (bliski plan)
	{
		float px = qf.x * 1.6;
		float pid = floor(px);
		float pfx = fract(px) - 0.5;
		float lean = (h1(pid + 40.0) - 0.5) * 0.08;
		float ptop = -0.18 + 0.05 * h1(pid + 41.0);
		float post = smoothstep(0.035, 0.025, abs(pfx + lean * (qf.y + 0.5)) ) * step(qf.y, ptop);
		float wire = 0.0;
		for (int k = 0; k < 3; k++) {
			float wy = -0.42 + 0.09 * float(k) + 0.012 * sin(qf.x * 3.0 + float(k));
			wire = max(wire, smoothstep(0.004 + fwidth(qf.y), 0.0, abs(qf.y - wy)));
		}
		vec3 fcol = vec3(0.004, 0.005, 0.006) + vec3(0.4, 0.45, 0.55) * flash * 0.15;
		float fvis = kind == 3 ? 0.7 : 1.0;
		col = mix(col, fcol, max(post, wire * 0.8) * fvis);
	}

	// deszcz w trzech planach
	if (kind == 1 || kind == 2) {
		float k2 = kind == 2 ? 1.0 : 0.0;
		vec3 rc = sky_bot * 2.2 + vec3(0.05, 0.055, 0.065) + vec3(0.8, 0.85, 1.0) * flash * 0.9;
		float r = 0.0;
		r += rain_layer(p0 + vec2(dx * 1.5 / (L + 1.5), 0.0), 9.0, 2.4 + k2, 1.6, 0.35 - 0.15 * k2, 1.0) * 0.55;
		r += rain_layer(p0 + vec2(dx * 4.0 / (L + 4.0), 0.0), 22.0, 1.9 + k2, 2.4, 0.45 - 0.2 * k2, 7.0) * 0.4;
		r += rain_layer(p0 + vec2(dx * 12.0 / (L + 12.0), 0.0), 55.0, 1.5 + k2 * 0.8, 3.5, 0.5 - 0.2 * k2, 13.0) * 0.28;
		col = mix(col, rc, clamp(r, 0.0, 1.0) * 0.75);
		col = mix(col, sky_bot * 1.1, 0.12 + 0.1 * k2);     // zasłona deszczu zmiękcza plany
	}

	// ---- szkło
	float edge = min(qmax.x - abs(q.x), qmax.y - abs(q.y));
	float dirt = fbm(q * vec2(5.0, 6.0) + 11.0);
	float dirt_k = (0.25 + 0.75 * smoothstep(0.12, 0.0, edge)) * smoothstep(0.35, 0.7, dirt);
	dirt_k = max(dirt_k, smoothstep(-0.28, -0.5, q.y) * 0.5 * dirt);
	col *= 1.0 - 0.3 * dirt_k;
	col += room_col * 0.012 * dirt_k;
	if (kind == 3) {
		// kondensacja: zmatowienie i drobne kropelki
		float fogg = 0.45 + 0.25 * fbm(q * 3.0 + 5.0);
		col = mix(col, vec3(0.038, 0.045, 0.052), fogg * 0.45);
		float bead = step(0.985, h2(floor(q * 120.0)));
		col += vec3(0.05) * bead * 0.25;
	}
	if (kind == 1 || kind == 2) {
		col *= 1.0 - wet * 0.08;
		col += (room_col * 0.06 + vec3(0.6, 0.7, 0.9) * flash * 0.5) * spec;
	}
	// odblask pokoju na szkle: ciepła łuna od lampy u góry, chłodniej w dole
	float refl = 0.022 * smoothstep(-0.6, 0.6, q.y) * (0.6 + 0.4 * smoothstep(qmax.x, -qmax.x, q.x));
	refl += 0.012 * smoothstep(0.09, 0.0, abs(q.x * 0.55 + q.y - 0.15)) * (0.5 + 0.5 * fbm(q * 4.0));   // ukośna smuga odblasku
	col += room_col * refl;
	// cień wnęki przy ramie
	col *= mix(0.55, 1.0, smoothstep(0.0, 0.06, edge));
	ALBEDO = col;
}
"""

## Rozbłysk burzy w chwili `t` (s): Vector4(jasność 0..1, widoczność kanału 0..1, położenie kanału, ziarno). Seria 2–3 błysków
## w oknach co ok. 9 s, część okien bez uderzenia; kanał widać tylko przy mocnym pierwszym błysku. `soft` (efekty pogody REDUCED, jak
## `weather_fx.gd` `_flash`): sama miękka poświata — 0,5 s narastania, ok. 1,2 s opadania, 40% amplitudy, bez kanału.
static func storm_flash(t: float, soft := false) -> Vector4:
	const PERIOD := 9.0
	var k := floorf(t / PERIOD)
	var r := _h(k)
	if _h(k + 0.37) < 0.25:
		return Vector4(0.0, 0.0, 0.0, k)
	var t0 := k * PERIOD + 0.8 + r * (PERIOD - 2.5)
	var dt := t - t0
	if soft:
		var rise := clampf((dt + 0.5) / 0.5, 0.0, 1.0)
		var fall := clampf(1.0 - maxf(dt, 0.0) / 1.2, 0.0, 1.0)
		return Vector4(0.4 * rise * fall, 0.0, (_h(k + 0.13) - 0.5) * 1.6, k)
	if dt < 0.0 or dt > 1.6:
		return Vector4(0.0, 0.0, 0.0, k)
	var f := exp(-dt * 16.0)
	if dt > 0.16:
		f = maxf(f, 0.75 * exp(-(dt - 0.16) * 11.0))
	if r > 0.4 and dt > 0.42:
		f = maxf(f, 0.55 * exp(-(dt - 0.42) * 7.0))
	var strong := _h(k + 0.71) > 0.35
	var bolt := clampf((f - 0.35) * 2.0, 0.0, 1.0) if strong else 0.0
	var bx := (_h(k + 0.13) - 0.5) * 1.6
	return Vector4(f * (1.0 if strong else 0.55), bolt, bx, k)

static func _h(x: float) -> float:
	var v := sin(x * 127.1 + 0.7) * 43758.5453
	return v - floorf(v)

## Kolory nieba wg prognozy [góra, dół].
const SKY := {"clear": [Color(0.022, 0.04, 0.10), Color(0.07, 0.10, 0.19)], "rain": [Color(0.045, 0.055, 0.075), Color(0.10, 0.12, 0.155)],
	"storm": [Color(0.03, 0.035, 0.05), Color(0.08, 0.09, 0.115)], "fog": [Color(0.028, 0.034, 0.042), Color(0.04, 0.047, 0.056)]}
const KIND := {"clear": 0, "rain": 1, "storm": 2, "fog": 3}

## Stan materiału i światła okna na klatkę. `fx_mode` = Settings.weather_fx_idx (0 FULL, 1 REDUCED, 2 OFF — bez błysków);
## `dev_flash` ≥ 0 (--shotflash[=K]): stały błysk do zrzutów, od 0,5 z kanałem pioruna.
static func sync(mat: ShaderMaterial, light: OmniLight3D, forecast: String, t: float, fx_mode := 0, dev_flash := -1.0) -> void:
	var fc := forecast if KIND.has(forecast) else "clear"
	mat.set_shader_parameter("kind", int(KIND[fc]))
	var fl := Vector4.ZERO
	if fc == "storm" and dev_flash >= 0.0:
		fl = Vector4(dev_flash, 1.0 if dev_flash >= 0.5 else 0.0, -0.35, 3.0)
	elif fc == "storm" and fx_mode != 2:
		fl = storm_flash(t, fx_mode == 1)
	mat.set_shader_parameter("flash", fl.x)
	mat.set_shader_parameter("bolt", fl.y)
	mat.set_shader_parameter("bolt_x", fl.z)
	mat.set_shader_parameter("bolt_seed", fl.w)
	var sc: Array = SKY[fc]
	mat.set_shader_parameter("sky_top", sc[0])
	mat.set_shader_parameter("sky_bot", sc[1])
	light.light_energy = (0.25 if fc == "storm" or fc == "rain" else 0.35) + 3.2 * fl.x

## Buduje okno pod `root` (początek: środek dołu okna na podłodze). `box` = Callable(root, size, pos, mat) → MeshInstance3D z widoku.
## Zwraca [materiał szyby, światło okna].
static func build(root: Node3D, w: float, box: Callable, mk_mat: Callable, world_layer: int, light_layers: int) -> Array:
	var steel: Material = mk_mat.call(Color(0.09, 0.095, 0.10), 0.3, 0.75)
	var conc: Material = mk_mat.call(Color(0.30, 0.29, 0.27), 0.0, 0.9)
	var ply: Material = mk_mat.call(Color(0.33, 0.25, 0.16), 0.0, 0.85)
	var board: Material = mk_mat.call(Color(0.17, 0.13, 0.09), 0.0, 0.9)
	var yc := Y0 + H * 0.5
	var fw := 0.08                                              # ościeżnica stalowa
	box.call(root, Vector3(w + 2.0 * fw, fw, 0.10), Vector3(0.0, Y0 + H + fw * 0.5, Z_GLASS + 0.02), steel)
	box.call(root, Vector3(w + 2.0 * fw, fw, 0.10), Vector3(0.0, Y0 - fw * 0.5, Z_GLASS + 0.02), steel)
	for s in [-1.0, 1.0]:
		box.call(root, Vector3(fw, H, 0.10), Vector3(s * (w + fw) * 0.5, yc, Z_GLASS + 0.02), steel)
	box.call(root, Vector3(w + 0.5, 0.07, 0.30), Vector3(0.0, Y0 - fw - 0.035, Z_GLASS + 0.11), conc)     # parapet
	box.call(root, Vector3(w + 0.4, 0.16, 0.06), Vector3(0.0, Y0 + H + fw + 0.08, Z_GLASS + 0.03), conc)  # nadproże
	for i in range(1, PANES.x):
		box.call(root, Vector3(BAR_W, H, 0.04), Vector3(-w * 0.5 + w * float(i) / float(PANES.x), yc, Z_GLASS + 0.025), steel)
	for j in range(1, PANES.y):
		box.call(root, Vector3(w, BAR_W, 0.04), Vector3(0.0, Y0 + H * float(j) / float(PANES.y), Z_GLASS + 0.025), steel)
	# szybka zabita deską (dwie deski na krzyż)
	var pw := w / float(PANES.x)
	var ph := H / float(PANES.y)
	var pc := Vector3(-w * 0.5 + pw * (float(BOARDED.x) + 0.5), Y0 + H - ph * (float(BOARDED.y) + 0.5), Z_GLASS + 0.05)
	box.call(root, Vector3(pw - 0.01, ph - 0.01, 0.015), pc, ply)
	var plank: MeshInstance3D = box.call(root, Vector3(pw * 1.15, 0.09, 0.025), pc + Vector3(0.0, 0.0, 0.02), board)
	plank.rotation.z = atan2(ph, pw) * 0.8
	var qm := QuadMesh.new()
	qm.size = Vector2(w, H)
	var gm := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = SHADER
	gm.shader = sh
	gm.set_shader_parameter("size", Vector2(w, H))
	gm.set_shader_parameter("panes", Vector2(PANES))
	var gmi := MeshInstance3D.new()
	gmi.name = "WindowGlass"
	gmi.mesh = qm
	gmi.material_override = gm
	gmi.layers = world_layer
	gmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gmi.position = Vector3(0.0, yc, Z_GLASS)
	root.add_child(gmi)
	var wl := OmniLight3D.new()                                 # zimne światło z okna (błyski burzy rozświetlają pokój)
	wl.light_color = Color(0.55, 0.7, 1.0)
	wl.omni_range = 6.0
	wl.light_energy = 0.35
	wl.light_volumetric_fog_energy = 1.0
	wl.layers = light_layers
	wl.position = Vector3(0.0, yc, -1.2)
	root.add_child(wl)
	return [gm, wl]
