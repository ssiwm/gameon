extends RefCounted
## Linia wzroku, światła i dźwięku przez przegrody z dziurami (DESTRUCTION_PLAN.md D2, „dziury jako informacja”): promień, który wchodzi
## w przegrodę (`breakable.gd`) na wysokości jej dziury, leci dalej — przestrzelona deska to wizjer, ale też szpara, przez którą wróg widzi
## latarkę. Bez zależności od innych skryptów (wołają go walka, światła, wrogowie i dźwięk), przegrodę rozpoznaje po grupie `breakables`.

const MAX_PASSES := 4            ## ile przegród z dziurami jeden promień może minąć (więcej na jednej linii na mapach nie ma)

## Przegroda, do której należy trafione ciało (`collider` z `intersect_ray`), albo null.
static func barrier_of(collider: Object) -> Node2D:
	var n := collider as Node
	if n == null:
		return null
	var b := n.get_parent() as Node2D
	return b if b != null and b.is_in_group("breakables") else null

## Czy trafienie w `collider` w punkcie `p` to dziura przegrody (promień leci dalej).
static func through_hole(collider: Object, p: Vector2) -> bool:
	var b := barrier_of(collider)
	return b != null and bool(b.call("hole_at", p.y))

## Wolna linia od `a` do `b` na warstwach `mask` (domyślnie świat): pierwsza przeszkoda zatrzymuje promień, chyba że to dziura przegrody.
static func clear(space: PhysicsDirectSpaceState2D, a: Vector2, b: Vector2, mask := 1) -> bool:
	return first_hit(space, PhysicsRayQueryParameters2D.create(a, b, mask)).is_empty()

## `intersect_ray` z przelotem przez dziury przegród: pierwsze trafienie, które nie jest dziurą, albo pusty słownik.
static func first_hit(space: PhysicsDirectSpaceState2D, q: PhysicsRayQueryParameters2D) -> Dictionary:
	for _i in MAX_PASSES + 1:
		var hit := space.intersect_ray(q)
		if hit.is_empty() or not through_hole(hit["collider"], hit["position"]):
			return hit
		var ex := q.exclude
		ex.append(hit["rid"])
		q.exclude = ex
	return {}
