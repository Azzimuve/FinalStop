extends Control

signal action_selected(index: int)
signal continue_requested

var heading: Label
var description: Label
var actions: VBoxContainer
var continue_button: Button


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var panel := PanelContainer.new()
	add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.offset_left = -230.0
	panel.offset_right = 230.0
	panel.offset_top = -145.0
	panel.offset_bottom = 145.0
	var layout := VBoxContainer.new()
	panel.add_child(layout)
	heading = Label.new()
	heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layout.add_child(heading)
	description = Label.new()
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(description)
	actions = VBoxContainer.new()
	layout.add_child(actions)
	continue_button = Button.new()
	continue_button.text = "Продолжить путь"
	continue_button.pressed.connect(func(): continue_requested.emit())
	layout.add_child(continue_button)
	hide()


func open(event: Dictionary, available: Array[bool]) -> void:
	heading.text = event.title
	description.text = event.description
	for child in actions.get_children():
		actions.remove_child(child)
		child.queue_free()
	for index in range(event.actions.size()):
		var button := Button.new()
		button.text = event.actions[index].text
		button.disabled = not available[index]
		button.pressed.connect(func(): action_selected.emit(index))
		actions.add_child(button)
	actions.show()
	continue_button.hide()
	show()


func show_result(text: String) -> void:
	description.text = text
	actions.hide()
	continue_button.show()
