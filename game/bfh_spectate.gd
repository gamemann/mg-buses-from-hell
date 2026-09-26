extends Node

const BfhPlayer := preload("bfh_player.gd")

## Where a runner who has been run down looks until the next round.
##
## [b]Until 2026-09-25 a runner who was out looked at the patch of sand they were run over
## on, for up to three minutes.[/b] Out means out here — there is no respawn until the next
## round, by design — so the part of the game a runner spends dead is not two seconds before
## a respawn, it is most of a round on a bad one. A first-person game whose dead players
## stare at the floor for that long is a game people alt-tab out of.
##
## [codeblock]
## spectate.setup(world, authoritative, tick_rate)
## spectate.on_death(&"u7", where, &"u900000", tick)   # the world does this
## spectate.request(&"u7", BfhSpectate.ASK_NEXT)       # the player's click
## camera.global_transform = spectate.camera_for(&"u7")
## [/codeblock]
##
## [b]The server decides and the client draws, and they are two instances of this.[/b] The
## authority's [DotSpectatorManager] runs the chain — a death camera on the bus that did it,
## a freeze on its cab, then somebody to follow — and answers every click. A connected
## client's copy is a MIRROR: told its own view as per-player state
## (`BfhPlayerNet.net_watch`, owner-only), it computes the camera from the positions it is
## already drawing, and it decides nothing. An offline client is an authority, so it is the
## same code as a server.
##
## [b]The policy, and why it is the loosest one in the family.[/b]
## - [b]Anybody may be watched, a bus included[/b] (`force_camera` 0). The obvious worry —
##   a dead runner calling out where the bus is — is not one this game can defend against
##   with a camera: every player and every bus is ALWAYS relevant here (`BfhNetBridge`
##   replicates everything to everybody, because the bowl is a disc with nothing tall in
##   it), so any client already has every position the camera could show it. A policy that
##   forbade the bus would protect nothing from a modified client and deny an honest one the
##   most watchable thing on the server. And "own side only" would mean a runner may watch
##   runners — the half of the round that is not being chased by anything.
## - [b]No delay[/b], for the same reason: a delay that only a client enforces, over data
##   the client already has, is theatre. (A mirror records its own history since
##   2026-09-25, so it would draw — but only what this client already has.)
## - [b]No roaming.[/b] A free camera over a 92 m bowl is a map of it, and above the tanks
##   it is exactly the view the tank farm exists to take away from a runner on the ground.
## - [b]The living do not watch.[/b] A runner who is up is playing; a driver cannot be out.
##
## [b]A bus's "eyes" are its cab.[/b] A driver's own position is where they sat down —
## nothing moves a rider (see [member BfhPlayer.ridden]) — so a camera on a driver's body
## would sit on the sand watching an empty patch while the bus they are steering chases
## somebody else. [method pose_of] answers with the bus.

const CHANNEL := "bfh.spectate"

## What a spectator can ask for. Also the wire format of `BfhEvents.Ask.WATCH`.
const ASK_NEXT := 0
const ASK_PREVIOUS := 1
const ASK_VIEW := 2

## Where a driver's view is, in their bus's own frame: over the cab roof, behind the
## container its forks carry out front.
##
## [b]Higher than a driver's head, on purpose, and the first render is why.[/b] At seat
## height (2.9 m, just forward of the seat) the Kenney truck's container filled the bottom
## third of the frame and the road the bus was about to take was behind it. Up here the
## container is a strip along the bottom edge that says "you are the bus", and the runners
## it is chasing are in the middle of the picture.
const CAB_EYE := Vector3(0.0, 3.8, -1.2)

## And pitched down the road rather than at the horizon, which is where the runners are.
const CAB_PITCH_DEG := -14.0

## Seconds of death camera: from where they fell, looking at the bus that did it.
const DEATH_CAM_SEC := 1.0

## Seconds of freeze camera: from the cab of the bus that did it. Who got you, and where
## they are going next.
const FREEZE_CAM_SEC := 2.0

var manager: DotSpectatorManager = null

var _world: Node3D = null


## Builds the manager. [param authoritative] false builds a mirror.
func setup(world: Node3D, authoritative: bool, tick_rate: int) -> DotResult:
	_world = world

	manager = DotSpectatorManager.new()
	manager.name = "Manager"
	manager.authoritative = authoritative
	manager.rules = rules_for(tick_rate)
	manager.participants_fn = _participants
	manager.alive_fn = _alive
	manager.team_fn = _team
	manager.pose_fn = pose_of
	add_child(manager)

	var built := manager.setup()
	if not built.ok:
		return built.wrap("spectating")

	# Once per world. INFO because it is the policy an admin is asked about.
	if authoritative:
		DotLog.info(CHANNEL, "spectating is set up", {
			"watch_anybody": manager.rules.force_camera == 0,
			"roaming": manager.rules.allow_roaming,
			"death_cam_ticks": manager.rules.death_cam_ticks,
			"freeze_cam_ticks": manager.rules.freeze_cam_ticks,
		})

	return DotResult.success(self)


## The policy, as a document. See the class note for each line.
static func rules_for(tick_rate: int) -> DotSpectatorRules:
	var rules := DotSpectatorRules.new()
	rules.force_camera = 0
	rules.allow_while_alive = false
	rules.allow_while_dead = true
	rules.allow_unassigned = true
	rules.allow_roaming = false
	rules.cycle_includes_dead = false
	rules.auto_retarget = true
	rules.delay_ticks = 0
	rules.death_cam_ticks = int(DEATH_CAM_SEC * float(tick_rate))
	rules.freeze_cam_ticks = int(FREEZE_CAM_SEC * float(tick_rate))
	# Far enough back that a runner is a figure in a scene rather than a back of a head,
	# and that a bus — nine metres of it in front of its own cab — is behind the camera's
	# subject rather than over it.
	rules.chase_distance = 7.0
	rules.chase_height = 2.5
	return rules


# --- Callables the manager asks ------------------------------------------------

func _players() -> Dictionary:
	return _world.get("players") as Dictionary if _world != null else {}


## Everybody who could be watched: every player, sorted by key so "next" is stable.
func _participants() -> PackedStringArray:
	var out := PackedStringArray()
	var ids: Array = _players().keys()
	ids.sort()
	for id: Variant in ids:
		out.append(String(id))
	return out


func _alive(key: String) -> bool:
	var player: BfhPlayer = _players().get(StringName(key))
	return player != null and (player.health == null or player.health.alive)


## The side, as dot-spectate's team number. Zero is "no side".
func _team(key: String) -> int:
	return int((_world.get("sides") as Dictionary).get(StringName(key), 0)) if _world != null else 0


## Where somebody's eyes are: a runner's, or a driver's bus's cab.
##
## Read from what this machine is drawing — the controller's state on a runner, which a
## client's interpolation writes every frame, and the bus's body, which it moves — so a
## mirror's camera is exactly as smooth as the picture it is looking at.
func pose_of(key: String) -> Transform3D:
	var player: BfhPlayer = _players().get(StringName(key))

	if player == null or player.controller == null:
		return Transform3D.IDENTITY

	if player.riding and player.ridden != null and is_instance_valid(player.ridden):
		var bus := player.ridden.global_transform
		var yaw := atan2(-bus.basis.z.x, -bus.basis.z.z)
		var cab := Basis.from_euler(Vector3(deg_to_rad(CAB_PITCH_DEG), yaw, 0.0))
		return Transform3D(cab, bus * CAB_EYE)

	var state := player.controller.state
	var basis := Basis.from_euler(Vector3(deg_to_rad(state.pitch), deg_to_rad(state.yaw), 0.0))
	return Transform3D(basis, state.position + Vector3(0.0, BfhPlayer.EYE_HEIGHT, 0.0))


# --- What the world reports ----------------------------------------------------

## The world ticked. Runs the death camera's hand-overs and moves anybody whose target
## went away. A mirror's is a no-op inside dot-spectate.
func tick(tick_number: int) -> void:
	if manager != null:
		manager.advance(tick_number)


## Somebody is out. The chain starts: where they fell, then who did it, then somebody.
func on_death(player_id: StringName, at: Vector3, by: StringName, tick_number: int) -> void:
	if manager == null or not manager.authoritative:
		return

	manager.on_death(String(player_id), at, String(by), tick_number)

	# DEBUG: a transition. "My camera went somewhere odd when I was run over" is answered by
	# who it was put on.
	DotLog.debug(CHANNEL, "a runner who is out is watching", {
		"player": String(player_id), "killer": String(by), "view": describe_view(player_id),
	})


## A round began: everybody has a new body, so nobody is watching.
func on_round_began() -> void:
	if manager == null or not manager.authoritative:
		return

	for key in manager.viewers():
		manager.on_spawn(key)


## Somebody left. Call AFTER the world has dropped them, so a spectator who was watching
## them is moved to somebody who is still there — dot-spectate chooses the replacement from
## the participants, and a world that reported first would have it pick the leaver.
func on_leave(player_id: StringName) -> void:
	if manager != null:
		manager.on_leave(String(player_id))


# --- What a spectator asks -----------------------------------------------------

## A click, on the authority. [param ask] is one of the ASK_* constants.
##
## [b]Every answer is the manager's.[/b] A living runner asking to watch is refused by the
## same rule that decides everything else, rather than by this function having an opinion.
func request(player_id: StringName, ask: int) -> DotResult:
	if manager == null:
		return DotResult.fail(DotError.CODE_STATE, "Spectating is not set up.")
	if not manager.authoritative:
		return DotResult.fail(DotError.CODE_FORBIDDEN, "A client asks the server; it does not decide.")

	var key := String(player_id)

	match ask:
		ASK_NEXT:
			return manager.next_target(key)
		ASK_PREVIOUS:
			return manager.previous_target(key)
		ASK_VIEW:
			var view := manager.view(key)
			if not view.follows_target() or view.is_timed():
				return DotResult.fail(
					DotError.CODE_STATE, "There is nobody to change the view of yet."
				)
			var wanted := (
				DotSpectatorView.Mode.CHASE if view.mode == DotSpectatorView.Mode.FIRST_PERSON
				else DotSpectatorView.Mode.FIRST_PERSON
			)
			return manager.set_mode(key, wanted)

	return DotResult.fail(DotError.CODE_INVALID, "Unknown spectator request %d." % ask)


# --- Reading, and the mirror ---------------------------------------------------

func is_spectating(player_id: StringName) -> bool:
	return manager != null and manager.is_spectating(String(player_id))


## Where [param player_id]'s camera is, or identity when they are not watching.
func camera_for(player_id: StringName) -> Transform3D:
	return manager.camera_of(String(player_id)) if manager != null else Transform3D.IDENTITY


func mode_of(player_id: StringName) -> int:
	return int(manager.view(String(player_id)).mode) if is_spectating(player_id) else 0


## Who they are looking at: the target, or on a death camera the killer it looks at.
func target_of(player_id: StringName) -> StringName:
	if not is_spectating(player_id):
		return &""

	var view := manager.view(String(player_id))

	if view.mode == DotSpectatorView.Mode.DEATH_CAM:
		return StringName(view.killer)

	return StringName(view.target)


## A mirror is told its own view. [param target] is who [method target_of] would answer.
##
## [b]The place they fell is taken from where THIS machine last drew them[/b], on the
## transition into watching, because it is not in the state that is replicated
## (`net_watch` is a mode and a target). dot-spectate's own wire carries it since
## 2026-09-25, but this game does not send that wire. A mirror left at the default would
## draw every death camera from the world origin.
func adopt(player_id: StringName, mode: int, target: StringName) -> void:
	if manager == null or manager.authoritative:
		return

	var key := String(player_id)
	var view := manager.view(key)
	var was_watching := view.is_watching()

	if mode <= 0 or mode >= DotSpectatorView.Mode.size():
		if was_watching:
			manager.stop(key)
		return

	if not was_watching:
		var player: BfhPlayer = _players().get(player_id)
		if player != null and player.controller != null:
			view.death_position = player.controller.state.position

	var as_mode := mode as DotSpectatorView.Mode
	var wire := {"m": mode, "t": "", "k": "", "u": -1}

	if as_mode == DotSpectatorView.Mode.DEATH_CAM:
		wire["k"] = String(target)
	elif as_mode == DotSpectatorView.Mode.FREEZE_CAM:
		wire["k"] = String(target)
		wire["t"] = String(target)
	else:
		wire["t"] = String(target)

	manager.apply_wire({"k": key, "v": wire})


func describe_view(player_id: StringName) -> String:
	if not is_spectating(player_id):
		return "playing"

	return "%s %s" % [
		DotSpectatorView.Mode.keys()[mode_of(player_id)], String(target_of(player_id))
	]


func describe() -> Dictionary:
	return manager.describe() if manager != null else {}


func describe_lines() -> PackedStringArray:
	if manager == null:
		return PackedStringArray(["spectate: not set up"])
	return manager.describe_lines()
