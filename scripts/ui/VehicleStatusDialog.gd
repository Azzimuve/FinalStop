extends AcceptDialog

const VehicleState = preload("res://scripts/simulation/VehicleState.gd")
const VehiclePartsView = preload("res://scripts/ui/VehiclePartsView.gd")

signal repair_requested(part_id: String)

var vehicle: VehicleState
var repairs_allowed: bool = false
var credits: float = 0.0
var selected_repair_part_id: String = ""
var vehicle_parts_view: VehiclePartsView
var repair_details: VBoxContainer
var repair_details_label: Label
var selected_repair_button: Button


func _ready() -> void:
	vehicle_parts_view = VehiclePartsView.new()
	var status_content := VBoxContainer.new()
	add_child(status_content)
	status_content.add_child(vehicle_parts_view)
	vehicle_parts_view.selectable = true
	vehicle_parts_view.slot_clicked.connect(_on_repair_slot_clicked)
	repair_details = VBoxContainer.new()
	status_content.add_child(repair_details)
	repair_details_label = Label.new()
	repair_details_label.custom_minimum_size.x = 280.0
	repair_details_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	repair_details.add_child(repair_details_label)
	selected_repair_button = Button.new()
	selected_repair_button.text = "Ремонт"
	selected_repair_button.pressed.connect(_request_repair)
	repair_details.add_child(selected_repair_button)
	repair_details.hide()


func open(model: VehicleState, money: float, allow_repairs: bool) -> void:
	vehicle = model
	repairs_allowed = allow_repairs
	selected_repair_part_id = ""
	refresh(money)
	popup_centered()


func _on_repair_slot_clicked(part_id: String) -> void:
	if not repairs_allowed:
		return
	selected_repair_part_id = part_id
	refresh(credits)


func _request_repair() -> void:
	if repairs_allowed and not selected_repair_button.disabled:
		repair_requested.emit(selected_repair_part_id)


func refresh(money: float) -> void:
	credits = money
	var at_workshop := repairs_allowed
	vehicle_parts_view.selectable = at_workshop
	vehicle_parts_view.mouse_filter = Control.MOUSE_FILTER_STOP if at_workshop else Control.MOUSE_FILTER_IGNORE
	var part := vehicle.get_part(selected_repair_part_id)
	vehicle_parts_view.selected = part if at_workshop else null
	vehicle_parts_view.show_vehicle(vehicle)
	repair_details.visible = at_workshop and part != null
	if not repair_details.visible:
		return
	var cost := vehicle.repair_cost(selected_repair_part_id)
	repair_details_label.text = "%s: %.1f%%\nРемонт: %.2f кр., %.2f мин.%s" % [
		VehicleState.PART_NAMES[selected_repair_part_id], part.condition_percent, cost,
		vehicle.repair_time_minutes(selected_repair_part_id),
		"\nНужно обслуживание" if part.condition_percent <= vehicle.settings.vehicle_service_condition_percent else "",
	]
	selected_repair_button.disabled = part.condition_percent >= 100.0 or credits < cost
