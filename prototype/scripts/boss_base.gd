extends CharacterBody2D
## Wspólna podstawa bossów (ENEMY_PLAN.md F2b): Żyła (`boss.gd`) i Pijawka (`leech.gd`). Trzyma to, co oba dublowały: stan i fazy,
## HP skalowane liczbą ludzi i trudnością, przywoływanych Trzosków (tworzenie, sprzątanie, zabijanie przy śmierci), łup po śmierci i wstrząs kamery.
## Reszta — ataki, okna obrażeń, replikacja stanu, rysowanie — jest własna dla każdego bossa. Symulacja TYLKO na serwerze.

signal died

const NightShift := preload("res://scripts/night_shift.gd")
const SUMMON_SCENE := preload("res://scenes/enemy.tscn")

enum State { DORMANT, AWAKE, DEAD }

var state: int = State.DORMANT
var hp := 0.0                          ## ustawia podklasa (BASE_HP) w `_init`
var max_hp := 0.0
var phase := 1                         ## 1 / 2 / 3 — progi HP i skutki fazy ma każdy boss osobno

## Aktywny boss to zagrożenie (boty strzelają, Dyrektor liczy starcie); śpiący i martwy nie.
func is_threat() -> bool:
	return state == State.AWAKE

func is_alive() -> bool:
	return state != State.DEAD

## Liczba ludzi w drużynie (boty nie liczą się do skalowania).
func _humans() -> int:
	var n := 0
	for p in get_tree().get_nodes_in_group("players"):
		if not p.is_bot:
			n += 1
	return n

## HP bossa: baza + dodatek za każdego dodatkowego człowieka, razy trudność (`boss_hp`) i mnożnik Nocnego Dyżuru.
static func scaled_hp(base: float, per_extra_human: float, humans: int) -> float:
	return (base + per_extra_human * float(maxi(0, humans - 1))) * Difficulty.m("boss_hp") * NightShift.hp_mult()

## Wstrząs kamery lokalnego człowieka, jeśli jest w 400 px od bossa.
func _shake_near(amount: float) -> void:
	for p in get_tree().get_nodes_in_group("players"):
		if not p.is_bot and p.is_multiplayer_authority() and p.global_position.distance_to(global_position) < 400.0:
			Feel.shake(amount)

# ---------------------------------------------------------------- przywołani (Trzoski bossa)

## Tworzy na KAŻDYM peerze Trzoska o nazwie `n` w `pos` (przywołany: wie, gdzie są gracze, nie daje XP ani dropów); na serwerze go budzi.
## Zwraca węzeł (podklasa dopisuje go do swojej listy) albo null, gdy taki już istnieje. `pitch`: wysokość dźwięku pojawienia się.
func _summon(n: String, pos: Vector2, pitch: float) -> Node:
	var lvl := get_parent()
	if lvl.has_node(n):
		return null
	var e := SUMMON_SCENE.instantiate()
	e.name = n
	e.kind = "trzosek"
	e.omniscient = true                         # wsparcie bossa, nie zwykła wataha
	e.summoned = true                           # bez XP i dropów (enemy.gd: _die)
	e.position = pos
	lvl.add_child(e)
	Audio.play_variant_at("impact_flesh", 3, pos, Audio.BUS_WORLD, -6.0, pitch)
	if NoiseMgr.is_server():
		e.wake()
	return e

## Usuwa przywołanych o nazwach zaczynających się od `prefix` (restart misji).
func _clear_summoned(prefix: String) -> void:
	for n in get_parent().get_children():
		if String(n.name).begins_with(prefix):
			n.queue_free()

## Zabija żywych z listy (śmierć bossa): rozerwani jednym trafieniem.
func _kill_summoned(list: Array) -> void:
	for b in list:
		if is_instance_valid(b) and b.alive:
			b.take_bullet(global_position, 999.0)

## Łup po bossie: dwie apteczki na drogę do ekstrakcji przez obudzony teren i złom.
func _drop_boss_loot() -> void:
	var lvl := get_tree().get_first_node_in_group("level")
	if lvl == null:
		return
	lvl.spawn_health(global_position + Vector2(-20, -30))
	lvl.spawn_health(global_position + Vector2(20, -30))
	if Scrap.enabled():
		lvl.spawn_item("scrap", 0, global_position + Vector2(0, -30), Scrap.BOSS_VALUE)
		Scrap.add_samples(Scrap.SAMPLE_BOSS)                         # boss: próbki do pracowni (W6a)
