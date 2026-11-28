@tool
extends Control

# Каждая цифра вращается в своём окне. Старшие разряды сдвигаются при переносе.
@export var numeral_font: Font
@export var numeral_size := 46
@export var ink := Color("#393723")
var reading := 0.0
var rolling := false

func display(amount: float, moving: bool) -> void:
	reading = maxf(amount, 0.0)
	rolling = moving
	queue_redraw()

func _draw() -> void:
	if numeral_font == null:
		return
	var hundredths := reading * 100.0
	if not rolling:
		hundredths = roundf(hundredths)
	if hundredths >= 100000.0:
		# Крупная сумма при изменённом в инспекторе тарифе должна помещаться целиком.
		draw_rect(Rect2(Vector2.ZERO, size), Color("#efd7a5"))
		draw_string(numeral_font, Vector2(0, size.y * 0.83), String.num(reading, 2).replace(".", ","), HORIZONTAL_ALIGNMENT_CENTER, size.x, numeral_size - 8, ink)
		return
	var centers := [19.0, 56.0, 94.0, 138.0, 174.0]
	var place := 10000
	var baseline := (size.y + numeral_font.get_ascent(numeral_size) - numeral_font.get_descent(numeral_size)) * 0.5
	for center: float in centers:
		var digit := floori(hundredths / place) % 10
		var travel := clampf(fmod(hundredths, place) - place + 1.0, 0.0, 1.0) if rolling else 0.0
		var origin := Vector2(center - 18.0, baseline - travel * size.y)
		draw_string(numeral_font, origin, str(digit), HORIZONTAL_ALIGNMENT_CENTER, 36, numeral_size, ink)
		if travel > 0.0:
			draw_string(numeral_font, origin + Vector2(0, size.y), str((digit + 1) % 10), HORIZONTAL_ALIGNMENT_CENTER, 36, numeral_size, ink)
		place = floori(place / 10.0)
