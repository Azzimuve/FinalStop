extends Node

@export var road_id := "Highway1"
@export var event_id := "abandoned_car"

@onready var game := $Game
@onready var test_hud: Control = $TestHUD
@onready var actions: VBoxContainer = $TestHUD/Actions


func _ready() -> void:
	game.prologue.step = game.prologue.Step.FREE
	game.prologue._refresh()
	game.prologue._close_radio()
	game.prologue.set_process(false)

	var layers = game.modal_layers
	layers.hud.hide()
	test_hud.reparent(layers.hud.get_parent(), false)
	layers.hud = test_hud
	game.radio_bulletin.reparent(test_hud, false)
	game.travel_button.reparent(actions, false)
	actions.get_node("Repeat").pressed.connect(func(): get_tree().reload_current_scene())
	game.map_view._cancel_camera_transition()
	game.map_view._show_world_view()

	var reports = game.road_bulletins
	for road in reports.roads:
		if road.id != road_id:
			continue
		for event in reports.events:
			if event.id == event_id:
				reports.roads.assign([road])
				reports.events.assign([event])
				reports.chance_percent = 100
				reports.next_check = game.clock.total_minutes
				reports.update_at(game.clock.total_minutes)
				reports.chance_percent = 0
				game.travel_events.events.clear()
				game.map_view.camera.position = game.map_view.incident_marker.position
				return
	actions.get_node("Hint").text = "Проверьте Road ID и Event ID в инспекторе тестовой сцены."
