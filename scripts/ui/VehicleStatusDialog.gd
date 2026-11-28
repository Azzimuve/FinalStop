extends AcceptDialog

const VehicleState = preload("res://scripts/simulation/VehicleState.gd")
const VehiclePartsView = preload("res://scripts/ui/VehiclePartsView.gd")

signal repair_requested(part_id: String)

var vehicle: VehicleState
var repairs_allowed: bool = false
var credits: float = 0.0
var selected_repair_part_id: String = ""
@onready var vehicle_parts_view: VehiclePartsView = $Content/Diagram/PartsView
@onready var repair_details: VBoxContainer = $Content/RepairDetails
@onready var repair_details_label: Label = $Content/RepairDetails/Description
@onready var selected_repair_button: Button = $Content/RepairDetails/Repair


func _ready() -> void:
	vehicle_parts_view.slot_clicked.connect(_on_repair_slot_clicked)
	selected_repair_button.pressed.connect(_request_repair)


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
