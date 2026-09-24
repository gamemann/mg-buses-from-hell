extends CanvasLayer

const BfhGame := preload("bfh_game.gd")
const BfhPlayer := preload("bfh_player.gd")

## Health, the clock, and how much cover is left. Four numbers and a crosshair.
##
## [b]How much cover is left is the one number that is not obvious, and it is the most
## important of the four.[/b] Health tells a runner how many mistakes they have left
## and the clock tells them how long they have to survive; neither tells them whether
## surviving is still possible. The crate count does: a bowl down to its last few
## blocks is a bowl where standing still stops working, and a player who can see that
## number drop starts moving before it is too late rather than after.

# No `const CHANNEL`. This draws four numbers from state somebody else owns and has
# nothing an operator would act on; the round, the deaths and the bowl are logged by
# [BfhGame], which is where the decisions are. A channel declared and never used is a file
# that meant to say something and does not.

var game: BfhGame = null
var player: BfhPlayer = null

var _clock: Label = null
var _health: Label = null
var _cover: Label = null
var _status: Label = null
var _crosshair: Control = null
var _root: Control = null

## An administrator's `blind`, over the world and under the four numbers.
##
## [b]Under the numbers, on purpose.[/b] A blind takes the bowl away, not the player's
## bearings: the clock, their health and the cover count still say that the round is going
## on and that they are in it, which is what makes it read as "an admin did this" rather
## than as a client that stopped drawing. The chat box is its own layer above this one.
##
## Black rather than white. A white screen at full brightness is a thing a player can be
## hurt by in a dark room, and taking the picture away is the whole of the point.
var blind_overlay: ColorRect = null

## Seconds a blind takes to come down and to lift. Short, so it is unmistakably on, and
## not instant, so it reads as something done to the screen rather than a frame dropped.
const BLIND_FADE_SEC := 0.25

const BLIND_COLOUR := Color(0.01, 0.01, 0.015)


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

	# First, so every label added below draws over it. See [member blind_overlay].
	blind_overlay = ColorRect.new()
	blind_overlay.name = "Blind"
	blind_overlay.color = BLIND_COLOUR
	blind_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	blind_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	blind_overlay.modulate.a = 0.0
	blind_overlay.visible = false
	_root.add_child(blind_overlay)

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


func _process(delta: float) -> void:
	present_blind(delta)

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


## Fades [member blind_overlay] toward whether this HUD's player is blinded.
##
## Read off [member player] rather than pushed by anybody, because the flag arrives in a
## snapshot on a connected client and is set directly offline, and a HUD that had to be
## told would need telling from two places. Public so a check can step it.
##
## [b]Sized to the viewport every frame it shows, not trusted to its anchors.[/b] The root
## it sits in is full-rect under a [CanvasLayer], which today IS the viewport — but a blind
## that left a strip of the bowl showing would be a blind a player can still play through,
## and one line here costs less than finding that out from a picture.
func present_blind(delta: float) -> void:
	if blind_overlay == null:
		return

	var want := 1.0 if player != null and player.blinded else 0.0
	blind_overlay.modulate.a = move_toward(
		blind_overlay.modulate.a, want, maxf(delta, 0.0) / BLIND_FADE_SEC
	)
	blind_overlay.visible = blind_overlay.modulate.a > 0.0

	if blind_overlay.visible and blind_overlay.is_inside_tree():
		var inverse := blind_overlay.get_parent_control().get_global_transform().affine_inverse()
		blind_overlay.position = inverse * Vector2.ZERO
		blind_overlay.size = inverse.basis_xform(blind_overlay.get_viewport_rect().size)


## The rectangle the blind covers, in viewport pixels. For a check.
func blind_rect() -> Rect2:
	if blind_overlay == null:
		return Rect2()

	return blind_overlay.get_global_rect()


func _status_line() -> String:
	# First, because a black screen with no reason on it reads as the client broken. The
	# line is drawn over the blind; see [member blind_overlay].
	if player != null and player.blinded:
		return "blinded by an admin"
	if not game.sides_are_playable():
		return "waiting for both sides"
	if player != null and player.riding:
		return "driving"
	if player != null and player.health != null and not player.health.alive:
		return "down — next round"
	return ""
