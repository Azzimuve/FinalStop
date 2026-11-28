@tool
extends Control

@onready var diagram: Control = $Diagram

func _ready() -> void:
	resized.connect(_fit_diagram)
	_fit_diagram()

func _fit_diagram() -> void:
	var factor := minf(size.x / diagram.size.x, size.y / diagram.size.y)
	diagram.scale = Vector2.ONE * factor
	diagram.position = ((size - diagram.size * factor) * 0.5).round()
