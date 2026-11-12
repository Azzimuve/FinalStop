extends RefCounted

const MINUTES_PER_DAY: float = 1440.0
const GAME_MINUTES_PER_REAL_SECOND: float = 3.0

var total_minutes: float = 8.0 * 60.0


func advance(minutes: float) -> void:
	if minutes > 0.0:
		total_minutes += minutes


func time_text() -> String:
	var minute_of_day := floori(fposmod(total_minutes, MINUTES_PER_DAY))
	return "%02d:%02d" % [minute_of_day / 60, minute_of_day % 60]


func format_deadline(deadline_total_minutes: float) -> String:
	var minute_of_day := floori(fposmod(deadline_total_minutes, MINUTES_PER_DAY))
	var hours := minute_of_day / 60
	var minutes := minute_of_day % 60
	var deadline_day := floori(deadline_total_minutes / MINUTES_PER_DAY)
	var current_day := floori(total_minutes / MINUTES_PER_DAY)
	var day_offset := deadline_day - current_day
	var suffix := ""
	if day_offset == 1:
		suffix = " (+1 день)"
	elif day_offset > 1:
		suffix = " (+%d дн.)" % day_offset
	return "%02d:%02d%s" % [hours, minutes, suffix]
