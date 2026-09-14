extends RefCounted

const BfhGame := preload("../bfh_game.gd")

## The wire format for everything that is not a snapshot or an input.
##
## Encoders and decoders in pairs, and nothing checks that they are inverses for you —
## `headless_net` round-trips every one of them, because this family has already shipped
## a serialisation whose two ends never met: dot-moderation wrote `"voice muted"` and
## read back a warning, and the one thing that addon existed for silently did nothing.
##
## [b]Everything in the bowl is ANNOUNCED and then moved by snapshot, and it needs
## both.[/b] A snapshot carries a position and a rotation; it cannot carry what a thing
## IS. So a crate, a barrel, a block and a bus each arrive as an event naming the
## catalogue id and the net id the snapshot will move, and the client builds the same
## body from the same catalogue. A factory keyed on a script would be the alternative,
## and a script cannot be named: a `class_name` inside a mounted dot-cloud pack is not
## registered in the host, which is the whole reason this game's content is addressed by
## path in [BfhContent].

enum Kind {
	## Who you are, how fast the server ticks, and how big the bowl is.
	HELLO,
	## A player is in the world: net id, name, side.
	JOIN,
	LEAVE,
	## A player changed sides. Every third round, everybody gets one.
	TEAM,
	## A crate, a barrel, a block or a bus now exists.
	PROP,
	## It is gone, and why — broken, driven over, or the round being re-laid.
	PROP_GONE,
	## Somebody got into or out of a bus.
	SEAT,
	## The round clock, and the two numbers a client cannot count for itself.
	CLOCK,
	## A round began or ended.
	ROUND,
	## Somebody was run over or caught a barrel.
	DEATH,
	## A barrel went off. The client draws it; the server decided it.
	BLAST,
	## Text for one player or for everybody.
	NOTICE,
	## One chat line, already routed, sanitised and addressed by [DotChatRouter].
	CHAT,
}

enum Ask {
	## I have built my world and can receive. Tell me everything in the bowl.
	READY,
	## I typed a line. The server decides what channel it lands on and who hears it.
	SAY,
}

## Every decoder returns an `ok` beside its fields, and every caller checks it.
##
## [b]A reader past its end returns plausible zeros rather than failing.[/b] dot-net
## shipped with exhaustion that was not sticky, so a decoder that skipped this check got
## a believable value for the field AFTER the overrun — and a truncated packet decodes as
## a valid message about nothing.
const NAME_BYTES := 64
const ID_BYTES := 64
const TEXT_BYTES := 256

## Where a body may be, in metres, on the wire.
##
## [b]Read from [BfhGame], not written here.[/b] A quantised position is decoded against
## this range, so two files holding two numbers do not lose precision — they put the
## crate somewhere else. game-arena had exactly this, 256 against 128, in two files that
## each looked right on its own.
const WORLD_EXTENT := BfhGame.NET_WORLD_EXTENT
const POS_BITS := 24

## The round clock, in seconds. Fifteen minutes is far past anything `round_seconds`
## allows, and the ninth bit is cheaper than the bug of a clock that wraps.
const CLOCK_MAX := 900.0
const CLOCK_BITS := 14


static func kind_name(kind: int) -> String:
	var names := Kind.keys()
	return String(names[kind]) if kind >= 0 and kind < names.size() else "?"


static func ask_name(ask: int) -> String:
	var names := Ask.keys()
	return String(names[ask]) if ask >= 0 and ask < names.size() else "?"


static func _w() -> DotNetWriter:
	return DotNetWriter.new()


# --- Hello -----------------------------------------------------------------

## What a client needs before it can build anything.
##
## [b]The arena radius is in here, and a client that guessed it would build a different
## bowl.[/b] This game's map is not a file, it is `BfhArena.build(radius)` run on both
## ends — which is what makes it free to deliver and free to change — so the radius is
## the whole map as far as the wire is concerned. A client on 46 against a server on 30
## has a wall seven metres past where the server says the wall is.
static func write_hello(
	player_id: int,
	tick_rate: int,
	server_tick: int,
	arena_radius: float,
	round_seconds: float
) -> PackedByteArray:
	var w := _w()
	w.write_varint(player_id)
	w.write_uint(tick_rate, 9)
	w.write_varint(server_tick)
	w.write_float_range(arena_radius, 0.0, 512.0, 16)
	w.write_float_range(round_seconds, 0.0, CLOCK_MAX, CLOCK_BITS)
	return w.to_bytes()


static func read_hello(r: DotNetReader) -> Dictionary:
	var player_id := r.read_varint()
	var tick_rate := r.read_uint(9)
	var server_tick := r.read_varint()
	var arena_radius := r.read_float_range(0.0, 512.0, 16)
	var round_seconds := r.read_float_range(0.0, CLOCK_MAX, CLOCK_BITS)
	return {
		"player_id": player_id,
		"tick_rate": tick_rate,
		"server_tick": server_tick,
		"arena_radius": arena_radius,
		"round_seconds": round_seconds,
		"ok": r.ok(),
	}


# --- Players ---------------------------------------------------------------

static func write_join(
	player_id: int, net_id: int, display_name: String, team: int
) -> PackedByteArray:
	var w := _w()
	w.write_varint(player_id)
	w.write_varint(net_id)
	w.write_string(display_name, NAME_BYTES)
	w.write_uint(clampi(team, 0, 3), 2)
	return w.to_bytes()


static func read_join(r: DotNetReader) -> Dictionary:
	var player_id := r.read_varint()
	var net_id := r.read_varint()
	var display_name := r.read_string(NAME_BYTES)
	var team := r.read_uint(2)
	return {
		"player_id": player_id,
		"net_id": net_id,
		"name": display_name,
		"team": team,
		"ok": r.ok(),
	}


static func write_player(player_id: int) -> PackedByteArray:
	var w := _w()
	w.write_varint(player_id)
	return w.to_bytes()


static func read_player(r: DotNetReader) -> int:
	return r.read_varint()


## A side change. One player per message, because a swap is rare and a list is a second
## encoding of the same fact that can disagree with the first.
static func write_team(player_id: int, team: int) -> PackedByteArray:
	var w := _w()
	w.write_varint(player_id)
	w.write_uint(clampi(team, 0, 3), 2)
	return w.to_bytes()


static func read_team(r: DotNetReader) -> Dictionary:
	var player_id := r.read_varint()
	var team := r.read_uint(2)
	return {"player_id": player_id, "team": team, "ok": r.ok()}


# --- What is in the bowl ---------------------------------------------------

## Something the world has put out: a crate, a barrel, a block or a bus.
##
## [param vehicle] says which catalogue [param kind_id] is in. It is a bit rather than a
## second message kind because everything else about the two is identical — a net id, a
## scene, a place to put it — and two near-identical messages is two decoders to keep in
## step.
static func write_prop(
	net_id: int, kind_id: StringName, at: Vector3, vehicle: bool
) -> PackedByteArray:
	var w := _w()
	w.write_varint(net_id)
	w.write_string(String(kind_id), ID_BYTES)
	w.write_vector3_range(at, -WORLD_EXTENT, WORLD_EXTENT, POS_BITS)
	w.write_bool(vehicle)
	return w.to_bytes()


static func read_prop(r: DotNetReader) -> Dictionary:
	var net_id := r.read_varint()
	var kind_id := r.read_string(ID_BYTES)
	var at := r.read_vector3_range(-WORLD_EXTENT, WORLD_EXTENT, POS_BITS)
	var vehicle := r.read_bool()
	return {
		"net_id": net_id,
		"kind_id": StringName(kind_id),
		"position": at,
		"vehicle": vehicle,
		"ok": r.ok(),
	}


static func write_prop_gone(net_id: int, reason: StringName) -> PackedByteArray:
	var w := _w()
	w.write_varint(net_id)
	w.write_string(String(reason), ID_BYTES)
	return w.to_bytes()


static func read_prop_gone(r: DotNetReader) -> Dictionary:
	var net_id := r.read_varint()
	var reason := r.read_string(ID_BYTES)
	return {"net_id": net_id, "reason": StringName(reason), "ok": r.ok()}


## Who is driving what.
##
## [b]The client is told the answer rather than running the ride.[/b] It has no vehicle
## spawner, no seats and no exit sweep — the server owns all three — and what it does
## with this is stop predicting a player who is no longer walking. Without it a predicted
## controller fights the snapshots that are carrying the bus, every tick, at a metre a
## time.
static func write_seat(player_id: int, net_id: int, seated: bool) -> PackedByteArray:
	var w := _w()
	w.write_varint(player_id)
	w.write_varint(net_id)
	w.write_bool(seated)
	return w.to_bytes()


static func read_seat(r: DotNetReader) -> Dictionary:
	var player_id := r.read_varint()
	var net_id := r.read_varint()
	var seated := r.read_bool()
	return {"player_id": player_id, "net_id": net_id, "seated": seated, "ok": r.ok()}


# --- The round -------------------------------------------------------------

## The clock and the two numbers a client cannot count for itself.
##
## [b]`cover` is why this message exists.[/b] A client does not run the prop spawner —
## its crates are mirrored bodies — so `crates_left()` on a client counts nothing, and
## that number is the most important one on this game's HUD: it is what tells a runner
## whether standing still is still an option. Health and the clock a client can see for
## itself; this it has to be told.
static func write_clock(
	round_number: int, elapsed: float, cover: int, alive: int, playable: bool
) -> PackedByteArray:
	var w := _w()
	w.write_varint(round_number)
	w.write_float_range(clampf(elapsed, 0.0, CLOCK_MAX), 0.0, CLOCK_MAX, CLOCK_BITS)
	w.write_uint(clampi(cover, 0, 1023), 10)
	w.write_uint(clampi(alive, 0, 255), 8)
	w.write_bool(playable)
	return w.to_bytes()


static func read_clock(r: DotNetReader) -> Dictionary:
	var round_number := r.read_varint()
	var elapsed := r.read_float_range(0.0, CLOCK_MAX, CLOCK_BITS)
	var cover := r.read_uint(10)
	var alive := r.read_uint(8)
	var playable := r.read_bool()
	return {
		"round": round_number,
		"elapsed": elapsed,
		"cover": cover,
		"alive": alive,
		"playable": playable,
		"ok": r.ok(),
	}


## A round began, or ended with a winner. [param winner] is a `BfhGame.TEAM_*`, or 0.
static func write_round(number: int, began: bool, winner: int) -> PackedByteArray:
	var w := _w()
	w.write_varint(number)
	w.write_bool(began)
	w.write_uint(clampi(winner, 0, 3), 2)
	return w.to_bytes()


static func read_round(r: DotNetReader) -> Dictionary:
	var number := r.read_varint()
	var began := r.read_bool()
	var winner := r.read_uint(2)
	return {"round": number, "began": began, "winner": winner, "ok": r.ok()}


static func write_death(player_id: int, by: int) -> PackedByteArray:
	var w := _w()
	w.write_varint(player_id)
	w.write_varint(by)
	return w.to_bytes()


static func read_death(r: DotNetReader) -> Dictionary:
	var player_id := r.read_varint()
	var by := r.read_varint()
	return {"player_id": player_id, "by": by, "ok": r.ok()}


## Where a barrel went off and how far it reached.
##
## [b]An event and not a replicated property, because a blast is an instant.[/b] A client
## that learned about it from a snapshot would learn about it once the barrel had already
## been removed, at whatever the interpolation delay is — which is a bang with nothing
## under it. Reliable, for the same reason: a missed one is a player wondering why
## they are suddenly in the air.
static func write_blast(at: Vector3, radius: float) -> PackedByteArray:
	var w := _w()
	w.write_vector3_range(at, -WORLD_EXTENT, WORLD_EXTENT, POS_BITS)
	w.write_float_range(radius, 0.0, 64.0, 12)
	return w.to_bytes()


static func read_blast(r: DotNetReader) -> Dictionary:
	var at := r.read_vector3_range(-WORLD_EXTENT, WORLD_EXTENT, POS_BITS)
	var radius := r.read_float_range(0.0, 64.0, 12)
	return {"position": at, "radius": radius, "ok": r.ok()}


# --- Chat ------------------------------------------------------------------

## A chat line's own field widths. Wider than the rules allow, so a rule can be raised
## without the wire silently truncating what it lets through.
const CHAT_BYTES := 200
const CHAT_CHANNEL_BYTES := 24
const CHAT_KEY_BYTES := 48
const CHAT_KIND_BITS := 4


## One routed line, in [DotChatMessage]'s own wire shape.
##
## [b]Field by field rather than `var_to_bytes`, like every other message here.[/b] A
## dictionary serialised whole is a dictionary whose contents are whatever the sender put
## in it — including keys a client will happily read — and the widths below are the
## validation. `x.p` is the one meta field this game carries: the speaker's session id, so
## a client can colour a line by whose it is.
static func write_chat(wire: Dictionary) -> PackedByteArray:
	var w := _w()
	w.write_varint(int(wire.get("n", 0)))
	w.write_uint(int(wire.get("t", 0)), 32)
	w.write_string(str(wire.get("c", "")), CHAT_CHANNEL_BYTES)
	w.write_uint(
		maxi(0, DotChatMessage.kind_from_name(str(wire.get("k", "say")))), CHAT_KIND_BITS
	)
	w.write_string(str(wire.get("s", "")), CHAT_KEY_BYTES)
	w.write_string(str(wire.get("d", "")), NAME_BYTES)
	w.write_string(str(wire.get("w", "")), CHAT_KEY_BYTES)
	w.write_string(str(wire.get("m", "")), CHAT_BYTES)

	var meta: Variant = wire.get("x")
	var player_id := 0

	if typeof(meta) == TYPE_DICTIONARY:
		player_id = int((meta as Dictionary).get("p", 0))

	w.write_varint(maxi(player_id, 0))
	return w.to_bytes()


static func read_chat(r: DotNetReader) -> Dictionary:
	var out := {
		"n": r.read_varint(),
		"t": r.read_uint(32),
		"c": r.read_string(CHAT_CHANNEL_BYTES),
	}

	var kind := r.read_uint(CHAT_KIND_BITS)
	out["k"] = (
		DotChatMessage.KIND_NAMES[kind] if kind >= 0 and kind < DotChatMessage.KIND_NAMES.size()
		else "say"
	)

	out["s"] = r.read_string(CHAT_KEY_BYTES)
	out["d"] = r.read_string(NAME_BYTES)
	out["w"] = r.read_string(CHAT_KEY_BYTES)
	out["m"] = r.read_string(CHAT_BYTES)

	var player_id := r.read_varint()

	if player_id > 0:
		out["x"] = {"p": player_id}

	out["ok"] = r.ok()
	return out


## What a client sends when somebody presses Enter: a channel and a line, and nothing else.
##
## [b]No speaker, no time, no colour.[/b] Everything about what a line MEANS is decided on
## the server — who said it, whether they are gagged, whether they are talking too fast,
## which of the four channels they may use and who can hear it. A client that sent any of
## that would be a client that could claim it.
static func write_say(channel_id: StringName, text: String) -> PackedByteArray:
	var w := _w()
	w.write_string(String(channel_id), CHAT_CHANNEL_BYTES)
	w.write_string(text, CHAT_BYTES)
	return w.to_bytes()


static func read_say(r: DotNetReader) -> Dictionary:
	var out := {
		"channel": r.read_string(CHAT_CHANNEL_BYTES),
		"text": r.read_string(CHAT_BYTES),
	}
	out["ok"] = r.ok()
	return out


static func write_notice(text: String) -> PackedByteArray:
	var w := _w()
	w.write_string(text, TEXT_BYTES)
	return w.to_bytes()


static func read_notice(r: DotNetReader) -> Dictionary:
	var text := r.read_string(TEXT_BYTES)
	return {"text": text, "ok": r.ok()}
