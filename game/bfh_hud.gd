class_name BfhHud
extends CanvasLayer

## Health, the clock, and how much cover is left. Four numbers and a crosshair.
##
## [b]How much cover is left is the one number that is not obvious, and it is the most
## important of the four.[/b] Health tells a runner how many mistakes they have left
## and the clock tells them how long they have to survive; neither tells them whether
## surviving is still possible. The crate count does: a bowl down to its last few
## blocks is a bowl where standing still stops working, and a player who can see that
## number drop starts moving before it is too late rather than after.

const CHANNEL := "bfh.hud"

var game: BfhGame = null
var player: BfhPlayer = null

var _clock: Label = null
var _health: Label = null
var _cover: Label = null
var _status: Label = null
var _crosshair: Control = null
var _root: Control = null


func bind(p_game: BfhGame, p_player: BfhPlayer) -> void:
	game = p_game
	player = p_player
	_build()


func _build() -> void:
	# [b]A full-rect Control between the CanvasLayer and the labels, and the first
	# render is why.[/b] A CanvasLayer is not a Control and does not lay its children
	# out, so anchors on a Label parented straight to one resolve against nothing:
	# every label landed in the top-left corner stacked on top of the others, and the
	# only one visible was the clock, clipped in half by the edge of the screen. It
	# reads as the HUD being half-written rather than as four labels in one place.
	_root = Control.new()
	_root.name = "Screen"
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	var font_size := 22

	_clock = _label(font_size + 12)
	_clock.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_clock.offset_top = 18.0
	_clock.offset_bottom = 70.0
	_clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	_status = _label(font_size)
	_status.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_status.offset_top = 74.0
	_status.offset_bottom = 110.0
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	_health = _label(font_size + 16)
	_health.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_health.offset_left = 30.0
	_health.offset_right = 260.0
	_health.offset_top = -86.0
	_health.offset_bottom = -26.0

	_cover = _label(font_size)
	_cover.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_cover.offset_left = -330.0
	_cover.offset_right = -30.0
	_cover.offset_top = -76.0
	_cover.offset_bottom = -30.0
	_cover.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	# A dot rather than a cross: the hammer has a reach of two metres and no spread,
	# so what a player needs is "the point I will hit", not a spread indicator.
	var dot := ColorRect.new()
	dot.name = "Crosshair"
	dot.color = Color(1.0, 1.0, 1.0, 0.75)
	dot.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	dot.offset_left = -3.0
	dot.offset_top = -3.0
	dot.offset_right = 3.0
	dot.offset_bottom = 3.0
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(dot)
	_crosshair = dot


func _label(size: int) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", Color(1, 1, 1))
	# An outline rather than a panel behind it. A HUD over a sand-coloured bowl in
	# bright light is unreadable in white and unreadable in black; an outline is
	# readable over both and costs nothing.
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	label.add_theme_constant_override("outline_size", 6)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(label)
	return label


func _process(_delta: float) -> void:
	if game == null or game.config == null:
		return

	var left := maxf(game.config.round_seconds - game.round_elapsed, 0.0)
	_clock.text = "%d:%02d" % [int(left) / 60, int(left) % 60]

	if player != null and player.health != null:
		_health.text = "%d" % int(round(player.health.health))
		# Red below a quarter, which is one bus bump from gone.
		var hurt := player.health.health <= player.health.max_health * 0.25
		_health.add_theme_color_override(
			"font_color", Color(1.0, 0.35, 0.3) if hurt else Color(1, 1, 1)
		)

	_cover.text = "%d cover   %d alive" % [game.crates_left(), game.alive_runners()]

	_status.text = _status_line()


func _status_line() -> String:
	if not game.sides_are_playable():
		return "waiting for both sides"
	if player != null and player.riding:
		return "driving"
	if player != null and player.health != null and not player.health.alive:
		return "down — next round"
	return ""
