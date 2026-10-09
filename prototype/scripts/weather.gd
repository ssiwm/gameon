extends RefCounted
## Pogoda misji i prognoza z radiostacji w kryjówce (GDD §10.3 „Radiostacja": prognoza pogody = modyfikatory misji).
##
## Przy wejściu do kryjówki serwer losuje prognozę na NASTĘPNĄ misję kampanii (`forecast`); radiostacja pokazuje ją graczom,
## a po wyjściu z kryjówki staje się pogodą misji (`current`). Pogoda to łagodniejsza odmiana modyfikatorów Nocnego Dyżuru:
## ma plusy i minusy i działa przez te same mnożniki co NightShift (hałas, amunicja, progi Stalkera), więc żaden system
## nie czyta jej osobno (NightShift.noise_mult() itd. mnożą / łączą ją ze swoimi). W Nocnym Dyżurze i w kryjówce jej nie ma.
##
## Stan statyczny jak w NightShift: czytają go systemy symulowane na serwerze i HUD na każdym peerze; klienci dostają go przez
## mission._sync.

const KINDS := {
	"clear": {"color": Color(0.88, 0.82, 0.55), "name": "CLEAR NIGHT", "short": "NO EFFECTS", "text": "No wind, no rain. Nothing helps you and nothing hurts you.", "weight": 3},
	"rain": {"color": Color(0.45, 0.66, 0.95), "name": "RAIN", "short": "NOISE -25%  ·  START 20", "text": "Rain on the roofs: every noise is 25% quieter. The squad is on edge, though: attention starts at 20.", "weight": 3,
		"noise": 0.75, "start": 20.0},
	"storm": {"color": Color(0.62, 0.52, 0.92), "name": "STORM", "short": "NOISE -40%  ·  AMMO -25%", "text": "Thunder swallows sound: every noise is 40% quieter. But the supply crates are soaked: 25% less ammo.", "weight": 2,
		"noise": 0.6, "ammo": 0.75},
	"fog": {"color": Color(0.72, 0.77, 0.8), "name": "FOG", "short": "NOISE -15%  ·  STALKER 50 / 20", "text": "Fog dulls sound: noise is 15% quieter. The stalker senses you from further away: wakes at 50, sleeps at 20.", "weight": 2,
		"noise": 0.85, "awake": 50.0, "sleep": 20.0},
}

## Prognoza na następną misję (ustawia serwer przy wejściu do kryjówki) i pogoda trwającej misji ("" = brak).
static var forecast := "clear"
static var current := ""
## Ziarno pogody misji (losuje je serwer razem z `current`, replikowane w mission._sync): z niego liczy się harmonogram błyskawic (weather_fx.gd).
static var seed := 0
## Dev (--shotweather=ID): wymusza pogodę na zrzuty (także mnożniki).
static var dev_id := ""

## Losuje pogodę wg wag. `rng` opcjonalny (testy).
static func roll(rng: RandomNumberGenerator = null) -> String:
	var total := 0
	for id in KINDS:
		total += int(KINDS[id]["weight"])
	var pick := (rng.randi() if rng != null else randi()) % total
	for id in KINDS:
		pick -= int(KINDS[id]["weight"])
		if pick < 0:
			return String(id)
	return "clear"

## Pogoda wpływająca na rozgrywkę: pusta w kryjówce / poza kampanią (current == "") i w Nocnym Dyżurze.
static func active_id() -> String:
	if KINDS.has(dev_id):
		return dev_id
	return current if KINDS.has(current) else ""

static func reset_state() -> void:
	forecast = "clear"
	current = ""

# ---------------------------------------------------------------- mnożniki (łączone w NightShift.*)

static func _f(key: String, default: float) -> float:
	var id := active_id()
	return float(KINDS[id].get(key, default)) if id != "" else default

static func noise_mult() -> float:
	return _f("noise", 1.0)

static func ammo_mult() -> float:
	return _f("ammo", 1.0)

## Początkowa Uwaga misji: wyższa z bazowej i pogodowej.
static func start_noise(base: float) -> float:
	return maxf(base, _f("start", 0.0))

## Progi Stalkera: pogoda tylko je obniża (mgła).
static func awake_threshold(base: float) -> float:
	return minf(base, _f("awake", base))

static func sleep_threshold(base: float) -> float:
	return minf(base, _f("sleep", base))

static func color_of(id: String) -> Color:
	return KINDS[id].get("color", Color.WHITE) if KINDS.has(id) else Color.WHITE

static func name_of(id: String) -> String:
	return String(KINDS[id]["name"]) if KINDS.has(id) else ""

## Jedna linia efektów dla HUD (przy mierniku hałasu).
static func short_of(id: String) -> String:
	return String(KINDS[id].get("short", "")) if KINDS.has(id) else ""

static func text_of(id: String) -> String:
	return String(KINDS[id]["text"]) if KINDS.has(id) else ""
