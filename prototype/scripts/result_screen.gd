extends Control
## Raport po akcji (RESULTS_PLAN.md): ekran po zakończonej misji zamiast dawnej statycznej karty wyniku.
##
## Kolejność odsłaniania: wynik (tytuł) → pieczątki celów („za co”, z nagrodą) → złom drużyny → twoje XP z paskiem poziomu
## i awansem → drużyna z wyróżnieniami i gotowością → znaleziska, rekordy, przebieg misji → akcje. Całość ok. 5,2 s, pierwsze
## naciśnięcie pomija do końca, „Ogranicz efekty” pokazuje od razu stan końcowy.
##
## Dane: `collect(mission)` zbiera wszystko z węzłów i autoloadów do słownika `ctx`, a statyczne `build_model(ctx)` liczy z niego
## czysty model (tytuł, pieczątki, liczniki, drużyna, czasy etapów) — test `--resulttest` sprawdza go bez rysowania.
## Animacja jest funkcją czasu `t` (`advance`), więc pominięcie to po prostu `t = end`.
##
## Każdy peer odtwarza raport sam; akcje rozstrzyga main.gd (`result_action`): host zmienia mapę, klient zgłasza gotowość.

const UiTheme := preload("res://scripts/ui_theme.gd")
const Mission := preload("res://scripts/mission.gd")
const Actions := preload("res://scripts/actions.gd")
const NightShift := preload("res://scripts/night_shift.gd")
const Parts := preload("res://scripts/parts.gd")
const Weapons := preload("res://scripts/weapons.gd")
const Codex := preload("res://scripts/codex.gd")
const Look := preload("res://scripts/look.gd")

## Czasy sekwencji (s od otwarcia) — wszystkie w jednym miejscu (RESULTS_PLAN.md §4).
const T_TITLE := 0.25
const T_SUB := 0.55
const SUB_DUR := 0.45
const T_TILES := 0.9
const TILE_GAP := 0.22
const T_SCRAP := 1.9
const SCRAP_DUR := 0.9
const T_XP := 2.8
const XP_DUR := 1.6
const T_SQUAD := 4.4
const SQUAD_GAP := 0.1
const T_AWARDS := 4.7
const AWARD_GAP := 0.15
const T_FINDS := 5.0
const FIND_GAP := 0.15
const T_DONE := 5.2
const STAMP_DUR := 0.16
const FADE_DUR := 0.22
const HUD_FADE := 0.3                 ## s, w których HUD rozgrywki gaśnie pod raportem
const INPUT_LOCK := 0.6               ## s od otwarcia, przez które raport ignoruje wejście (E z ekstrakcji, Enter z czatu)
const DATA_WAIT := 1.5                ## s, które etap złomu / XP czeka na dane od serwera, zanim pójdzie dalej bez nich
const TICK_GAP_MS := 50               ## licznik cyka najwyżej 20 razy na sekundę
const LEVEL_FLASH := 0.12             ## s rozjaśnienia paska przy awansie
const DIM := 0.65                     ## ściemnienie świata pod raportem

const PANEL_W := 880.0                ## szerokość panelu (jednostki logiczne HUD, ok. 2/3 ekranu przy skali NORMAL); większa skala UI zmniejsza raport, żeby się zmieścił
const PAD := 24.0
const FS := 1.4                       ## mnożnik krojów: HUD rysuje w ~0,48 (UI_SCALE × NORMAL), a raport ma mieć min. ~14 px przy 1080p
const XP_COL := Color(0.902, 0.886, 0.769)     ## liczba XP: kość (WARM)
const LOCKED := Color(0.42, 0.41, 0.37)        ## nagroda, której nie zdobyto

## Dźwięki raportu: [klucz manifestu, głośność dB] — wysokość podaje etap. Generator: tools/bake_sfx.py (build_ui).
const SND := {
	"stamp": ["ui_stamp", -6.0], "tick": ["ui_tick", -14.0], "type": ["ui_type", -18.0],
	"levelup": ["ui_levelup", -4.0], "skip": ["ui_confirm", -8.0], "record": ["radio_beep", -10.0],
}
## Kolory slotów graczy — te same co w HUD (hud.gd SLOT_COLORS, kurtki postaci).
const SLOT_COLORS := [Color(0.91, 0.62, 0.22), Color(0.25, 0.72, 0.85), Color(0.86, 0.28, 0.36), Color(0.45, 0.80, 0.30)]

## Przebieg misji (P2): rodzaj zdarzenia → [znak, kolor]. Kolejność = legenda.
const MARKS := {
	"objective": ["◆", Color(0.851, 0.573, 0.18)], "stash": ["◇", Color(0.851, 0.573, 0.18)], "boss": ["■", Color(0.898, 0.282, 0.227)],
	"woke": ["▲", Color(0.898, 0.282, 0.227)], "down": ["✕", Color(0.898, 0.282, 0.227)], "revive": ["✚", Color(0.541, 0.659, 0.475)],
	"escape": ["!", Color(0.902, 0.886, 0.769)], "lure": ["○", Color(0.435, 0.639, 0.608)], "extract": ["┃", Color(0.541, 0.659, 0.475)],
}
const MARK_NAMES := {"objective": "objective", "boss": "boss", "woke": "Stalker woke", "down": "down", "revive": "revive",
	"escape": "close call", "lure": "lure", "extract": "extraction"}

## Pasek poziomu: tło, wypełnienie i krótkie rozjaśnienie przy awansie.
class XpBar extends Control:
	var value := 0.0
	var flash := 0.0
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color("1a1b18"))
		draw_rect(Rect2(Vector2.ZERO, size), UiTheme.LINE, false, 1.0)
		var fill: Color = UiTheme.CALM.lerp(UiTheme.WARM, clampf(flash, 0.0, 1.0))
		draw_rect(Rect2(Vector2(1, 1), Vector2(maxf(0.0, (size.x - 2.0) * clampf(value, 0.0, 1.0)), size.y - 2.0)), fill)

## Przebieg misji jako taśma: oś czasu i znaki zdarzeń (RESULTS_PLAN.md P2, wzór: dziennik Hunt: Showdown).
class RunStrip extends Control:
	var length := 1.0
	var marks: Array = []                 ## [[t, kind, slot]]
	var reveal := 1.0                     ## 0..1 — taśma „przewija się” razem z sekwencją
	var font: Font
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		var y := size.y * 0.5
		var w := size.x * clampf(reveal, 0.0, 1.0)
		draw_line(Vector2(0, y), Vector2(size.x, y), UiTheme.HAIR, 1.0)
		draw_line(Vector2(0, y), Vector2(w, y), UiTheme.LINE.lightened(0.25), 1.0)
		for i in 5:
			var tx := size.x * float(i) / 4.0
			draw_line(Vector2(tx, y - 2.0), Vector2(tx, y + 2.0), UiTheme.LINE.lightened(0.25), 1.0)
		if font == null:
			return
		for mk in marks:
			var fx: float = size.x * clampf(float(mk[0]) / maxf(1.0, length), 0.0, 1.0)
			if fx > w + 0.5:
				continue
			var spec: Array = MARKS.get(String(mk[1]), ["·", UiTheme.TEXT])
			var glyph: String = spec[0]
			var gs := font.get_string_size(glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, 13)
			draw_string(font, Vector2(fx - gs.x * 0.5, y + 5.0), glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, spec[1])

var model: Dictionary = {}
var t := 0.0                          ## czas sekwencji (zatrzymuje się, gdy etap czeka na dane)
var _age := 0.0                       ## czas od otwarcia (płynie zawsze — blokada wejścia)
var hold_at := -1.0                   ## dev (--shotresultt=S): sekwencja staje w chwili S — zrzut z połowy animacji
var _waited := 0.0
var _skipped := false
var _mission: Node = null
var _ctx_sig := 0
var _ctx_t := 0.0
var _anims: Array = []                ## [{node, t, kind}] — „fade” (alfa), „stamp” (alfa + skala), „title”
var _cues: Array = []                 ## [{t, snd, pitch}] — dźwięki etapów, każdy raz
var _cue_i := 0
var _last_tick_ms := 0
var _scrap_shown := -1
var _xp_shown := -1

var _panel: PanelContainer
var _sub: Label
var _scrap_val: Label
var _scrap_rows: Array = []           ## [[Label wiersza, próg licznika]]
var _xp_val: Label
var _xp_rows: Array = []
var _xp_bar: XpBar
var _lv_lo: Label
var _lv_hi: Label
var _strip: RunStrip
var _prompt_box: HBoxContainer
var _skip_hint: Label
var _ready_note: Label

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false

# ---------------------------------------------------------------- otwieranie i stan

## Otwiera raport dla bieżącej misji (faza SUCCESS albo FAILED). Sekwencja startuje od zera.
func open(m: Node) -> void:
	_mission = m
	t = 0.0
	_age = 0.0
	_waited = 0.0
	_skipped = Settings.fx_mult() <= 0.0
	_cue_i = 0
	_scrap_shown = -1
	_xp_shown = -1
	var ctx := collect(m)
	_ctx_sig = hash(_sig_of(ctx))
	model = build_model(ctx)
	_rebuild()
	if _skipped:
		t = float(model["end_t"])
		_cue_i = _cues.size()
	visible = true
	_animate()

func close() -> void:
	visible = false
	_mission = null

## Czy sekwencja doszła do końca (albo została pominięta).
func is_done() -> bool:
	return not model.is_empty() and t >= float(model["end_t"]) - 0.0001

## 1 = HUD rozgrywki widoczny, 0 = schowany pod raportem.
func hud_fade() -> float:
	if not visible:
		return 1.0
	return 0.0 if _skipped else 1.0 - clampf(_age / HUD_FADE, 0.0, 1.0)

## Ściemnienie świata pod raportem (0..DIM).
func dim_alpha() -> float:
	if not visible:
		return 0.0
	return DIM if _skipped else DIM * clampf(_age / 0.4, 0.0, 1.0)

## Krok sekwencji. Etap złomu / XP czeka do DATA_WAIT s na dane od serwera; potem idzie dalej, a wartość dolicza się bez animacji.
func advance(delta: float) -> void:
	if model.is_empty():
		return
	_age += delta
	var end: float = float(model["end_t"])
	if hold_at >= 0.0:
		end = minf(end, hold_at)
	if t < end:
		var wait_scrap: bool = bool(model["scrap"]["show"]) and not bool(model["scrap"]["ready"]) and t >= T_SCRAP
		var wait_xp: bool = bool(model["xp"]["show"]) and not bool(model["xp"]["ready"]) and t >= T_XP
		if (wait_scrap or wait_xp) and _waited < DATA_WAIT:
			_waited += delta
		else:
			t = minf(end, t + delta)
	_fire_cues()

## Pierwsze naciśnięcie w trakcie sekwencji: stan końcowy od razu (jeden dźwięk zamiast wszystkich zaległych).
func skip() -> void:
	if model.is_empty() or is_done():
		return
	t = float(model["end_t"])
	_age = maxf(_age, HUD_FADE)
	_skipped = true
	_cue_i = _cues.size()
	_play("skip")
	_animate()

## Akcja raportu („continue” albo „next”). Zwraca, co się stało: "locked", "skipped" albo "act".
func press(kind: String) -> String:
	if not visible or model.is_empty():
		return "locked"
	if _age < INPUT_LOCK:
		return "locked"
	if not is_done():
		skip()
		return "skipped"
	var main := get_tree().current_scene
	if main != null and main.has_method("result_action"):
		main.result_action(kind)
	return "act"

func _unhandled_input(event: InputEvent) -> void:
	if not visible or not is_visible_in_tree():
		return
	if event.is_action_pressed("result_continue") or event.is_action_pressed("restart"):
		press("continue")
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("result_next"):
		press("next")
		get_viewport().set_input_as_handled()

## Co klatkę (HUD): dane, które dochodzą później (XP, złom, gotowość, statystyki) przebudowują raport bez zmiany czasu sekwencji.
func refresh(delta: float) -> void:
	if _mission == null or not is_instance_valid(_mission):
		return
	_ctx_t -= delta
	if _ctx_t <= 0.0:
		_ctx_t = 0.2
		var ctx := collect(_mission)
		var sig := hash(_sig_of(ctx))
		if sig != _ctx_sig:
			_ctx_sig = sig
			model = build_model(ctx)
			_rebuild()
			_cue_i = 0
			while _cue_i < _cues.size() and float(_cues[_cue_i]["t"]) <= t:
				_cue_i += 1                        # dźwięki, które już zagrały, nie grają drugi raz
	advance(delta)
	_animate()

func _sig_of(ctx: Dictionary) -> String:
	return str([ctx["players"], ctx["xp"]["ready"], ctx["xp"]["end"], ctx["scrap_info"], ctx["levels"], ctx["record"], ctx["gains"], Actions.pad_mode,
		TranslationServer.get_locale()])

# ---------------------------------------------------------------- dane

## Zbiera dane raportu z misji i autoloadów (każdy peer ma je lokalnie: replikowane albo z własnego profilu).
func collect(m: Node) -> Dictionary:
	var lvl := get_tree().get_first_node_in_group("level")
	var map_id := String(lvl.map_id) if lvl != null else ""
	var success: bool = int(m.phase) == Mission.Phase.SUCCESS
	var xp_ready: bool = success and Profile.result_ms > 0 and Profile.result_ms >= _open_ms() - 5000
	var players: Array = []
	var ids: Array = (m.player_stats as Dictionary).keys()
	ids.sort()
	var peers: Array = Array(multiplayer.get_peers()) if multiplayer.has_multiplayer_peer() else []
	for id in ids:
		var st: Dictionary = m.player_stats[id]
		var nm := String(st.get("name", "P1"))
		players.append({"id": int(id), "call": String(st.get("call", nm)), "slot": clampi(int(nm.substr(1)) - 1, 0, 3) if nm.begins_with("P") else 0,
			"kills": int(st.get("kills", 0)), "downs": int(st.get("downs", 0)), "revives": int(st.get("revives", 0)),
			"me": int(id) == NoiseMgr.local_id(), "host": int(id) == 1, "ready": bool((m.result_ready as Dictionary).get(int(id), false)),
			"gone": int(id) != 1 and int(id) != NoiseMgr.local_id() and not peers.is_empty() and not peers.has(int(id))})
	var main := get_tree().current_scene
	var demo_last := false
	if Settings.DEMO and lvl != null:
		demo_last = (int(m.phase) == Mission.Phase.FAILED or m.shift_complete()) if NightShift.active else map_id == String(lvl.CAMPAIGN[lvl.CAMPAIGN.size() - 1])
	return {
		"success": success, "kind": String(m.kind), "map_id": map_id, "map_title": String(lvl.title) if lvl != null else "",
		"difficulty": String(Difficulty.level_name()), "elapsed": float(m.elapsed), "downs": int(m.downs), "attempts": int(m.attempts),
		"goal_total": int(m.goal_total), "nests_total": int(m.nests_total), "stash_found": int(m.stashes_found), "stash_total": int(m.stash_total),
		"peak": float(m.peak_noise), "silent_counts": bool(m.silent_counts()), "silent_ok": bool(m.silent_ok()), "silent_cap": int(m.SILENT_CAP),
		"stealth_cap": int(m.STEALTH_CAP), "side_done": bool(m.side_done()),
		"night": {"active": NightShift.active, "stage": NightShift.stage, "missions": NightShift.MISSIONS, "cleared": int(m.shift_cleared),
			"time": float(m.shift_time), "downs": int(m.shift_downs), "record": bool(m.shift_record), "complete": bool(m.shift_complete()),
			"best_c": int(Settings.shift_best_cleared), "best_t": float(Settings.shift_best_time)},
		"scrap_enabled": Scrap.enabled() and not NightShift.active, "scrap_info": (m.result_info as Dictionary).duplicate(true),
		"xp": {"ready": xp_ready, "mission": Profile.last_mission_xp, "run": Profile.last_run_xp, "rows": Profile.last_mission_rows.duplicate(true),
			"end": Profile.xp},
		"record": Profile.last_record.duplicate() if success else {}, "gains": Profile.mission_gains() if success else {},
		"players": players, "awards": Mission.awards(m.player_stats, bool(m.stalker_woke)), "levels": (m.result_levels as Dictionary).duplicate(),
		"timeline": (m.result_info as Dictionary).get("timeline", []),
		"companion": main == null or main.get("companion_on") != false, "server": not multiplayer.has_multiplayer_peer() or multiplayer.is_server(),
		"local_ready": bool((m.result_ready as Dictionary).get(NoiseMgr.local_id(), false)), "demo_last": demo_last,
	}

func _open_ms() -> int:
	return Time.get_ticks_msec() - int(_age * 1000.0)

static func _tr(s: String) -> String:
	return TranslationServer.translate(s)

static func mmss(secs: float) -> String:
	var s := int(secs)
	return "%d:%02d" % [s / 60, s % 60]

## Czysty model raportu z `ctx` (collect). Teksty już przetłumaczone; czasy etapów wyliczone (pieczątki, awanse, znaleziska, koniec).
static func build_model(ctx: Dictionary) -> Dictionary:
	var night: Dictionary = ctx["night"]
	var success: bool = ctx["success"]
	var kind := String(ctx["kind"])
	var md := {"success": success, "night": bool(night["active"])}
	# --- tytuł i podpis
	var title := "EXTRACTION COMPLETE"
	var sub := "The squad made it out of the woods."
	var col: Color = UiTheme.OK
	if bool(night["active"]):
		if not success:
			title = "SERIES BROKEN"
			sub = "The night took the squad."
			col = UiTheme.DANGER
		elif bool(night["complete"]):
			title = "SHIFT COMPLETE"
			sub = "The whole night, survived."
		else:
			title = _tr("MISSION %d CLEARED") % int(night["stage"])
			sub = "Night Shift — the next one is harder."
	elif kind == "tags":
		sub = "The patrol's tags are with the squad — time to go home."
	elif kind == "boss":
		title = "THE LEECH IS DEAD"
		sub = "The hall is quiet again — only the water drips."
	elif kind == "generators":
		sub = "The broadcast is over — the squad is out."
	md["title"] = _tr(title)
	md["sub"] = _tr(sub)
	md["color"] = col
	var head := [_tr("AFTER-ACTION REPORT")]
	if String(ctx["map_title"]) != "":
		head.append(_tr(String(ctx["map_title"])))
	head.append(_tr(String(ctx["difficulty"])))
	md["header_l"] = "  ·  ".join(head).to_upper()
	if bool(night["active"]):
		md["header_r"] = (_tr("SERIES %s") % mmss(float(night["time"]))).to_upper()
	else:
		md["header_r"] = (_tr("ATTEMPT #%d") % int(ctx["attempts"]) + "  ·  " + _tr("TIME %s") % mmss(float(ctx["elapsed"]))).to_upper()
	# --- pieczątki celów (albo drabinka Nocnego Dyżuru)
	var tiles: Array = []
	if bool(night["active"]):
		for i in int(night["missions"]):
			var n := i + 1
			var done: bool = n <= int(night["cleared"])
			var cur: bool = n == int(night["stage"])
			tiles.append({"id": "stage", "label": _tr("MISSION %d") % n, "what": _tr("cleared") if done else (_tr("fell here") if cur and not success else "—"),
				"value": "✓" if done else ("✕" if cur and not success else "·"), "ok": done, "xp": 0, "scrap": 0, "stamp": done or (cur and not success)})
	elif success:
		var main_what: String = {"tags": "Dog tags", "generators": "Generators started", "boss": "The Leech", "nests": "Nests destroyed"}.get(kind, "Nests destroyed")
		var main_val := "%d / %d" % [int(ctx["goal_total"]), int(ctx["goal_total"])]
		if kind == "boss":
			main_val = _tr("slain")
		elif kind == "nests":
			main_val = "%d / %d" % [int(ctx["nests_total"]), int(ctx["nests_total"])]
		tiles.append({"id": "main", "label": _tr("MAIN OBJECTIVE"), "what": _tr(main_what), "value": main_val, "ok": true,
			"xp": Profile.XP_MISSION + (Profile.XP_BOSS if kind == "boss" else 0), "scrap": Scrap.BONUS_CLEAR, "stamp": true})
		if kind == "tags" and int(ctx["stash_total"]) > 0:
			tiles.append({"id": "side", "label": _tr("SIDE OBJECTIVE"), "what": _tr("Hidden stashes"),
				"value": "%d / %d" % [int(ctx["stash_found"]), int(ctx["stash_total"])], "ok": bool(ctx["side_done"]), "xp": Profile.XP_SIDE,
				"scrap": Scrap.BONUS_SIDE, "stamp": true})
		elif kind == "generators":
			tiles.append({"id": "side", "label": _tr("STEALTH"), "what": _tr("Attention below %d") % int(ctx["stealth_cap"]),
				"value": _tr("peak %d") % int(ctx["peak"]), "ok": bool(ctx["side_done"]), "xp": Profile.XP_SIDE, "scrap": Scrap.BONUS_SIDE, "stamp": true})
		elif kind == "nests":
			tiles.append({"id": "vein", "label": _tr("THE VEIN"), "what": _tr("Brood mother"), "value": _tr("slain"), "ok": true, "xp": 0, "scrap": 0,
				"stamp": true})
		tiles.append({"id": "no_downs", "label": _tr("NO DOWNS"), "what": _tr("Squad downs"), "value": str(int(ctx["downs"])), "ok": int(ctx["downs"]) == 0,
			"xp": Profile.XP_NO_DOWNS, "scrap": Scrap.BONUS_NO_DOWNS, "stamp": true})
		if bool(ctx["silent_counts"]):
			tiles.append({"id": "silent", "label": _tr("SILENT RUN"), "what": _tr("Attention peak (limit %d)") % int(ctx["silent_cap"]),
				"value": str(int(ctx["peak"])), "ok": bool(ctx["silent_ok"]), "xp": 0, "scrap": Scrap.BONUS_SILENT, "stamp": true})
	var scrap_on: bool = bool(ctx["scrap_enabled"]) and success
	for i in tiles.size():
		var tl: Dictionary = tiles[i]
		tl["t"] = T_TILES + TILE_GAP * float(i)
		var parts: Array = []
		if int(tl["xp"]) > 0:
			parts.append("+%d XP" % int(tl["xp"]))
		if int(tl["scrap"]) > 0 and scrap_on:
			parts.append(_tr("+%d scrap") % int(tl["scrap"]))
		var rw := "   ".join(parts)
		tl["reward"] = rw if bool(tl["ok"]) or rw == "" else _tr("missed: %s") % rw
	md["tiles"] = tiles
	md["ladder"] = bool(night["active"])
	# --- złom drużyny: łup + premie (rozbicie od serwera w mission.result_info)
	var info: Dictionary = ctx["scrap_info"]
	var scrap := {"show": scrap_on, "ready": info.has("gain"), "total": int(info.get("gain", 0)), "rows": []}
	if scrap_on and info.has("gain"):
		var bonus := 0
		var rows: Array = []
		for b in Array(info.get("bonus", [])):
			bonus += int(b[1])
			rows.append([_tr({"clear": "bonus: mission", "side": "bonus: side objective", "no_downs": "bonus: no downs", "silent": "bonus: silent run"}.get(String(b[0]), String(b[0]))), int(b[1])])
		rows.push_front([_tr("mission loot"), maxi(0, int(info["gain"]) - bonus)])
		scrap["rows"] = rows
	md["scrap"] = scrap
	# --- XP gracza: licznik od (koniec − zdobyte) do końca, przelania poziomów z czasem i odblokowaniami
	var xd: Dictionary = ctx["xp"]
	var earned: int = int(xd["mission"]) + int(xd["run"])
	var xp := {"show": success, "ready": bool(xd["ready"]), "earned": earned, "end": int(xd["end"]), "start": maxi(0, int(xd["end"]) - earned),
		"rows": [], "levels": []}
	if success and bool(xd["ready"]):
		var rows: Array = []
		for r in Array(xd["rows"]):
			rows.append([_tr(String(r[0])).to_lower(), int(r[1])])
		if bool(night["active"]) and not rows.is_empty():
			rows = [[_tr("night shift (half)"), int(xd["mission"])]]
		if int(xd["run"]) > 0:
			rows.append([_tr("kills and revives"), int(xd["run"])])
		xp["rows"] = rows
		var lv0 := Profile.level_of(int(xp["start"]))
		var lv1 := Profile.level_of(int(xp["end"]))
		for lv in range(lv0 + 1, lv1 + 1):
			var q := clampf(float(Profile.xp_for_level(lv) - int(xp["start"])) / float(maxi(1, earned)), 0.0, 1.0)
			var tl := T_XP + (1.0 - pow(1.0 - q, 1.0 / 3.0)) * XP_DUR               # odwrotność ease-out cubic licznika
			xp["levels"].append({"lv": lv, "t": tl, "unlocks": unlocks_at(lv)})
	md["xp"] = xp
	# --- drużyna: wiersze z wyróżnieniami-pieczątkami i stanem gotowości
	var by_id := {}
	for a in Array(ctx["awards"]):
		var pid: int = int(a[3]) if (a as Array).size() > 3 else -1
		var aid := String(a[0])
		var note := _tr(String(Mission.AWARD_NOTES[aid]))
		var why: String = note if aid == "ghost" else "%s: %d" % [note, int(a[2])]
		if not by_id.has(pid):
			by_id[pid] = []
		(by_id[pid] as Array).append({"title": _tr(String(Mission.AWARD_TITLES[aid])), "why": why, "kind": "award"})
	var squad: Array = []
	var players: Array = ctx["players"]
	var solo := players.size() <= 1
	var levels: Dictionary = ctx["levels"]
	var k := 0
	var others := 0
	var ready_n := 0
	for i in players.size():
		var p: Dictionary = players[i]
		var aws: Array = (by_id.get(int(p["id"]), []) as Array).duplicate()
		if not bool(p["me"]) and levels.has(int(p["id"])):
			var lvp: Array = levels[int(p["id"])]
			if int(lvp[1]) > int(lvp[0]):
				aws.append({"title": _tr("LEVEL UP"), "why": "→ %d" % int(lvp[1]), "kind": "level"})
		for a in aws:
			(a as Dictionary)["t"] = T_AWARDS + AWARD_GAP * float(k)
			k += 1
		var status := ""
		var scol: Color = UiTheme.MUTED
		if solo:
			status = _tr("SOLO")
		elif bool(p["host"]):
			status = _tr("HOST")
		elif bool(p["gone"]):
			status = _tr("disconnected")
			scol = UiTheme.DANGER
		elif bool(p["ready"]):
			status = _tr("READY")
			scol = UiTheme.OK
		else:
			status = _tr("reading…")
		if not bool(p["host"]) and not bool(p["gone"]):
			others += 1
			if bool(p["ready"]):
				ready_n += 1
		var nm := String(p["call"])
		squad.append({"id": int(p["id"]), "name": (_tr("%s  (you)") % nm) if bool(p["me"]) else nm, "slot": int(p["slot"]), "me": bool(p["me"]),
			"kills": int(p["kills"]), "downs": int(p["downs"]), "revives": int(p["revives"]), "status": status, "status_col": scol,
			"gone": bool(p["gone"]), "awards": aws, "t": T_SQUAD + SQUAD_GAP * float(i)})
	md["squad"] = squad
	# --- znaleziska, rekordy, wprawa, kodeks
	var finds: Array = []
	if success and not bool(night["active"]):
		var rec: Dictionary = ctx["record"]
		if bool(rec.get("first", false)):
			finds.append({"text": _tr("FIRST CLEAR"), "stamp": true, "color": UiTheme.ACCENT})
		elif bool(rec.get("new", false)) and float(rec.get("prev", 0.0)) > 0.0:
			finds.append({"text": _tr("NEW RECORD %s") % mmss(float(rec["time"])), "why": _tr("(was %s)") % mmss(float(rec["prev"])), "stamp": true,
				"color": UiTheme.DANGER, "snd": "record"})
		var fi: Dictionary = info.get("finds", {})
		for pid in Array(fi.get("parts", [])):
			var pd := Parts.get_part(String(pid))
			finds.append({"text": _tr("NEW PART: %s") % _tr(String(pd.get("name", pid))), "stamp": false, "color": UiTheme.TEXT})
		if int(fi.get("samples", 0)) > 0:
			finds.append({"text": _tr("+%d lab sample") % int(fi["samples"]), "stamp": false, "color": UiTheme.TEXT})
		if int(fi.get("batteries", 0)) > 0:
			finds.append({"text": _tr("4.5 V batteries picked up: %d") % int(fi["batteries"]), "stamp": false, "color": UiTheme.TEXT})
		if bool(fi.get("trophy", false)):
			finds.append({"text": _tr("TROPHY WEAPON UNLOCKED"), "stamp": false, "color": UiTheme.ACCENT})
		var gains: Dictionary = ctx["gains"]
		for g in Array(gains.get("mastery", [])):
			var wid := Weapons.index_of(String(g[0]))
			var wn: String = String(Weapons.base_def(wid).name) if Weapons.is_valid(wid) else String(g[0]).to_upper()
			finds.append({"text": _tr("%s: mastery %d → %d") % [wn, int(g[1]), int(g[2])], "stamp": false, "color": UiTheme.TEXT})
		for b in Array(gains.get("beasts", [])):
			finds.append({"text": _tr("NEW CODEX ENTRY: %s") % _tr(Codex.beast_name(String(b))), "stamp": false, "color": UiTheme.TEXT})
	elif bool(night["active"]) and bool(night["record"]):
		finds.append({"text": _tr("NEW RECORD"), "stamp": true, "color": UiTheme.DANGER, "snd": "record"})
	for i in finds.size():
		(finds[i] as Dictionary)["t"] = T_FINDS + FIND_GAP * float(i)
	md["finds"] = finds
	# --- przebieg misji
	var marks: Array = ctx["timeline"]
	md["timeline"] = {"show": success and not bool(night["active"]) and not marks.is_empty(), "len": float(ctx["elapsed"]), "marks": marks}
	# --- stopka i akcje
	var foot: Array = []
	if bool(night["active"]):
		foot.append(_tr("Missions cleared %d / %d") % [int(night["cleared"]), int(night["missions"])])
		foot.append(_tr("Squad downs %d") % int(night["downs"]))
		if int(night["best_c"]) > 0:
			foot.append(_tr("Best %d / %d") % [int(night["best_c"]), int(night["missions"])] + ((" · " + mmss(float(night["best_t"]))) if float(night["best_t"]) > 0.0 else ""))
	else:
		foot.append(_tr("AI companion: %s") % _tr("on" if bool(ctx["companion"]) else "off"))
		if not solo:
			foot.append(_tr("%d players") % players.size())
		var rec2: Dictionary = ctx["record"]
		if float(rec2.get("best", 0.0)) > 0.0 and not bool(rec2.get("new", false)):
			foot.append(_tr("Map record %s") % mmss(float(rec2["best"])))
	md["foot_l"] = "  ·  ".join(foot)
	var prompts: Array = []
	var note := ""
	if bool(ctx["server"]):
		if bool(night["active"]):
			prompts.append({"kind": "continue", "action": "result_continue", "label": _tr("New shift" if (not success or bool(night["complete"])) else "Next mission")})
		elif success:
			prompts.append({"kind": "continue", "action": "result_continue", "label": _tr("Safe room")})
			prompts.append({"kind": "next", "action": "result_next", "label": _tr("Next mission now")})
		else:
			prompts.append({"kind": "continue", "action": "result_continue", "label": _tr("Continue")})
		if others > 0:
			note = _tr("%d / %d ready") % [ready_n, others]
	elif bool(ctx["local_ready"]):
		note = _tr("Waiting for the host to continue…")
	else:
		prompts.append({"kind": "continue", "action": "result_continue", "label": _tr("Ready")})
	md["prompts"] = prompts
	md["ready_note"] = note
	md["demo_footer"] = bool(ctx["demo_last"])
	# --- koniec sekwencji: ostatnia pieczątka (+ czas jej „przybicia”) albo T_DONE
	var end := T_DONE
	for a_row in squad:
		for a in Array((a_row as Dictionary)["awards"]):
			end = maxf(end, float((a as Dictionary)["t"]) + STAMP_DUR)
	for f in finds:
		end = maxf(end, float((f as Dictionary)["t"]) + STAMP_DUR)
	for lv in Array(xp["levels"]):
		end = maxf(end, float((lv as Dictionary)["t"]) + 0.5)
	md["end_t"] = end
	return md

## Co odblokowuje poziom `lv`: slot perka, perki, stroje i barwy (te same tabele co menu PERKS i ekran wyglądu).
static func unlocks_at(lv: int) -> Array:
	var out: Array = []
	if Profile.SLOT_LEVELS.has(lv):
		out.append(_tr("perk slot %d") % (Profile.SLOT_LEVELS.find(lv) + 1))
	for id in Profile.Perks.unlocked_at(lv):
		out.append(_tr("perk %s") % _tr(Profile.Perks.display_name(String(id))))
	for o in Look.UNLOCK_LEVEL:
		if int(Look.UNLOCK_LEVEL[o]) == lv and lv > 1:
			out.append(_tr("outfit %s") % _tr(String(Look.OUTFIT_NAMES[o])))
	for p in Look.PALETTES:
		if int(p["level"]) == lv and lv > 1:
			out.append(_tr("colours %s") % _tr(String(p["name"])))
	return out

# ---------------------------------------------------------------- budowa widoku

func _rebuild() -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()
	_anims.clear()
	_cues.clear()
	_scrap_rows.clear()
	_xp_rows.clear()
	_panel = PanelContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.custom_minimum_size = Vector2(PANEL_W, 0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.043, 0.047, 0.043, 0.96)
	sb.border_color = UiTheme.PANEL_EDGE
	sb.set_border_width_all(1)
	sb.border_width_bottom = 2
	sb.content_margin_left = PAD
	sb.content_margin_right = PAD
	sb.content_margin_top = 14
	sb.content_margin_bottom = 10
	sb.shadow_color = Color(0, 0, 0, 0.55)
	sb.shadow_size = 18
	_panel.add_theme_stylebox_override("panel", sb)
	add_child(_panel)
	_anim(_panel, 0.1, "fade")
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 9)
	_panel.add_child(col)
	# A — nagłówek
	var head := HBoxContainer.new()
	head.add_child(UiTheme.mono(UiTheme.label(String(model["header_l"]), _f(7), UiTheme.MUTED)))
	head.add_child(_spacer())
	head.add_child(UiTheme.mono(UiTheme.label(String(model["header_r"]), _f(7), UiTheme.MUTED, HORIZONTAL_ALIGNMENT_RIGHT)))
	col.add_child(head)
	col.add_child(_rule())
	# B — tytuł (bohater pierwszych 0,6 s) i podpis maszynopisem
	var title := UiTheme.heading(String(model["title"]), _f(34), Color(model["color"]).lightened(0.12), HORIZONTAL_ALIGNMENT_CENTER)
	col.add_child(title)
	_anim(title, T_TITLE, "title")
	_cue(T_TITLE, "stamp", 0.85)
	_sub = UiTheme.whisper(UiTheme.label(String(model["sub"]), _f(10), UiTheme.BONE_DIM, HORIZONTAL_ALIGNMENT_CENTER))
	col.add_child(_sub)
	for i in 6:
		_cue(T_SUB + SUB_DUR * float(i) / 6.0, "type", 0.9 + 0.05 * float(i % 3))
	# C — pieczątki celów
	var tiles: Array = model["tiles"]
	if not tiles.is_empty():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		for i in tiles.size():
			row.add_child(_tile(tiles[i], i))
		col.add_child(row)
	# D — drużyna | łup
	var lower := HBoxContainer.new()
	lower.add_theme_constant_override("separation", 20)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 1.18
	left.add_theme_constant_override("separation", 4)
	_build_squad(left)
	lower.add_child(left)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 5)
	_build_loot(right)
	if right.get_child_count() > 0:
		lower.add_child(right)
	else:
		right.free()
	col.add_child(lower)
	# przebieg misji (P2)
	var tl: Dictionary = model["timeline"]
	if bool(tl["show"]):
		col.add_child(_build_strip(tl))
	# F — stopka i akcje
	col.add_child(_rule())
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 12)
	var fl := UiTheme.mono(UiTheme.label(String(model["foot_l"]), _f(7), UiTheme.MUTED))
	fl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	foot.add_child(fl)
	foot.add_child(_spacer())
	_ready_note = UiTheme.mono(UiTheme.label(String(model["ready_note"]), _f(7), UiTheme.MUTED, HORIZONTAL_ALIGNMENT_RIGHT))
	_ready_note.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	foot.add_child(_ready_note)
	_skip_hint = UiTheme.label("[%s]  %s" % [Actions.key("result_continue"), tr("Skip")], _f(9), UiTheme.MUTED, HORIZONTAL_ALIGNMENT_RIGHT)
	foot.add_child(_skip_hint)
	_prompt_box = HBoxContainer.new()
	_prompt_box.add_theme_constant_override("separation", 14)
	for p in Array(model["prompts"]):
		var b := Button.new()
		b.flat = true
		b.focus_mode = Control.FOCUS_NONE
		b.text = "[%s]  %s" % [Actions.key(String(p["action"])), String(p["label"])]
		b.add_theme_font_size_override("font_size", _f(10))
		for st in ["font_color", "font_hover_color", "font_pressed_color"]:
			b.add_theme_color_override(st, UiTheme.ACCENT if st == "font_color" else UiTheme.WARM)
		var kind := String(p["kind"])
		b.pressed.connect(func() -> void: press(kind))
		_prompt_box.add_child(b)
	foot.add_child(_prompt_box)
	col.add_child(foot)
	if bool(model["demo_footer"]):
		col.add_child(_rule())
		col.add_child(UiTheme.heading("THANKS FOR PLAYING THE DEMO", _f(8), UiTheme.TEXT, HORIZONTAL_ALIGNMENT_CENTER))
		col.add_child(UiTheme.label("Wishlist DEAD AIR '87 on Steam — more zones, weapons and monsters are coming.", _f(8), UiTheme.MUTED, HORIZONTAL_ALIGNMENT_CENTER))
		if Settings.STORE_URL != "":
			col.add_child(UiTheme.label(tr("[%s]  Open the Steam page") % Actions.key("open_store"), _f(8), UiTheme.ACCENT, HORIZONTAL_ALIGNMENT_CENTER))
	_cues.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["t"]) < float(b["t"]))
	_layout()

func _tile(td: Dictionary, i: int) -> Control:
	var ok: bool = td["ok"]
	var tile := PanelContainer.new()
	tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tile.custom_minimum_size = Vector2(0, 42 if bool(model["ladder"]) else 86)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("0e0f0d")
	sb.border_color = Color(UiTheme.OK, 0.5) if ok else UiTheme.LINE
	sb.set_border_width_all(1)
	sb.set_content_margin_all(10)
	tile.add_theme_stylebox_override("panel", sb)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 1)
	tile.add_child(box)
	var top := HBoxContainer.new()
	var lab := UiTheme.heading(String(td["label"]), _f(9), UiTheme.TEXT if ok else UiTheme.MUTED)
	lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lab.clip_text = true
	top.add_child(lab)
	if bool(td.get("stamp", true)):
		var stamp := _stamp(_tr("CLEARED") if ok else _tr("LOST"), UiTheme.OK if ok else UiTheme.DANGER, _f(8), 1)
		stamp.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		top.add_child(stamp)
		stamp.rotation = deg_to_rad(-7.0 + 3.0 * float(i % 4))
		_anim(stamp, float(td["t"]) + 0.08, "stamp")
	box.add_child(top)
	if not bool(model["ladder"]):
		box.add_child(UiTheme.label(String(td["what"]), _f(7), UiTheme.MUTED))
		box.add_child(UiTheme.mono(UiTheme.label(String(td["value"]), _f(12), UiTheme.WARM if ok else UiTheme.MUTED)))
		if String(td["reward"]) != "":
			box.add_child(UiTheme.mono(UiTheme.label(String(td["reward"]), _f(7), UiTheme.ACCENT if ok else LOCKED)))
	else:
		box.add_child(UiTheme.label(String(td["what"]), _f(7), UiTheme.MUTED))
	_anim(tile, float(td["t"]), "fade")
	if ok:
		_cue(float(td["t"]) + 0.08, "stamp", 1.0 + 0.06 * float(i))
	return tile

func _build_squad(box: VBoxContainer) -> void:
	var squad: Array = model["squad"]
	if squad.is_empty():
		return
	var head := HBoxContainer.new()
	head.add_child(UiTheme.mono(UiTheme.label(tr("SQUAD"), _f(7), UiTheme.MUTED)))
	head.add_child(_spacer())
	head.add_child(UiTheme.mono(UiTheme.label(tr("KILLS · DOWNS · REVIVES"), _f(7), UiTheme.MUTED, HORIZONTAL_ALIGNMENT_RIGHT)))
	box.add_child(head)
	_anim(head, T_SQUAD - 0.05, "fade")
	for p in squad:
		var pd: Dictionary = p
		var row := PanelContainer.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color("10110f")
		sb.border_color = UiTheme.LINE
		sb.set_border_width_all(1)
		var slot_col: Color = SLOT_COLORS[clampi(int(pd["slot"]), 0, 3)]
		sb.content_margin_left = 0
		sb.content_margin_right = 7
		sb.content_margin_top = 4
		sb.content_margin_bottom = 4
		row.add_theme_stylebox_override("panel", sb)
		var strip := ColorRect.new()                    # pasek koloru slotu przy lewej krawędzi
		strip.color = slot_col if not bool(pd["gone"]) else UiTheme.MUTED
		strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 8)
		strip.custom_minimum_size = Vector2(3, 0)
		hb.add_child(strip)
		var mid := VBoxContainer.new()
		mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mid.add_theme_constant_override("separation", 2)
		var top := HBoxContainer.new()
		top.add_theme_constant_override("separation", 6)
		var nm := UiTheme.label(String(pd["name"]), _f(10), UiTheme.ACCENT if bool(pd["me"]) else (UiTheme.MUTED if bool(pd["gone"]) else UiTheme.TEXT))
		nm.clip_text = true
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		top.add_child(nm)
		var stl := UiTheme.mono(UiTheme.label(String(pd["status"]), _f(7), Color(pd["status_col"]), HORIZONTAL_ALIGNMENT_RIGHT))
		stl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		top.add_child(stl)
		_anim(stl, T_DONE, "fade")
		mid.add_child(top)
		var aws: Array = pd["awards"]
		if not aws.is_empty():
			var flow := HFlowContainer.new()
			flow.add_theme_constant_override("h_separation", 5)
			flow.add_theme_constant_override("v_separation", 3)
			for a in aws:
				var ad: Dictionary = a
				var ac: Color = UiTheme.CALM if String(ad.get("kind", "")) == "level" else UiTheme.ACCENT
				var st := _stamp(String(ad["title"]), ac, _f(8), 1, String(ad["why"]))
				st.rotation = deg_to_rad(-2.5)
				flow.add_child(st)
				_anim(st, float(ad["t"]), "stamp")
				_cue(float(ad["t"]), "stamp", 0.8)
			mid.add_child(flow)
		hb.add_child(mid)
		var nums := UiTheme.mono(UiTheme.label("%d · %d · %d" % [int(pd["kills"]), int(pd["downs"]), int(pd["revives"])], _f(11), UiTheme.WARM, HORIZONTAL_ALIGNMENT_RIGHT))
		nums.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		hb.add_child(nums)
		row.add_child(hb)
		box.add_child(row)
		_anim(row, float(pd["t"]), "fade")

func _build_loot(box: VBoxContainer) -> void:
	var sc: Dictionary = model["scrap"]
	if bool(sc["show"]):
		var blk := VBoxContainer.new()
		blk.add_theme_constant_override("separation", 1)
		var h := HBoxContainer.new()
		var cap := UiTheme.mono(UiTheme.label(tr("SQUAD SCRAP"), _f(7), UiTheme.MUTED))
		cap.size_flags_vertical = Control.SIZE_SHRINK_END
		h.add_child(cap)
		h.add_child(_spacer())
		_scrap_val = UiTheme.mono(UiTheme.label("+0", _f(24), UiTheme.ACCENT, HORIZONTAL_ALIGNMENT_RIGHT))
		h.add_child(_scrap_val)
		blk.add_child(h)
		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 12)
		grid.add_theme_constant_override("v_separation", 0)
		var cum := 0
		for r in Array(sc["rows"]):
			var cell := _row_cell(String(r[0]), int(r[1]))
			grid.add_child(cell)
			_scrap_rows.append([cell, cum])
			cum += int(r[1])
		blk.add_child(grid)
		box.add_child(blk)
		_anim(blk, T_SCRAP - 0.05, "fade")
	var xd: Dictionary = model["xp"]
	if bool(xd["show"]):
		if bool(sc["show"]):
			box.add_child(_rule())
		var blk := VBoxContainer.new()
		blk.add_theme_constant_override("separation", 2)
		var h := HBoxContainer.new()
		var cap := UiTheme.mono(UiTheme.label(tr("YOUR XP"), _f(7), UiTheme.MUTED))
		cap.size_flags_vertical = Control.SIZE_SHRINK_END
		h.add_child(cap)
		h.add_child(_spacer())
		_xp_val = UiTheme.mono(UiTheme.label("+0", _f(24), XP_COL, HORIZONTAL_ALIGNMENT_RIGHT))
		h.add_child(_xp_val)
		blk.add_child(h)
		var bar_row := HBoxContainer.new()
		bar_row.add_theme_constant_override("separation", 6)
		_lv_lo = UiTheme.mono(UiTheme.label("LV 1", _f(7), UiTheme.BONE_DIM))
		bar_row.add_child(_lv_lo)
		_xp_bar = XpBar.new()
		_xp_bar.custom_minimum_size = Vector2(0, 9)
		_xp_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_xp_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar_row.add_child(_xp_bar)
		_lv_hi = UiTheme.mono(UiTheme.label("LV 2", _f(7), UiTheme.BONE_DIM, HORIZONTAL_ALIGNMENT_RIGHT))
		bar_row.add_child(_lv_hi)
		blk.add_child(bar_row)
		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 12)
		grid.add_theme_constant_override("v_separation", 0)
		var cum := 0
		for r in Array(xd["rows"]):
			var cell := _row_cell(String(r[0]), int(r[1]))
			grid.add_child(cell)
			_xp_rows.append([cell, cum])
			cum += int(r[1])
		blk.add_child(grid)
		for lv in Array(xd["levels"]):
			var ld: Dictionary = lv
			var lr := HFlowContainer.new()
			lr.add_theme_constant_override("h_separation", 8)
			var st := _stamp(tr("LEVEL UP · LEVEL %d") % int(ld["lv"]), UiTheme.ACCENT, _f(9), 2)
			st.rotation = deg_to_rad(-3.0)
			lr.add_child(st)
			_anim(st, float(ld["t"]) + 0.05, "stamp")
			_cue(float(ld["t"]), "levelup", 1.0)
			var un: Array = ld["unlocks"]
			if not un.is_empty():
				var ul := UiTheme.label(tr("Unlocked: %s") % ", ".join(un), _f(8), UiTheme.TEXT)
				ul.size_flags_vertical = Control.SIZE_SHRINK_CENTER
				lr.add_child(ul)
				_anim(ul, float(ld["t"]) + 0.35, "fade")
			blk.add_child(lr)
		box.add_child(blk)
		_anim(blk, T_XP - 0.05, "fade")
	var finds: Array = model["finds"]
	if not finds.is_empty():
		box.add_child(_rule())
		var flow := HFlowContainer.new()
		flow.add_theme_constant_override("h_separation", 10)
		flow.add_theme_constant_override("v_separation", 3)
		for f in finds:
			var fd: Dictionary = f
			var n: Control
			if bool(fd["stamp"]):
				n = _stamp(String(fd["text"]), Color(fd["color"]), _f(8), 1, String(fd.get("why", "")))
				n.rotation = deg_to_rad(-4.0)
				_anim(n, float(fd["t"]), "stamp")
				_cue(float(fd["t"]), String(fd.get("snd", "stamp")), 0.95)
			else:
				n = UiTheme.label("◆ " + String(fd["text"]), _f(8), Color(fd["color"]))
				_anim(n, float(fd["t"]), "fade")
			flow.add_child(n)
		box.add_child(flow)

func _build_strip(tl: Dictionary) -> Control:
	var blk := VBoxContainer.new()
	blk.add_theme_constant_override("separation", 1)
	var h := HBoxContainer.new()
	h.add_child(UiTheme.mono(UiTheme.label(tr("MISSION TIMELINE"), _f(7), UiTheme.MUTED)))
	h.add_child(_spacer())
	var seen := {}
	for mk in Array(tl["marks"]):
		seen[String(mk[1])] = true
	var legend: Array = []
	for k in MARK_NAMES:
		if seen.has(k):
			legend.append("%s %s" % [MARKS[k][0], tr(String(MARK_NAMES[k]))])
	h.add_child(UiTheme.label("   ".join(legend), _f(7), UiTheme.MUTED, HORIZONTAL_ALIGNMENT_RIGHT))
	h.add_child(UiTheme.mono(UiTheme.label("  " + mmss(float(tl["len"])), _f(7), UiTheme.MUTED)))
	blk.add_child(h)
	_strip = RunStrip.new()
	_strip.custom_minimum_size = Vector2(0, 18)
	_strip.length = float(tl["len"])
	_strip.marks = tl["marks"]
	_strip.font = UiTheme.mono_font()
	blk.add_child(_strip)
	_anim(blk, T_SQUAD, "fade")
	return blk

func _row_cell(label: String, v: int) -> Control:
	var hb := HBoxContainer.new()
	hb.custom_minimum_size = Vector2(170, 0)
	var l := UiTheme.label(label, _f(8), UiTheme.BONE_DIM)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.clip_text = true
	hb.add_child(l)
	hb.add_child(UiTheme.mono(UiTheme.label("+%d" % v, _f(8), UiTheme.BONE_DIM, HORIZONTAL_ALIGNMENT_RIGHT)))
	return hb

## Pieczątka: tekst w ramce koloru tuszu (rotację i „przybicie” ustawia wołający).
func _stamp(text: String, col: Color, fsize: int, border: int, why := "") -> Control:
	var pc := PanelContainer.new()
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(col, 0.06)
	sb.border_color = Color(col, 0.9)
	sb.set_border_width_all(border)
	sb.content_margin_left = 4
	sb.content_margin_right = 4
	sb.content_margin_top = 0
	sb.content_margin_bottom = 0
	pc.add_theme_stylebox_override("panel", sb)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 4)
	hb.add_child(UiTheme.heading(text, fsize, col))
	if why != "":
		var w := UiTheme.label(why, fsize, Color(col, 0.85))
		w.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		hb.add_child(w)
	pc.add_child(hb)
	return pc

func _rule() -> ColorRect:
	var r := ColorRect.new()
	r.color = UiTheme.HAIR
	r.custom_minimum_size = Vector2(0, 1)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r

func _spacer() -> Control:
	var s := Control.new()
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return s

func _anim(n: Control, t0: float, kind: String) -> void:
	_anims.append({"node": n, "t": t0, "kind": kind})

func _cue(t0: float, snd: String, pitch: float) -> void:
	_cues.append({"t": t0, "snd": snd, "pitch": pitch})

# ---------------------------------------------------------------- klatka

## Rozmiar i pozycja panelu: środek ekranu HUD, pomniejszony, gdy duża skala UI by go wypchnęła poza ekran.
func _layout() -> void:
	var host := get_parent() as Control
	var area: Vector2 = host.size if host != null else get_viewport_rect().size
	size = area
	position = Vector2.ZERO
	_panel.reset_size()
	var ps := _panel.get_combined_minimum_size()
	var k := minf(1.0, minf((area.x - 16.0) / maxf(1.0, ps.x), (area.y - 16.0) / maxf(1.0, ps.y)))
	_panel.scale = Vector2(k, k)
	_panel.position = ((area - ps * k) * 0.5).floor()

func _animate() -> void:
	if model.is_empty() or _panel == null:
		return
	_layout()
	for a in _anims:
		var n: Control = a["node"]
		if not is_instance_valid(n):
			continue
		var t0: float = a["t"]
		match String(a["kind"]):
			"fade":
				n.modulate.a = _ease(clampf((t - t0) / FADE_DUR, 0.0, 1.0))
			"title":
				var p := _ease(clampf((t - t0) / STAMP_DUR, 0.0, 1.0))
				n.modulate.a = p
				n.pivot_offset = n.size * 0.5
				n.scale = Vector2.ONE * lerpf(1.18, 1.0, p)
			"stamp":
				var p := _ease(clampf((t - t0) / STAMP_DUR, 0.0, 1.0))
				n.modulate.a = p
				n.pivot_offset = n.size * 0.5
				n.scale = Vector2.ONE * lerpf(1.35, 1.0, p)
	_sub.visible_ratio = clampf((t - T_SUB) / SUB_DUR, 0.0, 1.0)
	_drive_counters()
	var done := is_done()
	_prompt_box.modulate.a = 1.0 if done else 0.35
	_skip_hint.visible = not done
	if _strip != null:
		_strip.reveal = clampf((t - T_SQUAD) / 0.6, 0.0, 1.0)
		_strip.queue_redraw()

func _drive_counters() -> void:
	var sc: Dictionary = model["scrap"]
	if bool(sc["show"]) and _scrap_val != null:
		var p := _ease(clampf((t - T_SCRAP) / SCRAP_DUR, 0.0, 1.0))
		var v := int(round(float(sc["total"]) * p))
		_scrap_val.text = ("+%d" % v) if bool(sc["ready"]) else "…"
		for r in _scrap_rows:
			(r[0] as Control).modulate.a = 1.0 if v > int(r[1]) else 0.0
		if v != _scrap_shown:
			if _scrap_shown >= 0 and v > _scrap_shown:
				_tick(0.9 + 0.4 * p)
			_scrap_shown = v
	var xd: Dictionary = model["xp"]
	if bool(xd["show"]) and _xp_val != null:
		var p := _ease(clampf((t - T_XP) / XP_DUR, 0.0, 1.0))
		var gained := int(round(float(xd["earned"]) * p))
		var shown: int = int(xd["start"]) + gained
		_xp_val.text = ("+%d" % gained) if bool(xd["ready"]) else "…"
		var lv := Profile.level_of(shown)
		var lo := Profile.xp_for_level(lv)
		var hi := Profile.xp_for_level(lv + 1)
		_lv_lo.text = "LV %d" % lv
		_lv_hi.text = "LV %d" % (lv + 1)
		_xp_bar.value = float(shown - lo) / float(maxi(1, hi - lo)) if bool(xd["ready"]) else 0.0
		var fl := 0.0
		if not _skipped:
			for l in Array(xd["levels"]):
				var lt: float = (l as Dictionary)["t"]
				if t >= lt and t < lt + LEVEL_FLASH:
					fl = 1.0
		_xp_bar.flash = fl
		_xp_bar.queue_redraw()
		for r in _xp_rows:
			(r[0] as Control).modulate.a = 1.0 if gained > int(r[1]) else 0.0
		if gained != _xp_shown:
			if _xp_shown >= 0 and gained > _xp_shown:
				_tick(0.66 + 0.3 * p)
			_xp_shown = gained

func _tick(pitch: float) -> void:
	if _skipped:
		return
	var now := Time.get_ticks_msec()
	if now - _last_tick_ms < TICK_GAP_MS:
		return
	_last_tick_ms = now
	_play("tick", pitch)

func _fire_cues() -> void:
	while _cue_i < _cues.size() and float(_cues[_cue_i]["t"]) <= t:
		var c: Dictionary = _cues[_cue_i]
		_cue_i += 1
		if not _skipped:
			_play(String(c["snd"]), float(c["pitch"]))

func _play(id: String, pitch := 1.0) -> void:
	if not SND.has(id) or Audio == null:
		return
	var spec: Array = SND[id]
	Audio.play(String(spec[0]), Audio.BUS_UI, float(spec[1]), pitch)

static func _f(n: int) -> int:
	return int(round(float(n) * FS))

static func _ease(x: float) -> float:
	return 1.0 - pow(1.0 - x, 3.0)
