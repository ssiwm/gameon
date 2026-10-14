extends RefCounted
## Strefy trafień wrogów: wyższe niż ciało, którym wróg się porusza. Modele 3D wrogów mają wysokość z `enemy3d.gd` (SPEC „fit"), a ciała
## ruchu są niższe (mieszczą się w korytarzach z dwóch kafli) — bez strefy pocisk wymierzony w widoczną głowę przelatywał nad hitboxem.
## Strefa to `Area2D` na warstwie ciała; zapytania fizyczne pocisków i promieni widzą ją (`collide_with_areas`), a `resolve` podmienia ją na
## ciało, więc reszta kodu (przebicia, `take_hit`, kompensacja opóźnienia) widzi zwykłe trafienie we wroga.

static var _area_of := {}                    ## RID ciała → RID jego strefy trafień (do wyłączeń w zapytaniach)

## Dokłada ciału `body` (początek układu = stopy) strefę trafień `width` × `height` px. Nic nie robi, gdy strefa nie byłaby wyższa niż ciało.
static func add(body: CollisionObject2D, width: float, height: float) -> void:
	var cs := body.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if cs == null or not (cs.shape is RectangleShape2D) or height <= (cs.shape as RectangleShape2D).size.y + 0.5:
		return
	var area := Area2D.new()
	area.name = "Hurt"
	area.collision_layer = body.collision_layer
	area.collision_mask = 0
	area.monitoring = false
	area.set_meta("hurt_of", body)
	var s := CollisionShape2D.new()
	var r := RectangleShape2D.new()
	r.size = Vector2(width, height)
	s.shape = r
	s.position = Vector2(0.0, -height * 0.5)
	s.disabled = cs.disabled
	area.add_child(s)
	body.add_child(area)
	body.set_meta("hurt_shape", s)
	var brid := body.get_rid()
	_area_of[brid] = area.get_rid()
	body.tree_exiting.connect(func(): _area_of.erase(brid))

## Włącza / wyłącza ciało razem ze strefą trafień (śmierć, ukrycie, powrót).
static func set_enabled(body: Node, on: bool) -> void:
	(body.get_node("CollisionShape2D") as CollisionShape2D).set_deferred("disabled", not on)
	# Nie `get_meta(…, null)`: w Godocie 4 domyślne `null` znaczy „bez domyślnej", więc wróg bez strefy sypał błędem do logu.
	if not body.has_meta("hurt_shape"):
		return
	var s = body.get_meta("hurt_shape")
	if is_instance_valid(s):
		(s as CollisionShape2D).set_deferred("disabled", not on)

## Wyłączenia zapytania: do RID-ów ciał dokłada RID-y ich stref (wróg już przebity albo przewinięty nie trafia drugi raz strefą).
static func with_areas(ex: Array[RID]) -> Array[RID]:
	if _area_of.is_empty():
		return ex
	var out: Array[RID] = ex.duplicate()
	for r in ex:
		if _area_of.has(r):
			out.append(_area_of[r])
	return out

## Wynik zapytania fizycznego (`intersect_ray` / element `intersect_point`): trafiona strefa → jej ciało (collider i rid).
static func resolve(hit: Dictionary) -> Dictionary:
	if hit.is_empty():
		return hit
	var c = hit.get("collider")
	if c is Area2D and (c as Node).has_meta("hurt_of"):
		var body = (c as Node).get_meta("hurt_of")
		if is_instance_valid(body):
			hit["collider"] = body
			hit["collider_id"] = (body as Object).get_instance_id()
			hit["rid"] = (body as CollisionObject2D).get_rid()
	return hit
