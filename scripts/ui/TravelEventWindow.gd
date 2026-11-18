extends Control

const ACTION_SCENE = preload("res://scenes/ui/EventAction.tscn")

signal action_selected(index: int)
signal continue_requested

@onready var heading: Label = $Panel/Layout/Heading
@onready var description: Label = $Panel/Layout/Description
@onready var actions: VBoxContainer = $Panel/Layout/Actions
@onready var continue_button: Button = $Panel/Layout/Continue


func _ready() -> void:
	continue_button.pressed.connect(func(): continue_requested.emit())


func open(event: Dictionary, available: Array[bool]) -> void:
	heading.text = event.title
	description.text = event.description
	for child in actions.get_children():
		actions.remove_child(child)
		child.queue_free()
	for index in range(event.actions.size()):
		var button := ACTION_SCENE.instantiate() as Button
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
