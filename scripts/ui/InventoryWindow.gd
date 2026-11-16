extends Panel

const VehicleInventory = preload("res://scripts/simulation/VehicleInventory.gd")
const CargoItem = preload("res://scripts/simulation/CargoItem.gd")
const InventoryInteraction = preload("res://scripts/ui/InventoryInteraction.gd")

signal closed
signal discarded(item: CargoItem)
signal used(item: CargoItem)

var interaction: InventoryInteraction
var warehouse := VehicleInventory.new(Vector2i(16, 24))
var pickup_cargo: Array[CargoItem] = []
var auto_button: Button
var close_button: Button
var loading: bool = false


func _ready() -> void:
	hide()
	interaction = InventoryInteraction.new()
	add_child(interaction)
	interaction.transfer_check = _check_pickup_transfer
	interaction.discarded.connect(func(item: CargoItem): discarded.emit(item))
	interaction.used.connect(func(item: CargoItem): used.emit(item))
	auto_button = Button.new()
	auto_button.text = "Взять всё"
	auto_button.position = Vector2(12, 600)
	auto_button.pressed.connect(_take_all)
	add_child(auto_button)
	close_button = Button.new()
	close_button.text = "Закрыть"
	close_button.pressed.connect(_close)
	add_child(close_button)


func open(model: VehicleInventory, order_cargo: Array[CargoItem], allow_loading: bool, capacity_kg: float) -> void:
	loading = allow_loading
	pickup_cargo = order_cargo.duplicate()
	warehouse = VehicleInventory.new(Vector2i(16, 24))
	if loading:
		for item in pickup_cargo:
			if not model.contains(item):
				warehouse.auto_load([item])
	size = Vector2(1200 if loading else 600, 640)
	close_button.position = Vector2(size.x - 100, size.y - 40)
	auto_button.visible = loading
	interaction.cargo_capacity_kg = capacity_kg
	interaction.configure(model, warehouse if loading else null, "Инвентарь склада · 16×24")
	position = (get_viewport_rect().size - size) / 2.0
	show()


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
