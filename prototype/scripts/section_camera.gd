extends RefCounted
## Kamera przekroju (kryjówka „dwa pokłady”, `HUB_LAYOUT_PLAN.md` E3): pas w pionie dla `Camera2D` gracza (player.gd) i wysokość oka
## kamery 3D (view3d.gd). Bez autoloadów, żeby test `tools/test_hub_camera.gd` (`-s`) mógł ją wczytać.

const EYE_UP_M := 2.2                      ## wysokość oka kamery 3D ponad środkiem kadru na misjach [m] (punkt zbiegu nad głowami postaci)

static var _eye_arg := -2.0                ## `--eyeup=M` raz odczytane z wiersza poleceń (-2 = jeszcze nie, -1 = brak)

## Granice kamery w pionie [limit_top, limit_bottom] dla pasa `cam_lock` [wiersz stropu, wiersz podłogi] i wysokości kadru `view_h`
## [px świata]: gdy pas mieści się w kadrze — kadr wyśrodkowany na pasie (kamera jedzie tylko w poziomie, oba pokłady widać naraz);
## przy ciaśniejszym zbliżeniu (CLOSE) — sam pas, więc kamera idzie za graczem i staje na stropie parteru albo podłodze piwnicy.
static func band(cam_lock: Vector2i, tile: float, view_h: float) -> Vector2i:
	var top := float(cam_lock.x) * tile
	var bot := float(cam_lock.y + 1) * tile
	if view_h >= bot - top:
		# granice całkowite, a ich różnica = wysokość kadru: przy floor/ceil osobno (WIDE: 225 px → 226) kadr drgał o 1 px przy skoku
		var t := int(round((top + bot - view_h) * 0.5))
		return Vector2i(t, t + int(ceil(view_h - 0.001)))
	return Vector2i(int(floor(top)), int(ceil(bot)))

## Wysokość oka kamery 3D nad środkiem kadru dla mapy (`EYE_UP` w danych, level.gd `eye_up`); dev `--eyeup=M` ma pierwszeństwo.
static func eye_up_for(level: Object) -> float:
	if _eye_arg < -1.5:
		_eye_arg = -1.0
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--eyeup="):
				_eye_arg = maxf(0.0, float(a.get_slice("=", 1)))
	if _eye_arg >= 0.0:
		return _eye_arg
	if level != null and level.get("eye_up") != null and float(level.get("eye_up")) >= 0.0:
		return float(level.get("eye_up"))
	return EYE_UP_M
