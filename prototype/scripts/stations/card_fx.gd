extends RefCounted
## Efekty karty stanowiska (WORKSHOP_IMMERSION_PLAN.md R0b): portfel z licznikiem bębnowym, dźwięk i błysk udanej operacji oraz
## zdarzenia Kryjówki na karcie (pukanie do D-7 — STATION_CARDS_PLAN.md §5; w R2 przejdzie do świata). Wydzielone z workshop_ui.gd
## bez zmiany zachowania; `ui` to panel, który woła te funkcje przez funkcje o tych samych nazwach.

const UiTheme := preload("res://scripts/ui_theme.gd")
const LabArt := preload("res://scripts/station_lab_art.gd")

var ui                                   ## panel stanowisk (workshop_ui.gd): stan, etykiety, karta

func _init(panel: Control) -> void:
	ui = panel

## Portfel odlicza do nowej kwoty (zakup, zamówienie, odbiór) zamiast skakać i krótko przygasa na czerwono przy wydatku — widać, ile kosztowało.
func _tick_wallet() -> void:
	var target := Scrap.bank
	if ui._bank_shown < 0 or Settings.reduce_fx:
		ui._bank_shown = target
		ui._wallet.text = "%d" % target
		ui._drum.shown = float(target)
		return
	if target == ui._bank_shown and (ui._wallet_tween == null or not ui._wallet_tween.is_running()):
		return
	if ui._wallet_tween != null and ui._wallet_tween.is_running():
		if ui._wallet_tween.get_meta("to", -1) == target:
			return
		ui._wallet_tween.kill()
	var from = ui._bank_shown
	ui._wallet_tween = ui.create_tween()
	ui._wallet_tween.set_meta("to", target)
	ui._wallet_tween.tween_method(func(v: float) -> void:
		ui._bank_shown = int(round(v))
		ui._drum.shown = v                                     # bębny obracają się płynnie jak w liczniku mechanicznym
		ui._wallet.text = "%d" % ui._bank_shown, float(from), float(target), 0.7).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)

## Udana operacja: potwierdzenie UI, dźwięk stanowiska (magazynek na ławie, łuski przy prasie, ogniwo w pracowni…) i krótki błysk wybranego kafla.
func _success_fx(vol_db := -4.0) -> void:
	Audio.play("ui_confirm", Audio.BUS_UI, vol_db)
	var snd: Array = ui.STATION_SOUNDS.get(ui._mode, [])
	if not snd.is_empty():
		if int(snd[1]) > 0:
			Audio.play_variant(String(snd[0]), int(snd[1]), Audio.BUS_UI, vol_db - 2.0)
		else:
			Audio.play(String(snd[0]), Audio.BUS_UI, vol_db - 2.0)
	ui._stamp()
	if Settings.reduce_fx:
		return
	var tile: Control = null
	match ui._page:
		0:
			tile = ui._tiles[ui._sel] if not (ui._mode == "bench") else null      # ława 3D ma własną animację montażu
		1:
			tile = ui._sup_tiles[ui._sup_sel]
		2:
			tile = ui._perk_tiles[ui._perk_sel]
		3:
			tile = ui._look_tiles[ui._look_sel]
	if tile == null or not tile.is_visible_in_tree():
		return
	tile.modulate = Color(1.55, 1.4, 0.95)
	ui.create_tween().tween_property(tile, "modulate", Color.WHITE, 0.35)

## Zdarzenia Kryjówki na karcie (STATION_CARDS_PLAN.md §5): stuknięcie zza D-7 — papiery
## drgają, czerwony błysk od strony drzwi i napis dźwięku z kierunkiem. „Reduce effects” wyłącza migotanie, drganie i błysk (napis zostaje).
func _hub_events() -> void:
	# burza: przygasa tylko lampa generatora w świecie (view3d.gd) — karta nie (od 1.7.421: skok jasności całej karty z tekstem
	# co kilka sekund wyglądał jak migotanie ekranu i utrudniał czytanie)
	var d7: Node2D = null
	for n in ui.get_tree().get_nodes_in_group("hub_props"):
		if String(n.get("kind")) == "d7":
			d7 = n as Node2D
			break
	if d7 == null:
		return
	var k := float(d7.get("knock_flash"))
	if k >= 0.95 and ui._knock_prev < 0.95:
		_on_knock(d7)
	ui._knock_prev = k

func _on_knock(d7: Node2D) -> void:
	var me: Node2D = null
	for p in ui.get_tree().get_nodes_in_group("players"):
		if not p.is_bot and p.is_multiplayer_authority():
			me = p
	var left := me != null and d7.global_position.x < me.global_position.x
	if ui._jars != null and ui._jars.is_visible_in_tree():
		(ui._jars as LabArt.Jars).hear(-1.0 if left else 1.0)         # D2a: kształty w słojach zwracają się w stronę stukania
	# napis dźwięku po stronie drzwi, nad kartą — nie zmienia układu karty (wiersz komunikatów zostaje dla wyników operacji)
	ui._knock_label.text = ("◀  " if left else "") + tr("Knocking behind D-7") + ("" if left else "  ▶")
	ui._knock_label.reset_size()
	var cr = ui._card.get_global_rect()
	ui._knock_label.position = Vector2(cr.position.x + 8.0 if left else cr.end.x - ui._knock_label.size.x - 8.0, maxf(2.0, cr.position.y - ui._knock_label.size.y - 2.0))
	ui._knock_label.modulate.a = 1.0
	var kt = ui.create_tween()
	kt.tween_interval(1.4)
	kt.tween_property(ui._knock_label, "modulate:a", 0.0, 0.6)
	if Settings.fx_mult() <= 0.0:
		return
	ui._edge_flash.size = Vector2(ui.size.x * 0.16, ui.size.y)
	ui._edge_flash.position = Vector2(0.0 if left else ui.size.x - ui._edge_flash.size.x, 0.0)
	ui._edge_flash.color = Color(UiTheme.DANGER, 0.22)
	ui.create_tween().tween_property(ui._edge_flash, "color:a", 0.0, 0.9)
	for p in ui._papers:
		var pc := p as Control
		if not pc.is_visible_in_tree():
			continue
		pc.pivot_offset = pc.size * Vector2(0.5, 0.0)
		var tw = ui.create_tween()
		for r in [0.9, -0.6, 0.35, 0.0]:
			tw.tween_property(pc, "rotation_degrees", r * (-1.0 if left else 1.0), 0.07)
