extends RefCounted
## Cienie w widoku 3D (`view3d.gd`): które światła rzucają cień i cień modeli graczy.
##
## (1) Lampy z cieniem: najwyżej `View3D.SHADOW_LIGHTS` świateł najbliższych środka kadru, wybieranych przy każdym przeglądzie świateł.
##     Do 1.7.523 cień dostawało światło tylko przy tworzeniu (pięć najbliższych w chwili wczytania mapy), a lampy, które wchodziły do
##     zestawu w czasie gry, nigdy go nie miały: w hali stacji 1.2 nie było żadnego cienia lampy.
## (2) Cień graczy: lampy z cieniem świecą tylko na warstwę świata (`light_cull_mask`), a modele graczy leżą w warstwie graczy, więc gracz
##     nie rzucał cienia, choć wrogowie (warstwa świata) rzucają. Każda siatka modelu dostaje kopię „tylko cień” w warstwie świata.

## Które światła mają mieć cień. `ranked`: id świateł, które mogą rzucać cień, od najbliższego środka kadru; `current`: id świateł z cieniem
## teraz. Cień zostaje u świateł, które go mają i są wśród pierwszych `limit + keep` (histereza: lampa na granicy nie przełącza cienia przy
## każdym kroku), a wolne miejsca dostają kolejne od najbliższego. Wynik: id → true, najwyżej `limit` pozycji.
static func pick(ranked: Array, current: Dictionary, limit: int, keep: int) -> Dictionary:
	var out := {}
	for i in mini(ranked.size(), limit + keep):
		if out.size() < limit and current.has(ranked[i]):
			out[ranked[i]] = true
	for id in ranked:
		if out.size() >= limit:
			break
		out[id] = true
	return out

## Kopie „tylko cień” wszystkich siatek z warstwy `src_layer` pod `root` (ciało, broń, kilof): ta sama siatka, skóra i szkielet (rodzeństwo
## oryginału, więc ścieżka do szkieletu wskazuje ten sam węzeł), warstwa `cast_layer`, `SHADOWS_ONLY` — w obrazie nic nie widać, a lampy
## widzą postać jak wroga. Siatki już skopiowane (i same kopie) pomija. Zwraca nowe pary [oryginał, kopia] do `sync`.
static func add(root: Node, src_layer: int, cast_layer: int) -> Array:
	var pairs: Array = []
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.layers != src_layer or m.has_meta("shadow_cast") or m.has_meta("shadow_src"):
			continue
		var c := m.duplicate(0) as MeshInstance3D
		for ch in c.get_children():
			c.remove_child(ch)
			ch.free()
		c.name = String(m.name) + "_ShadowCast"
		c.set_meta("shadow_cast", true)
		c.layers = cast_layer
		c.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		m.set_meta("shadow_src", true)
		m.add_sibling(c)
		pairs.append([m, c])
	return pairs

## Widoczność kopii jak u oryginału (np. schowana broń); pary z usuniętym węzłem (zmiana wyglądu zwalnia stary model) wypadają z listy.
static func sync(pairs: Array) -> Array:
	var alive: Array = []
	for pr in pairs:
		if not is_instance_valid(pr[0]) or not is_instance_valid(pr[1]):
			if is_instance_valid(pr[1]):
				(pr[1] as Node).queue_free()
			continue
		var m := pr[0] as MeshInstance3D
		var c := pr[1] as MeshInstance3D
		if c.visible != m.visible:
			c.visible = m.visible
		alive.append(pr)
	return alive

## Usuwa kopie (gracz wraca do własnego świata Char3D): oryginały tracą znacznik, więc przy kolejnym `add` dostaną nowe kopie.
static func clear(pairs: Array) -> void:
	for pr in pairs:
		if is_instance_valid(pr[1]):
			var c := pr[1] as Node
			if c.get_parent() != null:
				c.get_parent().remove_child(c)
			c.queue_free()
		if is_instance_valid(pr[0]):
			(pr[0] as Node).remove_meta("shadow_src")
