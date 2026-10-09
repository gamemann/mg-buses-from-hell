extends Node

const BfhGame := preload("bfh_game.gd")
const BfhPlayer := preload("bfh_player.gd")
const BfhNetBridge := preload("net/bfh_net_bridge.gd")

## The score, and who is on which side: held on Tab, and up on its own between rounds.
##
## [b]Two sides, not two teams of the same thing.[/b] A symmetric game's scoreboard is one
## ranked list with a team colour per row; here two people drive and everybody else runs, and
## "who is still up" is a question about the runners only. So the board is two blocks side by
## side, each under its side's tally, and the per-player column is the one thing a player
## looks for: in a bus or on foot, up or out.
##
## [b]What dot-match scores in this game is rounds, per side.[/b] Its per-player records —
## kills, deaths, score — are never reported to (a runner cannot kill and a driver cannot
## die, so they would be one number and a column of zeros; see "What a player's numbers
## are" in CLAUDE.md). The tallies are [method BfhGame.rounds_won], which is dot-match's
## `rounds_won` on the authority and what the last CLOCK said on a client.
##
## [b]Drawn by dot-menu's `DotMenuScoreboard` since 2026-10-09[/b]; this file is what is this
## game's: the sides, the statuses, the tallies, the line about the round, and being up on its
## own after one. It drew its own two `DotTableView`s before, and had to give each an explicit
## size because a table in a container is drawn zero pixels tall; the menu's board is
## containers all the way down. Online the rows are the server's roster — names, pings and
## time connected, which no client knew for anybody else — with the side and the status joined
## in by id.

## Whose row is highlighted. Asked every time, because on a connected client the local
## player arrives in a JOIN frames after this exists.
var _own: Callable = Callable()

var game: BfhGame = null

## The board it draws on: the menu's, or one of its own when bound without one (a suite).
var board: DotMenuScoreboard = null

## Tab is down.
var held: bool = false

## Between a round's end and the next one's start, when it is up without being asked.
var after_round: bool = false

## The last round's winner, a `BfhGame.TEAM_*` or 0, for the line under the tables.
var last_winner: int = 0

var _layer: CanvasLayer = null

## When this client started: offline, the local player's time on.
var _started_msec: int = Time.get_ticks_msec()


## [param p_board] is the menu's board; null builds one here. [param link] is the client
## link, whose roster is drawn when there is one; null draws the local world.
func bind(p_game: BfhGame, own: Callable = Callable(), p_board: DotMenuScoreboard = null, link: Object = null) -> void:
	game = p_game
	_own = own
	board = p_board
	if board == null:
		_layer = CanvasLayer.new()
		_layer.layer = 50
		add_child(_layer)
		board = DotMenuScoreboard.new()
		board.name = "Board"
		_layer.add_child(board)

	board.title_text = "Buses from Hell"
	board.columns = [
		{"key": &"name", "title": "Player", "width": 3.0},
		{"key": &"status", "title": "", "width": 1.4, "align": HORIZONTAL_ALIGNMENT_RIGHT},
		{"key": &"seconds", "title": "Time", "kind": DotMenuScoreboard.KIND_DURATION},
		{"key": &"ping", "title": "Ping", "kind": DotMenuScoreboard.KIND_PING},
	]
	board.sort_with = func(a: Dictionary, b: Dictionary) -> bool:
		if (a.get(&"status", "") == "up") != (b.get(&"status", "") == "up"):
			return a.get(&"status", "") == "up"
		return str(a.get("name", "")).naturalnocasecmp_to(str(b.get("name", ""))) < 0
	board.decorate = _decorate_row
	board.prepare = _prepare
	if link != null:
		board.feed_from(link)
	else:
		board.source = snapshot

	game.round_over.connect(func(_number: int, winner: int) -> void:
		after_round = true
		last_winner = winner
		refresh()
	)
	game.round_began.connect(func(_number: int) -> void:
		after_round = false
		refresh()
	)
	refresh()


## Tab, held. Returns whether the event was the scoreboard's.
func handle_key(event: InputEvent) -> bool:
	var key := event as InputEventKey
	if key == null or key.echo or key.physical_keycode != KEY_TAB:
		return false
	held = key.pressed
	refresh()
	return true


func shown() -> bool:
	return held or after_round


## Up or down to match [method shown], and redrawn when up.
func refresh() -> void:
	if board == null:
		return
	if shown():
		if board.is_open():
			board.redraw()
		else:
			board.open()
	else:
		board.close()


## The local world as the board's snapshot: offline, and in a suite.
func snapshot() -> Dictionary:
	var players: Array = []
	if game != null:
		for id: StringName in game.players:
			var who: BfhPlayer = game.players[id]
			if who == null or not is_instance_valid(who):
				continue
			var here := int((Time.get_ticks_msec() - _started_msec) / 1000) if id == _own_id() else -1
			players.append({"id": String(id), "name": who.display_name, "ping": -1, "seconds": here})
	return {"server": {"name": "Buses from Hell", "game": "offline"}, "players": players}


## The side and the status onto a row, by id — the server's roster names sessions, the world
## names players, and [method BfhNetBridge.player_key] is the one place the two meet.
func _decorate_row(row: Dictionary) -> void:
	if game == null:
		return
	var id := StringName(str(row.get("id", "")))
	if not game.players.has(id):
		id = BfhNetBridge.player_key(int(row.get("id", 0)))
	var who: BfhPlayer = game.players.get(id)
	if who == null or not is_instance_valid(who):
		return
	var team := game.team_of(id)
	row["team"] = team
	row[&"status"] = status_of(who, team)
	row["you"] = id == _own_id()


## The two sides with their tallies, and the line about the round.
func _prepare(snap: Dictionary) -> void:
	if game == null:
		return
	snap["teams"] = [
		{"id": BfhGame.TEAM_DRIVERS, "name": side_name(game, BfhGame.TEAM_DRIVERS),
			"color": side_colour(game, BfhGame.TEAM_DRIVERS), "score": game.rounds_won(BfhGame.TEAM_DRIVERS)},
		{"id": BfhGame.TEAM_RUNNERS, "name": side_name(game, BfhGame.TEAM_RUNNERS),
			"color": side_colour(game, BfhGame.TEAM_RUNNERS), "score": game.rounds_won(BfhGame.TEAM_RUNNERS)},
	]
	snap["header"] = {"": footer_line(game, after_round, last_winner)}


## What the board's header says about a side, and about the round. For a check.
func header_text(team: int) -> String:
	return header_line(game, team)


func footer_text() -> String:
	return footer_line(game, after_round, last_winner)


## One side's rows. Static so a check reads the same rows the board draws.
##
## Drivers by name. Runners who are up first, then by name: the living are the part of the
## list a runner reads, and the table is capped at [constant RUNNER_ROWS].
static func rows_for(p_game: BfhGame, team: int, own: StringName = &"") -> Array[Dictionary]:
	var rows: Array[Dictionary] = []

	for id: StringName in p_game.players:
		if p_game.team_of(id) != team:
			continue
		var player: BfhPlayer = p_game.players[id]
		if player == null or not is_instance_valid(player):
			continue
		rows.append({
			&"name": player.display_name,
			&"status": status_of(player, team),
			&"id": String(id),
			"highlight": id == own,
		})

	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if team == BfhGame.TEAM_RUNNERS and (a[&"status"] == "up") != (b[&"status"] == "up"):
			return a[&"status"] == "up"
		return String(a[&"name"]).naturalnocasecmp_to(String(b[&"name"])) < 0
	)
	return rows


## What one player is doing, in the words a row says it.
static func status_of(player: BfhPlayer, team: int) -> String:
	if team == BfhGame.TEAM_DRIVERS:
		return "driving" if player.riding else "on foot"
	if player.health != null and not player.health.alive:
		return "out"
	return "up"


## A side's name as dot-match has it, and the rounds it has won.
static func header_line(p_game: BfhGame, team: int) -> String:
	var won := p_game.rounds_won(team)
	return "%s   %d %s won" % [side_name(p_game, team), won, "round" if won == 1 else "rounds"]


static func side_name(p_game: BfhGame, team: int) -> String:
	var side: DotTeam = null
	if p_game.match_node != null and p_game.match_node.teams != null:
		side = p_game.match_node.teams.team(team)
	if side != null and side.display_name != "":
		return side.display_name
	return "Drivers" if team == BfhGame.TEAM_DRIVERS else "Runners"


static func side_colour(p_game: BfhGame, team: int) -> Color:
	var side: DotTeam = null
	if p_game.match_node != null and p_game.match_node.teams != null:
		side = p_game.match_node.teams.team(team)
	return side.colour if side != null else Color(1, 1, 1)


## The line under the tables: who took the round just played, or which round this is.
static func footer_line(p_game: BfhGame, p_after_round: bool, winner: int) -> String:
	if p_after_round:
		match winner:
			BfhGame.TEAM_DRIVERS:
				return "Round %d: the buses got everybody" % p_game.round_number
			BfhGame.TEAM_RUNNERS:
				return "Round %d: the runners outlasted the clock" % p_game.round_number
			_:
				return "Round %d: nobody took it" % p_game.round_number
	return "Round %d" % p_game.round_number


func _own_id() -> StringName:
	var player: BfhPlayer = _own.call() if _own.is_valid() else null
	return player.player_id if player != null else &""


func describe() -> Dictionary:
	var drawn := board.rows() if board != null else []
	return {
		"shown": shown(),
		"held": held,
		"after_round": after_round,
		"drivers": drawn.filter(func(r: Dictionary) -> bool: return int(r.get("team", 0)) == BfhGame.TEAM_DRIVERS).size(),
		"runners": drawn.filter(func(r: Dictionary) -> bool: return int(r.get("team", 0)) == BfhGame.TEAM_RUNNERS).size(),
	}
