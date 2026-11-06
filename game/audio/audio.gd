extends Node
## Autoload "Audio": music per place with crossfades (title, places, combat,
## boss, victory and defeat stings), sfx for combat events (rules in
## assets/audio/audio_map.json), UI clicks of the Kit buttons, footsteps, room
## ambiences, story sounds (level up, chest, grille, the bell), and captions
## for the sounds that carry information (signal `captioned`, shown by the
## story banners). Buses: Master, Music, SFX, UI, Ambience
## (res://default_bus_layout.tres). Nothing plays before the first user input
## (browser autoplay rules). No volume is saved here: the settings screen calls
## set_bus_volume() with its own saved values.

signal captioned(text: String)

const FADE_S := 1.2
const COMBAT_FADE_S := 0.5
const SILENT_DB := -60.0
const SFX_VOICES := 10
const UI_VOICES := 3
## The same sfx is not restarted closer than this (×4 speed, area spells).
const MIN_REPEAT_S := 0.06
const CAPTION_REPEAT_S := 6.0
const STEP_EVERY_S := 0.36
const STEP_MIN_SPEED := 1.2
const POLL_S := 0.2
const BELL_DUCK_DB := -12.0
## Screens that keep whatever plays (opened from the title or from the game).
const NEUTRAL_SCREENS := ["settings", "content_error"]
const TITLE_SCREENS := ["title", "save_recovery"]

## True once the player has pressed something (web autoplay policy).
var unlocked := false
## Id of the music playing (or fading in), "" for none.
var music_id := ""
var ambience_id := ""
var _music: Array[AudioStreamPlayer] = []
var _active := 0
var _music_tween: Tween
var _sting: AudioStreamPlayer
var _ambience: AudioStreamPlayer
var _sfx: Array[AudioStreamPlayer] = []
var _ui: Array[AudioStreamPlayer] = []
var _next_sfx := 0
var _next_ui := 0
var _last_played := {}
var _last_caption := {}
var _streams := {}
var _poll := 0.0
var _step_clock := 0.0
var _step_variant := 0
## Combat: "" (none), "combat" or "boss"; the view it belongs to.
var _combat := ""
var _combat_view: WeakRef
var _hold_until_ms := 0
var _leader_level := -1
var _duck_tween: Tween
var _duck_db := 0.0
## Bus -> volume in dB set by the settings screen (ducking is added on top).
var _user_db := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	ensure_buses()
	for i in 2:
		_music.append(_player("Music%d" % i, "Music"))
		_music[i].volume_db = SILENT_DB
	_sting = _player("Sting", "Music")
	_ambience = _player("Ambience", "Ambience")
	for i in SFX_VOICES:
		_sfx.append(_player("Sfx%d" % i, "SFX"))
	for i in UI_VOICES:
		_ui.append(_player("Ui%d" % i, "UI"))
	if GameState.has_signal("story_events"):
		GameState.story_events.connect(_on_story_events)
		GameState.game_replaced.connect(func() -> void: _leader_level = -1)


## Adds any missing bus of AudioCatalog.BUSES (the layout file normally has them).
static func ensure_buses() -> void:
	for bus: String in AudioCatalog.BUSES:
		if AudioServer.get_bus_index(bus) == -1:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, bus)
			AudioServer.set_bus_send(i, "Master")


# --- Public API ------------------------------------------------------------------


## Volume of a bus ("Master", "Music", "SFX", "UI", "Ambience") from a 0..1
## slider. 0 mutes the bus. Nothing is persisted here.
func set_bus_volume(bus: String, linear: float) -> void:
	var i := AudioServer.get_bus_index(bus)
	if i == -1:
		push_warning("Audio: unknown bus %s" % bus)
		return
	var v := clampf(linear, 0.0, 1.0)
	AudioServer.set_bus_mute(i, v <= 0.0)
	_user_db[bus] = linear_to_db(maxf(v, 0.0001))
	_apply_bus(bus)


## Current 0..1 volume of a bus (0 when muted).
func get_bus_volume(bus: String) -> float:
	var i := AudioServer.get_bus_index(bus)
	if i == -1 or AudioServer.is_bus_mute(i):
		return 0.0
	return clampf(db_to_linear(float(_user_db.get(bus, 0.0))), 0.0, 1.0)


## Plays an sfx id (a random variant when it has several). Returns false when
## nothing played (locked, unknown id, or restarted too soon).
func play_sfx(
	id: String, bus: String = "SFX", volume_db: float = 0.0, jitter: float = 0.04
) -> bool:
	if not unlocked:
		return false
	var paths := AudioCatalog.sfx_paths(id)
	if paths.is_empty():
		return false
	var now := Time.get_ticks_msec()
	if now - int(_last_played.get(id, -100000)) < int(MIN_REPEAT_S * 1000.0):
		return false
	_last_played[id] = now
	var path := paths[0]
	if paths.size() > 1:
		_step_variant = (_step_variant + 1 + randi() % (paths.size() - 1)) % paths.size()
		path = paths[_step_variant]
	var p: AudioStreamPlayer
	if bus == "UI":
		p = _ui[_next_ui]
		_next_ui = (_next_ui + 1) % _ui.size()
	else:
		p = _sfx[_next_sfx]
		_next_sfx = (_next_sfx + 1) % _sfx.size()
	p.bus = bus
	p.stream = _load(path)
	p.volume_db = volume_db
	p.pitch_scale = 1.0 + randf_range(-jitter, jitter)
	p.play()
	return true


func play_ui(kind: String) -> void:
	play_sfx(AudioCatalog.ui_sfx(kind), "UI", 0.0, 0.02)


## Shows a caption (strings.csv key) for an information-carrying sound, at
## most once per CAPTION_REPEAT_S for the same key.
func caption(key: String) -> void:
	if key == "":
		return
	var now := Time.get_ticks_msec()
	if now - int(_last_caption.get(key, -100000)) < int(CAPTION_REPEAT_S * 1000.0):
		return
	_last_caption[key] = now
	captioned.emit(tr(key))


## The cloister bell: music ducked while it rings. `with_caption` for the
## places that do not already subtitle it.
func ring_bell(with_caption: bool = false) -> void:
	play_sfx(AudioCatalog.story_sfx("bell"), "SFX", 0.0, 0.0)
	duck_music(BELL_DUCK_DB, 7.0)
	if with_caption:
		caption(AudioCatalog.caption_for("bell"))


## Lowers the Music bus for `seconds`, then brings it back (sidechain-like).
func duck_music(db: float, seconds: float) -> void:
	if _duck_tween:
		_duck_tween.kill()
	_duck_tween = create_tween()
	_duck_tween.tween_method(_set_duck, 0.0, db, 0.4)
	_duck_tween.tween_interval(maxf(seconds - 1.6, 0.0))
	_duck_tween.tween_method(_set_duck, db, 0.0, 1.2)


## One central hook for the Kit buttons: a click (or a confirm for primary
## buttons, a "back" for buttons whose probe id ends in ".back").
func hook_button(b: BaseButton, primary: bool, probe_id: String = "") -> void:
	var back := (
		probe_id.ends_with(".back") or (b is Button and (b as Button).text == tr("ui.menu.back"))
	)
	var kind := "back" if back else ("confirm" if primary else "click")
	b.pressed.connect(play_ui.bind(kind))


## Crossfades to a music id ("" fades out). Same id: nothing changes.
func play_music(id: String, fade_s: float = FADE_S) -> void:
	if id == music_id or not unlocked:
		return
	if id != "" and not AudioCatalog.has_music(id):
		return
	music_id = id
	if _music_tween:
		_music_tween.kill()
	var old := _music[_active]
	_active = 1 - _active
	var nxt := _music[_active]
	_music_tween = create_tween().set_parallel(true)
	if id != "":
		var stream := _load(AudioCatalog.music_path(id))
		if stream is AudioStreamOggVorbis:
			(stream as AudioStreamOggVorbis).loop = true
		nxt.stream = stream
		nxt.volume_db = SILENT_DB
		nxt.play()
		_music_tween.tween_property(nxt, "volume_db", 0.0, fade_s).set_trans(Tween.TRANS_SINE)
	_music_tween.tween_property(old, "volume_db", SILENT_DB, fade_s).set_trans(Tween.TRANS_SINE)
	_music_tween.chain().tween_callback(old.stop)


# --- Combat (called by CombatFx.handle for every sim event) -----------------------


func on_combat_event(e: Dictionary, view: Node = null) -> void:
	match str(e.get("type", "")):
		"encounter_started":
			var boss := str(e.get("kind", "")) == "boss"
			_combat = "boss" if boss else "combat"
			_combat_view = weakref(view) if view else null
			_hold_until_ms = 0
			play_music(AudioCatalog.music_for(_combat), COMBAT_FADE_S)
			return
		"encounter_completed":
			_end_combat(str(e.get("result", "")) == "victory")
			return
	var facts := {}
	if e.has("target") and view and view.has_method("snapshot_unit"):
		var def_id := str(
			(view.call("snapshot_unit", str(e["target"])) as Dictionary).get("def_id", "")
		)
		facts["target_family"] = str(Content.get_entity(def_id).get("family", ""))
	if e.get("type", "") == "loot_dropped":
		facts["rarity"] = AudioCatalog.best_rarity(e)
	var rule := AudioCatalog.combat_rule(e, facts)
	if rule.is_empty():
		return
	play_sfx(str(rule.get("sfx", "")), str(rule.get("bus", "SFX")))
	caption(str(rule.get("caption", "")))


func _end_combat(victory: bool) -> void:
	if _combat == "":
		return
	_combat = ""
	var sting := AudioCatalog.music_for("victory" if victory else "defeat")
	play_music("", COMBAT_FADE_S)
	if unlocked and AudioCatalog.has_music(sting):
		_sting.stream = _load(AudioCatalog.music_path(sting))
		_sting.play()
		var length := _sting.stream.get_length()
		_hold_until_ms = Time.get_ticks_msec() + int((length - 0.8) * 1000.0)


# --- Polling: which music, ambience and footsteps -------------------------------


func _input(event: InputEvent) -> void:
	if unlocked:
		return
	if (
		(event is InputEventMouseButton and event.pressed)
		or (event is InputEventKey and event.pressed)
		or (event is InputEventScreenTouch and event.pressed)
		or (event is InputEventJoypadButton and event.pressed)
	):
		unlocked = true
		_poll = POLL_S


func _process(delta: float) -> void:
	if not unlocked:
		return
	_steps(delta)
	_poll += delta
	if _poll < POLL_S:
		return
	_poll = 0.0
	if _combat != "" and (_combat_view == null or _combat_view.get_ref() == null):
		_combat = ""  # the fight was left without a result
	if _combat == "" and Time.get_ticks_msec() >= _hold_until_ms:
		var key := music_key(Router.current_id, GameState.has_game(), _place())
		if key != "":
			play_music(AudioCatalog.music_for(key))
	_update_ambience()
	_check_level()


## Which music entry a screen asks for: "title", a place id, or "" (keep).
static func music_key(screen: String, has_game: bool, place: String) -> String:
	if screen == "" or screen in NEUTRAL_SCREENS:
		return ""
	if screen in TITLE_SCREENS or not has_game:
		return "title"
	return place


## Location or dungeon the party is in ("" without a game).
func _place() -> String:
	if not GameState.has_game():
		return ""
	var run := DungeonRun.run(GameState.data)
	if not run.is_empty():
		return str(run.get("dungeon_id", ""))
	return str(GameState.data["world"]["location_id"])


func _update_ambience() -> void:
	var id := ""
	if _combat == "" and Router.current_id == "explore" and GameState.has_game():
		var run := DungeonRun.run(GameState.data)
		if not run.is_empty():
			for room: Dictionary in Content.get_entity(str(run["dungeon_id"])).get("rooms", []):
				if room.get("id", "") == run.get("room", ""):
					id = AudioCatalog.room_ambience(str(room.get("kind", "")))
	if id == ambience_id:
		return
	ambience_id = id
	var tw := create_tween()
	if id == "" or not AudioCatalog.has_sfx(id):
		tw.tween_property(_ambience, "volume_db", SILENT_DB, FADE_S)
		tw.tween_callback(_ambience.stop)
		return
	var stream := _load(AudioCatalog.sfx_paths(id)[0])
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	_ambience.stream = stream
	_ambience.volume_db = SILENT_DB
	_ambience.play()
	tw.tween_property(_ambience, "volume_db", 0.0, FADE_S)


func _steps(delta: float) -> void:
	if Router.current_id != "explore" or Router.world_root == null:
		return
	var view := Router.world_root.get_node_or_null("ExploreView")
	var player: Variant = view.get("player") if view else null
	if not player is CharacterBody3D or not is_instance_valid(player):
		return
	var v := (player as CharacterBody3D).velocity
	if Vector2(v.x, v.z).length() < STEP_MIN_SPEED:
		_step_clock = STEP_EVERY_S * 0.5
		return
	_step_clock += delta
	if _step_clock >= STEP_EVERY_S:
		_step_clock = 0.0
		play_sfx(AudioCatalog.steps_for(_place()), "SFX", -6.0, 0.06)


func _check_level() -> void:
	if not GameState.has_game():
		_leader_level = -1
		return
	var hero: Dictionary = GameState.data["characters"].get(GameState.data["party"][0], {})
	var level := int(hero.get("level", 0))
	if _leader_level >= 0 and level > _leader_level:
		play_sfx(AudioCatalog.story_sfx("level_up"))
	_leader_level = level


func _on_story_events(events: Array) -> void:
	for e: Dictionary in events:
		match str(e.get("type", "")):
			"discovery_found":
				var d := Content.get_entity(str(e.get("discovery_id", "")))
				var kind := "chest" if str(d.get("kind", "")) == "chest" else "discovery"
				play_sfx(AudioCatalog.story_sfx(kind))
			"dungeon_room_cleared":
				play_sfx(AudioCatalog.story_sfx("room_cleared"), "SFX", -3.0)


# --- Helpers -------------------------------------------------------------------------


func _player(node_name: String, bus: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.name = node_name
	p.bus = bus
	add_child(p)
	return p


func _load(path: String) -> AudioStream:
	if not _streams.has(path):
		_streams[path] = load(path) as AudioStream
	return _streams[path]


func _set_duck(db: float) -> void:
	_duck_db = db
	_apply_bus("Music")


func _apply_bus(bus: String) -> void:
	var i := AudioServer.get_bus_index(bus)
	if i == -1:
		return
	var db := float(_user_db.get(bus, 0.0)) + (_duck_db if bus == "Music" else 0.0)
	AudioServer.set_bus_volume_db(i, db)
