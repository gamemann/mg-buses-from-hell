extends Node3D

const BfhArena := preload("bfh_arena.gd")
const BfhConfig := preload("bfh_config.gd")
const BfhContent := preload("bfh_content.gd")
const BfhPlayer := preload("bfh_player.gd")

## The simulation. Headless, authoritative, and the only thing that decides anything.
##
## [b]One side drives and the other side runs, and every decision in this file comes
## from that being asymmetric.[/b] It is not a deathmatch with vehicles in it: the
## drivers have no way to lose except the clock, the runners have no way to win except
## the clock, and the only thing either side can change is the shape of the bowl
## between them. So the crates are the game, and everything here is about keeping
## enough of them standing to make the last thirty seconds interesting.
##
## [b]What it owns and what it borrows.[/b] The round, the sides and the scoreboard are
## dot-match's; health and damage are dot-combat's; the crates and barrels are
## dot-props'; the bus is dot-vehicle's; the bowl is this file's. The joins are the
## part that is new, and they are the part worth reading.

const CHANNEL := "bfh.game"

const TEAM_DRIVERS := 1
const TEAM_RUNNERS := 2

## Where this world publishes itself, so a module can find it.
##
## [b]A registry name and not an autoload, which is the family rule and here also a
## requirement.[/b] A server and a client in one editor session is two of these, and the
## suite builds two worlds in one process on purpose -- see [method _build_random] for
## what the other kind of global already cost this game.
const SERVICE := &"bfh_game"

## Snapshots a second. Twenty, against a sixty-tick simulation.
##
## [b]Lower than the games whose whole content is a person aiming at another person.[/b]
## Nothing here is decided at the precision of a single frame: a bus is nine metres of
## telegraphed intent, and what a runner reads off it is a direction and a speed rather
## than a silhouette. The interpolator covers the rest, and the bandwidth goes to the
## thirty-odd rigid bodies instead, which is where this game's snapshot actually is.
const NET_SNAPSHOT_RATE := 20

## How far a position may be from the origin, in metres, on the wire.
##
## [b]The bowl is 46 m across and this is 256.[/b] Not tidiness: a quantised position is
## decoded against this range, so a client and a server that disagree about it do not
## lose precision, they land somewhere else entirely. It is written here, once, and both
## ends read it from here -- the arena client and the module said 256 and 128 in two
## other games in this family and that is the bug being avoided.
const NET_WORLD_EXTENT := 256.0

## Somebody is in the world. The bridge answers this by making them an entity.
signal player_added(player_id: StringName)

## And is not any more.
signal player_removed(player_id: StringName)

## Every player changed sides. Round-numbered, because a client redraws its HUD from it.
signal sides_swapped(round_number: int)

## A round began. The bowl has been re-laid by the time this fires.
signal round_began(number: int)

## A round ended. [param winner] is one of the TEAM_* constants, or 0 for a draw.
signal round_over(number: int, winner: int)

## Somebody was run over or caught a barrel.
signal player_died(player_id: StringName, by: StringName)

## A barrel went off. The client draws it; this decides it.
signal barrel_exploded(at: Vector3, radius: float)

@export var config: BfhConfig = null

## Whether this instance decides anything. A client sets this false.
@export var authoritative: bool = true

@export_range(1, 240, 1) var tick_rate: int = 60

## Whether something else drives the tick.
##
## [b]Set by the bridge on both ends, and it has to be both.[/b] A game's tick has to
## happen INSIDE the netcode's -- between applying each peer's inputs and building the
## snapshot -- so a world still running its own `_physics_process` moves every player
## twice a tick, and what that looks like is a server running at double speed only while
## somebody is connected. A client's is worse: it would simulate the local player twice
## and dead-reckon every remote one from stale state.
@export var external_tick: bool = false

## Whether this world publishes itself under [constant SERVICE].
##
## Off on a client that shares a process with a server -- the suite, an editor session
## running both -- because a registry name is global and the last one to register wins.
@export var register_service: bool = true

var arena: BfhArena = null
var props: DotPropSpawner = null
var prop_damage: DotPropDamage = null
var carry: DotPropCarry = null
var vehicles: DotVehicleSpawner = null
var ride: DotVehicleRide = null
var combat: DotCombatManager = null
var match_node: DotMatch = null
var random: DotRandomManager = null

## player id -> BfhPlayer.
var players: Dictionary = {}

## player id -> team, for the sides that outlive a round.
var sides: Dictionary = {}

var round_number: int = 0

## Simulated seconds since the round began. Never a wall clock.
var round_elapsed: float = 0.0

## What the server last said about the numbers a client cannot count for itself.
##
## [b]Negative means "count it yourself", which is what a server and an offline client
## do.[/b] A client does not run the prop spawner — its crates are mirrored bodies with
## no [DotPropInstance] behind them — so `crates_left()` there would count zero and the
## HUD would tell every networked player that all the cover was gone. See
## `BfhEvents.Kind.CLOCK`.
var remote_cover: int = -1

## And whether the server says there is somebody on each side.
var remote_playable: bool = false

var _tick: int = 0

## Every world object this game has an id for. See [DotEntityTable].
##
## Replaces a `_next_entity_id` counter that was correct and did two things this is
## not: it had no reverse index, so finding out who an attacker was walked every
## player on the server ([method _on_player_died]); and nothing ever closed anything,
## so `DotCombatManager` kept a `DotHealth` for every player who had ever joined --
## nodes that were freed with their player, leaving the manager holding references to
## deleted objects for the life of the process. `forget()` is called now, from the one
## place that knows a player has gone.
var entities := DotEntityTable.new()
var _layout_seed: int = 0
var _bus_ids: Array[int] = []

## Instance id -> seconds this bus has been asking to move and not moving.
var _bus_stuck: Dictionary = {}


func _ready() -> void:
	if config == null:
		config = BfhConfig.new()

	var valid := config.validate()
	if not valid.ok:
		# FATAL is reserved in this family for "the process cannot continue", and a
		# configuration that contradicts itself is not that: the right answer is to
		# say so loudly and refuse to run a round, not to take the server down.
		DotLog.error(CHANNEL, "the configuration is not usable", {"why": valid.error.message})
		return

	_layout_seed = config.arena_seed

	_apply_gravity()
	_build_random()
	_build_arena()
	_build_props()
	_build_vehicles()
	_build_combat()
	_build_match()

	if register_service:
		DotRegistry.register(SERVICE, self)

	DotLog.info(CHANNEL, "world ready", config.describe())


func _exit_tree() -> void:
	# By instance, never by name. Unregistering the NAME from a world that lost the
	# race to register it takes the other world's entry out with it, and the symptom is
	# a module that cannot find a game that is sitting in the tree.
	if register_service:
		DotRegistry.unregister_instance(SERVICE, self)


## Puts this world's physics space on the gravity the game was tuned for.
##
## [b]On the SPACE, not on `ProjectSettings`.[/b] Two worlds in one process is the normal
## case here — a server and a client in one editor session, and every section of the
## suite — and a global would be one of them deciding for the other. A space is a world's
## own, so each gets the same answer independently.
##
## [b]And it is done at all because a project setting does not travel in a pack.[/b] See
## [member BfhConfig.gravity]: delivered into the server tool's project, this game ran at
## Godot's default 9.8 against numbers chosen for 20, and the only symptom was that
## everything floated.
func _apply_gravity() -> void:
	var world := get_world_3d()

	if world == null:
		DotLog.warn(CHANNEL, "no world to set gravity on", {})
		return

	PhysicsServer3D.area_set_param(
		world.space, PhysicsServer3D.AREA_PARAM_GRAVITY, config.gravity
	)


func _build_random() -> void:
	random = DotRandomManager.new()
	random.name = "Random"
	# [b]Off, and the addon's own comment says why.[/b] A registry name is global to
	# the process, so the last manager to register wins — and two worlds in one
	# process is not exotic here: it is a server and a client in one editor session,
	# and it is what the suite does in every section. With it on, the second world's
	# manager displaced the first's and two worlds built from the same seed laid out
	# different bowls, which is the one thing a seed exists to prevent.
	random.register_as_service = false
	add_child(random)
	random.setup()
	random.reseed(_layout_seed)


func _build_arena() -> void:
	arena = BfhArena.new()
	arena.name = "Arena"
	add_child(arena)
	arena.build(config.arena_radius)


func _build_props() -> void:
	props = DotPropSpawner.new()
	props.name = "Props"
	props.catalogue = BfhContent.props(config)
	props.limits = DotPropLimits.new()
	# The bowl's furniture is spawned by the world rather than by a player, so the
	# per-player budget and the cooldown are not what is being defended against here —
	# the world cap is, and it has to be above what a round lays out or the last few
	# crates silently never appear.
	props.limits.spawn_interval = 0.0
	props.limits.per_player_budget = 400
	props.limits.world_budget = 400
	props.limits.clean_up_on_leave = false
	props.authoritative = authoritative
	add_child(props)

	prop_damage = DotPropDamage.new()
	prop_damage.name = "PropDamage"
	prop_damage.authoritative = authoritative
	props.add_child(prop_damage)
	prop_damage.exploded.connect(_on_prop_exploded)

	carry = DotPropCarry.new()
	carry.name = "PropCarry"
	props.add_child(carry)


func _build_vehicles() -> void:
	vehicles = DotVehicleSpawner.new()
	vehicles.name = "Vehicles"
	vehicles.catalogue = BfhContent.vehicles(config)
	vehicles.authoritative = authoritative
	# The buses are put out by the world at the top of a round, not requested by
	# players, so the limits that exist to stop somebody spamming a spawn key are the
	# wrong shape here. The interval in particular: every bus is placed in the same
	# instant, and at the shipped 1.0 s only the first one appears — silently, because
	# a refused spawn is a refusal rather than an error.
	vehicles.spawn_interval = 0.0
	vehicles.per_player_budget = 16
	vehicles.world_budget = 16
	add_child(vehicles)

	# [b]The SPAWNER'S ride, not a second one.[/b] `DotVehicleSpawner` builds one in its
	# own `_init` and uses it for three things: evacuating a vehicle that is destroyed
	# with people in it, answering `vehicle_of_rider`, and reporting how many riders there
	# are. This game used to construct its own beside it, so those three read an index
	# that was always empty — `describe()` said nobody was driving while somebody was, and
	# a destroyed bus released nobody, which is the "stuck aboard a bus that no longer
	# exists" failure this game already had once from the other direction.
	#
	# It is a [RefCounted] rather than a Node, and dot-vehicle made it one deliberately:
	# seating a rider means stopping their controller and reparenting their node, and
	# neither is something that addon can do without naming dot-player-controller — which
	# would make it fail to parse in a project that does not have it. The two callables
	# below are that seam, and this game is the half that knows what a player is.
	ride = vehicles.ride
	ride.carry_rider_nodes = false
	ride.on_seated = func(rider_id: StringName, _v: DotVehicleInstance, _s: DotVehicleSeat) -> void:
		_set_riding(rider_id, true)
	ride.on_unseated = func(
		rider_id: StringName, _v: DotVehicleInstance, _s: DotVehicleSeat, at: Vector3
	) -> void:
		_set_riding(rider_id, false, at)


func _build_combat() -> void:
	combat = DotCombatManager.new()
	combat.name = "Combat"
	combat.is_authority = authoritative

	# [b]Said out loud, because the inherited default says the opposite of what this game
	# does.[/b] [DotDamageRules] defaults `friendly_fire` to false, and a reader who found
	# that here would conclude that a runner cannot hurt another runner. A runner very much
	# can: [method _on_prop_exploded] filters a barrel blast on dead-or-riding and on nothing
	# else, and a blast that asked whose side you were on would not be a blast.
	#
	# [b]And `team_of` stays unset deliberately.[/b] dot-combat decides friendly fire through
	# a `team_of` [Callable] and treats a missing one as "nobody is anybody's team mate" —
	# which is a real trap, and cost another game in this family a round where friendly fire
	# was on in a game whose rules said it was off. It is not a trap HERE, because the one
	# damage path that could hit your own side already does the side test itself before it
	# calls in: a bus skips every driver by key, so a bus cannot run over a driver even after
	# its own driver has been evacuated onto foot. Wiring `team_of` now would not fix
	# anything; it would silently start refusing the barrel splash that is meant to be
	# indiscriminate.
	var rules := DotDamageRules.new()
	rules.friendly_fire = true
	combat.rules = rules

	add_child(combat)


func _build_match() -> void:
	match_node = DotMatch.new()
	match_node.name = "Match"
	match_node.register_service = false

	var match_config := DotMatchConfig.new()
	match_config.tick_rate = tick_rate
	match_config.auto_start = false
	match_config.log_transitions = false
	match_node.config = match_config

	var rules := DotRulesElimination.make(config.round_seconds)
	rules.intermission_sec = config.intermission_seconds
	rules.warmup_sec = config.warmup_seconds
	rules.countdown_sec = 0.0
	rules.rounds_to_win = 99
	# [b]One.[/b] dot-match defaults to two because a deathmatch with one player in it
	# is not a match; a round here with one runner and no drivers is a legitimate, if
	# dull, thing for a nearly-empty server to be doing, and the alternative is a
	# server that sits in warmup for ever and looks broken to the one person on it.
	rules.min_players = 1
	# [b]The rule asks the game who is alive, and that is the seam dot-match is built
	# around.[/b] Being alive is a `DotHealth`, which lives in dot-combat, which
	# dot-match deliberately does not depend on. Left unset this falls back to a score
	# and a clock — and the tell is specific and visible in the first round played:
	# the round runs to the full clock instead of ending on the last kill.
	rules.alive_fn = _is_alive
	match_node.rules = rules

	add_child(match_node)

	match_node.round_started.connect(_on_round_started)
	match_node.round_ended.connect(_on_round_ended)

	var teams: Array[DotTeam] = [
		DotTeam.make(TEAM_DRIVERS, "Drivers", Color(0.92, 0.74, 0.17)),
		DotTeam.make(TEAM_RUNNERS, "Runners", Color(0.35, 0.62, 0.88)),
	]
	match_node.teams.teams = teams
	# Off: this game balances itself, because the sides are not interchangeable. Two
	# drivers against six runners is the design rather than an imbalance, and a
	# balancer that did not know that would move four people into the buses every
	# round and there are two seats.
	match_node.teams.force_balance = false
	match_node.teams.allow_choice = true
	# [b]And off in the second place dot-match balances, which `force_balance` does not
	# reach.[/b] `max_difference` defaults to 1 and REFUSES any join that puts a side more
	# than one ahead — so on a shipped server the second driver and every runner past the
	# drivers' count plus one were on no team at all in dot-match, while `sides` had them
	# placed correctly. The elimination rule counts survivors off dot-match's teams, so a
	# round was handed to the drivers the moment the runners it knew about were down, with
	# the others still standing. `sides` decides who is on which side; dot-match is told.
	match_node.teams.max_difference = 0


# --- Players ---------------------------------------------------------------

## Puts somebody in the world. [param wanted_team] is a TEAM_* constant, or 0 to be placed.
func add_player(
	player_id: StringName,
	display_name: String,
	wanted_team: int = 0,
	samples_input: bool = false,
) -> BfhPlayer:
	if players.has(player_id):
		return players[player_id]

	var team := wanted_team if wanted_team != 0 else _side_for_new_player()

	var player := BfhPlayer.new()
	player.name = "Player_%s" % String(player_id)
	player.player_id = player_id
	player.display_name = display_name
	player.samples_input = samples_input
	player.tick_rate = tick_rate
	# Before `add_child`, because `_ready` is what builds the controller and its tunables.
	player.config = config
	player.mass_kg = config.runner_mass
	player.carry = carry
	add_child(player)

	var opened := entities.open(
		DotEntity.KIND_PLAYER,
		player,
		&"",
		player_id,
		float(_tick) / float(maxi(tick_rate, 1))
	)

	if not opened.ok:
		# A refusal here means this player id is already an entity, which cannot
		# happen -- `add_player` returns early on a duplicate. Logged rather than
		# ignored because arming them anyway would register a second health record
		# against one body, and the symptom of that is a player taking half damage.
		DotLog.error(CHANNEL, "could not open an entity for a player", {
			"id": String(player_id), "why": opened.error.message,
		})

	player.entity_id = (opened.value as DotEntityHandle).id if opened.ok else 0

	var health := DotHealth.new()
	health.name = "Health"
	health.max_health = config.runner_health
	health.health = config.runner_health
	player.add_child(health)
	player.health = health
	combat.register_health(player.entity_id, health)

	health.died.connect(func(damage: DotDamage) -> void: _on_player_died(player, damage))

	players[player_id] = player
	sides[player_id] = team

	var joined := match_node.add_player(String(player_id), display_name, _tick, team)

	if not joined.ok:
		# Not fatal to the join -- they can still move and be seen -- but the round rule
		# cannot count them, which is a round decided without them. Said out loud because
		# the last time this was refused, nothing did.
		DotLog.error(CHANNEL, "dot-match refused a player's side", {
			"id": String(player_id), "team": team, "why": joined.error.message,
		})

	if team == TEAM_RUNNERS:
		player.give_hammer(config)

	DotLog.debug(CHANNEL, "player joined", {"id": String(player_id), "team": team})

	# Last, after the hammer and the health: the bridge answers this by building the
	# replicated entity and announcing the join, and an entity built over a half-made
	# player replicates the half.
	player_added.emit(player_id)

	# After the announcement, because seating fires `ride.entered` and the bridge answers
	# that by writing to the entity it has just built.
	if authoritative and team == TEAM_DRIVERS:
		_seat_in_an_empty_bus(player)

	return player


## Puts a driver who arrived after the buses were placed into one nobody is driving.
##
## [b]Seating used to happen only at the top of a round, and the bots made that a real
## gap.[/b] A person driving disconnects, their bus stays where it stopped, and the module
## fills the seat with a bot inside two seconds -- in `sides`, and nowhere else. The bot
## then stood on the sand as a pedestrian nothing can run over while its bus sat still for
## the rest of the round. With no empty bus this does nothing and the next round seats
## them, which is what always happened.
func _seat_in_an_empty_bus(player: BfhPlayer) -> void:
	if ride == null or ride.is_riding(player.player_id):
		return

	for instance_id in _bus_ids:
		var bus := vehicles.get_vehicle(instance_id)
		if bus == null or not bus.is_alive() or bus.driver() != &"":
			continue

		ride.enter(bus, player.player_id, player, &"driver")
		return


## Which side somebody new goes on.
##
## [b]Drivers are capped and runners are not, which is the opposite of a balancer.[/b]
## There are `driver_count` buses and a driver without one is a person standing on a
## ledge watching, so the cap is the number of seats rather than a fraction of the
## server.
func _side_for_new_player() -> int:
	var drivers := 0
	for id: StringName in sides:
		if int(sides[id]) == TEAM_DRIVERS:
			drivers += 1
	return TEAM_DRIVERS if drivers < config.driver_count else TEAM_RUNNERS


func remove_player(player_id: StringName) -> void:
	if not players.has(player_id):
		return

	var player: BfhPlayer = players[player_id]

	if ride != null and ride.is_riding(player_id):
		ride.exit(vehicles.get_vehicle(ride.vehicle_id_of(player_id)), player_id, true)

	# Before the node goes. dot-combat keyed a `DotHealth` on this entity and NOTHING
	# in this game had ever told it to let go -- so every player who had ever joined
	# left a health record behind, pointing at a node freed with them. The manager's
	# own documentation says what that costs; what made it invisible is that a stale
	# entity is never asked about, because nothing traces against a player who left.
	if combat != null and is_instance_valid(combat) and player.entity_id != 0:
		combat.forget(player.entity_id)
		entities.close(player.entity_id, DotEntityTable.REASON_OWNER_LEFT)

	# And dot-match, which kept counting them as present: towards `min_players`, and on
	# the side they left from. Their scoreboard record stays, which is dot-match's own rule.
	if match_node != null:
		match_node.remove_player(String(player_id))

	players.erase(player_id)
	sides.erase(player_id)
	player.queue_free()

	player_removed.emit(player_id)


## Flips a player between walking and driving. Called by the ride, never directly.
func _set_riding(player_id: StringName, value: bool, at: Vector3 = Vector3.ZERO) -> void:
	var player: BfhPlayer = players.get(player_id)
	if player == null:
		return

	player.set_riding(value)

	if not value and at != Vector3.ZERO:
		player.global_position = at
		player.controller.state.position = at


func team_of(player_id: StringName) -> int:
	return int(sides.get(player_id, 0))


func runners() -> Array[BfhPlayer]:
	return _players_on(TEAM_RUNNERS)


func drivers() -> Array[BfhPlayer]:
	return _players_on(TEAM_DRIVERS)


func _players_on(team: int) -> Array[BfhPlayer]:
	var out: Array[BfhPlayer] = []
	for id: StringName in players:
		if int(sides.get(id, 0)) == team:
			out.append(players[id])
	return out


func _is_alive(key: String) -> bool:
	var player: BfhPlayer = players.get(StringName(key))
	return player != null and player.health != null and player.health.alive


# --- The round -------------------------------------------------------------

func start() -> void:
	if not authoritative:
		return

	# [b]The bowl is laid out here and not only on `round_started`, and that is the
	# difference between an empty server and a broken-looking one.[/b] dot-match runs
	# a warmup before the first round, so a world that only furnished itself when a
	# round began sat for the whole warmup as a bare disc with nothing in it — which
	# is what somebody joining an empty server would see, and is indistinguishable
	# from the props having failed to spawn. A round re-lays it; this puts it there.
	_clear_bowl()
	_lay_out_bowl()
	_place_players()
	_place_buses()

	match_node.start(_tick)


func _on_round_started(number: int) -> void:
	round_number = number
	round_elapsed = 0.0

	if config.reseed_each_round:
		# Derived from the configured seed and the round number rather than from a
		# clock, so a server and a replay of it lay the same round out. `hash` would
		# do; this is one multiply and is stable across engine versions, which `hash`
		# on a built-in is not promised to be.
		_layout_seed = config.arena_seed + number * 7919
		random.reseed(_layout_seed)

	_clear_bowl()
	_lay_out_bowl()
	_place_players()
	_place_buses()

	round_began.emit(number)
	DotLog.info(CHANNEL, "round began", {"number": number, "seed": _layout_seed})


func _on_round_ended(number: int, winner: int, _outcome: int) -> void:
	round_over.emit(number, winner)
	DotLog.info(CHANNEL, "round over", {"number": number, "winner": winner})

	if config.rounds_before_swap > 0 and number % config.rounds_before_swap == 0:
		_swap_sides()


## Swaps every player's side.
##
## [b]Driving is the fun half and there are two seats for it.[/b] A server that never
## swaps is a server where the same two people drive all night, which is the failure
## this game has that a symmetric one does not.
func _swap_sides() -> void:
	for id: StringName in sides:
		var was := int(sides[id])
		var now := TEAM_RUNNERS if was == TEAM_DRIVERS else TEAM_DRIVERS
		sides[id] = now

		# [b]dot-match as well, because its elimination rule is what decides the round
		# and it reads teams off its own scoreboard.[/b] Flipping `sides` alone left the
		# rule on the old sides for the rest of the server's life: the drivers ran the new
		# runners down and every such round was announced as the runners' win.
		var switched := match_node.switch_team(String(id), now, _tick)
		if not switched.ok:
			DotLog.error(CHANNEL, "dot-match refused a side swap", {
				"id": String(id), "team": now, "why": switched.error.message,
			})

		var player: BfhPlayer = players[id]
		if now == TEAM_RUNNERS and player.hammer == null:
			player.give_hammer(config)
		elif now == TEAM_DRIVERS:
			player.hammer = null

	sides_swapped.emit(round_number)
	DotLog.info(CHANNEL, "sides swapped", {"round": round_number})


func _clear_bowl() -> void:
	for prop in props.all_props():
		props.remove(prop.instance_id, DotPropSpawner.REASON_CLEANUP)

	for instance_id in _bus_ids:
		var bus := vehicles.get_vehicle(instance_id)
		if bus == null:
			continue

		# [b]Riders out before the bus goes, and nothing else does this for us.[/b]
		# `DotVehicleRide` is a RefCounted holding its own rider index and it does not
		# watch the spawner — so a bus removed underneath somebody leaves the ride
		# still believing they are aboard, and every later `enter` is refused with
		# "You are already in a vehicle." Permanently: there is no bus left to get out
		# of. The symptom is a driver who is put on the ledge at the top of round two
		# and never gets into anything again, which reads as the seating being broken
		# rather than as a round having cleaned up in the wrong order.
		# `occupants` is keyed by SEAT id and valued by rider id, which is the
		# direction `seat_of()` reads it in. Iterating the keys hands `exit` a seat
		# name where it wants a rider, and it answers "You are not in that vehicle" —
		# truthfully, about a rider called "driver" who does not exist — so the real
		# rider is never released and is stuck aboard a bus that no longer exists.
		for rider_id: StringName in bus.occupants.values():
			ride.exit(bus, rider_id, true)

		vehicles.remove(instance_id)

	_bus_ids.clear()
	# Keyed by instance ids that are gone now, and never read again: a slow leak of two
	# entries a round for the life of the server rather than a behaviour, but a leak.
	_bus_stuck.clear()
	_bus_inverted.clear()


func _lay_out_bowl() -> void:
	var stream := random.stream(&"bowl")

	for _i in range(config.crate_count):
		props.spawn(BfhContent.CRATE, &"world", arena.scatter_point(stream, 8.0, 0.6))

	for _i in range(config.barrel_count):
		props.spawn(BfhContent.BARREL, &"world", arena.scatter_point(stream, 10.0, 0.8))

	# A sixth as many blocks as crates, and never fewer than three. The blocks are the
	# floor under the round: whatever the drivers break, this much cover remains.
	var blocks := maxi(config.crate_count / 6, 3)
	for _i in range(blocks):
		props.spawn(BfhContent.BLOCK, &"world", arena.scatter_point(stream, 12.0, 0.5))


func _place_players() -> void:
	var stream := random.stream(&"spawns")

	for id: StringName in players:
		var player: BfhPlayer = players[id]

		if player.health != null:
			player.health.health = config.runner_health
			player.health.alive = true

		if int(sides.get(id, 0)) == TEAM_DRIVERS:
			player.global_position = arena.ledge_centre() + Vector3(0.0, 1.0, 0.0)
		else:
			var at := arena.scatter_point(stream, 10.0, 1.2)
			player.global_position = at

		player.controller.state.position = player.global_position
		player.controller.state.velocity = Vector3.ZERO
		player.set_riding(false)


func _place_buses() -> void:
	var seats := mini(config.driver_count, drivers().size())

	for i in range(maxi(seats, 1)):
		var at := arena.bus_start(i, maxi(seats, 1))

		# [b]Turned to face the bowl, and the default is 180 degrees wrong.[/b]
		# `spawn` orients with `Basis.IDENTITY` unless told otherwise, and identity
		# faces -Z — which from a ledge at the north edge is straight into the wall
		# seven metres behind it. The bus then drove forward, at full throttle, into
		# that wall, for the whole round: four wheels on the ground, correct engine
		# force, correct steering, and a speedometer reading 0.0 m/s. Every number was
		# right and the only wrong one was which way it was pointing.
		var facing := Vector3(-at.x, 0.0, -at.z)
		var orientation := (
			Basis.looking_at(facing.normalized()) if facing.length() > 0.01
			else Basis.IDENTITY
		)

		var bus := vehicles.spawn(BfhContent.BUS, at, &"world", orientation)

		if bus == null:
			DotLog.warn(CHANNEL, "a bus could not be spawned", {"index": i})
			continue

		_bus_ids.append(bus.instance_id)

		var seated := drivers()
		if i < seated.size():
			var driver := seated[i]
			# `on_seated` is what flips the player, not this call site: a rider can also
			# be put down by the ride itself — a destroyed bus, an admin removing one —
			# and a game that only flipped the flag where it seated somebody would leave
			# them frozen in mid-air the one time it mattered.
			ride.enter(bus, driver.player_id, driver, &"driver")


# --- The tick --------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if not authoritative or match_node == null or external_tick:
		return
	simulate(delta)


## One simulated tick, counted by this world. What an offline client and the suite use.
func simulate(delta: float) -> void:
	_tick += 1
	_step(delta)


## One simulated tick, numbered by the netcode. What the bridge uses.
##
## [b]The tick number comes from outside and the step does not.[/b] A snapshot is
## stamped with the netcode's tick and a client reconciles against that number, so a
## world counting its own would be replying about a different tick than the one it was
## asked about. The STEP stays a fixed `1 / tick_rate` either way: a simulation stepped
## by a frame's delta is a simulation that runs differently on a server having a bad
## second, and this family has paid for that twice.
func tick_once(tick: int) -> void:
	if match_node == null:
		return

	_tick = tick
	_step(delta_for_tick())


## The step both entry points share.
func _step(delta: float) -> void:
	round_elapsed += delta

	for id: StringName in players:
		var player: BfhPlayer = players[id]
		player.simulate(_tick, delta)

	_drive_buses(delta)
	_check_bus_impacts(delta)

	# [b]A round with one side empty is not a round, and letting the clock run on one
	# is an infinite loop with a scoreboard.[/b] The elimination rule ends a round the
	# moment a side has nobody alive, and a side with nobody *at all* satisfies that on
	# the first tick — so a server holding five runners and no drivers starts a round,
	# ends it, swaps the sides, starts another and ends that, several times a second,
	# for as long as nobody joins. Nothing errors: every round is decided correctly
	# and the decision is correct. The suite found it as crates vanishing out from
	# under a test that had just spawned them.
	if not sides_are_playable():
		return

	match_node.tick(_tick)


## The fixed step. One place, because three files were about to compute it.
func delta_for_tick() -> float:
	return 1.0 / float(maxi(tick_rate, 1))


## Adopts a tick rate, on a client being told what the server runs at.
##
## [b]Every player's controller as well as this world, and that is the whole reason it
## is a method.[/b] `tick_rate` is a plain property on a [BfhPlayer] with a setter that
## forwards to the controller, so a world that changed only its own left every player
## integrating at the old rate -- which is a client that walks at 60/128 of the speed
## the server moves it at and is corrected on every snapshot for doing so.
func set_tick_rate(rate: int) -> bool:
	if rate <= 0 or rate == tick_rate:
		return false

	tick_rate = rate

	for id: StringName in players:
		(players[id] as BfhPlayer).tick_rate = rate

	if match_node != null and match_node.config != null:
		match_node.config.tick_rate = rate

	return true


## Whether there is somebody on each side. See [method simulate].
func sides_are_playable() -> bool:
	var has_driver := false
	var has_runner := false

	for id: StringName in sides:
		match int(sides[id]):
			TEAM_DRIVERS:
				has_driver = true
			TEAM_RUNNERS:
				has_runner = true

	if not authoritative:
		# A client knows the sides from JOIN and TEAM, but not whether the server has
		# decided a round is playable — and the answer is the whole of the HUD's "waiting
		# for both sides" line, which is the only thing telling somebody on an empty
		# server that nothing is broken.
		return remote_playable

	return has_driver and has_runner


## Turns each driver's movement keys into throttle and steering.
##
## [b]The sample is the same one the walking controller takes, deliberately.[/b] A
## driver's forward key is the throttle and their strafe keys are the wheel, so nobody
## has to learn a second set of controls for the half of the game they only play every
## third round.
func _drive_buses(delta: float) -> void:
	for id: StringName in players:
		var player: BfhPlayer = players[id]

		if not player.riding:
			continue

		var instance_id := ride.vehicle_id_of(player.player_id)
		if instance_id == 0:
			continue

		var bus := vehicles.get_vehicle(instance_id)
		if bus == null or not bus.is_alive():
			continue

		# `current_command` is what `apply_command` stored and what the next tick would
		# have moved them with. Read rather than re-sampled: sampling a second time
		# here would consume a frame's mouse motion twice and make the driver's view
		# turn at double rate, which reads as the bus having drifty steering.
		var command: DotVehicleCommand = null

		if player.is_bot:
			command = _autopilot(player, bus, delta)
			bus.command = command
			if bus.chassis != null:
				(bus.chassis as DotVehicleChassis).drive(command, delta)
			continue

		var pending := player.controller.current_command
		command = DotVehicleCommand.new()

		if pending != null:
			# `move.y` is forward and `move.x` strafes right. The wheel is the strafe
			# axis negated, because steering right is a negative yaw in Godot's frame
			# and a driver pressing D expects the bus to go right.
			command.throttle = clampf(pending.move.y, -1.0, 1.0)
			command.steer = clampf(-pending.move.x, -1.0, 1.0)
			command.handbrake = pending.is_pressed(DotFpsCommand.BUTTON_CROUCH)
			command.aim_yaw = pending.yaw
			command.aim_pitch = pending.pitch

		bus.command = command

		if bus.chassis != null:
			(bus.chassis as DotVehicleChassis).drive(command, delta)


## Drives a bot's bus at whoever is nearest.
##
## [b]`set_target` each tick rather than a route, and that is what makes a bot bus
## readable.[/b] [DotVehicleDriver] will follow a waypoint list, which is the right
## shape for traffic and the wrong one here: a runner's entire game is reading where a
## bus has committed to and stepping out of it, and a bus on rails is not committing to
## anything about them. Re-aimed every tick it behaves like a person who has picked a
## target — it overshoots, it has to come round again, and the gap while it does is the
## opening the round is played in.
func _autopilot(player: BfhPlayer, bus: DotVehicleInstance, delta: float) -> DotVehicleCommand:
	if player.autopilot == null:
		player.autopilot = DotVehicleDriver.new()
		player.autopilot.target_speed = config.bus_top_speed
		# Wider than the default, because a bus is nine metres long: a waypoint radius
		# tighter than the vehicle means it can never be "at" its target and it circles
		# the spot for ever.
		# [b]Tiny, because arriving is the one thing this driver must never do.[/b]
		# `DotVehicleDriver` slows down inside `arrive_radius` and stops at the
		# waypoint, which is right for traffic and exactly wrong for a chase: at 6 m
		# the bus coasted to a halt beside the runner and sat there with the throttle
		# at zero. A bus is not trying to reach a person, it is trying to be where
		# they are at speed.
		player.autopilot.arrive_radius = 0.5
		player.autopilot.waypoint_radius = 2.0

	var quarry := _nearest_runner(bus.position())

	if quarry == null:
		# Nobody left to chase. Returned idle rather than left holding the last
		# command: a bus still flooring it at a target that no longer exists is a bus
		# that drives into the wall for the rest of the round.
		return DotVehicleCommand.new()

	# Aimed PAST them, not at them. The driver decides its speed from the distance to
	# its target, so a target sitting on the runner is a target that is always nearly
	# reached — the bus arrives gently. A point eight metres beyond them, along the
	# line the bus is already on, keeps the throttle down through the moment that
	# matters and is what makes a near miss look like one.
	var line := quarry.global_position - bus.position()
	line.y = 0.0

	var beyond := (
		quarry.global_position + line.normalized() * 8.0 if line.length() > 0.5
		else quarry.global_position
	)

	# And round the stacks, because the driver has no idea they are there. A bus aimed
	# through a pillar wedges nose-on and the stuck rule then teleports it back to its
	# start line, which from the runner's side reads as hiding behind a pillar deleting
	# the bus. See [method BfhArena.steer_around].
	player.autopilot.set_target(arena.steer_around(bus.position(), beyond))
	return player.autopilot.drive(bus, delta)


func _nearest_runner(to: Vector3) -> BfhPlayer:
	var best: BfhPlayer = null
	var best_distance := INF

	for candidate in runners():
		if candidate.health == null or not candidate.health.alive:
			continue

		var distance := candidate.global_position.distance_to(to)
		if distance < best_distance:
			best = candidate
			best_distance = distance

	return best


## A bus that touched somebody, and what that costs them.
##
## [b]Closing speed, not the bus's speed.[/b] A runner sprinting into the side of a
## parked bus is not being run over, and a bus reversing at 3 m/s into somebody who is
## running away from it at 6 is not either. Taking the bus's own speed makes both of
## those kills, which reads as the game being unfair in a way nobody can point at.
func _check_bus_impacts(delta: float) -> void:
	for instance_id in _bus_ids:
		var bus := vehicles.get_vehicle(instance_id)
		if bus == null or not bus.is_alive():
			continue

		var body := bus.body()
		if body == null:
			continue

		var bus_velocity := bus.velocity()
		var driver_id := driver_of(instance_id)

		for id: StringName in players:
			var player: BfhPlayer = players[id]

			if player.riding or player.health == null or not player.health.alive:
				continue
			if int(sides.get(id, 0)) == TEAM_DRIVERS:
				continue

			var offset := player.global_position - body.global_position
			# A crude bound rather than a physics contact: the bus is a 2.5 x 2.6 x 9
			# box and this is the sphere around it. Deliberately generous, because a
			# miss that should have been a hit is the complaint this game would
			# actually get, and a hit is checked against closing speed anyway.
			if offset.length() > 4.2:
				continue

			# [b]Along the offset, not against it.[/b] `offset` runs from the bus to
			# the player, so a bus moving toward them has a POSITIVE component along
			# it. The first version negated this, which made every genuine run-over
			# read as a closing speed below the threshold and every impact was
			# silently skipped — a bus that drove through people and left them
			# standing. Nothing errored; the arithmetic was simply backwards.
			var closing := (bus_velocity - player.controller.state.velocity).dot(
				offset.normalized()
			)

			if closing < 1.0:
				continue

			_bus_hit(player, driver_id, closing, offset)

		_break_props_under(bus, bus_velocity.length(), driver_id)
		_unstick(bus, driver_id, delta)
		_upright(bus, delta)


func _bus_hit(player: BfhPlayer, by: StringName, closing: float, offset: Vector3) -> void:
	var lethal := closing >= config.bus_lethal_speed
	var amount := config.runner_health * 2.0 if lethal else closing * config.bus_bump_damage

	var attacker := 0
	if players.has(by):
		attacker = (players[by] as BfhPlayer).entity_id

	var damage := DotDamage.make(attacker, player.entity_id, amount, null)
	damage.point = player.global_position
	damage.direction = offset.normalized()
	combat.apply_damage(damage)

	# Knocked away whether or not it killed them, because a bus that passes through
	# somebody standing still and leaves them standing still is the one thing in this
	# game that would look broken from every angle.
	player.controller.state.velocity += offset.normalized() * closing * 0.6


## Crates and barrels a moving bus has driven into.
##
## [b]The bus's own box, not a sphere around it, and the sphere was wrong in both
## directions.[/b] A nine-metre bus has a centre five metres from its nose, so a radius
## generous enough to catch what it is about to hit also catches everything beside and
## behind it — a bus flattened a line of crates it merely drove past. Testing the prop
## in the bus's local frame is the same arithmetic and answers the question actually
## being asked: is this thing under the bus.
const BUS_HALF_WIDTH := 1.5
const BUS_HALF_LENGTH := 3.2

func _break_props_under(bus: DotVehicleInstance, speed: float, by: StringName) -> void:
	if speed < 4.0 or prop_damage == null:
		return

	var body := bus.body()
	var into_bus := body.global_transform.affine_inverse()

	for prop in props.all_props():
		if not prop.is_alive():
			continue

		var prop_body := prop.body()
		if prop_body == null:
			continue

		var local := into_bus * prop_body.global_position

		if absf(local.x) > BUS_HALF_WIDTH or absf(local.z) > BUS_HALF_LENGTH:
			continue

		# Vertically too, or a bus passing under a ledge takes out whatever is standing
		# on top of it.
		if absf(local.y) > 2.5:
			continue

		prop_damage.impact(prop.instance_id, speed, by)


## Seconds of asking to move before a bus is assumed to be caught on something.
const STUCK_BREAK_SEC := 1.0

## And before it is put back on its start line.
const STUCK_RESET_SEC := 5.0


## A bus that is throttling and going nowhere, and what to do about it.
##
## [b]A crate stops a bus, and it should not, and no amount of tuning fixes it.[/b] A
## raycast vehicle has no wheel collider: each wheel is a ray, so a crate does not hit
## a wheel, it passes under one and lifts the corner of the bus off the ground. The bus
## ends up high-centred with two wheels in the air and a crate wedged under the
## chassis, going nowhere — and the speed-gated impact rule cannot save it, because by
## then it has no speed. Lowering the hull so it rams crates instead was tried and is
## worse: the hull then drags on the ground and the bus barely moves at all.
##
## So the rule is about intent rather than geometry. A bus asking for throttle and not
## moving is caught on something; after a second, whatever is under it stops existing,
## and after five it goes back to its start line. That second rule is not a fallback
## for the first — it is what recovers a bus that drove up the ramp and beached itself
## on the ledge, where there is no prop to blame.
func _unstick(bus: DotVehicleInstance, by: StringName, delta: float) -> void:
	var asking := bus.command != null and absf(bus.command.throttle) > 0.3
	var moving := bus.speed() > 1.0

	if not asking or moving:
		_bus_stuck.erase(bus.instance_id)
		return

	var held := float(_bus_stuck.get(bus.instance_id, 0.0)) + delta
	_bus_stuck[bus.instance_id] = held

	if held < STUCK_BREAK_SEC:
		return

	# Whatever is under it, at any speed. This is the one place the closing-speed rule
	# is deliberately not applied: the bus is not hitting the crate, it is sitting on it.
	if prop_damage != null:
		var into_bus := bus.body().global_transform.affine_inverse()
		for prop in props.all_props():
			if not prop.is_alive() or prop.body() == null:
				continue
			var local := into_bus * prop.body().global_position
			if absf(local.x) > BUS_HALF_WIDTH or absf(local.z) > BUS_HALF_LENGTH:
				continue
			if absf(local.y) > 2.5:
				continue
			prop_damage.break_now(prop.instance_id, by)

	if held < STUCK_RESET_SEC:
		return

	var index := maxi(_bus_ids.find(bus.instance_id), 0)
	var at := arena.bus_start(index, maxi(_bus_ids.size(), 1))
	var facing := Vector3(-at.x, 0.0, -at.z)

	var body := bus.body()
	body.linear_velocity = Vector3.ZERO
	body.angular_velocity = Vector3.ZERO
	body.global_transform = Transform3D(
		Basis.looking_at(facing.normalized()) if facing.length() > 0.01 else Basis.IDENTITY,
		at,
	)

	_bus_stuck.erase(bus.instance_id)
	DotLog.info(CHANNEL, "a bus was put back on its start line", {"stuck_for": held})


## Seconds a bus may lie on its roof before it is rolled back over.
const INVERTED_RIGHT_SEC := 2.0

## Instance id -> seconds this bus has been upside down.
var _bus_inverted: Dictionary = {}


## A bus that has rolled over, and why it is not left there.
##
## [b]A bus on its roof is a driver out of the round through no decision anybody made.[/b]
## dot-vehicle's own tunables comment says it about the centre of mass; this is the other
## half, because no amount of lowering the centre of mass makes a 2.6 m box on a 2.5 m
## track impossible to flip — a ramp, a crate under one wheel and a hard turn will do it.
## The round is three minutes long and there are two buses, so a driver spending one of
## those minutes upside down is a quarter of the game's threat gone for reasons the
## runners cannot see and did not cause.
##
## [b]Rolled over where it lies rather than put back on its start line.[/b] `_unstick` has
## the start line for the case where the bus is somewhere it cannot get out of; this is
## for the case where it is somewhere perfectly good and merely inverted, and teleporting
## it across the bowl would take it away from the chase it was in the middle of. Its
## heading is kept and its velocity is not: a bus that lands upright still carrying the
## roll's momentum immediately flips again.
func _upright(bus: DotVehicleInstance, delta: float) -> void:
	if not bus.is_inverted():
		_bus_inverted.erase(bus.instance_id)
		return

	var held := float(_bus_inverted.get(bus.instance_id, 0.0)) + delta
	_bus_inverted[bus.instance_id] = held

	if held < INVERTED_RIGHT_SEC:
		return

	var body := bus.body()

	if body == null:
		return

	# The heading, flattened. `global_basis.z` on an upside-down body still points the way
	# the bus was facing; what has to go is the roll and the pitch around it.
	var facing := -body.global_basis.z
	facing.y = 0.0

	var orientation := (
		Basis.looking_at(facing.normalized()) if facing.length() > 0.01
		else Basis.IDENTITY
	)

	body.linear_velocity = Vector3.ZERO
	body.angular_velocity = Vector3.ZERO
	body.global_transform = Transform3D(
		orientation, body.global_position + Vector3(0.0, 1.0, 0.0)
	)

	_bus_inverted.erase(bus.instance_id)
	DotLog.info(CHANNEL, "a bus was rolled back onto its wheels", {"upside_down_for": held})


## Who is driving the bus with this instance id, or an empty name.
##
## Public because a bridge, a console command and a suite all ask it, and the alternative
## is three copies of a loop over the ride's index.
func driver_of(instance_id: int) -> StringName:
	for id: StringName in players:
		if ride.vehicle_id_of(id) == instance_id:
			return id
	return &""


# --- Reacting --------------------------------------------------------------

## A barrel went off. dot-props described the blast; this is what it does to people.
##
## [b]The blast reaches players through dot-combat and props through dot-props, and
## that split is the addon boundary rather than an accident.[/b] dot-props knows what a
## prop is and nothing else — a player, an NPC and a vehicle each need somebody else's
## id space and authority rules — so it shoves the other crates itself and hands the
## rest over here.
func _on_prop_exploded(
	at: Vector3, radius: float, damage_amount: float, force: float, by: StringName
) -> void:
	barrel_exploded.emit(at, radius)

	var attacker := 0
	if players.has(by):
		attacker = (players[by] as BfhPlayer).entity_id

	for id: StringName in players:
		var player: BfhPlayer = players[id]

		if player.health == null or not player.health.alive or player.riding:
			continue

		var offset := player.global_position - at
		var distance := offset.length()

		if distance > radius:
			continue

		var falloff := 1.0 - (distance / radius)
		var damage := DotDamage.make(
			attacker, player.entity_id, damage_amount * falloff, null
		)
		damage.point = player.global_position
		damage.direction = offset.normalized() if distance > 0.01 else Vector3.UP
		combat.apply_damage(damage)

		# Thrown, and a barrel is the only thing in the game that throws a runner
		# UPWARD. It is the one way onto a crate stack that the crates themselves do
		# not offer, and it is why a barrel is worth standing near as well as away
		# from.
		var push := damage.direction * force * falloff * 0.004
		player.controller.state.velocity += push + Vector3.UP * falloff * 4.0


func _on_player_died(player: BfhPlayer, damage: DotDamage) -> void:
	# One dictionary read. This walked every player on the server comparing ints,
	# which is the reverse index [DotEntityTable] keeps so nobody has to -- and it
	# ran on every death, which on this game is a lot of them.
	#
	# An attacker of 0 is dot-combat's "the world" -- a bus that nobody was driving,
	# a fall -- and the table returns an empty key for it, which is the same answer
	# the scan gave and means the same thing.
	var by := entities.key_for_id(damage.attacker)

	player_died.emit(player.player_id, by)
	DotLog.debug(CHANNEL, "player died", {"id": String(player.player_id), "by": String(by)})


# --- Reporting -------------------------------------------------------------

func alive_runners() -> int:
	var count := 0
	for player in runners():
		if player.health != null and player.health.alive:
			count += 1
	return count


func crates_left() -> int:
	if not authoritative and remote_cover >= 0:
		return remote_cover

	var count := 0
	for prop in props.all_props():
		if prop.is_alive() and prop.def != null and prop.def.id == BfhContent.CRATE:
			count += 1
	return count


func describe() -> Dictionary:
	return {
		"round": round_number,
		"elapsed": "%.0f s" % round_elapsed,
		"players": players.size(),
		"runners_alive": alive_runners(),
		"crates": crates_left(),
		"props": props.world_count() if props != null else 0,
		"buses": _bus_ids.size(),
		"gravity": "%.1f m/s2" % config.gravity,
		"bus_at": _bus_report(),
	}


## Where each bus is and how fast, for a console dump and a bug report.
##
## [b]Position and speed, because "the bus does nothing" has three causes and they look
## identical from the floor.[/b] It can be stuck on the ledge, upside down, or driving
## perfectly well somewhere the player is not — and only one of those is a bug.
func _bus_report() -> String:
	var parts := PackedStringArray()

	for instance_id in _bus_ids:
		var bus := vehicles.get_vehicle(instance_id)
		if bus == null or not bus.is_alive():
			parts.append("gone")
			continue

		var at := bus.position()

		# Wheels on the ground, because a vehicle with none is not a vehicle that is
		# broken — it is a vehicle that is airborne, and the two are the same picture.
		var grounded := 0
		var wheels := 0
		var body := bus.body()
		if body != null:
			for child in body.get_children():
				var wheel := child as VehicleWheel3D
				if wheel == null:
					continue
				wheels += 1
				if wheel.is_in_contact():
					grounded += 1

		var vb := body as VehicleBody3D
		var drive_line := ""
		if vb != null:
			drive_line = " engine=%.0f steer=%.2f thr=%.2f frz=%s slp=%s m=%.0f v=%s" % [
				vb.engine_force, vb.steering,
				bus.command.throttle if bus.command != null else 0.0,
				vb.freeze, vb.sleeping, vb.mass, str(vb.linear_velocity),
			]

		parts.append("(%.1f, %.1f, %.1f) %.1f m/s %d/%d wheels down" % [
			at.x, at.y, at.z, bus.speed(), grounded, wheels,
		] + drive_line + (" INVERTED" if bus.is_inverted() else ""))

	return ", ".join(parts) if not parts.is_empty() else "none"


func describe_lines() -> PackedStringArray:
	var lines := PackedStringArray()
	lines.append("buses-from-hell, round %d" % round_number)
	var facts := describe()
	for key: String in facts:
		lines.append("  %-16s %s" % [key, facts[key]])
	return lines
