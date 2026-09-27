extends CanvasLayer

const BfhGame := preload("bfh_game.gd")
const BfhPlayer := preload("bfh_player.gd")

## The score, and who is on which side: held on Tab, and up on its own between rounds.
##
## [b]Two tables, not one, because the sides are not two teams of the same thing.[/b] A
## symmetric game's scoreboard is one ranked list with a team colour per row; here two
## people drive and everybody else runs, and "who is still up" is a question about the
## runners only. So the buses get a short table and the runners a long one, side by side,
## each under its side's tally.
##
## [b]What dot-match scores in this game is rounds, per side.[/b] Its per-player records —
## kills, deaths, score — are never reported to (a runner cannot kill and a driver cannot
## die, so they would be one number and a column of zeros; see "What a player's numbers
## are" in CLAUDE.md), so the per-player column is the one thing a player looks for: in a
## bus or on foot, up or out. The tallies are [method BfhGame.rounds_won], which is
## dot-match's `rounds_won` on the authority and what the last CLOCK said on a client.
##
## [b]Every Control here is given its size, never left to find one.[/b] A [DotTableView] is
## a plain Control over a full-rect box of rows, so its minimum size is zero, and inside a
## container that is exactly the size it gets: the table is built, filled, and drawn zero
## pixels tall. The family's HUDs have each met that once; `headless_net` measures the
## cells.

# No `const CHANNEL`: it draws state the world owns and decides nothing an operator would
# read about. See the same note in [BfhHud].

## Above the HUD and below the chat box (100), which a player may be typing in.
const LAYER := 50

const PANEL_HALF := Vector2(390.0, 220.0)

## The height of a row in a table, for the tables' explicit sizes.
const ROW_PX := 30.0

## Rows a table is sized for. Beyond it the runners' table scrolls nothing and shows the
## top of the list, which is the living, which is the part that matters.
const DRIVER_ROWS := 3
const RUNNER_ROWS := 10

## A side's columns. Status is the per-player column; see the class notes. A function
## rather than a const, because a const array is read-only and a table keeps what it is given.
static func columns_for(team: int) -> Array[Dictionary]:
	return [
		{"key": &"name", "title": "Driver" if team == BfhGame.TEAM_DRIVERS else "Runner", "width": 3.0},
		{"key": &"status", "title": "", "width": 1.4, "align": HORIZONTAL_ALIGNMENT_RIGHT},
	]


var game: BfhGame = null

## Whose row is highlighted. Asked every time, because on a connected client the local
## player arrives in a JOIN frames after this exists.
var _own: Callable = Callable()

## Tab is down.
var held: bool = false

## Between a round's end and the next one's start, when it is up without being asked.
var after_round: bool = false

## The last round's winner, a `BfhGame.TEAM_*` or 0, for the line under the tables.
var last_winner: int = 0

var root: Control = null
var panel: PanelContainer = null
var drivers_table: DotTableView = null
var runners_table: DotTableView = null
var drivers_header: Label = null
var runners_header: Label = null
var footer: Label = null

var _drawn_signature: String = ""


func bind(p_game: BfhGame, own: Callable = Callable()) -> void:
	game = p_game
	_own = own
	layer = LAYER
	_build()
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


func _process(_delta: float) -> void:
	if shown():
		refresh()


## Brings what is drawn up to date, and only rebuilds the rows when they changed: a
## [DotTableView] rebuilds every Label on each `set_rows`, and this runs every frame it is up.
func refresh() -> void:
	if root == null:
		return

	root.visible = shown()

	if not root.visible or game == null:
		return

	var own := _own_id()
	var drivers := rows_for(game, BfhGame.TEAM_DRIVERS, own)
	var runners := rows_for(game, BfhGame.TEAM_RUNNERS, own)

	drivers_header.text = header_line(game, BfhGame.TEAM_DRIVERS)
	runners_header.text = header_line(game, BfhGame.TEAM_RUNNERS)
	footer.text = footer_line(game, after_round, last_winner)

	var signature := str(drivers) + str(runners)
	if signature != _drawn_signature:
		_drawn_signature = signature
		drivers_table.set_rows(drivers)
		runners_table.set_rows(runners)


## One side's rows, as a [DotTableView] takes them. Static so a check reads the same rows.
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


func _build() -> void:
	if root != null:
		return

	# Full-rect under the CanvasLayer, for the reason [BfhHud] gives: a CanvasLayer lays
	# nothing out, and anchors on a child of one resolve against nothing.
	root = Control.new()
	root.name = "Scoreboard"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = DotUiTheme.dark().build()
	root.visible = false
	add_child(root)

	panel = PanelContainer.new()
	panel.name = "Panel"
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -PANEL_HALF.x
	panel.offset_right = PANEL_HALF.x
	panel.offset_top = -PANEL_HALF.y
	panel.offset_bottom = PANEL_HALF.y
	# Held during play, so it never takes the mouse from the game under it.
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	panel.add_child(column)

	var sides := HBoxContainer.new()
	sides.add_theme_constant_override("separation", 28)
	sides.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(sides)

	var left := _side(sides, BfhGame.TEAM_DRIVERS, DRIVER_ROWS, 2.0)
	drivers_header = left[0]
	drivers_table = left[1]

	var right := _side(sides, BfhGame.TEAM_RUNNERS, RUNNER_ROWS, 3.0)
	runners_header = right[0]
	runners_table = right[1]

	footer = Label.new()
	footer.name = "Footer"
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	footer.custom_minimum_size = Vector2(0.0, 26.0)
	column.add_child(footer)


## A side's header and table, in a column. Returns `[header, table]`.
func _side(
	parent: Control, team: int, rows: int, ratio: float
) -> Array:
	var side := VBoxContainer.new()
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side.size_flags_stretch_ratio = ratio
	parent.add_child(side)

	var header := Label.new()
	header.add_theme_font_size_override("font_size", 22)
	header.add_theme_color_override("font_color", side_colour(game, team))
	header.custom_minimum_size = Vector2(0.0, 36.0)
	side.add_child(header)

	var table := DotTableView.new()
	# The size is the point; see the class notes. Header row plus [param rows].
	table.custom_minimum_size = Vector2(0.0, ROW_PX * float(rows + 1))
	table.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	table.max_rows = rows
	table.highlight_colour = Color(1.0, 0.9, 0.5)
	side.add_child(table)
	table.set_columns(columns_for(team))

	return [header, table]


func describe() -> Dictionary:
	return {
		"shown": shown(),
		"held": held,
		"after_round": after_round,
		"drivers": drivers_table.row_count() if drivers_table != null else 0,
		"runners": runners_table.row_count() if runners_table != null else 0,
	}
