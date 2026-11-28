extends Panel

const VehicleInventory = preload("res://scripts/simulation/VehicleInventory.gd")
const VehicleState = preload("res://scripts/simulation/VehicleState.gd")
const CargoItem = preload("res://scripts/simulation/CargoItem.gd")
const InventoryInteraction = preload("res://scripts/ui/InventoryInteraction.gd")

signal closed
signal discarded(item: CargoItem)
signal used(item: CargoItem)

@onready var interaction: InventoryInteraction = $Interaction
var warehouse := VehicleInventory.new(Vector2i(16, 24))
var pickup_cargo: Array[CargoItem] = []
@onready var auto_button: Button = $TakeAll
@onready var close_button: Button = $Close
var loading: bool = false


func _ready() -> void:
	resized.connect(_fit_interaction)
	interaction.transfer_check = _check_pickup_transfer
	interaction.discarded.connect(func(item: CargoItem): discarded.emit(item))
	interaction.used.connect(func(item: CargoItem): used.emit(item))
	auto_button.pressed.connect(_take_all)
	close_button.pressed.connect(_close)


func open(vehicle: VehicleState, order_cargo: Array[CargoItem], allow_loading: bool, capacity_kg: float) -> void:
	var model := vehicle.inventory
	interaction.character_slots.show_vehicle(vehicle)
	loading = allow_loading
	pickup_cargo = order_cargo.duplicate()
	warehouse = VehicleInventory.new(Vector2i(16, 24))
	if loading:
		for item in pickup_cargo:
			if not model.contains(item):
				warehouse.auto_load([item])
	auto_button.visible = loading
	interaction.cargo_capacity_kg = capacity_kg
	interaction.configure(model, warehouse if loading else null, "Инвентарь склада · 16×24")
	_fit_interaction()
	show()


func _fit_interaction() -> void:
	if not is_node_ready():
		return
	var width := interaction.custom_minimum_size.x
	interaction.size = Vector2(width, size.y - 62.0)
	interaction.position = Vector2(roundf((size.x - width) * 0.5), 6.0)


func _check_pickup_transfer(item: CargoItem, from_warehouse: bool) -> String:
	if not from_warehouse and not pickup_cargo.has(item):
		return "На склад можно вернуть только груз текущего заказа."
	return ""


func _take_all() -> void:
	interaction.reset_selection()
	# Копия нужна, потому что успешный перенос изменяет склад.
	for placement in warehouse.placements.duplicate():
		interaction.auto_transfer(placement.item, true)


func _close() -> void:
	interaction.reset_selection()
	hide()
	closed.emit()


func _input(event: InputEvent) -> void:
	if visible:
		interaction.handle_input(event)
