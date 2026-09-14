extends DotNetInput

const BfhNetCommand := preload("bfh_net_command.gd")

## One tick of a player's intent, on the wire: a [DotFpsCommand] and nothing else.
##
## [b]The same command drives a runner and a bus, and that is this game's design rather
## than a saving.[/b] A driver's forward key is the throttle and their strafe keys are
## the wheel — nobody has to learn a second set of controls for the half of the game they
## play every third round — so there is one thing to send either way and the server
## decides which of the two it means. A client that sent "throttle" would be telling the
## server it was in a bus.
##
## The hammer rides in [member DotFpsCommand.buttons] for the same reason a jump does: it
## is per-tick, it is held rather than pressed once, and it has to be ordered against the
## movement it was aimed with. Sending it as a request would put every swing a round trip
## behind the mouse and reorder it against the step the player took while swinging.

## The hammer. `BUTTON_USER_0`, which is what dot-player-controller reserves for a game.
const BUTTON_SWING := DotFpsCommand.BUTTON_USER_0

var move: DotFpsCommand = DotFpsCommand.new()


func _write(writer: DotNetWriter) -> void:
	move.write(writer)


func _read(reader: DotNetReader) -> void:
	move = DotFpsCommand.new()
	move.read(reader)


## Not optional. Quantisation bounds each field; it cannot bound the relationship between
## them, and a move vector of (1, 1) is 41% more speed than anybody else.
func _sanitise() -> void:
	move.sanitise()


func _equals(other: DotNetInput) -> bool:
	var them := other as BfhNetCommand
	return them != null and move.equals(them.move)
