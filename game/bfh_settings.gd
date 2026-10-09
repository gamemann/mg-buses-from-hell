extends DotMenuSettings

## A player's own settings and the menu that changes them: how fast the view turns, how wide
## it is, how loud things are, the window, and the look of the menu itself.
##
## [codeblock]
## var settings := BfhSettings.new()
## add_child(settings)
## settings.setup()                    # loads, and pushes every value at what reads it
## settings.bind_look(sampler.tunables)
## settings.bind_camera(camera)
## settings.bind_audio(audio.manager)
## settings.open()                     # Escape does this in the client
## [/codeblock]
##
## [b]dot-menu's `DotMenuSettings` with this game's schema[/b] (2026-10-09). This was the
## original of a 250-line file — a manager, a `match` over four keys and a bare settings
## screen — that five other games copied. What is left here is what is this
## game's: where the document lives, and the stock keys it has nothing to apply to.
##
## [b]The scopes are the family's, not this game's.[/b] `sensitivity` is ACCOUNT under the
## shared `tmc_account` namespace — a person's hand, the same number in every game here.
## `field_of_view` is SERVER_CLAMPED: a wide view is an advantage a server may cap, and
## dot-settings gives a server no way to READ it. The volumes are this machine's.

const SCHEMA_VERSION := 1

## Where this game's own document lives. The shared account document is dot-settings'.
const SETTINGS_DIR := "user://buses_settings"

## The app's namespace. ACCOUNT settings are shared under dot-menu's `tmc_account`.
const APP_NAMESPACE := &"buses_from_hell"

## The field of view the camera had before this existed, and still the default.
const DEFAULT_FOV := 90

## Stock keys nothing here applies: the chat box has no switch. The interface bus is real
## here (the round's cues play on it) and so are the effects, which the client binds.
const NOT_APPLIED: Array[StringName] = [&"chat_window"]


func _init() -> void:
	name = "Settings"
	directory = SETTINGS_DIR
	app_namespace = APP_NAMESPACE
	schema = schema_for()
	config = DotMenuConfig.new()
	config.brand_name = "Buses from Hell"
	# Nothing to leave to and no keys table to help with; Escape and Resume close the menu.
	config.show_help = false
	config.show_leave = false
	var _layered := config.load_layered()


## The document: this game's field of view first, so it keeps its own default, then the
## stock settings it applies.
static func schema_for() -> DotSettingsSchema:
	var s := DotSettingsSchema.new()
	s.version = SCHEMA_VERSION
	s.add(DotSettingsDef.integer(&"field_of_view", DEFAULT_FOV, 70, 120, &"video").with_scope(
		DotSettingsDef.Scope.SERVER_CLAMPED
	))
	return DotMenuStock.declare(s, DotMenuStock.DEFAULT_GROUPS, null, NOT_APPLIED)
