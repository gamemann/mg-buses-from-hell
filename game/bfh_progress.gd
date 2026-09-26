extends Node

const BfhAwards := preload("bfh_awards.gd")
const BfhContent := preload("bfh_content.gd")
const BfhPlayer := preload("bfh_player.gd")
const BfhStats := preload("bfh_stats.gd")

## What a player's round was worth: dot-stats counts it, dot-achievements decides what the
## counting earns.
##
## [codeblock]
## var progress := BfhProgress.new()
## world.add_child(progress)
## progress.attach(world)       # listens to the world; nothing calls in
## progress.session_values(&"u7").get_value(BfhStats.CRATES_BROKEN)
## [/codeblock]
##
## [b]A child of the authoritative world, and only of that.[/b] The server decides every
## number here — a client counting its own crates is a client that awards itself
## achievements — and an offline client IS an authoritative world, so the same node counts
## a game played alone. A connected client's world never builds one.
##
## [b]It listens and nothing calls it.[/b] Every reading is a world signal: `run_over`,
## `swung`, `bus_struck`, dot-props' `broken`, the round's own two. A counter fed from
## call sites inside the simulation is a counter that misses the one call site somebody
## added later.
##
## [b]The link between the two trackers is [DotAchievementStatsLink], not a
## `connect`.[/b] dot-stats' `recorded` carries a SESSION total and an achievement is about
## a lifetime; wiring one straight into the other adds the running total to itself on every
## reading. The link differences them, and that is its whole job.
##
## [b]In memory, and nothing is reported, both for the same reason: this game has no
## identity layer.[/b] Without one a player's key is their session on this server
## (`bfh-u<session>`), and a session id is handed out again by the next boot — so a file
## store would give one person's lifetime to whoever next got their number, and a report to
## the backbone would file it under a name that means nobody. dot-stats refuses an account
## id as a key for the same reason. When `BfhModule._wants_platform_module` turns on, the
## key becomes the scoped pseudonymous one and both of these become one line each.

const CHANNEL := "bfh.progress"

## Seconds after a hammer shove within which a bus driving into that crate credits the
## runner who moved it. Long enough for a bus that was ten metres off to arrive at cruising
## speed; short enough that a crate shoved in the first minute and hit in the third was
## not put there for the bus.
const SHOVE_CREDIT_SEC := 3.0

## Somebody earned something. What the bridge tells them, and what an offline HUD shows.
signal unlocked(player_id: StringName, achievement: DotAchievement)

var stats: DotStatsTracker = null
var achievements: DotAchievementTracker = null

## The differencer between the two. See the class note.
var link: DotAchievementStatsLink = null

var _world: Node3D = null

## player id -> the round time they started standing: the top of the round, or when they
## joined it. See [method _seconds_up].
var _up_since: Dictionary = {}

## prop instance id -> {"by": player id, "at": round time}. The last hammer shove on each
## crate, until a bus hits it or [constant SHOVE_CREDIT_SEC] passes.
var _shoves: Dictionary = {}

## storage key -> player id, for turning an unlock back into somebody to tell.
var _player_of_key: Dictionary = {}


## Builds both trackers and listens to [param world]. Call once, after this is in the tree
## and the world has built its props.
func attach(world: Node3D) -> DotResult:
	if world == null or world.get("props") == null or world.get("prop_damage") == null:
		return DotResult.fail(DotError.CODE_STATE, "Progress needs a world with its props built.")

	_world = world

	stats = DotStatsTracker.new()
	stats.name = "Stats"
	stats.schema = BfhStats.schema()
	# Off, and see the class note: nothing here has a key the backbone could file under.
	stats.report_to_backbone = false
	add_child(stats)

	var counted := stats.start()
	if not counted.ok:
		return counted.wrap("the stats tracker")

	achievements = DotAchievementTracker.new()
	achievements.name = "Achievements"
	achievements.catalogue = BfhAwards.catalogue()
	achievements.store = DotAchievementStoreMemory.new()
	achievements.report_to_backbone = false
	# [b]Not registered.[/b] A registry name is global to the process and a server and an
	# offline world — or the suite's dozen worlds — would take it off each other. This node
	# owns both trackers and hands them to the link directly.
	achievements.register_as = &""
	add_child(achievements)

	var awarded := achievements.start()
	if not awarded.ok:
		return awarded.wrap("the achievement tracker")

	achievements.unlocked.connect(_on_unlocked)

	link = DotAchievementStatsLink.new()
	link.name = "StatsLink"
	link.tracker = achievements
	link.stats = stats
	add_child(link)

	var linked := link.start()
	if not linked.ok:
		return linked.wrap("the stats-to-achievements link")

	world.connect("player_added", _on_player_added)
	world.connect("player_removed", _on_player_removed)
	world.connect("player_died", _on_player_died)
	world.connect("round_began", _on_round_began)
	world.connect("round_over", _on_round_over)
	world.connect("run_over", _on_run_over)
	world.connect("swung", _on_swung)
	world.connect("bus_struck", _on_bus_struck)
	(world.get("prop_damage") as DotPropDamage).broken.connect(_on_prop_broken)

	# Anybody already in the world. A world builds this in `_ready`, before any player
	# exists, so today this is empty — and a progress node attached late would otherwise
	# count nobody until they reconnected, with nothing saying so.
	for id: StringName in (world.get("players") as Dictionary):
		_on_player_added(id)

	return DotResult.success(self)


# --- Keys --------------------------------------------------------------------

## The key a player's numbers are kept under, or empty for somebody who is not counted.
##
## [b]A bot is not counted.[/b] Bots are what keep the buses full on an empty server, so on
## a dedicated server they do most of the flattening; a bot earning "Rush Hour" is a board
## of who the server was, and a runner flattened by a bot credits nobody.
func key_of(player_id: StringName) -> String:
	var player := _player(player_id)

	if player == null or player.is_bot:
		return ""

	return "bfh-%s" % String(player_id)


func _player(player_id: StringName) -> BfhPlayer:
	if _world == null or player_id == &"":
		return null
	return (_world.get("players") as Dictionary).get(player_id) as BfhPlayer


func _record(player_id: StringName, stat: StringName, value: float = 1.0) -> void:
	var key := key_of(player_id)

	if key == "" or stats == null:
		return

	var recorded := stats.record(StringName(key), stat, value)

	if not recorded.ok:
		# An undeclared id is a typo in this file and is the one failure worth a line: it
		# is a number the game is counting into nothing.
		DotLog.warn(CHANNEL, "a reading was refused", {
			"stat": String(stat), "why": recorded.error.message,
		})


# --- Players -----------------------------------------------------------------

func _on_player_added(player_id: StringName) -> void:
	var key := key_of(player_id)

	if key == "":
		return

	_player_of_key[key] = player_id
	_up_since[player_id] = float(_world.get("round_elapsed"))

	var player := _player(player_id)
	stats.begin(StringName(key), player.display_name if player != null else "")

	# Not awaited: a join does not wait on a store. Readings that arrive during a slow
	# load are still counted — dot-stats records them regardless, and the link neither
	# files them nor moves its baseline while the tracker has no such player, so the
	# first delta after the load carries everything that happened during it.
	_begin(key)


func _begin(key: String) -> void:
	var began: DotResult = await achievements.begin(key)

	if not began.ok:
		DotLog.warn(CHANNEL, "achievement progress could not be loaded", {
			"player": key, "why": began.error.message,
		})


func _on_player_removed(player_id: StringName) -> void:
	var key := "bfh-%s" % String(player_id)

	_up_since.erase(player_id)

	if not _player_of_key.has(key):
		return

	_player_of_key.erase(key)
	stats.end(StringName(key))
	# Without this the link holds one baseline per stat per player who has ever joined,
	# for as long as the server is up. Its own documentation says so.
	link.forget(key)
	_end(key)


func _end(key: String) -> void:
	var ended: DotResult = await achievements.end(key)

	if not ended.ok:
		DotLog.debug(CHANNEL, "achievement progress could not be saved", {
			"player": key, "why": ended.error.message,
		})


# --- What happened -------------------------------------------------------------

## A bus touched a runner. Only a kill is a flattening, and only a driver who is a person
## is credited with one.
func _on_run_over(_player_id: StringName, by: StringName, lethal: bool) -> void:
	if lethal:
		_record(by, BfhStats.RUNNERS_FLATTENED)


## A runner is out: the seconds they stood this round go on their total.
func _on_player_died(player_id: StringName, _by: StringName) -> void:
	_seconds_up(player_id)


func _on_round_began(_number: int) -> void:
	var now := float(_world.get("round_elapsed"))

	for id: Variant in _up_since.keys():
		_up_since[id] = now

	# Every crate is re-laid with the round, under new instance ids, so a shove from the
	# last round can never be credited — and the table would otherwise keep one row per
	# crate ever shoved for as long as the server is up.
	_shoves.clear()


## The round is over. Every runner still standing survived it.
##
## [b]Before the sides swap, and the world's order guarantees it:[/b] `round_over` is
## emitted before `_swap_sides` runs, so "a runner" here is somebody who spent this round
## running rather than somebody about to spend the next one driving.
func _on_round_over(_number: int, _winner: int) -> void:
	var runners: Array = _world.call("runners")

	for runner: BfhPlayer in runners:
		if runner.health == null or not runner.health.alive:
			continue

		_record(runner.player_id, BfhStats.ROUNDS_SURVIVED)
		_seconds_up(runner.player_id)


func _seconds_up(player_id: StringName) -> void:
	if not _up_since.has(player_id):
		return

	# Runners only, asked of the world rather than written as a side number here: a driver
	# out of their bus can be caught by a barrel, and seconds a driver "survived" are not
	# a number anybody on that side is playing for.
	var player := _player(player_id)
	if player == null or not (_world.call("runners") as Array).has(player):
		return

	var stood := float(_world.get("round_elapsed")) - float(_up_since[player_id])
	# Consumed, so a death and the round's end in one tick do not both count the round.
	_up_since.erase(player_id)

	# Whole seconds. A counter of fractions summed across a server's life accumulates the
	# rounding of every round; a second is what a player page shows anyway.
	var whole := floorf(stood)
	if whole >= 1.0:
		_record(player_id, BfhStats.SECONDS_SURVIVED, whole)


## A hammer went round. A crate it moved and did not break is remembered, in case a bus
## drives into it next.
func _on_swung(player_id: StringName, instance_id: int, broke: bool) -> void:
	if instance_id == 0 or broke:
		return

	_shoves[instance_id] = {"by": player_id, "at": float(_world.get("round_elapsed"))}


## A bus drove into a prop. If a runner shoved it there recently, that runner put it in
## the bus's path — once, however many ticks the bus spends against it.
func _on_bus_struck(instance_id: int, _by: StringName) -> void:
	if not _shoves.has(instance_id):
		return

	var shove: Dictionary = _shoves[instance_id]
	_shoves.erase(instance_id)

	if float(_world.get("round_elapsed")) - float(shove["at"]) > SHOVE_CREDIT_SEC:
		return

	_record(StringName(shove["by"]), BfhStats.CRATES_INTO_PATH)
	DotLog.debug(CHANNEL, "a shoved crate was in a bus's path", {
		"runner": String(shove["by"]), "prop": instance_id,
	})


## Anything broken, credited to whoever broke it if it was a crate. A barrel is not cover,
## and a block cannot break.
func _on_prop_broken(prop: DotPropInstance, _at: Vector3, by: StringName) -> void:
	_shoves.erase(prop.instance_id if prop != null else 0)

	if prop == null or prop.def == null or prop.def.id != BfhContent.CRATE:
		return

	_record(by, BfhStats.CRATES_BROKEN)


func _on_unlocked(key: String, achievement: DotAchievement) -> void:
	var player_id: StringName = _player_of_key.get(key, &"")

	# INFO: what an admin keeps. "I did the thing and was not told" is answered from here.
	DotLog.info(CHANNEL, "an achievement was unlocked", {
		"player": key, "achievement": String(achievement.id), "points": achievement.points,
	})

	if player_id != &"":
		unlocked.emit(player_id, achievement)


# --- Reading -------------------------------------------------------------------

## A player's numbers this session. Empty for a bot or a stranger.
func session_values(player_id: StringName) -> DotStatsValues:
	var key := key_of(player_id)

	if key == "" or stats == null:
		return DotStatsValues.new()

	return stats.session_values(StringName(key))


func is_unlocked(player_id: StringName, id: StringName) -> bool:
	var key := key_of(player_id)
	return key != "" and achievements != null and achievements.is_unlocked(key, id)


## What `bfh_stats` prints for one player.
func player_lines(player_id: StringName) -> PackedStringArray:
	var out := PackedStringArray()
	var key := key_of(player_id)

	if key == "":
		out.append("%s: not counted (a bot, or not in the world)" % String(player_id))
		return out

	var values := session_values(player_id)
	out.append("%s (%s), this session:" % [String(player_id), key])

	for def in BfhStats.schema().stats:
		out.append("  %-26s %s" % [def.display_name, def.format_value(values.get_value(def.id))])

	for row in achievements.listing(key):
		if row.has("at"):
			out.append("  earned: %s" % str(row.get("name", row.get("id", "?"))))

	return out


func describe() -> Dictionary:
	return {
		"players": _player_of_key.size(),
		"shoves_pending": _shoves.size(),
		"stats": stats.describe() if stats != null else {},
		"achievements": achievements.describe() if achievements != null else {},
	}


func describe_lines() -> PackedStringArray:
	var out := PackedStringArray()

	if stats != null:
		out.append_array(stats.describe_lines())

	if achievements != null:
		out.append_array(achievements.describe_lines())

	return out
