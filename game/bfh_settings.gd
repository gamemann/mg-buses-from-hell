extends Node

## A player's own settings: how fast the view turns, how wide it is, how loud things are.
##
## [codeblock]
## var settings := BfhSettings.new()
## add_child(settings)
## settings.setup()                    # loads, and pushes every value at what reads it
## settings.bind_look(sampler.tunables)
## settings.bind_camera(camera)
## settings.bind_audio(audio.audio)
## settings.open()                     # Escape does this in the client
## [/codeblock]
##
## [b]A document with a screen, and the client had a place for both only once it had
## audio.[/b] Until 2026-09-25 the camera's field of view was a literal 90, the view turned
## at dot-player-controller's unchosen default, and there was nothing to be loud or quiet.
## Now three things read a setting — the samplers, the camera and dot-audio's mixer — and
## Escape, which only ever let go of the mouse, opens dot-ui's settings screen over the
## bowl: a released pointer with nothing to click on was a key that did half a job.
##
## [b]`apply_all()` on load, and it is the line this family keeps losing.[/b] A value read
## from disk has not CHANGED, so a game that applies settings only from `changed` ignores
## every saved one until the player touches it — their saved sensitivity does nothing, and
## the slider shows the number they chose. Every value is pushed once after load and once
## whenever something new binds, then `changed` keeps them current.
##
## [b]The scopes are the family's, not this game's.[/b] `sensitivity` is ACCOUNT under the
## shared `tmc_account` namespace — a person's hand, the same number in every game here, so
## it is converted the way every other game converts it ([constant DEGREES_PER_COUNT]).
## `field_of_view` is SERVER_CLAMPED: a wide view is an advantage a server may cap, and
## dot-settings gives a server no way to READ it. The volumes are this machine's.

const CHANNEL := "bfh.settings"

const SCHEMA_VERSION := 1

## Where this game's own document lives. The shared account document is dot-settings'.
const SETTINGS_DIR := "user://buses_settings"

## The app's namespace, and the family's shared one for ACCOUNT settings.
const APP_NAMESPACE := &"buses_from_hell"
const SHARED_NAMESPACE := &"tmc_account"

## Degrees of view per unit of mouse motion at a sensitivity of 1.
##
## [b]The family's constant, so a player's sensitivity means one turning speed in every
## game that reads it.[/b] game-arena and game-g2gfast convert with this number; a game
## that converted differently would turn a player's one number into two speeds. It also
## changes this game's default turn from dot-player-controller's 0.25 degrees per unit —
## a number nobody here chose — to 2.5 x 0.022 = 0.055, the one the rest of the family ships.
const DEGREES_PER_COUNT := 0.022

## The field of view the camera had before this existed, and still the default.
const DEFAULT_FOV := 90

var settings: DotSettingsManager = null

## The menu the screen lives in, over the bowl. Null when built without a screen.
var stack: DotScreenStack = null
var screen: DotSettingsScreen = null

var _layer: CanvasLayer = null

## Every tunables object a sampler reads. Two on a connected client that has played
## offline, never more; an array so a rebind does not orphan the first.
var _look: Array[DotFpsTunables] = []
var _camera: Camera3D = null
var _audio: DotAudioManager = null


## The document. Five settings, each read by something.
static func schema() -> DotSettingsSchema:
	var s := DotSettingsSchema.new()
	s.version = SCHEMA_VERSION

	s.add(DotSettingsDef.number(&"sensitivity", 2.5, 0.05, 20.0, &"controls").with_scope(
		DotSettingsDef.Scope.ACCOUNT
	).with_description("The same number in every game that reads it."))

	s.add(DotSettingsDef.integer(&"field_of_view", DEFAULT_FOV, 70, 120, &"video").with_scope(
		DotSettingsDef.Scope.SERVER_CLAMPED
	))

	s.add(DotSettingsDef.number(&"master_volume", 0.8, 0.0, 1.0, &"audio"))
	# The bowl: engines, horns, hammers, crates. The one a runner turns UP, because the
	# engine is how they hear which side of a tank the bus is on.
	s.add(DotSettingsDef.number(&"sfx_volume", 1.0, 0.0, 1.0, &"audio"))
	s.add(DotSettingsDef.number(&"voice_volume", 1.0, 0.0, 1.0, &"audio"))
	return s


## Loads the document and builds the screen. [param store] replaces the file store, which
## is what a suite does; [param with_screen] false builds the document alone.
func setup(store: DotSettingsStore = null, with_screen: bool = true) -> DotResult:
	settings = DotSettingsManager.new()
	settings.name = "Manager"
	settings.schema = schema()
	settings.local_store = store if store != null else DotSettingsStoreFile.new(SETTINGS_DIR)
	settings.app_namespace = APP_NAMESPACE
	settings.shared_namespace = SHARED_NAMESPACE
	# A server and a client in one editor session, and a suite, hold two of these; a
	# registry name is the last one's.
	settings.register_as_service = false
	add_child(settings)

	var loaded := settings.setup()
	if not loaded.ok:
		return loaded.wrap("the player's settings")

	settings.changed.connect(_on_changed)

	if with_screen:
		var built := _build_screen()
		if not built.ok:
			# Not fatal: the document still applies, which is most of what matters. The
			# screen is how a player changes it, and a WARN says it is not there.
			DotLog.warn(CHANNEL, "no settings screen", {"why": built.error.message})

	apply_all()
	return DotResult.success(self)


func _build_screen() -> DotResult:
	_layer = CanvasLayer.new()
	_layer.name = "MenuLayer"
	# Over the HUD and over the chat box, which is layer 100: a menu drawn under the chat
	# is a menu with somebody's line of text across its Apply button.
	_layer.layer = 110
	add_child(_layer)

	stack = DotScreenStack.new()
	stack.name = "Menus"
	stack.register_service = false
	# The client owns the pointer: it captures on a click, which is the only way a browser
	# will allow, and a stack that captured on close would be refused silently there.
	stack.manage_mouse = false
	var config := DotUiConfig.new()
	# Never paused. This is a networked game and the round does not stop because one
	# player is choosing a volume.
	config.allow_pause = false
	stack.config = config
	_layer.add_child(stack)

	var stacked := stack.setup()
	if not stacked.ok:
		return stacked

	screen = DotSettingsScreen.new()
	screen.name = "Settings"
	screen.title_text = "Settings"
	screen.half_size = Vector2(280.0, 210.0)
	var built := screen.build(settings)
	if not built.ok:
		screen.free()
		screen = null
		return built

	return stack.register(screen)


## Pushes every current value at whatever reads it. See the class note.
func apply_all() -> void:
	if settings == null:
		return

	for key in settings.schema.keys():
		_on_changed(key, settings.get_value(key), &"applied")


# --- What reads them ----------------------------------------------------------

## A sampler's tunables. The look fields only, which `DotFpsTunables.fingerprint` leaves
## out: a sensitivity is a preference and never enters the simulation, so writing it
## cannot put a client out of step with its server.
func bind_look(tunables: DotFpsTunables) -> void:
	if tunables == null or _look.has(tunables):
		return
	_look.append(tunables)
	_apply_look()


func bind_camera(camera: Camera3D) -> void:
	_camera = camera
	_apply_fov()


func bind_audio(audio: DotAudioManager) -> void:
	_audio = audio
	_apply_volume()


func _on_changed(key: StringName, _value: Variant, _why: StringName) -> void:
	match key:
		&"sensitivity":
			_apply_look()
		&"field_of_view":
			_apply_fov()
		&"master_volume", &"sfx_volume", &"voice_volume":
			_apply_volume()


func _apply_look() -> void:
	if settings == null:
		return

	var degrees := look_degrees_per_count(settings.get_float(&"sensitivity", 2.5))
	for tunables in _look:
		if tunables != null:
			tunables.mouse_sensitivity = degrees


func _apply_fov() -> void:
	if _camera != null and settings != null:
		_camera.fov = float(settings.get_int(&"field_of_view", DEFAULT_FOV))


func _apply_volume() -> void:
	if _audio == null or _audio.mixer == null or settings == null:
		return

	_audio.mixer.master = settings.get_float(&"master_volume", 0.8)
	_audio.mixer.sfx = settings.get_float(&"sfx_volume", 1.0)
	_audio.mixer.voice = settings.get_float(&"voice_volume", 1.0)
	# Only where there is a device. A headless run's buses are the engine's dummy ones,
	# and creating buses on them is work for nobody — dot-audio's own setup makes the same
	# call on the same condition.
	if DotAudioSink.device_present():
		var _missing := _audio.mixer.apply_to_buses()


## A sensitivity setting as degrees per unit of mouse motion. See [constant DEGREES_PER_COUNT].
static func look_degrees_per_count(sensitivity: float) -> float:
	return maxf(sensitivity, 0.0) * DEGREES_PER_COUNT


# --- The screen ------------------------------------------------------------------

func is_open() -> bool:
	return stack != null and stack.any_open()


func open() -> void:
	if stack != null and screen != null and not stack.is_open(screen.screen_id()):
		var _pushed := stack.push(screen.screen_id())


func close() -> void:
	if stack != null and screen != null and stack.is_open(screen.screen_id()):
		var _popped := stack.pop(screen.screen_id())


func describe() -> Dictionary:
	var out := settings.describe() if settings != null else {}
	out["open"] = is_open()
	out["look_bound"] = _look.size()
	out["camera_bound"] = _camera != null
	out["audio_bound"] = _audio != null
	return out
