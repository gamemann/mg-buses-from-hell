extends DotGameModule

const BfhNetBridge := preload("net/bfh_net_bridge.gd")
const BfhServices := preload("bfh_services.gd")
const BfhPlayer := preload("bfh_player.gd")

const BfhGame := preload("bfh_game.gd")
const BfhStats := preload("bfh_stats.gd")

## Where the services keep punishments. Empty is [DotGameServices]'s own default,
## `user://buses_punishments.json` — the store a real server enforces.
##
## [b]Static, because nothing holds this module before it exists[/b]: dot-server constructs
## it from a path inside `load_module`, so there is no instance for a host to set a field on
## first. `examples/dedicated.tscn` points it at a directory of its own; before it could,
## every run appended the live tools' audit warnings to the real store, 134 of them by the
## time anybody counted. game-simple-lobby's `RoomModule.punishments_path` is the same seam.
static var punishments_file: String = ""

## This game, as a module a dedicated server loads.
##
## [b]The first game in this family to subclass [DotGameModule], and the reason it is the
## first is that it is the newest.[/b] The other five were written before that addon
## existed and each carries its own copy of the two hundred lines it holds — the netcode
## and its four load-bearing constants, the bridge, the seal, the identity layer, the
## roster, the tick, and a teardown in the reverse order. Two of those five copies had the
## same line wrong and nobody could join those servers. This file is what is actually
## this game's, and it is ninety lines.
##
## [b]No `class_name`, and that is a requirement rather than a style.[/b]
## [method DotModuleHost.load_module] takes a PATH and constructs the module itself — it
## must, because that is the shape that lets an operator name one in a config file — and a
## module delivered inside a dot-cloud pack cannot have a `class_name` at all: a mounted
## pack's globals are not registered in the host.
##
## [codeblock]
## server.modules.load_module("res://game/bfh_module.gd")
## [/codeblock]

# [b]No `const CHANNEL` here, and its absence is the point.[/b] [DotGameModule] already
# declares one and GDScript refuses to let a subclass redeclare it — which is the right
# refusal: a module logs through [method DotModule.log_info], which stamps the module's
# own name, so a second channel would split one module's records across two places an
# operator has to know to turn up separately.


func _module_name() -> String:
	return "buses"


func _game_service() -> StringName:
	return BfhGame.SERVICE


func _game_missing_hint() -> String:
	return (
		"create a BfhGame, add it to the tree and let its _ready() register it under "
		+ "'%s' — a module cannot build the world, because the world outlives it"
		% String(BfhGame.SERVICE)
	)


## The netcode's numbers, which are the game's and not the addon's.
##
## Tick rate from the world, so `sv_tickrate` reaches it: the server sets the engine's
## physics rate from that cvar at boot, the world is built after the server and reads it,
## and this reads the world. A number written here instead would be a netcode running at a
## rate the operator did not choose, silently.
func _net_config() -> DotNetConfig:
	var config := DotNetConfig.new()
	config.tick_rate = (game as BfhGame).tick_rate
	config.snapshot_rate = BfhGame.NET_SNAPSHOT_RATE
	config.world_extent = BfhGame.NET_WORLD_EXTENT
	config.enable_prediction = true
	# [b]Off, and this is the one game in the family where that is obviously right.[/b]
	# Lag compensation exists to resolve one player's shot against where they saw
	# somebody. Nothing here is resolved that way: the hammer has a reach of 2.4 m and
	# hits scenery, and a bus hits people by being where they are. There is no shot to
	# rewind for.
	config.enable_lag_compensation = false
	# A bowl holds thirty-odd crates, nine barrels, a handful of blocks and two buses, and
	# they are all always relevant — see [BfhNetBridge] on why nothing here is culled.
	config.max_entities_per_snapshot = 96
	return config


func _make_bridge() -> Node:
	return BfhNetBridge.new()


## Chat, voice and moderation, over [DotGameServices].
##
## [b]The bridge is handed over as the link, and that is the whole of the wiring.[/b] A
## chat line goes out through `send_chat` and a voice frame through `send_voice`, both on
## this game's own wire — see [BfhNetLink]. [DotGameModule] does the rest: it assigns the
## bridge's `voice_relay_fn`, checks `check_admission` before seating anybody, and tells
## the roster to follow this layer so a leaver is forgotten by the rate limiter and the
## voice router together.
func _make_services() -> Node:
	var services := BfhServices.new()
	services.bridge = bridge
	services.punishments_file = punishments_file
	return services


## [b]No identity layer, and that one is still deliberate.[/b] Profiles and avatars are
## real in this family and this game has not written that layer; [DotGameModule] logs its
## absence and carries on, which is the honest state — a server where everybody is a guest
## is a server. What it is NOT is a gap in anything else: a client connects, plays a whole
## round, talks, is scored, and can be gagged for it.
func _wants_platform_module() -> bool:
	return false


func _game_load() -> DotResult:
	var world := game as BfhGame

	if world == null:
		return DotResult.fail(
			DotError.CODE_STATE, "The registered game is not a BfhGame."
		)

	add_command("bfh_status", _cmd_status, "Show the round, the bowl and the buses")
	add_command("bfh_net", _cmd_net, "Show what the netcode is doing")
	add_command("bfh_say", _cmd_say, "Say something to everybody, as the server")
	add_command(
		"bfh_stats", _cmd_stats,
		"A player's numbers this session and what they have earned: bfh_stats <userid>"
	)

	_wire_chat()

	_add_tunables(world)

	_bots = add_cvar(
		"bfh_bots", "1",
		"Fill empty driving seats with bots. 0 leaves them empty."
	)

	# [b]Started here and not in the world's own `_ready`.[/b] `start()` lays the bowl out
	# and puts the buses on it, and a world that did that before the bridge existed would
	# have spawned every crate with nothing listening to `props.spawned` — thirty-four
	# bodies the server knows about and no client is ever told about. They would be
	# invisible cover: a runner shelters behind a crate a bus cannot see, and the bus
	# drives through it.
	world.start()

	log_info("the bowl is open", world.describe())
	return DotResult.success(null)


## The numbers an operator is actually going to want to change, as cvars.
##
## [b]Live, and each one writes through to the config the world already reads.[/b] The
## alternative is what most of this family's games still do — a JSON file and a restart —
## and the reason to do better here is the shape of this particular game: the whole thing
## is a balance between a bus's top speed, how much cover there is and how long a round
## lasts, and an operator finds their server's numbers by moving one of them between
## rounds with people watching.
##
## [b]What is NOT here is anything the world has already built.[/b] `bfh_crates` changes
## how many crates the NEXT round is laid out with; it does not put crates in the bowl
## now. A cvar that pretended otherwise would be one an admin sets in the middle of a
## round and then reports as broken.
func _add_tunables(world: BfhGame) -> void:
	var config := world.config

	_tunable("bfh_round_seconds", config.round_seconds, "Seconds in a round",
		func(value: float) -> void: config.round_seconds = value)
	_tunable("bfh_crates", float(config.crate_count), "Crates the next round is laid out with",
		func(value: float) -> void: config.crate_count = int(value))
	_tunable("bfh_barrels", float(config.barrel_count), "Barrels the next round is laid out with",
		func(value: float) -> void: config.barrel_count = int(value))
	_tunable("bfh_drivers", float(config.driver_count), "How many seats there are to drive",
		func(value: float) -> void: config.driver_count = int(value))
	_tunable("bfh_bus_top_speed", config.bus_top_speed, "A bus's top speed, in m/s",
		func(value: float) -> void: config.bus_top_speed = value)
	_tunable("bfh_bus_lethal_speed", config.bus_lethal_speed,
		"Closing speed at which a bus kills outright, in m/s",
		func(value: float) -> void: config.bus_lethal_speed = value)


## A number as an operator would type it: `34`, not `34.000000`.
##
## [b]Not `%g`, which GDScript's format strings do not have.[/b] It is accepted by the
## parser and fails at RUNTIME with "unsupported format character" — inside `_game_load`,
## which is the one place in the module sequence that unwinds everything above it. The
## symptom was a server whose netcode came up, logged that it was ready, and then reported
## that the game would not load.
static func _number(value: float) -> String:
	return "%d" % int(round(value)) if is_equal_approx(value, round(value)) else "%.2f" % value


## One cvar, its default taken from the configuration rather than written twice.
##
## [b]The default is the value the world was built with, and that is the whole point.[/b]
## A cvar declared with a literal default is a second copy of a number that
## `defaults < JSON < environment < argv` has already decided — so an operator who set
## `BFH_ROUND_SECONDS=300` would see `bfh_round_seconds` report 180 and, worse, would
## reset their own setting the moment anything wrote the value back.
func _tunable(
	cvar_name: String, current: float, description: String, apply: Callable
) -> void:
	var cvar := add_cvar(cvar_name, _number(current), description)

	if cvar == null:
		return

	cvar.changed.connect(func(_old: String, _new: String) -> void:
		apply.call(cvar.get_float())
		log_info("a tunable changed", {"cvar": cvar_name, "now": cvar.get_string()})
	)


## [b]Nothing to undo.[/b] The commands are the module's own and [DotModule] removes them;
## the netcode, the bridge and the roster are [DotGameModule]'s and it tears them down in
## the reverse order it built them. The world is NOT this module's to free: it was in the
## tree before the module loaded and a server can unload and reload a game module without
## the bowl going away, which is what `module reload` is for.
func _game_unload() -> void:
	pass


## Seconds between checks of who is driving. See [method _keep_the_seats_full].
const BOT_INTERVAL := 2.0

## The `bfh_bots` cvar, held so the tick does not look it up sixty times a second.
var _bots: DotConVar = null

var _since_bot_check: float = 0.0


## [b]A server with nobody in the buses is a server with no game in it, and that is
## specific to this game rather than a general nicety.[/b] Every other game in this family
## degrades gracefully when it is empty: a deathmatch with one person in it is a person
## walking around a map, a sandbox with one person in it is the whole sandbox. This one is
## ASYMMETRIC — a runner with no bus to run from has nothing at all to do, and
## `sides_are_playable` correctly refuses to start a round, so the first visitor to an
## empty server would stand in a bowl watching a clock that never moves.
##
## So the seats are kept full. A bot is removed the moment a person wants to drive, which
## is the other half: the bots are there to make the game exist, not to take the fun half
## from the people who came to play it.
func _game_tick(_tick: int, delta: float) -> void:
	_since_bot_check += delta

	if _since_bot_check < BOT_INTERVAL:
		return

	_since_bot_check = 0.0
	_keep_the_seats_full()


func _keep_the_seats_full() -> void:
	var world := game as BfhGame

	if world == null or bridge == null or _bots == null or not _bots.get_bool():
		return

	var wanted := world.config.driver_count
	var humans := 0
	var bots: Array[BfhPlayer] = []

	for driver in world.drivers():
		if driver.is_bot:
			bots.append(driver)
		else:
			humans += 1

	# [b]A bot that is no longer a driver is removed rather than left to walk.[/b] Sides
	# swap every few rounds and take the bots with them, and a bot RUNNER is a person
	# shaped obstacle that never moves: free points for the drivers and nothing for
	# anybody else. There is no walking AI here and there should not be one — the bots
	# exist to fill a bus, and a bus is the only thing this game can drive itself.
	for player in world.runners():
		if player.is_bot:
			bridge.call("remove_player", BfhNetBridge.session_of(player.player_id))

	var short := wanted - humans - bots.size()

	for _i in range(maxi(short, 0)):
		if bridge.call("add_bot", "Bus driver", BfhGame.TEAM_DRIVERS) == null:
			break

	# And one bot stands down for each person who wants the seat.
	for _i in range(maxi(humans + bots.size() - wanted, 0)):
		if bots.is_empty():
			break

		var leaving: BfhPlayer = bots.pop_back()
		bridge.call("remove_player", BfhNetBridge.session_of(leaving.player_id))


## Joins the bridge's two chat seams to the services layer's router.
##
## [b]Here rather than in either of them, because this is the only object that holds
## both.[/b] The bridge knows what arrived on the wire and nothing about what a line means;
## the services layer knows the rules and nothing about the wire. That separation is the
## reason a client cannot send a line with somebody else's name on it: what crosses is a
## channel id and a string, and everything else is decided on this side.
func _wire_chat() -> void:
	if bridge == null or services == null:
		return

	bridge.connect("say_requested", _on_say_requested)

	# What a client that has gone quiet is told, and what an admin's own commands echo
	# through. A refusal reaches the one person who asked; a refusal broadcast would be
	# a rate limit announced to the server.
	services.connect("command_entered", _on_chat_command)


func _on_say_requested(peer_id: int, channel_id: StringName, text: String) -> void:
	var said: DotResult = services.call("say", peer_id, channel_id, text)

	if said.ok:
		return

	# Back to the one person who asked. See [method BfhNetBridge.notice].
	bridge.call("notice", peer_id, said.error.message)


## A `!command` typed into chat. Run through the console as the person who typed it.
##
## [b]As THEM, not as the server.[/b] `run_command_as_uid` builds a context with that
## player's own flags, so `!kick` from somebody without the flag is refused by the same
## file that refuses it at the console — rather than by this function having an opinion.
func _on_chat_command(peer_id: int, command: String, args: PackedStringArray) -> void:
	if server == null:
		return

	var session := server.session_of(peer_id)

	if session == null:
		return

	for reply in server.run_command_as_uid(
		session.uid(), command, args, DotCmdContext.Source.CHAT
	):
		bridge.call("notice", peer_id, reply)


## The operator's own voice in the room. `bfh_say the server is restarting in a minute`.
func _cmd_say(ctx: DotCmdContext) -> void:
	var text := ctx.rest()

	if text.strip_edges() == "":
		ctx.reply("Say what?")
		return

	if services == null or services.get("chat") == null:
		ctx.reply("This server has no chat.")
		return

	var announced: Variant = services.get("chat").call("announce", text, BfhServices.CH_ALL)

	if announced is DotResult and not (announced as DotResult).ok:
		ctx.reply_error(announced)
		return

	ctx.reply("Said: %s" % text)


## One player's session: the five numbers and what they have earned. With no argument,
## everybody counted, one line each.
##
## [b]By userid, as the player list prints it, not by the storage key.[/b] The key is an
## implementation detail (`bfh-u<userid>`) and an operator types what `status` shows.
func _cmd_stats(ctx: DotCmdContext) -> void:
	var world := game as BfhGame

	if world == null or world.progress == null:
		ctx.reply("This server is not counting anything.")
		return

	var wanted := ctx.rest().strip_edges()

	if wanted != "":
		ctx.reply_lines(world.progress.player_lines(BfhNetBridge.player_key(wanted.to_int())))
		return

	var any := false

	for id: StringName in world.players:
		if world.progress.key_of(id) == "":
			continue
		any = true
		var values: DotStatsValues = world.progress.session_values(id)
		ctx.reply("%-8s %-20s flattened %d  survived %d  broken %d  in the way %d  %d s" % [
			String(id).trim_prefix("u"),
			(world.players[id] as BfhPlayer).display_name,
			int(values.get_value(BfhStats.RUNNERS_FLATTENED)),
			int(values.get_value(BfhStats.ROUNDS_SURVIVED)),
			int(values.get_value(BfhStats.CRATES_BROKEN)),
			int(values.get_value(BfhStats.CRATES_INTO_PATH)),
			int(values.get_value(BfhStats.SECONDS_SURVIVED)),
		])

	if not any:
		ctx.reply("Nobody is being counted. Bots are not.")


func _cmd_status(ctx: DotCmdContext) -> void:
	var world := game as BfhGame

	if world == null:
		ctx.reply("No world.")
		return

	ctx.reply_lines(world.describe_lines())


func _cmd_net(ctx: DotCmdContext) -> void:
	if bridge == null:
		ctx.reply("No bridge; this server is not replicating anything.")
		return

	ctx.reply_lines(bridge.call("describe_lines"))

	if services != null:
		ctx.reply_lines(services.call("describe_lines"))


func describe() -> Dictionary:
	var out := super.describe()
	var world := game as BfhGame

	if world != null:
		out.merge({"round": world.round_number, "bowl": world.describe()}, true)

	return out
