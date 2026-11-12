extends Node2D

const InventoryWindow = preload("res://scripts/ui/InventoryWindow.gd")
const ModalLayers = preload("res://scripts/ui/ModalLayers.gd")
var modal_layers := ModalLayers.new()
const WorkshopTrade = preload("res://scripts/ui/WorkshopTrade.gd")
const WorkshopUpgrade = preload("res://scripts/ui/WorkshopUpgrade.gd")
var workshop_trade: WorkshopTrade
var store_trade: WorkshopTrade
var workshop_upgrade: WorkshopUpgrade
var trade_button: Button
var upgrade_button: Button
const VehiclePartsView = preload("res://scripts/ui/VehiclePartsView.gd")
var vehicle_parts_view: VehiclePartsView
var inventory_window: InventoryWindow
var inventory_button: Button

const VehicleState = preload("res://scripts/simulation/VehicleState.gd")
const TripPhase = preload("res://scripts/simulation/TripPhase.gd")
const OrderBoard = preload("res://scripts/ui/OrderBoard.gd")
const DeliveryOrder = preload("res://scripts/orders/DeliveryOrder.gd")
const OrderGenerator = preload("res://scripts/orders/OrderGenerator.gd")
const GameClock = preload("res://scripts/simulation/GameClock.gd")
const FatigueState = preload("res://scripts/simulation/FatigueState.gd")
const MapView = preload("res://scripts/Map.gd")
const WorldMapData = preload("res://scripts/WorldMapData.gd")
const BALANCE_SETTINGS = preload("res://resources/GameBalanceSettings.tres")


enum OrderState {
	AVAILABLE,
	ACCEPTED,
	READY_TO_PICK_UP,
	TRAVELLING,
	READY_TO_HAND_OVER,
}

@onready var map_view: MapView = $Map
@onready var order_panel: PanelContainer = $HUD/UI/OrderPanel
@onready var status_label: Label = $HUD/UI/OrderPanel/Content/StatusText
@onready var city_label: Label = $HUD/UI/OrderPanel/Content/CityText
@onready var accept_button: Button = $HUD/UI/OrderPanel/Content/AcceptButton
@onready var travel_button: Button = $HUD/UI/OrderPanel/Content/TravelButton
@onready var order_text: Label = $HUD/UI/OrderPanel/Content/OrderText
@onready var order_title: Label = $HUD/UI/OrderPanel/Content/Title
@onready var panel_toggle_button: Button = $HUD/UI/OrderPanel/Content/PanelToggleButton
@onready var trip_time_label: Label = $HUD/UI/OrderPanel/Content/TripTimeLabel
@onready var pause_button: Button = $HUD/UI/OrderPanel/Content/PauseButton
@onready var game_time_label: Label = $HUD/UI/GameTimeLabel
@onready var fuel_label: Label = $HUD/UI/FuelLabel
@onready var fatigue_label: Label = $HUD/UI/FatigueLabel
@onready var refuel_button: Button = $HUD/UI/OrderPanel/Content/RefuelButton
@onready var money_label: Label = $HUD/UI/MoneyLabel
@onready var vehicle_condition_label: Label = $HUD/UI/VehicleConditionLabel
@onready var repair_button: Button = $HUD/UI/OrderPanel/Content/RepairButton
@onready var view_orders_button: Button = $HUD/UI/OrderPanel/Content/ViewOrdersButton
@onready var order_board: OrderBoard = $HUD/UI/OrderBoardOverlay

# Модели игрового состояния.
var vehicle := VehicleState.new(BALANCE_SETTINGS)
var clock := GameClock.new()
var fatigue := FatigueState.new()
var current_city_id: String = WorldMapData.START_CITY_ID
var current_location_id: String = WorldMapData.START_LOCATION_ID
var current_city_name: String = ""
var money_credits: float = 0.0

# Заказы и состояние панели.
var order_generator := OrderGenerator.new(BALANCE_SETTINGS)
var current_order: DeliveryOrder
var order_state: OrderState = OrderState.AVAILABLE
var last_order_result: String = ""
var order_panel_collapsed: bool = false

# Выбранная цель и расчёт поездки до её начала.
var route_available: bool = false
var route_is_intercity: bool = false
var route_target_city_id: String = ""
var route_target_location_id: String = ""
var route_target_name: String = ""
var local_destination_place_id: String = ""
var local_destination_name: String = ""
var intercity_distance_units: float = 0.0
var intercity_duration_seconds: float = 1.0
var destination_city_duration_seconds: float = 0.0

# Активные участки поездки хранят собственные время, расстояние и прогресс.
var intercity_trip := TripPhase.new()
var local_trip := TripPhase.new()
var trip_elapsed_before_phase_seconds: float = 0.0
var travel_paused: bool = false
var sleep_button: Button
var sleep_dialog: AcceptDialog
var sleep_hours: SpinBox
var forced_sleep_in_progress: bool = false


@onready var garage_diagnosis_button: Button = $HUD/UI/GarageDiagnosisButton
@onready var vehicle_status_dialog: AcceptDialog = $HUD/UI/VehicleStatusDialog


func _can_diagnose_in_garage() -> bool:
	return (
		not _is_trip_active()
		and current_location_id == "company_garage"
	)


func _on_garage_diagnosis_pressed() -> void:
	if not _can_diagnose_in_garage() or vehicle_status_dialog.visible:
		return
	vehicle_parts_view.show_vehicle(vehicle)
	vehicle_status_dialog.popup_centered()


func _ready() -> void:
	workshop_trade = WorkshopTrade.new()
	$HUD/UI.add_child(workshop_trade)
	workshop_trade.credits_changed.connect(_on_trade_credits_changed)
	workshop_trade.discarded.connect(_on_cargo_discarded)
	workshop_trade.used.connect(_on_cigarettes_used)
	store_trade = WorkshopTrade.new()
	store_trade.is_store = true
	$HUD/UI.add_child(store_trade)
	store_trade.credits_changed.connect(_on_trade_credits_changed)
	store_trade.discarded.connect(_on_cargo_discarded)
	store_trade.used.connect(_on_cigarettes_used)
	workshop_upgrade = WorkshopUpgrade.new()
	$HUD/UI.add_child(workshop_upgrade)
	workshop_upgrade.accepted.connect(_on_upgrade_accepted)
	workshop_upgrade.credits_changed.connect(_on_trade_credits_changed)
	trade_button = Button.new()
	trade_button.text = "Торговать"
	trade_button.pressed.connect(_open_workshop_trade)
	$HUD/UI/OrderPanel/Content.add_child(trade_button)
	upgrade_button = Button.new()
	upgrade_button.text = "Улучшить — %.0f кр." % BALANCE_SETTINGS.workshop_upgrade_cost_credits
	upgrade_button.pressed.connect(_open_workshop_upgrade)
	$HUD/UI/OrderPanel/Content.add_child(upgrade_button)
	vehicle_parts_view = VehiclePartsView.new()
	vehicle_status_dialog.add_child(vehicle_parts_view)
	inventory_window = InventoryWindow.new()
	$HUD/UI.add_child(inventory_window)
	inventory_window.closed.connect(_on_inventory_closed)
	inventory_window.discarded.connect(_on_cargo_discarded)
	inventory_window.used.connect(_on_cigarettes_used)
	sleep_button = Button.new()
	sleep_button.text = "Спать"
	sleep_button.pressed.connect(_open_sleep_dialog)
	$HUD/UI/OrderPanel/Content.add_child(sleep_button)
	sleep_dialog = AcceptDialog.new()
	sleep_dialog.title = "Сон"
	sleep_dialog.dialog_text = "Сколько часов проспать?"
	sleep_dialog.ok_button_text = "Спать"
	sleep_hours = SpinBox.new()
	sleep_hours.min_value = 1.0
	sleep_hours.max_value = 12.0
	sleep_hours.step = 1.0
	sleep_hours.value = 1.0
	sleep_dialog.add_child(sleep_hours)
	sleep_dialog.confirmed.connect(_on_sleep_confirmed)
	$HUD/UI.add_child(sleep_dialog)
	inventory_button = Button.new()
	inventory_button.text = "Инвентарь машины"
	inventory_button.scale = order_panel.scale
	inventory_button.pressed.connect(_open_inventory)
	$HUD/UI.add_child(inventory_button)
	order_panel.resized.connect(_position_inventory_button)
	_position_inventory_button()
	garage_diagnosis_button.pressed.connect(_on_garage_diagnosis_pressed)
	accept_button.pressed.connect(_on_accept_pressed)
	travel_button.pressed.connect(_on_travel_pressed)
	panel_toggle_button.pressed.connect(_on_panel_toggle_pressed)
	pause_button.pressed.connect(_on_pause_pressed)
	refuel_button.pressed.connect(_on_refuel_pressed)
	repair_button.pressed.connect(_on_repair_pressed)
	view_orders_button.pressed.connect(_on_view_orders_pressed)
	order_board.closed.connect(_refresh_buttons)
	order_board.order_selected.connect(_on_order_selected)
	map_view.city_view_changed.connect(_on_city_view_changed)
	map_view.city_selected.connect(_on_city_selected)
	map_view.location_selected.connect(_on_location_selected)
	modal_layers.setup($HUD/UI, [inventory_window, order_board, vehicle_status_dialog, workshop_trade, store_trade, workshop_upgrade], map_view)
	map_view.set_current_location(
		current_city_id,
		current_location_id,
		true
	)
	map_view.set_trip_progress(0.0)
	_update_game_time_label()
	_refresh_interface()


func _process(delta: float) -> void:
	if travel_paused:
		return

	if intercity_trip.active:
		_process_intercity_trip(delta)
		return

	if local_trip.active:
		_process_local_trip(delta)
		return


# Заказы компании.
func _on_view_orders_pressed() -> void:
	if current_location_id != "company_office" or current_order != null:
		return
	var offers := order_generator.generate(map_view.routes, clock.total_minutes)
	order_board.show_offers(offers, clock)
	view_orders_button.visible = false


func _on_order_selected(order: DeliveryOrder) -> void:
	if current_order != null:
		return
	current_order = order
	order_state = OrderState.ACCEPTED
	last_order_result = ""
	order_panel_collapsed = true
	order_board.visible = false
	route_available = false
	map_view.clear_local_route()
	map_view.clear_route()
	status_label.text = "Заказ принят. Проложите маршрут до точки сбора."
	_refresh_interface()


func _on_accept_pressed() -> void:
	if order_state == OrderState.READY_TO_PICK_UP and _is_at_order_pickup():
		_open_inventory(true)
		return

	if order_state == OrderState.READY_TO_HAND_OVER and _is_at_order_delivery():
		_complete_current_order()


func _is_at_order_pickup() -> bool:
	return (
		current_order != null
		and current_city_id == current_order.pickup_city_id
		and current_location_id == current_order.pickup_location_id
	)


func _is_at_order_delivery() -> bool:
	return (
		current_order != null
		and current_city_id == current_order.delivery_city_id
		and current_location_id == current_order.delivery_location_id
	)


func _handle_trip_arrival() -> void:
	if current_order != null and _is_at_order_pickup() and not current_order.remaining_cargo().is_empty():
		order_state = OrderState.READY_TO_PICK_UP
		status_label.text = "Вы на месте сбора. Заберите груз."
	elif order_state == OrderState.TRAVELLING and _is_at_order_delivery():
		order_state = OrderState.READY_TO_HAND_OVER
		status_label.text = "Вы на месте доставки. Сдайте заказ."
	else:
		status_label.text = "Прибытие: %s" % city_label.text
	_refresh_interface()


func _complete_current_order() -> void:
	for item in current_order.cargo:
		if vehicle.inventory.contains(item):
			vehicle.inventory.remove(item)
			current_order.delivered_cargo.append(item)
	if not current_order.remaining_cargo().is_empty():
		order_state = OrderState.ACCEPTED
		last_order_result = "Доставлено %d из %d. Вернитесь за оставшимся грузом." % [current_order.delivered_cargo.size(), current_order.cargo.size()]
		_refresh_interface()
		status_label.text = last_order_result
		return
	var full_reward: int = current_order.reward
	var late := clock.total_minutes > current_order.deadline_total_minutes
	var reward := floori(float(full_reward) / 3.0) if late else full_reward
	money_credits += reward
	last_order_result = "Заказ выполнен%s. Выплата: %d кр." % [" с опозданием" if late else "", reward]
	if not current_order.lost_cargo.is_empty():
		last_order_result = "Неполная доставка: %d из %d, потеряно %d. Выплата: %d кр." % [current_order.delivered_cargo.size(), current_order.cargo.size(), current_order.lost_cargo.size(), reward]
	current_order = null
	order_state = OrderState.AVAILABLE
	status_label.text = last_order_result
	map_view.clear_route()
	map_view.clear_local_route()
	route_available = false
	_refresh_interface()


func _position_inventory_button() -> void:
	inventory_button.position = order_panel.position + Vector2(0.0, order_panel.size.y * order_panel.scale.y + 6.0)
	inventory_button.size.x = order_panel.size.x


func _open_inventory(for_pickup: bool = false) -> void:
	if _is_trip_active() and not travel_paused:
		return
	var items: Array[DeliveryOrder.CargoItem] = []
	if current_order != null:
		items = current_order.remaining_cargo()
	inventory_window.open(vehicle.inventory, items, for_pickup and not _is_trip_active() and _is_at_order_pickup())


func _on_inventory_closed() -> void:
	if current_order == null or not _is_at_order_pickup() or _is_trip_active():
		return
	var remaining := current_order.remaining_cargo()
	var warehouse_has_cargo := false
	for item in remaining:
		if not vehicle.inventory.contains(item):
			warehouse_has_cargo = true
			break
	if warehouse_has_cargo:
		order_state = OrderState.READY_TO_PICK_UP
		_refresh_interface()
		return
	order_state = OrderState.TRAVELLING
	route_available = false
	map_view.clear_local_route()
	map_view.clear_route()
	status_label.text = "Груз получен. Проложите маршрут до пункта доставки."
	_refresh_interface()


func _on_cargo_discarded(item: DeliveryOrder.CargoItem) -> void:
	if current_order == null or not current_order.cargo.has(item):
		return
	if not current_order.lost_cargo.has(item):
		current_order.lost_cargo.append(item)
	# Даже при потере всего груза заказ сдаётся в пункте назначения.
	if current_order.remaining_cargo().is_empty():
		order_state = OrderState.TRAVELLING
	if _is_at_order_delivery():
		order_state = OrderState.READY_TO_HAND_OVER
	_refresh_interface()


# Выбор маршрута и движение.
func _on_city_selected(city_id: String, city_name: String) -> void:
	var destination: Dictionary = map_view.routes.cities_by_id[city_id]
	route_target_city_id = city_id
	route_target_location_id = destination["entry_location_id"]
	route_target_name = city_name
	route_is_intercity = true
	local_destination_place_id = route_target_location_id
	local_destination_name = route_target_name
	route_available = map_view.set_route(
		current_city_id,
		city_id,
		current_location_id
	)
	map_view.set_route_visible(route_available)
	status_label.text = "Маршрут до города построен."
	_update_route_estimate()
	_refresh_buttons()


func _on_city_view_changed(city_id: String, city_name: String, interactive: bool) -> void:
	if city_id.is_empty():
		city_label.text = "Общий вид"
		return

	if interactive:
		current_city_name = city_name
		city_label.text = "Вы в городе: %s" % city_name
	else:
		city_label.text = "Просмотр: %s (без взаимодействий)" % city_name


func _on_location_selected(
	city_id: String,
	place_id: String,
	place_name: String,
	selection_has_route: bool
) -> void:
	if _is_trip_active():
		return

	route_target_city_id = city_id
	route_target_location_id = place_id
	route_target_name = place_name
	route_is_intercity = city_id != current_city_id
	local_destination_place_id = place_id
	local_destination_name = place_name
	route_available = selection_has_route
	# Локальный маршрут уже построен картой; удаляем предыдущую межгородскую цель.
	if not route_is_intercity:
		map_view.clear_route()
	if route_is_intercity:
		route_available = map_view.set_route(
			current_city_id,
			city_id,
			current_location_id,
			place_id
		) and selection_has_route
		map_view.set_route_visible(route_available)
	city_label.text = "%s — %s" % [map_view.routes.cities_by_id[city_id]["name"], place_name]
	if selection_has_route:
		status_label.text = "Маршрут к точке построен."
	else:
		status_label.text = "Игрок уже находится в этой точке."
	_update_route_estimate()
	_refresh_buttons()


func _update_route_estimate() -> void:
	intercity_distance_units = 0.0
	if not route_available or not route_is_intercity:
		return

	var city_entry_location_id: String = map_view.arrival_location_id
	intercity_distance_units = map_view.routes.get_route_distance(
		current_city_id,
		current_location_id,
		route_target_city_id,
		city_entry_location_id
	)
	var route_local_distance_units := 0.0
	if route_target_location_id != city_entry_location_id:
		route_local_distance_units = map_view.routes.get_route_distance(
			route_target_city_id,
			city_entry_location_id,
			route_target_city_id,
			route_target_location_id
		)
	intercity_duration_seconds = vehicle.duration_for_distance(intercity_distance_units)
	destination_city_duration_seconds = (
		vehicle.duration_for_distance(route_local_distance_units)
		if route_local_distance_units > 0.0
		else 0.0
	)


func _on_travel_pressed() -> void:
	if not vehicle.is_complete():
		status_label.text = "Для поездки установите все детали автомобиля."
		return
	if _is_trip_active() or not route_available:
		return
	if vehicle.fuel_liters <= 0.0:
		status_label.text = "Топливо закончилось. Запустить поездку нельзя."
		return

	trip_elapsed_before_phase_seconds = 0.0
	travel_paused = false
	map_view.set_route_selection_locked(true)
	if route_is_intercity:
		intercity_trip.start(intercity_distance_units, intercity_duration_seconds)
		map_view.set_trip_progress(0.0)
		status_label.text = "В пути к %s: 0%%" % route_target_name
	else:
		var distance := map_view.get_local_route_distance()
		local_trip.start(distance, vehicle.duration_for_distance(distance))
		map_view.set_local_trip_progress(0.0)
		status_label.text = "В пути к %s: 0%%" % local_destination_name
	_refresh_trip_controls()
	_refresh_buttons()


func _advance_trip_phase(phase: TripPhase, delta: float) -> void:
	var actual_delta := phase.advance(delta, vehicle, fatigue.speed_multiplier())
	advance_game_time(actual_delta * GameClock.GAME_MINUTES_PER_REAL_SECOND)
	if fatigue.value <= FatigueState.HIDDEN_EXHAUSTION_LIMIT:
		travel_paused = true
		_forced_sleep()
	_update_trip_clock()
	_refresh_fuel_controls()
	_refresh_vehicle_controls()


func _process_intercity_trip(delta: float) -> void:
	_advance_trip_phase(intercity_trip, delta)
	var progress := intercity_trip.progress
	map_view.set_trip_progress(progress)
	status_label.text = "В пути к %s: %d%%" % [route_target_name, roundi(progress * 100.0)]
	if progress < 1.0:
		if vehicle.fuel_liters <= 0.0:
			travel_paused = true
			status_label.text = "Топливо закончилось. Маршрут сохранён, поездка остановлена."
			_refresh_trip_controls()
		return

	intercity_trip.active = false
	current_city_id = route_target_city_id
	var city_entry_location_id: String = map_view.arrival_location_id
	current_location_id = city_entry_location_id
	map_view.set_route_visible(false)
	map_view.set_current_location(current_city_id, current_location_id, true)
	if route_target_location_id != city_entry_location_id:
		trip_elapsed_before_phase_seconds += intercity_trip.elapsed_seconds
		local_destination_place_id = route_target_location_id
		local_destination_name = route_target_name
		if map_view.set_local_route(current_city_id, city_entry_location_id, local_destination_place_id):
			local_trip.start(map_view.get_local_route_distance(), destination_city_duration_seconds)
			map_view.set_local_trip_progress(0.0)
			if vehicle.fuel_liters <= 0.0:
				travel_paused = true
				status_label.text = "Топливо закончилось на въезде в город. Маршрут сохранён."
			else:
				status_label.text = "Въезд в город. Маршрут к %s: 0%%" % local_destination_name
			_refresh_trip_controls()
			_refresh_buttons()
			return

		push_warning("Could not build city route from %s to %s" % [city_entry_location_id, local_destination_place_id])
		route_available = false
		local_destination_place_id = ""
		local_destination_name = ""
		route_target_city_id = ""
		route_target_location_id = ""
		route_target_name = ""
		route_is_intercity = false
		map_view.clear_route()
		map_view.set_route_selection_locked(false)
		travel_paused = false
		status_label.text = "Маршрут по городу не построен. Игрок остановился на въезде."
		_refresh_trip_controls()
		_refresh_interface()
		return

	travel_paused = false
	map_view.set_route_selection_locked(false)
	current_location_id = route_target_location_id
	route_available = false
	local_destination_place_id = ""
	var arrived_place_name := route_target_name
	map_view.clear_route()
	status_label.text = "Прибытие: %s" % arrived_place_name
	route_target_city_id = ""
	route_target_location_id = ""
	route_target_name = ""
	route_is_intercity = false
	_refresh_trip_controls()
	_handle_trip_arrival()


func _process_local_trip(delta: float) -> void:
	_advance_trip_phase(local_trip, delta)
	var progress := local_trip.progress
	map_view.set_local_trip_progress(progress)
	status_label.text = "В пути к %s: %d%%" % [
		local_destination_name,
		roundi(progress * 100.0),
	]

	if progress < 1.0:
		if vehicle.fuel_liters <= 0.0:
			travel_paused = true
			status_label.text = "Топливо закончилось. Маршрут сохранён, поездка остановлена."
			_refresh_trip_controls()
		return

	local_trip.active = false
	travel_paused = false
	map_view.set_route_selection_locked(false)
	current_location_id = local_destination_place_id
	route_available = false
	var arrived_place_name := local_destination_name
	map_view.set_current_location(
		current_city_id,
		current_location_id,
		true
	)
	map_view.clear_route()
	city_label.text = "%s — %s" % [current_city_name, local_destination_name]
	route_target_city_id = ""
	route_target_location_id = ""
	route_target_name = ""
	route_is_intercity = false
	local_destination_place_id = ""
	local_destination_name = ""
	status_label.text = "Прибытие: %s" % arrived_place_name
	_refresh_trip_controls()
	_handle_trip_arrival()


func _on_pause_pressed() -> void:
	if not _is_trip_active() or vehicle.fuel_liters <= 0.0:
		return
	travel_paused = not travel_paused
	_refresh_trip_controls()
	if travel_paused:
		var progress := _current_trip_progress()
		status_label.text = "Остановлено на %d%%. Маршрут сохранён." % roundi(progress * 100.0)
	else:
		status_label.text = "Поездка продолжается."


func _is_trip_active() -> bool:
	return intercity_trip.active or local_trip.active


func _current_trip_elapsed() -> float:
	if intercity_trip.active:
		return trip_elapsed_before_phase_seconds + intercity_trip.elapsed_seconds
	if local_trip.active:
		return trip_elapsed_before_phase_seconds + local_trip.elapsed_seconds
	return trip_elapsed_before_phase_seconds


func _current_trip_progress() -> float:
	if intercity_trip.active:
		return intercity_trip.progress
	if local_trip.active:
		return local_trip.progress
	return 0.0


# Игровое время и обслуживание автомобиля.
func advance_game_time(minutes: float) -> void:
	clock.advance(minutes)
	if fatigue.advance(minutes):
		_forced_sleep()
	_update_game_time_label()
	_refresh_fatigue_controls()


func _open_sleep_dialog() -> void:
	if _is_trip_active() or sleep_dialog.visible:
		return
	sleep_hours.value = 1.0
	sleep_dialog.popup_centered()


func _on_sleep_confirmed() -> void:
	var hours := sleep_hours.value
	clock.advance(hours * 60.0)
	fatigue.restore(hours * 20.0)
	_update_game_time_label()
	_refresh_fatigue_controls()
	status_label.text = "Вы поспали %.0f ч. Усталость восстановлена." % hours
	_refresh_interface()


func _forced_sleep() -> void:
	if forced_sleep_in_progress or not _is_trip_active() or not travel_paused:
		return
	forced_sleep_in_progress = true
	var hours := randi_range(9, 12)
	clock.advance(float(hours) * 60.0)
	fatigue.value = minf(100.0, fatigue.display_value() + float(hours) * 20.0 / 3.0)
	_update_game_time_label()
	status_label.text = "Вы уснули от усталости на %d ч." % hours
	_refresh_trip_controls()
	forced_sleep_in_progress = false


func _on_cigarettes_used(item: RefCounted) -> void:
	if item.title != "Сигареты" or not vehicle.inventory.contains(item):
		return
	item.uses_remaining -= 1
	fatigue.restore(5.0)
	if item.uses_remaining <= 0:
		vehicle.inventory.remove(item)
		status_label.text = "Сигареты закончились. Усталость восстановлена на 5."
	else:
		status_label.text = "Сигарета использована: осталось %d." % item.uses_remaining
	_refresh_fatigue_controls()
	_refresh_interface()


func _is_fuel_station_location(location_id: String) -> bool:
	return location_id == "company_fuel_station" or location_id == "settlement_fuel_station"


func _on_refuel_pressed() -> void:
	if _is_trip_active():
		return
	if not _is_fuel_station_location(current_location_id):
		return
	var liters_to_refuel := vehicle.affordable_refuel_liters(money_credits)
	if liters_to_refuel <= 0.0:
		status_label.text = "Недостаточно кредитов для заправки."
		return
	var refuel_cost := liters_to_refuel * BALANCE_SETTINGS.fuel_price_per_liter_credits
	vehicle.fuel_liters = minf(BALANCE_SETTINGS.fuel_tank_capacity_liters, vehicle.fuel_liters + liters_to_refuel)
	money_credits = maxf(0.0, money_credits - refuel_cost)
	advance_game_time(BALANCE_SETTINGS.refuel_time_game_minutes)
	_refresh_fuel_controls()
	_refresh_buttons()
	status_label.text = "Заправлено %.1f л за %.2f кр. Потрачено 5 игровых минут." % [
		liters_to_refuel,
		refuel_cost,
	]


func _open_workshop_trade() -> void:
	if _is_trip_active():
		return
	if current_location_id == "settlement_shop":
		store_trade.open(vehicle.inventory, money_credits, BALANCE_SETTINGS)
	elif _is_workshop_location(current_location_id):
		workshop_trade.open(vehicle.inventory, money_credits, BALANCE_SETTINGS)


func _open_workshop_upgrade() -> void:
	if _is_trip_active() or not _is_workshop_location(current_location_id):
		return
	workshop_upgrade.open(vehicle, money_credits, BALANCE_SETTINGS.workshop_upgrade_cost_credits, BALANCE_SETTINGS.vehicle_inspection_cost_credits)


func _on_trade_credits_changed(delta: float) -> void:
	money_credits += delta
	_refresh_buttons()


func _on_upgrade_accepted(cost: float) -> void:
	money_credits -= cost
	_update_route_estimate()
	_refresh_interface()


func _is_workshop_location(location_id: String) -> bool:
	return location_id == "northern_settlement_workshop"


func _on_repair_pressed() -> void:
	if _is_trip_active() or not _is_workshop_location(current_location_id):
		return
	if vehicle.condition_percent >= 100.0:
		return
	var repair_cost: float = BALANCE_SETTINGS.vehicle_repair_cost_credits
	if money_credits < repair_cost:
		status_label.text = "Недостаточно кредитов для ремонта."
		return
	money_credits -= repair_cost
	vehicle.repair_all()
	advance_game_time(BALANCE_SETTINGS.vehicle_repair_time_game_minutes)
	_refresh_interface()
	status_label.text = "Машина отремонтирована за %.0f кр. Затрачено %.0f игровых минут." % [
		repair_cost,
		BALANCE_SETTINGS.vehicle_repair_time_game_minutes,
	]


# Отображение текущего состояния.
func _on_panel_toggle_pressed() -> void:
	order_panel_collapsed = not order_panel_collapsed
	_refresh_interface()


func _refresh_interface() -> void:
	var order_taken := current_order != null
	var panel_height := 110.0
	if order_taken:
		panel_height = 150.0 if order_panel_collapsed else 290.0
	if _is_workshop_location(current_location_id) and vehicle.condition_percent < 100.0:
		panel_height += 30.0
	order_panel.custom_minimum_size = Vector2(240.0, panel_height)
	order_panel.offset_bottom = order_panel.offset_top + panel_height
	order_title.visible = not order_panel_collapsed
	order_title.text = "Заказ компании" if order_taken else "Заказы компании"
	panel_toggle_button.visible = order_taken
	panel_toggle_button.text = "Развернуть заказ" if order_panel_collapsed else "Свернуть заказ"
	order_text.visible = order_taken or not order_panel_collapsed
	city_label.visible = not order_panel_collapsed
	if order_taken:
		order_text.text = (
			_current_order_route()
			if order_panel_collapsed
			else _current_order_summary()
		)
		if not _is_trip_active():
			if order_state == OrderState.ACCEPTED:
				status_label.text = "Заказ принят. Доберитесь до точки сбора."
			elif order_state == OrderState.READY_TO_PICK_UP:
				status_label.text = "Вы на месте сбора. Заберите груз."
			elif order_state == OrderState.TRAVELLING:
				status_label.text = "Груз получен. Проложите маршрут до доставки."
			elif order_state == OrderState.READY_TO_HAND_OVER:
				status_label.text = "Вы на месте доставки. Сдайте заказ."
	else:
		order_text.text = "Доберитесь до офиса компании, чтобы просмотреть заказы."
		if not _is_trip_active():
			status_label.text = last_order_result if not last_order_result.is_empty() else "Заказ не выбран."
	_refresh_buttons()
	_refresh_trip_controls()


func _current_order_summary() -> String:
	var pickup_text := "%s — %s" % [current_order.pickup_city_name, current_order.pickup_name]
	var delivery_text := "%s — %s" % [current_order.delivery_city_name, current_order.delivery_name]
	var stage_text := "Ожидает получения" if order_state in [OrderState.ACCEPTED, OrderState.READY_TO_PICK_UP] else "Груз получен"
	return "%s\n%s\nЗабрать: %s\nДоставить: %s\nСрок: %s\nРасстояние: %.1f км\nСтоимость: %d кр." % [
		stage_text,
		"Маршрут: %s — %s" % [current_order.pickup_city_name, current_order.delivery_city_name],
		pickup_text,
		delivery_text,
		clock.format_deadline(current_order.deadline_total_minutes),
		current_order.distance_km,
		current_order.reward,
	]


func _current_order_route() -> String:
	return "%s → %s" % [current_order.pickup_name, current_order.delivery_name]


func _refresh_buttons() -> void:
	var can_pick_up := (
		order_state == OrderState.READY_TO_PICK_UP
		and _is_at_order_pickup()
		and not _is_trip_active()
	)
	var can_deliver := (
		order_state == OrderState.READY_TO_HAND_OVER
		and _is_at_order_delivery()
		and not _is_trip_active()
	)
	accept_button.visible = can_pick_up or can_deliver
	accept_button.disabled = not accept_button.visible
	accept_button.text = "Забрать груз" if can_pick_up else "Сдать заказ"
	view_orders_button.visible = (
		current_location_id == "company_office"
		and current_order == null
		and not _is_trip_active()
		and not order_board.visible
	)
	money_label.text = "Баланс: %.2f кр." % money_credits


	var can_travel: bool = (
		not _is_trip_active()
		and route_available
		and vehicle.fuel_liters > 0.0
	)
	travel_button.visible = (
		route_available
		and not _is_trip_active()
	)
	travel_button.disabled = not can_travel
	_refresh_fuel_controls()
	_refresh_vehicle_controls()


func _refresh_trip_controls() -> void:
	var active := _is_trip_active()
	var moving := active and not travel_paused
	map_view.set_follow_traveling(moving, local_trip.active)
	inventory_button.disabled = moving
	inventory_button.tooltip_text = "Остановите автомобиль, чтобы открыть инвентарь." if moving else ""
	if moving and inventory_window.visible:
		inventory_window._close()
	var empty_tank := active and vehicle.fuel_liters <= 0.0
	trip_time_label.visible = active
	pause_button.visible = active
	pause_button.disabled = empty_tank
	pause_button.text = "Нет топлива" if empty_tank else ("Продолжить" if travel_paused else "Остановить")
	_update_trip_clock()


func _update_trip_clock() -> void:
	if not _is_trip_active():
		return
	var total_seconds := floori(_current_trip_elapsed())
	var minutes := total_seconds / 60
	var seconds := total_seconds % 60
	trip_time_label.text = "Время поездки: %02d:%02d" % [minutes, seconds]


func _update_game_time_label() -> void:
	game_time_label.text = clock.time_text()


func _refresh_vehicle_controls() -> void:
	var can_use_workshop := _is_workshop_location(current_location_id) and not _is_trip_active()
	trade_button.visible = can_use_workshop or (current_location_id == "settlement_shop" and not _is_trip_active())
	upgrade_button.visible = can_use_workshop
	upgrade_button.disabled = false
	garage_diagnosis_button.visible = _can_diagnose_in_garage()
	vehicle_condition_label.text = "Состояние машины: %.0f%%" % vehicle.condition_percent
	var at_workshop := (
		_is_workshop_location(current_location_id)
		and not _is_trip_active()
	)
	repair_button.visible = at_workshop and vehicle.condition_percent < 100.0
	repair_button.text = "Ремонт до 100%% — %.0f кр." % BALANCE_SETTINGS.vehicle_repair_cost_credits
	repair_button.disabled = (
		not at_workshop
		or vehicle.condition_percent >= 100.0
		or money_credits < BALANCE_SETTINGS.vehicle_repair_cost_credits
	)
	sleep_button.visible = not _is_trip_active()


func _refresh_fuel_controls() -> void:
	fuel_label.text = "Топливо: %.1f / %.0f л" % [
		vehicle.fuel_liters,
		BALANCE_SETTINGS.fuel_tank_capacity_liters,
	]
	_refresh_fatigue_controls()
	var at_fuel_station := _is_fuel_station_location(current_location_id)
	refuel_button.visible = at_fuel_station
	var liters_to_refuel := vehicle.affordable_refuel_liters(money_credits)
	var refuel_cost := liters_to_refuel * BALANCE_SETTINGS.fuel_price_per_liter_credits
	refuel_button.text = "Заправить %.1f л — %.2f кр." % [liters_to_refuel, refuel_cost]
	refuel_button.disabled = (
		not at_fuel_station
		or vehicle.fuel_liters >= BALANCE_SETTINGS.fuel_tank_capacity_liters - 0.0001
		or money_credits <= 0.0
		or _is_trip_active()
	)


func _refresh_fatigue_controls() -> void:
	fatigue_label.text = "Усталость: %.0f" % fatigue.display_value()
