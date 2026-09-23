extends DotFpsMotor

## The one line dot-player-controller is missing, so the ramp can be checked without it.
##
## [b]A stand-in, used by `headless_run` and by nothing a player runs.[/b]
## `DotFpsMotor._categorise_ground` opens with "moving upward faster than 0.1 m/s is not
## on the ground". Walking up this game's 18-degree ramp at 6.5 m/s is 2.0 m/s upward
## ALONG the surface, so every step up any walkable slope reads as a jump: the runner is
## put in AIR on the first tick of the ramp, rises a little, and stalls against the slope
## with nowhere to go. Measured on the built ramp: the stock motor stops 0.8 m up it, and
## this one walks to the deck.
##
## What this does instead is ask whether the player is moving AWAY from the surface they
## were standing on — velocity along the ground normal — which is the same test on flat
## ground and the right one on a slope. It belongs in the addon, and is written down for
## for that addon; it is here so that the ramp's own geometry has a check
## today rather than one that waits for that.
##
## Swapped in per player, after spawn, by the suite: see `_fit_slope_motor` there.


func _init(p_tunables: DotFpsTunables, p_body: DotFpsBody) -> void:
	super(p_tunables, p_body)


func _categorise_ground(state: DotFpsState) -> void:
	if (
		state.mode == DotFpsState.Mode.GROUND
		and state.velocity.y > 0.1
		and state.velocity.dot(state.ground_normal) <= 0.1
	):
		var moving := state.velocity
		state.velocity.y = 0.0
		super._categorise_ground(state)
		state.velocity = moving
		return

	super._categorise_ground(state)
