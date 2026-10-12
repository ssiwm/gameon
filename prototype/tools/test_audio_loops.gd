extends SceneTree
## Test pętli dźwięku: każda pętla z manifestu ma się zapętlać na całej swojej długości — także po imporcie z kompresją
## (QOA), gdzie rozmiar danych nie jest liczbą klatek, i w Ogg Vorbis (muzyka, ambient). Sprawdza wersję, którą gra
## faktycznie gra (z nagrań, jeśli jest).
##   godot --headless --path prototype -s tools/test_audio_loops.gd     → ostatni wiersz: [AUDIOLOOPS] PASS / FAIL

const Manifest := preload("res://scripts/audio_manifest.gd")


func _initialize() -> void:
	await process_frame                                  # autoloady (Audio) są w drzewie od pierwszej klatki
	var audio := root.get_node_or_null("Audio")
	if audio == null:
		print("[AUDIOLOOPS] FAIL: brak autoloadu Audio")
		quit(1)
		return
	var fails := 0
	for key in Manifest.LOOPS:
		var any: AudioStream = audio.stream(key)
		if any is AudioStreamOggVorbis:
			var o := any as AudioStreamOggVorbis
			var want := Manifest.MUSIC_LOOP_SEC if key in Manifest.MUSIC_STEMS else o.get_length()
			if not o.loop or o.loop_offset != 0.0 or o.get_length() <= 0.0 or absf(o.get_length() - want) > 0.5 / 48000.0:
				print("[AUDIOLOOPS] ", key, ": Ogg bez pętli albo o złej długości (", o.get_length(), " s)")
				fails += 1
			continue
		var s := any as AudioStreamWAV
		if s == null:
			print("[AUDIOLOOPS] ", key, ": nie załadował się jako AudioStreamWAV ani AudioStreamOggVorbis")
			fails += 1
			continue
		var frames := int(round(s.get_length() * s.mix_rate))
		if s.loop_mode != AudioStreamWAV.LOOP_FORWARD or s.loop_begin != 0 or s.loop_end != frames or frames <= 0:
			print("[AUDIOLOOPS] ", key, ": pętla ", s.loop_begin, "–", s.loop_end, " z ", frames, " klatek (format ", s.format, ")")
			fails += 1
	print("[AUDIOLOOPS] ", "PASS" if fails == 0 else "FAIL", " (pętli: ", Manifest.LOOPS.size(), ", błędów: ", fails, ")")
	quit(0 if fails == 0 else 1)
