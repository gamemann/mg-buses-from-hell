extends DotGameServices

const BfhGame := preload("bfh_game.gd")
const BfhNetBridge := preload("net/bfh_net_bridge.gd")
const BfhPlayer := preload("bfh_player.gd")

## Chat, voice and moderation — and the moderator's live tools — wired to this game's two sides.
##
## [b]Sixty lines, because [DotGameServices] holds the other five hundred.[/b] The five
## games written before this one each carry their own copy — 557 to 718 lines, differing in
## the channels, the rules and a voice range — and this is the first game to take the base
## instead. What is left here is what is genuinely this game's: who can hear whom, and
## where a player is standing.
##
## [b]The sides are the whole design, so the sides are the channels.[/b] Two drivers
## against everybody else is a game about two conversations that must not overhear each
## other: the drivers arranging who takes which half of the bowl, and the runners saying
## which way one is coming. `team` is therefore the channel that matters here — in a
## deathmatch it is a convenience and here it is the game — and it is what VOICE defaults
## to, which no other game in this family does.
##
## [b]There is no proximity channel, and that is a decision about the map.[/b] The bowl is
## 46 m across and a proximity range worth having would be most of it; a channel that
## reaches nearly everybody is a channel that lies about who can hear you. game-playground
## has one because a sandbox is a place with corners.

# No `const CHANNEL`: [DotGameServices] declares one and GDScript refuses a redeclaration,
# which is the right refusal — one layer, one channel an operator can turn up.

const CH_ALL := &"all"
const CH_TEAM := &"team"
const CH_ADMIN := &"admin"
const CH_WHISPER := &"whisper"


## The bridge, for the roster lookup `_position_of` needs. Set before [method setup].
var bridge: BfhNetBridge = null


func _services_name() -> String:
	return "buses"


## What a line may be.
##
## [b]Short and slow, because a runner types while being chased.[/b] 140 characters and 20
## a minute is a game whose chat is called out rather than written out: "north ramp", "he's
## turning". A sandbox's 200 at 30 is for people standing still, and this game has nobody
## standing still in it.
func _chat_rules() -> Object:
	return chat_rules()


## The same rules, as a static a CLIENT can ask for without building a services layer.
##
## [b]Static because the other end needs them and must not instantiate this.[/b]
## `BfhServices` is a [Node] with a moderation store and a router under it; a client that
## called `new()` on one to read two numbers off it would build all of that, leak it, and
## — inside a delivered pack — fail to compile, because a script whose base class comes
## from the HOST cannot have its return type inferred by a script in the mount. Both were
## measured: seven leaked objects in a suite, and a client scene that would not load at
## all on a real server.
static func chat_rules() -> DotChatRules:
	var rules := DotChatRules.new()
	rules.max_length = 140
	rules.refuse_over_length = false
	rules.allow_newlines = false
	rules.escape_markup = true
	rules.strip_invisible = true
	rules.collapse_whitespace = true
	rules.rate_per_minute = 20
	rules.burst = 4.0
	rules.flood_penalty_sec = 10.0
	rules.duplicate_window_sec = 8.0
	rules.duplicate_depth = 3
	rules.command_prefixes = PackedStringArray(["!", "/"])
	# An unclaimed `!command` is not broadcast: a player typing `!ban` at a server with no
	# such command would otherwise say "!ban" to the whole server, which is worse than
	# nothing happening.
	rules.broadcast_unknown_commands = false
	rules.history_limit = 300
	return rules


func _chat_channels() -> Array:
	return chat_channels()


## The channels, as a static for the same reason [method chat_rules] is one.
static func chat_channels() -> Array[DotChatChannel]:
	var out: Array[DotChatChannel] = []

	var everyone := DotChatChannel.make(CH_ALL, "All", DotChatChannel.Scope.EVERYONE)
	everyone.colour = Color(0.93, 0.94, 0.96)
	# Short, because a round is three minutes: a backlog longer than the round is a
	# conversation from a game the new player was not in.
	everyone.backlog = 10
	everyone.history_limit = 200
	out.append(everyone)

	var team := DotChatChannel.make(CH_TEAM, "Team", DotChatChannel.Scope.TEAM)
	team.prefix = "[team]"
	team.colour = Color(0.55, 0.82, 0.95)
	# [b]No backlog, and it is the sides that make that matter.[/b] A backlog is handed to
	# whoever joins — and everybody swaps sides every third round, so a replayed team line
	# is one side's plan handed to the people it was about.
	team.backlog = 0
	team.history_limit = 120
	out.append(team)

	var admin := DotChatChannel.make(CH_ADMIN, "Admin", DotChatChannel.Scope.EVERYONE)
	admin.prefix = "[ADMIN]"
	admin.colour = Color(0.98, 0.72, 0.35)
	admin.admin_only = true
	# A gag is about a player's speech; an admin who has been gagged has a bigger problem
	# than chat.
	admin.ignores_gag = true
	admin.backlog = 0
	out.append(admin)

	var whisper := DotChatChannel.make(CH_WHISPER, "Whisper", DotChatChannel.Scope.DIRECT)
	whisper.prefix = "[w]"
	whisper.colour = Color(0.78, 0.71, 0.93)
	whisper.backlog = 0
	out.append(whisper)

	return out


## The voice format, which both ends must agree on exactly.
##
## Static, because the CLIENT builds one too and a sample rate that differs between two
## peers is a stream of packets the router refuses for being the wrong length, counted and
## said to nobody. [method DotVoiceConfig.format_fingerprint] exists for that reason.
static func voice_format() -> DotVoiceConfig:
	var config := DotVoiceConfig.new()
	config.sample_rate = 16000
	config.frame_ms = 20.0
	config.codec_id = &"adpcm"
	# [b]Push to talk, in the one game in this family where it is not a preference.[/b] A
	# runner is being chased by a bus and is breathing into a microphone; open-mic voice
	# on a side of six people is six sets of breathing over the one thing anybody needs to
	# hear, which is somebody saying which way it is coming.
	config.push_to_talk = true
	config.activation_rms = 0.02
	config.hangover_ms = 250.0
	config.jitter_ms = 60.0
	config.jitter_max_ms = 400.0
	config.proximity_range = 24.0
	config.max_bytes_per_second = 6144
	return config


func _voice_config() -> Object:
	return voice_format()


## TEAM, and this is the only game here that says so.
##
## Everywhere else voice is the whole server, because everywhere else the sides are teams
## in a game rather than the game itself. Two drivers coordinating which half of the bowl
## each takes is a conversation the runners must not hear, and the runners calling a bus's
## line is one the drivers must not.
func _voice_default_channel() -> int:
	return DotVoiceRouter.Channel.TEAM


## Which side somebody is on, for the team channel and for team voice.
##
## [b]Read off the game rather than off dot-team, because the sides swap.[/b] `BfhGame`
## owns `sides` and rewrites the whole table every few rounds; anything caching a team id
## would put a player in the conversation they were in two rounds ago.
func _team_of(peer_id: int) -> int:
	var player := _player_of(peer_id)
	return (game as BfhGame).team_of(player.player_id) if player != null else 0


func _position_of(peer_id: int) -> Vector3:
	var player := _player_of(peer_id)

	# [b]The simulated state, not the node.[/b] A driver is not reparented into the bus in
	# this game — the ride is told not to carry rider nodes — but the state is still the
	# position the simulation agreed on, and the node is wherever the last frame drew them.
	return player.controller.state.position if player != null else Vector3.ZERO


func _player_of(peer_id: int) -> BfhPlayer:
	if bridge == null or game == null:
		return null

	var session_id := bridge.player_for_peer(peer_id)

	if session_id == 0:
		return null

	return (game as BfhGame).players.get(BfhNetBridge.player_key(session_id))


# --- dot-moderation's live tools ---------------------------------------------

## What the admin set means here, one callable per ability. See `DotGameServices`.
##
## [b]What is refused is refused for a reason about THIS game, and says so.[/b] Respawn is
## the one worth reading: a runner who is out stays out until the next round, and an admin
## who put one back mid-round would be deciding who won. Give and strip are refused because
## there is one thing anybody holds here and it is not a weapon. Anything that moves a body
## is refused for a driver while they drive, because the bus is what is moving and the
## body is a passenger in it.
func _mod_abilities() -> Dictionary:
	return {
		"noclip": func(id: StringName, args: Dictionary) -> DotResult:
			return _on_foot(id, func(p: BfhPlayer) -> DotResult:
				return DotFpsAdminModifiers.set_noclip(p.controller, bool(args["on"]))),
		"freeze": func(id: StringName, args: Dictionary) -> DotResult:
			return _on_foot(id, func(p: BfhPlayer) -> DotResult:
				return DotFpsAdminModifiers.set_frozen(p.controller, bool(args["on"]))),
		"speed": func(id: StringName, args: Dictionary) -> DotResult:
			return _on_foot(id, func(p: BfhPlayer) -> DotResult:
				return DotFpsAdminModifiers.set_speed(p.controller, float(args["scale"]))),
		"gravity": func(id: StringName, args: Dictionary) -> DotResult:
			return _on_foot(id, func(p: BfhPlayer) -> DotResult:
				return DotFpsAdminModifiers.set_gravity(p.controller, float(args["scale"]))),
		"god": func(id: StringName, args: Dictionary) -> DotResult:
			var p := _mod_player(id)
			if p == null or p.health == null:
				return _mod_absent(id)
			p.health.invulnerable = bool(args["on"])
			return DotResult.success(p.health.invulnerable),
		"buddha": func(id: StringName, args: Dictionary) -> DotResult:
			var p := _mod_player(id)
			if p == null or p.health == null:
				return _mod_absent(id)
			p.health.cannot_die = bool(args["on"])
			return DotResult.success(p.health.cannot_die),
		"health": func(id: StringName, args: Dictionary) -> DotResult:
			var p := _mod_player(id)
			if p == null or p.health == null:
				return _mod_absent(id)
			if not p.health.alive:
				return DotResult.fail(DotError.CODE_STATE, "They are out until the next round.")
			p.health.health = minf(float(args["value"]), 2000.0)
			return DotResult.success(p.health.health),
		"slay": func(id: StringName, _args: Dictionary) -> DotResult:
			return _mod_hurt(id, -1.0),
		"slap": func(id: StringName, args: Dictionary) -> DotResult:
			return _mod_hurt(id, float(args.get("damage", 0.0))),
		# [b]The screen and nothing else, for either side.[/b] A blinded runner still
		# moves and can still be run over; a blinded driver still drives, which is the
		# point. An admin who wants a runner stopped as well has freeze, and a verb that
		# did both would be a verb nobody could use for only the first.
		"blind": func(id: StringName, args: Dictionary) -> DotResult:
			var p := _mod_player(id)
			if p == null:
				return _mod_absent(id)
			p.blinded = bool(args["on"])
			return DotResult.success(p.blinded),
		# On a driver the beacon is drawn round their BUS, because the bus is the only
		# thing anybody can see of them; see `bfh_beacon.gd`.
		"beacon": func(id: StringName, args: Dictionary) -> DotResult:
			var p := _mod_player(id)
			if p == null:
				return _mod_absent(id)
			p.beacon = bool(args["on"])
			return DotResult.success(p.beacon),
		"rename": func(id: StringName, args: Dictionary) -> DotResult:
			var p := _mod_player(id)
			if p == null:
				return _mod_absent(id)
			p.display_name = str(args["name"]).strip_edges().substr(0, 32)
			return DotResult.success(p.display_name),
	}


func _mod_unsupported() -> Dictionary:
	return {
		"respawn": "a runner who is out stays out until the next round; putting one back decides who won",
		"give": "the hammer is the only thing anybody holds here",
		"strip": "the hammer is the only thing anybody holds here, and without it a runner has no game",
		"burn": "there is no fire in the bowl",
	}


## Toggles that outlive a new body here, beyond dot-moderation's own god and buddha.
##
## [b]Blind and beacon are about the person, not the body.[/b] Noclip and freeze end with
## the round because arriving in a new round frozen is the round broken; a player an admin
## blinded, or wanted the bowl to watch, is still that player after a round — and a round
## ending is exactly what a player being punished would otherwise wait out.
const PERSIST_ON_RESPAWN: Array[String] = ["blind", "beacon"]


func _mod_can_teleport() -> bool:
	return true


func _mod_position(id: StringName) -> Variant:
	var p := _mod_player(id)
	return p.controller.state.position if p != null and not p.riding else null


func _mod_teleport(id: StringName, to: Variant) -> void:
	var p := _mod_player(id)

	if p == null or p.riding or not (to is Vector3):
		return

	p.controller.teleport(to as Vector3, p.controller.state.yaw, p.controller.state.pitch)


func _mod_configure_commands(commands: Object) -> void:
	commands.set("alive_fn", func(id: StringName) -> bool:
		var p := _mod_player(id)
		return p != null and p.health != null and p.health.alive)
	# The two sides by name, because `@team:drivers` is what an admin types.
	commands.set("team_fn", func(id: StringName) -> String:
		match (game as BfhGame).team_of(_mod_key(id)):
			BfhGame.TEAM_DRIVERS:
				return "drivers"
			BfhGame.TEAM_RUNNERS:
				return "runners"
		return "")


func _mod_key(id: StringName) -> StringName:
	return BfhNetBridge.player_key(String(id).to_int())


func _mod_player(id: StringName) -> BfhPlayer:
	if game == null or not String(id).is_valid_int():
		return null

	return (game as BfhGame).players.get(_mod_key(id))


func _mod_absent(id: StringName) -> DotResult:
	return DotResult.fail(DotError.CODE_STATE, "Player %s is not in the bowl." % String(id))


func _on_foot(id: StringName, act: Callable) -> DotResult:
	var p := _mod_player(id)

	if p == null:
		return _mod_absent(id)

	if p.riding:
		return DotResult.fail(DotError.CODE_STATE, "They are driving a bus; the bus is what moves.")

	return act.call(p)


## A slay (amount < 0) or a slap, as ordinary damage through the combat manager — so the
## round's elimination rule hears about a slain runner exactly as it hears about a bus.
func _mod_hurt(id: StringName, amount: float) -> DotResult:
	var p := _mod_player(id)

	if p == null or p.health == null:
		return _mod_absent(id)

	if not p.health.alive:
		return DotResult.fail(DotError.CODE_STATE, "They are already out.")

	var bowl := game as BfhGame

	if amount < 0.0:
		var was_god := p.health.invulnerable
		var was_buddha := p.health.cannot_die
		p.health.invulnerable = false
		p.health.cannot_die = false
		var fatal := DotDamage.make(0, p.entity_id, p.health.health + 1000.0, null)
		fatal.weapon_id = &"slay"
		bowl.combat.apply_damage(fatal)
		p.health.invulnerable = was_god
		p.health.cannot_die = was_buddha
		return DotResult.success(null) if fatal.lethal else DotResult.fail(
			DotError.CODE_STATE, "The slay was refused: %s" % fatal.refusal
		)

	if not p.riding:
		# Into the simulated velocity, which replicates; the owning client reconciles to it.
		p.controller.state.velocity += Vector3(3.0, 5.0, 3.0)
		p.controller.state.mode = DotFpsState.Mode.AIR

	if amount > 0.0:
		var hurt := DotDamage.make(0, p.entity_id, amount, null)
		hurt.weapon_id = &"slap"
		bowl.combat.apply_damage(hurt)

	return DotResult.success(null)


## A round is everybody's new body: a freeze or a noclip from last round ends, god carries.
func _on_round_began_for_tools(_number: int) -> void:
	for key: StringName in (game as BfhGame).players:
		mod_player_respawned(StringName(str(BfhNetBridge.session_of(key))))


## The team seam dot-chat and dot-voice both ask for, which the base cannot wire.
##
## [DotGameServices] knows nothing about teams — a lobby has none — so the two `team_fn`
## hooks are set here, after the base has built each router.
func setup(p_server: DotServer, p_game: Object, p_link: Object) -> DotResult:
	var ready_now: DotResult = await super.setup(p_server, p_game, p_link)

	if not ready_now.ok:
		return ready_now

	if chat != null:
		chat.set("team_fn", Callable(self, "_team_of"))

	if voice != null:
		voice.set("team_fn", Callable(self, "_team_of"))

	# Read, appended and written back. Measured on 4.7.2, the append alone already reaches
	# the tools' own [PackedStringArray] — a packed array fetched through `get` shares its
	# buffer — but this family has also shipped the opposite case (an append to a packed
	# array inside a Dictionary landed on a copy), and the `set` is what stops this line
	# depending on which of the two the engine does. `dedicated` fails without the append.
	if mod_tools != null:
		var keep: PackedStringArray = mod_tools.get("persist_on_respawn")
		for action in PERSIST_ON_RESPAWN:
			if not keep.has(action):
				keep.append(action)
		mod_tools.set("persist_on_respawn", keep)

	if game is BfhGame and not (game as BfhGame).round_began.is_connected(_on_round_began_for_tools):
		(game as BfhGame).round_began.connect(_on_round_began_for_tools)

	DotLog.info(CHANNEL, "chat, voice and moderation are up for this game", describe())
	return ready_now
