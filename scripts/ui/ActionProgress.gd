extends CenterContainer

@onready var heading: Label = %Heading
@onready var duration: Label = %Duration
@onready var bar: ProgressBar = %Progress


func run(action_name: String, minutes: float, covered_window: Window = null) -> bool:
	if visible:
		return false
	if minutes <= 0.0:
		return true

	heading.text = action_name
	duration.text = "%s мин" % String.num(minutes, 2).replace(".", ",")
	if fmod(minutes, 60.0) == 0.0:
		duration.text = "%d ч" % int(minutes / 60.0)
	bar.value = 0.0
	show()
	if covered_window != null:
		covered_window.hide()

	# Самое долгое действие — сон на 12 часов.
	var seconds := lerpf(1.0, 5.0, clampf(minutes / (12.0 * 60.0), 0.0, 1.0))
	var tween := create_tween()
	tween.tween_property(bar, "value", bar.max_value, seconds)
	await tween.finished

	if covered_window != null:
		covered_window.show()
	hide()
	return true


func _input(_event: InputEvent) -> void:
	if visible:
		get_viewport().set_input_as_handled()
