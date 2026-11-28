extends Button

@export_range(1, 60, 1, "suffix:с") var display_seconds := 10.0
@export_range(0.05, 1.0, 0.05, "suffix:с") var slide_seconds := 0.3
@export var compact_size := Vector2(192, 36)

@onready var close_button: Button = $Close
@onready var expanded_size := size
@onready var shown_top := offset_top
var animation: Tween
var message := ""
var collapsed := false
var compact_title := "Сводка по рации"


func _ready() -> void:
	pressed.connect(_toggle)
	close_button.pressed.connect(hide)
	visibility_changed.connect(_on_visibility_changed)


func announce(new_message: String) -> void:
	message = new_message
	compact_title = "Сводка по рации"
	_expand()


func finish_report() -> void:
	if visible:
		compact_title = "Прошлая сводка"
		message += "\nСводка завершена."
		text = compact_title if collapsed else message


func _toggle() -> void:
	if collapsed:
		_expand()
	else:
		_collapse()


func _expand() -> void:
	if animation:
		animation.kill()
	collapsed = false
	close_button.hide()
	alignment = HORIZONTAL_ALIGNMENT_CENTER
	text = message
	offset_left = -expanded_size.x * 0.5
	offset_right = expanded_size.x * 0.5
	offset_top = shown_top
	offset_bottom = shown_top + expanded_size.y
	show()
	position.y = -size.y
	modulate.a = 0.0
	animation = create_tween()
	animation.tween_property(self, "position:y", shown_top, slide_seconds).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	animation.parallel().tween_property(self, "modulate:a", 1.0, slide_seconds)
	animation.tween_interval(maxf(0.0, display_seconds - slide_seconds))
	animation.tween_callback(_collapse)
	if not is_visible_in_tree():
		animation.pause()


func _collapse() -> void:
	if animation:
		animation.kill()
	collapsed = true
	text = compact_title
	alignment = HORIZONTAL_ALIGNMENT_LEFT
	close_button.show()
	animation = create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	animation.tween_property(self, "offset_left", -compact_size.x * 0.5, slide_seconds)
	animation.tween_property(self, "offset_right", compact_size.x * 0.5, slide_seconds)
	animation.tween_property(self, "offset_top", shown_top, slide_seconds)
	animation.tween_property(self, "offset_bottom", shown_top + compact_size.y, slide_seconds)
	animation.tween_property(self, "modulate:a", 1.0, slide_seconds)


func _on_visibility_changed() -> void:
	if not animation or not animation.is_valid():
		return
	if not visible:
		animation.kill()
	elif is_visible_in_tree():
		animation.play()
	else:
		animation.pause()
