extends RefCounted

const MAX_VALUE: float = 100.0
const MIN_VALUE: float = 0.0
const HIDDEN_EXHAUSTION_LIMIT: float = -10.0
const LOSS_PER_GAME_HOUR: float = 100.0 / 14.0

var value: float = MAX_VALUE

func advance(minutes: float) -> bool:
	if minutes <= 0.0:
		return false
	value = maxf(HIDDEN_EXHAUSTION_LIMIT, value - minutes / 60.0 * LOSS_PER_GAME_HOUR)
	return value <= HIDDEN_EXHAUSTION_LIMIT

func restore(amount: float) -> void:
	value = minf(MAX_VALUE, value + maxf(0.0, amount))

func speed_multiplier() -> float:
	if value <= 0.0:
		return 0.1
	if value < 20.0:
		return 0.6
	if value < 40.0:
		return 0.9
	return 1.0

func display_value() -> float:
	return maxf(0.0, value)
