extends Node

const BfhConfig := preload("bfh_config.gd")
const BfhGame := preload("bfh_game.gd")

## What a [DotServer] loads as its game scene. Never a client.
##
## [b]Small on purpose.[/b] Everything a dedicated server does is in `bfh_module.gd`;
## this exists because dot-server loads a SCENE and the game needs one, and because the
## world has to be in the tree — registered under [constant BfhGame.SERVICE] — before the
## module looks for it. dot-server loads the scene and then the module, in that order, for
## exactly this reason.
##
## [b]It lives in `game/`, not beside its own scene in `scenes/`.[/b] That is a deployment
## constraint rather than a preference: a game is vendored by copying its `game/`
## wholesale and its `scenes/*.tscn` — only the `.tscn` — so a script under `scenes/` is a
## script that never reaches the build. The scene then fails to load with "referenced
## non-existent resource", the module refuses to load because no game registered itself,
## and the server reports that the game loaded but its module did not. Every other game in
## this family keeps its server scene's script in `game/`, having learned it the same way.

const CHANNEL := "bfh.server"

## The world this server is running. What the module will find in the registry.
var game: BfhGame = null


func _ready() -> void:
	var config := BfhConfig.new()

	# The family's `defaults < JSON < environment < argv` chain, on the server too. It is
	# how an operator sets `BFH_ROUND_SECONDS` or `--bfh-arena-radius` without editing
	# anything, and the cvars the module adds are the live half of the same numbers.
	var loaded := config.load_layered("user://cfg/buses-from-hell.json")

	if not loaded.ok:
		DotLog.warn(CHANNEL, "falling back to defaults", {"why": loaded.error.message})

	game = BfhGame.new()
	game.name = "World"
	game.config = config
	# [b]The engine's rate, which the server has already set from `sv_tickrate`.[/b] Read
	# rather than chosen: this scene is loaded after the server has booted and executed
	# its config, so the number is already decided — and a game that picked its own would
	# be a simulation running at one rate inside a process ticking at another.
	game.tick_rate = Engine.physics_ticks_per_second
	add_child(game)

	DotLog.info(CHANNEL, "the world is up", {
		"tick_rate": game.tick_rate,
		"bowl": "%.0f m" % config.arena_radius,
	})

	# [b]Not started here.[/b] `start()` lays the bowl out and puts the buses on it, and
	# nothing is listening yet: the module builds the bridge that answers `props.spawned`,
	# so a bowl laid out now is thirty-four crates no client is ever told about. The module
	# starts it, on the last line of its own load.
