extends Node

const BfhNetBridge := preload("net/bfh_net_bridge.gd")
const BfhServices := preload("bfh_services.gd")

## The client's half of chat and voice: a box to type in and a key to talk with.
##
## [b]Everything here draws or captures, and nothing here decides.[/b] What a line may
## contain, who may hear it, whether somebody is gagged and whether they are talking too
## fast are all the server's, and this client's local copy of the rules exists only so a
## message that is going to be refused can be refused without a round trip. The server's
## answer is the one that counts, and when the two disagree the server wins — which is the
## right way round for a disagreement to fail.
##
## [b]The one thing it does decide is that typing is not moving.[/b] A chat box open over a
## first-person game whose keys are still driving the player is a player who walks into a
## bus while saying so, and every game in this family has had to learn it separately.

const CHANNEL := "bfh.chat"

## Push to talk. Bound to V, which is where twenty years of this genre put it.
const TALK_ACTION := &"bfh_voice_talk"
const TALK_KEY := KEY_V

const OPEN_ACTION := &"bfh_chat"
const TEAM_ACTION := &"bfh_chat_team"


## Whether the box has the keyboard. The client stops sampling movement while it does.
signal typing_changed(typing: bool)


var bridge: BfhNetBridge = null

var chat: DotChatClient = null
var window: DotChatWindow = null
var voice: DotVoiceManager = null

var _layer: CanvasLayer = null
var _talking: bool = false


## Builds the box, the client and the microphone over an attached bridge.
##
## [param p_bridge] may be null, which is the offline case: the box is still drawn and
## still echoes what the local player types, because a chat box that does nothing at all
## reads as broken rather than as absent.
func attach(p_bridge: BfhNetBridge) -> DotResult:
	bridge = p_bridge

	_build_window()
	_build_chat()

	var heard := _build_voice()
	DotLog.result(CHANNEL, "voice", heard)

	if bridge != null:
		bridge.chat_received.connect(_on_chat_received)
		bridge.voice_arrived.connect(_on_voice_arrived)

	return DotResult.success(self)


func _build_window() -> void:
	_layer = CanvasLayer.new()
	_layer.name = "ChatLayer"
	# Above the HUD, which is layer 0: a line drawn under the clock is a line nobody reads.
	_layer.layer = 100
	add_child(_layer)

	window = DotChatWindow.new()
	window.name = "ChatWindow"
	window.open_action = OPEN_ACTION
	window.team_action = TEAM_ACTION
	window.default_open_binding = "Y"
	window.default_team_binding = "U"
	# Clear of the health number, which `BfhHud` puts 86 pixels off the bottom left.
	window.margin_left = 30.0
	window.margin_bottom = 120.0
	window.max_length = 140
	# [b]An outline, because this map is pale sand in bright light.[/b] Three lines in three
	# colours over that floor are three lines nobody can read — measured in a screenshot,
	# with every property of every line correct. `BfhHud` had already reached the same
	# answer for its own labels; dot-ui's feed grew the option so both can say it once.
	window.outline_size = 5
	window.channels = [
		{"id": BfhServices.CH_ALL, "label": "Say", "colour": Color(0.88, 0.90, 0.94)},
		{
			"id": BfhServices.CH_TEAM,
			"label": "Say (TEAM)",
			"colour": Color(0.55, 0.82, 0.95),
			"team": true,
		},
	]
	_layer.add_child(window)

	window.submitted.connect(_on_submitted)
	window.opened.connect(func(_channel: StringName) -> void: typing_changed.emit(true))
	window.closed.connect(func() -> void: typing_changed.emit(false))


func _build_chat() -> void:
	chat = DotChatClient.new()
	chat.name = "ChatClient"
	# The statics, not `BfhServices.new()`: see [method BfhServices.chat_rules]. A client
	# that built a services layer to read its rules would build a moderation store and a
	# router with it — and would not compile at all inside a delivered pack.
	chat.rules = BfhServices.chat_rules()
	chat.channels = BfhServices.chat_channels()
	chat.history_limit = 200
	chat.send_fn = func(text: String, channel_id: StringName) -> void:
		if bridge != null:
			bridge.ask_say(channel_id, text)
	add_child(chat)

	chat.message_received.connect(_on_message)


## The microphone, which is allowed to be absent.
##
## [b]A machine with no input device is the normal case on a server and a common one on a
## desktop, and it must not be an error.[/b] `DotVoiceManager` reports it, listening still
## works, and what a player gets is a game where they can hear everybody and say nothing —
## which is exactly what somebody with no microphone should get.
func _build_voice() -> DotResult:
	# Typed explicitly rather than inferred. Inside a mounted pack a script whose base
	# class lives in the HOST build cannot hand its return type to a script in the mount,
	# and `:=` here is a client scene that fails to compile on a real server and works
	# perfectly in the project it was written in.
	var config: DotVoiceConfig = BfhServices.voice_format()
	# [b]The CLIENT captures, so the client's copy turns capture on.[/b] The same object on
	# the server has it off: a dedicated server with a microphone open is a dedicated
	# server sending its own room to everybody.
	config.capture_enabled = true

	voice = DotVoiceManager.new()
	voice.name = "Voice"
	voice.config = config
	# Empty, for the reason every netcode config here says: a stale `user://dot_voice.json`
	# is a client talking in a format the server refuses, counted and said to nobody.
	voice.config_file = ""
	voice.send_fn = func(payload: PackedByteArray) -> void:
		if bridge != null:
			bridge.send_voice(payload)

	add_child(voice)
	_register_talk_action()

	return DotResult.success(voice)


## Binds V, unless the player has already bound it to something.
##
## The same rule dot-ui's chat window follows for Y and U: an action that already exists is
## an action somebody configured, and overwriting it is a game taking a key back off a
## player who chose it.
func _register_talk_action() -> void:
	if InputMap.has_action(TALK_ACTION):
		return

	InputMap.add_action(TALK_ACTION)

	var key := InputEventKey.new()
	key.physical_keycode = TALK_KEY
	InputMap.action_add_event(TALK_ACTION, key)


## Push to talk, polled rather than driven by events.
##
## [b]A key that is HELD is a state, and an event queue is sampled per frame.[/b] Reading
## the press and the release as events works until a frame drops one, and what that leaves
## is a microphone that stays open after the key is up — which is the one failure mode of
## voice chat that nobody forgives.
func _process(_delta: float) -> void:
	if voice == null or not InputMap.has_action(TALK_ACTION):
		return

	# Not while typing: V is a letter when the box is open.
	var wanted := Input.is_action_pressed(TALK_ACTION) and not (window != null and window.is_open())

	if wanted == _talking:
		return

	_talking = wanted
	voice.set_talking(wanted)


func _on_submitted(text: String, channel: StringName) -> void:
	if text.strip_edges() == "":
		return

	if bridge == null:
		# Offline: there is no server to decide anything, so the line goes straight to the
		# log. Saying nothing at all would read as a chat box that does not work.
		window.add_said("You", text, Color(0.62, 0.78, 1.0))
		return

	var composed := chat.compose(channel, text)

	if not composed.ok:
		# The local pre-check refused it. Shown, because a line that silently does not
		# appear is a client that looks broken.
		window.add_text(composed.error.message, Color(0.95, 0.55, 0.45))


func _on_chat_received(wire: Dictionary) -> void:
	if chat != null:
		chat.receive(wire)


func _on_message(message: DotChatMessage, _channel_id: StringName) -> void:
	if window == null or message == null:
		return

	var colour := Color(0.88, 0.90, 0.94)

	if chat != null:
		var channel := chat.channel(message.channel)

		if channel != null:
			colour = channel.colour

	if message.sender_name == "":
		window.add_text(message.text, colour)
		return

	window.add_said(message.sender_name, message.text, colour)


## Something the server said to this player alone: a refusal, a rate limit, the reply to a
## `!command`.
##
## [b]Drawn in the chat log, because that is where the player was looking.[/b] A notice
## that arrives and is not drawn is the server explaining itself to nobody — which is
## exactly what "I pressed Enter and nothing happened" is, and it is the commonest thing a
## chat server ever has to say.
func notice(text: String) -> void:
	if window != null and text.strip_edges() != "":
		window.add_text(text, Color(0.98, 0.72, 0.35))


func _on_voice_arrived(payload: PackedByteArray) -> void:
	if voice != null:
		voice.receive(payload)


func is_typing() -> bool:
	return window != null and window.is_open()


func describe() -> Dictionary:
	return {
		"typing": is_typing(),
		"talking": _talking,
		"voice": voice.describe() if voice != null else {},
		"lines": chat.all_lines().size() if chat != null else 0,
	}
