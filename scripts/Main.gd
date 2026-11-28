extends Node2D

const TravelEvents = preload("res://scripts/events/TravelEvents.gd")
const RoadBulletins = preload("res://scripts/events/RoadBulletins.gd")
const RadioBulletin = preload("res://scripts/ui/RadioBulletin.gd")
const TravelEventWindow = preload("res://scripts/ui/TravelEventWindow.gd")
const InventoryWindow = preload("res://scripts/ui/InventoryWindow.gd")
const ModalLayers = preload("res://scripts/ui/ModalLayers.gd")
const WorkshopTrade = preload("res://scripts/ui/WorkshopTrade.gd")
const WorkshopUpgrade = preload("res://scripts/ui/WorkshopUpgrade.gd")
const VehicleStatusDialog = preload("res://scripts/ui/VehicleStatusDialog.gd")
const SleepDialog = preload("res://scripts/ui/SleepDialog.gd")
const RefuelDialog = preload("res://scripts/ui/RefuelDialog.gd")
const ActionProgress = preload("res://scripts/ui/ActionProgress.gd")
const VehicleState = preload("res://scripts/simulation/VehicleState.gd")
const TripPhase = preload("res://scripts/simulation/TripPhase.gd")
const OrderBoard = preload("res://scripts/ui/OrderBoard.gd")
const DeliveryOrder = preload("res://scripts/orders/DeliveryOrder.gd")
const OrderGenerator = preload("res://scripts/orders/OrderGenerator.gd")
const GameClock = preload("res://scripts/simulation/GameClock.gd")
const NeedsState = preload("res://scripts/simulation/NeedsState.gd")
const FatigueState = preload("res://scripts/simulation/FatigueState.gd")
const MapView = preload("res://scripts/Map.gd")
@export var balance_settings: GameBalanceSettings
@export var hotel_sleep_cost: float = 100.0
@export var hotel_restore_per_hour: float = 30.0
@export_group("Раскладка панели заказа")
@export var collapsed_order_height: float = 150.0
@export var expanded_order_height: float = 290.0
@export var workshop_extra_height: float = 30.0

enum OrderState {
	AVAILABLE,
	ACCEPTED,
	READY_TO_PICK_UP,
	TRAVELLING,
	READY_TO_HAND_OVER,
}

@onready var passenger_desk = $HUD/UI/PassengerDesk
@onready var prologue = $HUD/UI/BaseHUD/Prologue
@onready var map_view: MapView = $Map
@onready var order_panel: PanelContainer = $HUD/UI/BaseHUD/OrderPanel
@onready var idle_order_height: float = order_panel.custom_minimum_size.y
@onready var status_label: Label = $HUD/UI/BaseHUD/OrderPanel/Content/StatusText
@onready var city_label: Label = $HUD/UI/BaseHUD/StatusRail/Bar/CityText
@onready var accept_button: Button = $HUD/UI/BaseHUD/OrderPanel/Content/AcceptButton
@onready var travel_button: Button = $HUD/UI/BaseHUD/StatusRail/Bar/TravelButton
@onready var order_text: Label = $HUD/UI/BaseHUD/OrderPanel/Content/OrderText
@onready var order_title: Label = $HUD/UI/BaseHUD/OrderPanel/Content/Title
@onready var panel_toggle_button: Button = $HUD/UI/BaseHUD/OrderPanel/Content/PanelToggleButton
@onready var trip_time_label: Label = $HUD/UI/BaseHUD/OrderPanel/Content/TripTimeLabel
@onready var sheet_button: Button = $HUD/UI/BaseHUD/StatusRail/Bar/SheetButton
@onready var distance_group: Control = $HUD/UI/BaseHUD/StatusRail/Bar/Distance
@onready var distance_label: Label = $HUD/UI/BaseHUD/StatusRail/Bar/Distance/Value
@onready var pause_button: Button = $HUD/UI/BaseHUD/StatusRail/Bar/PauseButton
@onready var roadside_fuel_button: Button = $HUD/UI/BaseHUD/OrderPanel/Content/RoadsideFuelButton
@onready var game_time_label: Label = $HUD/UI/BaseHUD/StatusRail/Bar/GameTimeLabel
@onready var fuel_label: Label = $HUD/UI/BaseHUD/StatusRail/Bar/FuelLabel
@onready var fatigue_label: Label = $HUD/UI/BaseHUD/FatigueLabel
@onready var refuel_button: Button = $HUD/UI/BaseHUD/OrderPanel/Content/RefuelButton
@onready var refuel_dialog: RefuelDialog = $HUD/UI/RefuelDialog
@onready var action_progress: ActionProgress = $HUD/UI/ActionProgress
@onready var money_label: Label = $HUD/UI/BaseHUD/StatusRail/Bar/MoneyLabel
@onready var vehicle_condition_label: Label = $HUD/UI/BaseHUD/VehicleConditionLabel
@onready var repair_button: Button = $HUD/UI/BaseHUD/OrderPanel/Content/RepairButton
@onready var view_orders_button: Button = $HUD/UI/BaseHUD/OrderPanel/Content/ViewOrdersButton
@onready var order_board: OrderBoard = $HUD/UI/OrderBoardOverlay

@onready var garage_diagnosis_button: Button = $HUD/UI/BaseHUD/OrderPanel/Content/GarageDiagnosisButton
@onready var vehicle_status_dialog: VehicleStatusDialog = $HUD/UI/VehicleStatusDialog

# Окна и элементы управления из сохранённой сцены HUD.
@onready var modal_layers: ModalLayers = $HUD/UI/ModalLayers
@onready var workshop_trade: WorkshopTrade = $HUD/UI/WorkshopTrade
@onready var store_trade: WorkshopTrade = $HUD/UI/StoreTrade
@onready var workshop_upgrade: WorkshopUpgrade = $HUD/UI/WorkshopUpgrade
@onready var trade_button: Button = $HUD/UI/BaseHUD/OrderPanel/Content/TradeButton
@onready var upgrade_button: Button = $HUD/UI/BaseHUD/OrderPanel/Content/UpgradeButton
@onready var inventory_window: InventoryWindow = $HUD/UI/InventoryWindow
@onready var inventory_button: Button = $HUD/UI/BaseHUD/StatusRail/Bar/InventoryButton
@onready var sleep_button: Button = $HUD/UI/BaseHUD/OrderPanel/Content/SleepButton
@onready var hotel_sleep_button: Button = $HUD/UI/BaseHUD/OrderPanel/Content/HotelSleepButton
@onready var sleep_dialog: SleepDialog = $HUD/UI/SleepDialog

# Модели игрового состояния.
@onready var vehicle: VehicleState = $Map/Vehicle
var clock := GameClock.new()
var fatigue := FatigueState.new()
@onready var needs := NeedsState.new(balance_settings)
@onready var needs_label: Label = $HUD/UI/BaseHUD/NeedsLabel
@onready var hotel_meal_button: Button = $HUD/UI/BaseHUD/OrderPanel/Content/HotelMealButton
@onready var current_city_id: String = map_view.world.start_city_id
@onready var current_location_id: String = map_view.world.start_location_id
var current_city_name: String = ""
var money_credits: float = 0.0

# Заказы и состояние панели.
@onready var order_generator := OrderGenerator.new(balance_settings)
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

# Активные участки поездки хранят собственные время, расстояние и прогресс.
var intercity_trip := TripPhase.new()
var pending_checkpoints: Array[Dictionary] = []
var local_trip := TripPhase.new()
var trip_elapsed_before_phase_seconds: float = 0.0
var travel_paused: bool = false
var travel_events := TravelEvents.new()
@onready var road_bulletins: RoadBulletins = $RoadBulletins
@onready var radio_bulletin: RadioBulletin = $HUD/UI/BaseHUD/RadioBulletin
@onready var travel_event_window: TravelEventWindow = $HUD/UI/TravelEventWindow
@onready var checkpoint_dialogue: TravelEventWindow = $HUD/UI/CheckpointDialogue
var active_event_window: TravelEventWindow
@onready var drive_mode_buttons: Array[Button] = [$HUD/UI/BaseHUD/StatusRail/Bar/DriveModeControls/Economy, $HUD/UI/BaseHUD/StatusRail/Bar/DriveModeControls/Normal, $HUD/UI/BaseHUD/StatusRail/Bar/DriveModeControls/Forced]


func _ready() -> void:
	order_generator.source_city_id = current_city_id
	travel_events.load_data()
	road_bulletins.configure(map_view.routes.roads, travel_events.events)
	road_bulletins.changed.connect(_on_road_bulletin_changed)
	for window: TravelEventWindow in [travel_event_window, checkpoint_dialogue]:
		window.action_selected.connect(_on_event_action_selected)
		window.continue_requested.connect(_on_event_continue)
	passenger_desk.decided.connect(_passenger_decided)
	_bind_service_windows()
	_bind_inventory_controls()
	_bind_sleep_controls()
	_bind_needs_controls()
	_bind_drive_mode_controls()
	_connect_signals()
	modal_layers.setup($HUD/UI, [inventory_window, order_board, vehicle_status_dialog, workshop_trade, store_trade, workshop_upgrade, sleep_dialog, refuel_dialog, travel_event_window, checkpoint_dialogue, passenger_desk, action_progress], map_view)
	prologue.start(self)
	map_view.set_current_location(
		current_city_id,
		current_location_id,
		true
	)
	map_view.set_trip_progress(0.0)
	_update_game_time_label()
	_refresh_interface()


func _bind_service_windows() -> void:
	for trade in [workshop_trade, store_trade]:
		trade.credits_changed.connect(_on_trade_credits_changed)
		trade.discarded.connect(_on_cargo_discarded)
		trade.used.connect(_on_item_used)
	workshop_upgrade.accepted.connect(_on_upgrade_accepted)
	workshop_upgrade.credits_changed.connect(_on_trade_credits_changed)
	trade_button.pressed.connect(_open_workshop_trade)
	upgrade_button.text = "Улучшить — %.0f кр." % balance_settings.workshop_upgrade_cost_credits
	upgrade_button.pressed.connect(_open_workshop_upgrade)


func _bind_inventory_controls() -> void:
	inventory_window.closed.connect(_on_inventory_closed)
	inventory_window.discarded.connect(_on_cargo_discarded)
	inventory_window.used.connect(_on_item_used)
	inventory_button.pressed.connect(_open_inventory)
	sheet_button.toggled.connect(order_panel.set_visible)


func _bind_sleep_controls() -> void:
	sleep_button.pressed.connect(_open_sleep_dialog)
	hotel_sleep_button.text = "Спать в отеле — %.0f кр." % hotel_sleep_cost
	hotel_sleep_button.pressed.connect(_open_sleep_dialog.bind(true))
	sleep_dialog.sleep_requested.connect(_on_sleep_confirmed)


func _bind_needs_controls() -> void:
	hotel_meal_button.text = "Поесть и попить — %.0f кр." % balance_settings.hotel_meal_cost_credits
	hotel_meal_button.pressed.connect(_on_hotel_meal_pressed)


func _on_hotel_meal_pressed() -> void:
	if _is_trip_active() or _place_type(current_location_id) != "hotel":
		return
	if money_credits < balance_settings.hotel_meal_cost_credits:
		return
	if not await action_progress.run("Еда в отеле", balance_settings.hotel_meal_time_minutes):
		return
	money_credits -= balance_settings.hotel_meal_cost_credits
	advance_game_time(balance_settings.hotel_meal_time_minutes)
	needs.refill()
	_refresh_interface()
	status_label.text = "Вы поели и попили. Сытость и запас воды восстановлены."


func _bind_drive_mode_controls() -> void:
	for mode in range(drive_mode_buttons.size()):
		drive_mode_buttons[mode].set_pressed_no_signal(vehicle.drive_mode == mode)
		drive_mode_buttons[mode].pressed.connect(_on_drive_mode_pressed.bind(mode))


func _on_drive_mode_pressed(mode: VehicleState.DriveMode) -> void:
	vehicle.drive_mode = mode
	for index in range(drive_mode_buttons.size()):
		drive_mode_buttons[index].set_pressed_no_signal(index == mode)


func _connect_signals() -> void:
	garage_diagnosis_button.pressed.connect(_on_garage_diagnosis_pressed)
	accept_button.pressed.connect(_on_accept_pressed)
	travel_button.pressed.connect(_on_travel_pressed)
	panel_toggle_button.pressed.connect(_on_panel_toggle_pressed)
	pause_button.pressed.connect(_on_pause_pressed)
	roadside_fuel_button.pressed.connect(_on_roadside_fuel_pressed)
	refuel_button.pressed.connect(_on_refuel_pressed)
	refuel_dialog.fuel_requested.connect(_dispense_station_fuel)
	refuel_dialog.finished.connect(_finish_station_visit)
	repair_button.pressed.connect(_on_repair_pressed)
	view_orders_button.pressed.connect(_on_view_orders_pressed)
	order_board.closed.connect(_refresh_buttons)
	order_board.order_selected.connect(_on_order_selected)
	map_view.city_view_changed.connect(_on_city_view_changed)
	map_view.waypoint_removed.connect(_remove_waypoint)
	map_view.location_selected.connect(_on_location_selected)
	map_view.road_selected.connect(_on_road_selected)
	vehicle_status_dialog.repair_requested.connect(_on_part_repair_pressed)


func _process(delta: float) -> void:
	if not prologue.active() and road_bulletins.next_check < 0.0:
		road_bulletins.update_at(clock.total_minutes)
	if travel_paused or action_progress.visible or not travel_events.active_event.is_empty():
		return

	if intercity_trip.active:
		_process_intercity_trip(delta)
		return

	if local_trip.active:
		_process_local_trip(delta)
		return


# Заказы компании.
func _on_view_orders_pressed() -> void:
	if _place_type(current_location_id) != "company_office" or current_order != null:
		return
	if prologue.active():
		prologue.open_orders()
		return
	order_generator.refresh_offers(map_view.routes, clock.total_minutes, current_city_id)
	order_board.show_offers(order_generator.available_offers, clock, order_generator.next_refresh_minutes)
	view_orders_button.visible = false


func _on_order_selected(order: DeliveryOrder) -> void:
	if current_order != null:
		return
	if order.is_passenger_order() and not passenger_desk.prepare_manifest(order, prologue.step == prologue.Step.SECOND_ORDER):
		status_label.text = "Для этого рейса не составлен список пассажиров."
		return
	current_order = order
	order_generator.available_offers.erase(order)
	prologue.order_accepted(order)
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
	if not prologue.can_handle_order():
		return
	if current_order == null or _is_trip_active():
		return
	if order_state == OrderState.READY_TO_PICK_UP and _is_at_order_pickup():
		if current_order.is_passenger_order():
			_pick_up_passengers()
		else:
			_open_inventory(true)
		return

	if order_state == OrderState.READY_TO_HAND_OVER and _is_at_order_delivery():
		_complete_current_order()


func _pick_up_passengers() -> void:
	if current_order == null or not current_order.is_passenger_order() or current_order.passengers_picked_up:
		return
	if _is_trip_active() or not _is_at_order_pickup() or _place_type(current_location_id) != "stop":
		return
	passenger_desk.open(current_order, vehicle.free_passenger_seats())

func _passenger_decided(allow: bool) -> void:
	if current_order == null or not passenger_desk.visible or passenger_desk.order != current_order:
		return
	var tutorial: bool = prologue.step == prologue.Step.BOARD
	if tutorial and not allow:
		passenger_desk.open(current_order, vehicle.free_passenger_seats())
		prologue.remind_to_recheck_passenger()
		return
	if allow and not vehicle.board_passengers(1, current_order.manifest[current_order.decisions.size()].portrait):
		passenger_desk.open(current_order, vehicle.free_passenger_seats())
		return
	current_order.decisions.append(allow)
	if current_order.decisions.size() < current_order.passenger_count:
		passenger_desk.open(current_order, vehicle.free_passenger_seats())
		return
	passenger_desk.hide()
	passenger_desk.order = null
	if current_order.onboard_count() == 0:
		current_order = null
		order_state = OrderState.AVAILABLE
		last_order_result = "В посадке отказано всем пассажирам. Рейс закрыт без оплаты."
	else:
		current_order.passengers_picked_up = true
		order_state = OrderState.TRAVELLING
	route_available = false
	map_view.clear_local_route()
	map_view.clear_route()
	_refresh_interface()


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
	var city: Dictionary = map_view.routes.cities_by_id.get(current_city_id, {})
	if not city.is_empty():
		current_city_name = city.name
		var stop_name := str(_place_data(current_location_id).get("name", ""))
		city_label.text = current_city_name if stop_name.is_empty() else "%s · %s" % [current_city_name, stop_name]
	elif map_view.routes.road_stops.has(current_city_id):
		city_label.text = "Остановка на трассе"
	city_label.tooltip_text = city_label.text
	sheet_button.button_pressed = true
	if current_order != null and _is_at_order_pickup() and current_order.has_pending_pickup():
		order_state = OrderState.READY_TO_PICK_UP
		status_label.text = "Вы на автостанции. Посадите пассажиров." if current_order.is_passenger_order() else "Вы на месте сбора. Заберите груз."
	elif order_state == OrderState.TRAVELLING and _is_at_order_delivery():
		order_state = OrderState.READY_TO_HAND_OVER
		status_label.text = "Вы на месте доставки. Сдайте заказ."
	else:
		status_label.text = "Прибытие: %s" % city_label.text
	_refresh_interface()


func _complete_current_order() -> void:
	if current_order == null or _is_trip_active() or not _is_at_order_delivery() or order_state != OrderState.READY_TO_HAND_OVER:
		return
	if current_order.is_passenger_order():
		if not current_order.passengers_picked_up or not vehicle.disembark_passengers(current_order.onboard_count()):
			status_label.text = "Пассажиры этого заказа ещё не посажены в машину."
			return
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
	var full_reward: int = current_order.payable_reward()
	# При опоздании срочного заказа также требуется потеря репутации;
	# подключить после реализации системы репутации и согласования величины.
	var late := clock.total_minutes > current_order.deadline_total_minutes
	var reward := floori(float(full_reward) / 3.0) if late else full_reward
	money_credits += reward
	last_order_result = "Заказ выполнен%s. Выплата: %d кр." % [" с опозданием" if late else "", reward]
	if not current_order.lost_cargo.is_empty():
		last_order_result = "Неполная доставка: %d из %d, потеряно %d. Выплата: %d кр." % [current_order.delivered_cargo.size(), current_order.cargo.size(), current_order.lost_cargo.size(), reward]
	prologue.order_delivered(current_order)
	current_order = null
	order_state = OrderState.AVAILABLE
	status_label.text = last_order_result
	map_view.clear_route()
	map_view.clear_local_route()
	route_available = false
	_refresh_interface()


func _open_inventory(for_pickup: bool = false) -> void:
	if _is_trip_active() and not travel_paused:
		return
	var items: Array[DeliveryOrder.CargoItem] = []
	if current_order != null:
		items = current_order.remaining_cargo()
	var allow_loading := current_order != null and for_pickup and not _is_trip_active() and _is_at_order_pickup() and not current_order.is_passenger_order()
	inventory_window.open(vehicle, items, allow_loading, vehicle.settings.cargo_capacity_kg)


func _on_inventory_closed() -> void:
	if current_order == null or current_order.is_passenger_order() or not _is_at_order_pickup() or _is_trip_active():
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
func _remaining_waypoints(exclude := -1) -> Array[Dictionary]:
	var via: Array[Dictionary] = []
	for i in map_view.waypoints.size():
		var point := map_view.waypoints[i]
		if i == exclude or (point.get("road_passage", false) and i + 1 == exclude):
			continue
		if map_view.waypoint_pending(i):
			via.append(map_view.remaining_anchor(i))
	return via


func _remove_waypoint(index: int) -> void:
	if map_view.route_editable and route_available:
		_rebuild_route(_remaining_waypoints(index), map_view.remaining_anchor(map_view.waypoints.size()), route_target_city_id, route_target_location_id, route_target_name)


func _rebuild_route(via: Array[Dictionary], finish: Dictionary, city: String, place: String, label: String) -> void:
	var traveling := _is_trip_active()
	if traveling and not travel_paused:
		return
	var origin := map_view.route_origin(traveling, local_trip.active)
	var anchors: Array[Dictionary] = [origin]
	anchors.append_array(via)
	anchors.append(finish)
	var plan := map_view.waypoint_router.build(anchors)
	if plan.is_empty():
		status_label.text = "Из этой позиции путь до выбранной точки не построен."
		return

	if traveling:
		trip_elapsed_before_phase_seconds = _current_trip_elapsed()
		intercity_trip.active = false
		local_trip.active = false
	if plan.distance <= map_view.WaypointRouter.EPS:
		travel_paused = false
		route_available = false
		route_is_intercity = false
		route_target_city_id = ""
		route_target_location_id = ""
		route_target_name = ""
		local_destination_place_id = ""
		local_destination_name = ""
		pending_checkpoints.clear()
		current_city_id = city
		current_location_id = place
		map_view.set_route_selection_locked(false)
		map_view.set_current_location(city, place, false)
		map_view.clear_route()
		city_label.text = label
		_handle_trip_arrival()
		return
	var local := city == current_city_id and map_view.routes.cities_by_id.has(city) and is_inf(plan.first_highway)
	route_available = true
	route_is_intercity = not local
	route_target_city_id = city
	route_target_location_id = place
	route_target_name = label
	local_destination_place_id = place
	local_destination_name = label
	map_view.install_custom_route(plan, via, finish, city, place, local)
	if traveling:
		var phase := local_trip if local else intercity_trip
		_start_route_phase(phase)
		_prepare_checkpoints(plan.crossings)
	city_label.text = "%s  →  %s" % [current_city_name, label]
	city_label.tooltip_text = city_label.text
	_refresh_buttons()
	_refresh_trip_controls()
	_show_route_hint(plan.distance)


func _show_route_hint(distance: float) -> void:
	var km := distance * VehicleState.TravelRules.DISTANCE_KM_PER_UNIT
	status_label.text = "%s · %.1f км. Shift + ЛКМ — продлить путь. ПКМ по номеру — убрать." % [route_target_name, km]


func _on_city_view_changed(city_id: String, city_name: String, interactive: bool) -> void:
	if not route_available:
		city_label.tooltip_text = ""
	if city_id.is_empty():
		if not route_available:
			city_label.text = current_city_name
		return

	if interactive:
		current_city_name = city_name
		if not route_available:
			city_label.text = city_name
	else:
		if not route_available:
			city_label.text = "Обзор · %s" % city_name


func _on_road_selected(passage: Dictionary, append: bool) -> void:
	if not map_view.route_editable:
		return
	var router := map_view.waypoint_router
	if append:
		var origin := map_view.custom_finish if route_available else map_view.route_origin(_is_trip_active(), local_trip.active)
		var incoming: Dictionary = {}
		if route_available and not map_view.custom_path.segments.is_empty():
			incoming = map_view.custom_path.segments.back()
		var ahead := router.destination_ahead(origin, passage, incoming)
		if ahead.is_empty():
			status_label.text = "Дальше по этой дороге нет города или точки интереса."
			return
		var target: Dictionary = ahead.target
		var finish := router.location(target.city, target.place).duplicate()
		finish["via_edge"] = passage.edge
		finish["forward"] = ahead.forward
		_plot_destination(target.city, target.place, target.name, true, finish)
		return
	var target := router.destination_from(passage)
	if target.is_empty():
		status_label.text = "С этой дороги нет пути до города или точки интереса."
		return
	_plot_destination(target.city, target.place, target.name, false, router.location(target.city, target.place), passage)


func _on_location_selected(city: String, place: String, label: String, append := false) -> void:
	if not map_view.route_editable:
		return
	if not _is_trip_active() and city == map_view.incident_stop_id and city == current_city_id and not road_bulletins.event.is_empty() and not (append and route_available):
		travel_events.begin_road_event(road_bulletins.event)
		road_bulletins.clear()
		_open_travel_event(travel_event_window)
		return
	_plot_destination(city, place, label, append, map_view.waypoint_router.location(city, place))


func _plot_destination(city: String, place: String, label: String, append: bool, finish: Dictionary, passage: Dictionary = {}) -> void:
	var via: Array[Dictionary] = []
	if append and route_available:
		if route_target_city_id == city and route_target_location_id == place:
			return
		via = _remaining_waypoints()
		via.append(map_view.remaining_anchor(map_view.waypoints.size()))
	if not passage.is_empty():
		via.append(passage)
	_rebuild_route(via, finish, city, place, label)


func _start_route_phase(phase: TripPhase) -> void:
	var plan := map_view.custom_path
	phase.start(plan.distance, vehicle.duration_for_distance(plan.pace_offsets[-1]), plan.road_offsets, plan.pace_offsets)


func _on_travel_pressed() -> void:
	if not prologue.can_travel():
		return
	if not vehicle.is_complete():
		status_label.text = "Для поездки установите все детали автомобиля."
		return
	if _is_trip_active() or not route_available:
		return
	if vehicle.fuel_liters <= 0.0:
		status_label.text = "Топливо закончилось. Запустить поездку нельзя."
		return

	trip_elapsed_before_phase_seconds = 0.0
	sheet_button.button_pressed = false
	travel_paused = false
	map_view.set_route_selection_locked(true)
	if route_is_intercity:
		_start_route_phase(intercity_trip)
		_prepare_checkpoints(map_view.route_checkpoints)
		map_view.set_trip_progress(0.0)
		status_label.text = "В пути к %s: 0%%" % route_target_name
	else:
		_start_route_phase(local_trip)
		_prepare_checkpoints(map_view.local_checkpoints)
		map_view.set_local_trip_progress(0.0)
		status_label.text = "В пути к %s: 0%%" % local_destination_name
	_refresh_trip_controls()
	_refresh_buttons()


func _advance_trip_phase(phase: TripPhase, delta: float) -> void:
	var previous_progress := phase.progress
	var bulletin := road_bulletins.event
	var bulletin_expiry := road_bulletins.expires_at
	var bulletin_distance := INF
	var limit_units := (INF if prologue.active() else travel_events.distance_limit_km()) / VehicleState.TravelRules.DISTANCE_KM_PER_UNIT
	if phase == intercity_trip and not bulletin.is_empty():
		var midpoint := map_view.next_highway_midpoint(road_bulletins.road.id, phase.progress * phase.distance_units)
		var remaining := midpoint - phase.progress * phase.distance_units
		if remaining >= -0.0001:
			bulletin_distance = midpoint
			limit_units = minf(limit_units, maxf(remaining, 0.0))
	if not pending_checkpoints.is_empty():
		limit_units = minf(limit_units, maxf(0.0, pending_checkpoints[0].distance - phase.progress * phase.distance_units))
	var actual_delta := phase.advance(delta, vehicle, fatigue.speed_multiplier(), limit_units)
	advance_game_time(actual_delta * GameClock.GAME_MINUTES_PER_REAL_SECOND)
	_update_trip_clock()
	_refresh_fuel_controls()
	_refresh_vehicle_controls()
	var km := (phase.progress - previous_progress) * phase.distance_units * VehicleState.TravelRules.DISTANCE_KM_PER_UNIT
	if phase.progress * phase.distance_units + 0.0001 >= bulletin_distance and clock.total_minutes < bulletin_expiry:
		travel_events.begin_road_event(bulletin)
		road_bulletins.clear()
		_open_travel_event(travel_event_window)
	elif prologue.trigger_incident(phase) or (not prologue.active() and travel_events.advance_distance(km)):
		_open_travel_event(travel_event_window)
	elif not pending_checkpoints.is_empty() and phase.progress * phase.distance_units + 0.0001 >= pending_checkpoints[0].distance:
		var crossing: Dictionary = pending_checkpoints.pop_front()
		if not prologue.active():
			travel_events.active_event = crossing.post.roll_event()
			travel_events.resolved = travel_events.active_event.actions.is_empty()
			_open_travel_event(checkpoint_dialogue)
		elif prologue.begin_entry_inspection():
			_open_travel_event(checkpoint_dialogue)
	if fatigue.value <= FatigueState.HIDDEN_EXHAUSTION_LIMIT:
		travel_paused = true
		_forced_sleep()


func _prepare_checkpoints(crossings: Array[Dictionary]) -> void:
	pending_checkpoints.clear()
	for crossing in crossings:
		var post = crossing.post
		var entering: bool = crossing.forward != post.reverse_entry
		if prologue.active():
			if not (post.tutorial_checkpoint and entering and prologue.expects_entry_inspection()):
				continue
		elif not post.stops_for(entering):
			continue
		pending_checkpoints.append(crossing)
	pending_checkpoints.sort_custom(func(a, b): return a.distance < b.distance)


func _open_travel_event(window: TravelEventWindow) -> void:
	active_event_window = window
	travel_paused = true
	_refresh_trip_controls()
	var available: Array[bool] = []
	for index in range(travel_events.active_event.actions.size()):
		available.append(travel_events.can_choose(index, money_credits, vehicle.fuel_liters))
	window.open(travel_events.active_event, available)
	if travel_events.resolved:
		window.show_result(travel_events.active_event.description)


func _process_intercity_trip(delta: float) -> void:
	_advance_trip_phase(intercity_trip, delta)
	var progress := intercity_trip.progress
	map_view.set_trip_progress(progress)
	if not travel_events.active_event.is_empty():
		return
	status_label.text = "В пути к %s: %d%%" % [route_target_name, roundi(progress * 100.0)]
	if progress < 1.0:
		if vehicle.fuel_liters <= 0.0:
			travel_paused = true
			status_label.text = "Топливо закончилось. Маршрут сохранён, поездка остановлена."
			_refresh_trip_controls()
		return

	intercity_trip.active = false
	current_city_id = route_target_city_id
	current_location_id = route_target_location_id
	map_view.set_route_visible(false)
	map_view.finish_intercity_arrival(current_city_id, current_location_id)
	travel_paused = false
	map_view.set_route_selection_locked(false)
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
	if not travel_events.active_event.is_empty():
		return
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
	# Прибытие обновляет местоположение, сохраняя текущий вид камеры.
	# Повторное открытие города запускало перелёт к его центру.
	map_view.set_current_location(
		current_city_id,
		current_location_id,
		false
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


func _on_event_action_selected(index: int) -> void:
	if not travel_events.can_choose(index, money_credits, vehicle.fuel_liters):
		return
	var action: Dictionary = travel_events.active_event.actions[index]
	var minutes := float(action.get("minutes", 0.0))
	var action_name := str(action.text).get_slice(" — ", 0).get_slice(" · ", 0)
	if not await action_progress.run(action_name, minutes):
		return
	var outcome := travel_events.resolve(index)
	money_credits -= float(action.get("money_cost", 0.0))
	vehicle.fuel_liters = maxf(0.0, vehicle.fuel_liters - float(action.get("fuel_cost", 0.0)))
	if outcome.has("wheel_wear"):
		vehicle.get_part("front_right_wheel").wear(outcome.wheel_wear)
	advance_game_time(minutes)
	if minutes > 0.0 and fatigue.value <= FatigueState.HIDDEN_EXHAUSTION_LIMIT:
		await _forced_sleep()
	money_credits += float(outcome.get("money", 0.0))
	vehicle.fuel_liters = minf(vehicle.settings.fuel_tank_capacity_liters, vehicle.fuel_liters + float(outcome.get("fuel", 0.0)))
	fatigue.restore(float(outcome.get("fatigue_restore", 0.0)))
	_refresh_interface()
	active_event_window.show_result(outcome.text)


func _on_event_continue() -> void:
	if action_progress.visible or not travel_events.resolved:
		return
	var finished_event := travel_events.active_event
	travel_events.finish()
	active_event_window.hide()
	active_event_window = null
	prologue.travel_event_finished(finished_event)
	travel_paused = vehicle.fuel_liters <= 0.0 and _current_trip_progress() < 1.0
	_refresh_interface()


func _on_pause_pressed() -> void:
	if not travel_events.active_event.is_empty() or not _is_trip_active() or vehicle.fuel_liters <= 0.0:
		return
	travel_paused = not travel_paused
	_refresh_trip_controls()
	if travel_paused:
		var progress := _current_trip_progress()
		status_label.text = "Остановка на %d%%. ЛКМ — новый маршрут, Shift + ЛКМ — продлить." % roundi(progress * 100.0)
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
	fatigue.advance(needs.advance(minutes))
	_update_game_time_label()
	_refresh_fatigue_controls()


func _can_sleep_at_hotel() -> bool:
	return (
		_place_type(current_location_id) == "hotel"
		and not _is_trip_active()
		and money_credits >= hotel_sleep_cost
	)


func _can_sleep_on_stop() -> bool:
	return travel_events.active_event.is_empty() and (not _is_trip_active() or travel_paused)


func _open_sleep_dialog(at_hotel: bool = false) -> void:
	if not _can_sleep_on_stop() or sleep_dialog.visible:
		return
	if at_hotel and not _can_sleep_at_hotel():
		return
	sleep_dialog.open(at_hotel, hotel_sleep_cost, hotel_restore_per_hour, clock)


func _on_sleep_confirmed(requested_hours: float, sleeping_at_hotel: bool) -> void:
	if not _can_sleep_on_stop():
		return
	if sleeping_at_hotel and not _can_sleep_at_hotel():
		return
	var hours := clampf(requested_hours, 1.0, 12.0)
	var action_name := "Сон в отеле" if sleeping_at_hotel else "Сон на стоянке"
	if not await action_progress.run(action_name, hours * 60.0):
		return
	var restore_per_hour := hotel_restore_per_hour if sleeping_at_hotel else 20.0
	if sleeping_at_hotel:
		money_credits -= hotel_sleep_cost
	needs.advance(hours * 60.0, true)
	clock.advance(hours * 60.0)
	fatigue.restore(hours * restore_per_hour)
	_update_game_time_label()
	_refresh_fatigue_controls()
	_refresh_interface()
	if sleeping_at_hotel:
		status_label.text = "Вы поспали в отеле %.0f ч. Оплачено %.0f кр." % [hours, hotel_sleep_cost]
	else:
		status_label.text = "Вы поспали на стоянке %.0f ч." % hours


func _forced_sleep() -> void:
	if not _is_trip_active() or not travel_paused:
		return
	var hours := randi_range(9, 12)
	if not await action_progress.run("Сон от усталости", hours * 60.0):
		return
	needs.advance(float(hours) * 60.0, true)
	clock.advance(float(hours) * 60.0)
	fatigue.value = minf(100.0, fatigue.display_value() + float(hours) * 20.0 / 3.0)
	_update_game_time_label()
	status_label.text = "Вы уснули от усталости на %d ч." % hours
	_refresh_trip_controls()
	_refresh_fatigue_controls()


func _on_item_used(item: RefCounted) -> void:
	if not item.can_use() or not vehicle.inventory.contains(item):
		return
	item.uses_remaining -= 1
	fatigue.restore(float(item.properties.get("fatigue_restore", 0.0)))
	needs.satiety = minf(balance_settings.needs_max_value, needs.satiety + float(item.properties.get("satiety_restore", 0.0)))
	needs.water = minf(balance_settings.needs_max_value, needs.water + float(item.properties.get("water_restore", 0.0)))
	if item.uses_remaining <= 0:
		vehicle.inventory.remove(item)
	_refresh_interface()
	status_label.text = "%s: осталось использований %d." % [item.title, item.uses_remaining]


func _is_fuel_station_location(location_id: String) -> bool:
	return _place_type(location_id) == "fuel_station"


func _roadside_fuel_liters() -> float:
	if vehicle.fuel_liters > 0.0 or not travel_events.active_event.is_empty():
		return 0.0
	if not _is_trip_active() and _is_fuel_station_location(current_location_id):
		return 0.0
	return minf(balance_settings.roadside_fuel_liters, vehicle.settings.fuel_tank_capacity_liters)


func _on_roadside_fuel_pressed() -> void:
	var liters := _roadside_fuel_liters()
	var cost := balance_settings.roadside_fuel_cost
	var minutes := balance_settings.roadside_fuel_minutes
	if liters <= 0.0 or money_credits < cost:
		return
	if not await action_progress.run("Ожидание подвоза топлива", minutes):
		return
	money_credits -= cost
	vehicle.fuel_liters = liters
	advance_game_time(minutes)
	_refresh_interface()
	status_label.text = "Топливо доставлено: %s л. Оплачено %s кр." % [RefuelDialog.format_liters(liters), String.num(cost)]
	if fatigue.value <= FatigueState.HIDDEN_EXHAUSTION_LIMIT:
		_forced_sleep()


func _on_refuel_pressed() -> void:
	if refuel_dialog.visible:
		return
	if _available_refuel_liters() > 0.0:
		refuel_dialog.open(balance_settings.fuel_price_per_liter_credits, money_credits)


func _available_refuel_liters() -> float:
	if _is_trip_active() or not _is_fuel_station_location(current_location_id):
		return 0.0
	return vehicle.affordable_refuel_liters(money_credits, balance_settings.fuel_price_per_liter_credits)


func _dispense_station_fuel(requested: float) -> void:
	if not refuel_dialog.held:
		return
	var price := balance_settings.fuel_price_per_liter_credits
	var liters := clampf(requested, 0.0, _available_refuel_liters())
	var capacity := vehicle.settings.fuel_tank_capacity_liters
	var paid := liters * price
	if price > 0.0 and liters >= money_credits / price:
		paid = money_credits
	vehicle.fuel_liters = minf(capacity, vehicle.fuel_liters + liters)
	money_credits = maxf(0.0, money_credits - paid)
	refuel_dialog.record_delivery(liters, paid, money_credits, vehicle.fuel_liters >= capacity)


func _finish_station_visit(liters: float, paid: float) -> void:
	if liters <= 0.0:
		return
	prologue.refueled()
	advance_game_time(balance_settings.refuel_time_game_minutes)
	_refresh_buttons()
	status_label.text = "Заправлено %s л за %.2f кр. Время заправки — %s мин." % [
		RefuelDialog.format_liters(liters), paid, String.num(balance_settings.refuel_time_game_minutes),
	]


func _open_workshop_trade() -> void:
	if _is_trip_active():
		return
	if _place_type(current_location_id) == "store":
		store_trade.open(vehicle, money_credits, balance_settings, current_city_id, current_location_id)
	elif _is_workshop_location(current_location_id):
		workshop_trade.open(vehicle, money_credits, balance_settings, current_city_id, current_location_id)


func _open_workshop_upgrade() -> void:
	if _is_trip_active() or not _is_workshop_location(current_location_id):
		return
	workshop_upgrade.open(vehicle, money_credits, balance_settings.workshop_upgrade_cost_credits, balance_settings.vehicle_inspection_cost_credits)


func _on_trade_credits_changed(delta: float) -> void:
	money_credits += delta
	_refresh_buttons()


func _on_upgrade_accepted(cost: float) -> void:
	money_credits -= cost
	_refresh_interface()


func _can_diagnose_in_garage() -> bool:
	return (
		not _is_trip_active()
		and _place_type(current_location_id) == "garage"
	)


func _on_garage_diagnosis_pressed() -> void:
	if not _can_diagnose_in_garage() or vehicle_status_dialog.visible:
		return
	vehicle_status_dialog.open(vehicle, money_credits, false)


func _is_workshop_location(location_id: String) -> bool:
	return _place_type(location_id) == "workshop"


func _on_repair_pressed() -> void:
	if _is_trip_active() or not _is_workshop_location(current_location_id) or vehicle_status_dialog.visible:
		return
	var inspection_cost: float = balance_settings.vehicle_inspection_cost_credits
	if money_credits < inspection_cost:
		return
	money_credits -= inspection_cost
	_refresh_interface()
	vehicle_status_dialog.open(vehicle, money_credits, true)
	prologue.inspected()


func _on_part_repair_pressed(part_id: String) -> void:
	if _is_trip_active() or not _is_workshop_location(current_location_id) or not vehicle_status_dialog.visible:
		return
	var part := vehicle.get_part(part_id)
	if part == null or part.condition_percent >= 100.0:
		return
	var cost := vehicle.repair_cost(part_id)
	var minutes := vehicle.repair_time_minutes(part_id)
	if money_credits < cost:
		return
	if not await action_progress.run("Ремонт · %s" % VehicleState.PART_NAMES[part_id], minutes, vehicle_status_dialog):
		return
	if not vehicle.repair_part(part_id):
		return
	money_credits -= cost
	advance_game_time(minutes)
	_refresh_interface()
	vehicle_status_dialog.refresh(money_credits)
	status_label.text = "%s: ремонт за %.2f кр., %.2f игровых минут." % [VehicleState.PART_NAMES[part_id], cost, minutes]


# Отображение текущего состояния.
func _on_panel_toggle_pressed() -> void:
	order_panel_collapsed = not order_panel_collapsed
	_refresh_interface()


func _refresh_interface() -> void:
	var order_taken := current_order != null
	var panel_height := idle_order_height
	if order_taken:
		panel_height = collapsed_order_height if order_panel_collapsed else expanded_order_height
	if _is_workshop_location(current_location_id) and vehicle.condition_percent < 100.0:
		panel_height += workshop_extra_height
	order_panel.custom_minimum_size.y = panel_height
	order_panel.offset_bottom = order_panel.offset_top + panel_height
	order_title.visible = not order_panel_collapsed
	order_title.text = "Заказ компании" if order_taken else "Заказы компании"
	panel_toggle_button.visible = order_taken
	panel_toggle_button.text = "Развернуть заказ" if order_panel_collapsed else "Свернуть заказ"
	order_text.visible = order_taken or not order_panel_collapsed
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
				status_label.text = "Вы на автостанции. Посадите пассажиров." if current_order.is_passenger_order() else "Вы на месте сбора. Заберите груз."
			elif order_state == OrderState.TRAVELLING:
				status_label.text = "Пассажиры в машине. Проложите маршрут до высадки." if current_order.is_passenger_order() else "Груз получен. Проложите маршрут до доставки."
			elif order_state == OrderState.READY_TO_HAND_OVER:
				status_label.text = "Вы на месте назначения. Высадите пассажиров." if current_order.is_passenger_order() else "Вы на месте доставки. Сдайте заказ."
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
	if current_order.is_passenger_order():
		stage_text = "Пассажиры в машине" if current_order.passengers_picked_up else "Ожидает посадки"
		stage_text += " · %d чел." % current_order.trip_passenger_count()
	if current_order.is_urgent:
		stage_text = "Срочный · " + stage_text
	return "%s\n%s\nЗабрать: %s\nДоставить: %s\nСрок: %s\nРасстояние: %.1f км\nСтоимость: %d кр." % [
		stage_text,
		"Маршрут: %s — %s" % [current_order.pickup_city_name, current_order.delivery_city_name],
		pickup_text,
		delivery_text,
		clock.format_deadline(current_order.deadline_total_minutes),
		current_order.distance_km,
		current_order.payable_reward(),
	]


func _current_order_route() -> String:
	var prefix := "Срочный · " if current_order.is_urgent else ""
	if current_order.is_passenger_order():
		prefix += "Пассажиры: %d · " % current_order.trip_passenger_count()
	return prefix + "%s → %s" % [current_order.pickup_name, current_order.delivery_name]


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
	accept_button.disabled = not accept_button.visible or not prologue.can_handle_order()
	accept_button.text = "Забрать груз" if can_pick_up else "Сдать заказ"
	accept_button.tooltip_text = ""
	if current_order != null and current_order.is_passenger_order():
		accept_button.text = "Проверить документы" if can_pick_up else "Высадить пассажиров"
	view_orders_button.visible = (
		_place_type(current_location_id) == "company_office"
		and current_order == null
		and not _is_trip_active()
		and not order_board.visible
	)
	money_label.text = "%s кр." % String.num(money_credits, 2)
	money_label.tooltip_text = "Баланс водителя"
	_refresh_route_distance()

	var can_travel: bool = (
		not _is_trip_active()
		and route_available
		and vehicle.fuel_liters > 0.0
	)
	travel_button.visible = (
		route_available
		and not _is_trip_active()
	)
	travel_button.disabled = not can_travel or not prologue.can_travel()
	_refresh_fuel_controls()
	_refresh_vehicle_controls()


func _refresh_trip_controls() -> void:
	var active := _is_trip_active()
	var moving := active and not travel_paused
	map_view.route_editable = not moving and travel_events.active_event.is_empty()
	sleep_button.visible = _can_sleep_on_stop()
	var on_streets := local_trip.active or (not map_view.custom_path.is_empty() and is_inf(map_view.custom_path.first_highway))
	map_view.set_follow_traveling(moving, on_streets)
	inventory_button.disabled = moving
	inventory_button.tooltip_text = "Остановите автомобиль, чтобы открыть инвентарь." if moving else ""
	if moving and inventory_window.visible:
		inventory_window._close()
	var empty_tank := active and vehicle.fuel_liters <= 0.0
	if travel_paused or empty_tank:
		sheet_button.button_pressed = true
	trip_time_label.visible = active
	pause_button.visible = active and not empty_tank
	pause_button.disabled = empty_tank
	pause_button.text = "Продолжить" if travel_paused else "Остановить"
	_update_trip_clock()


func _refresh_route_distance() -> void:
	distance_group.visible = route_available and not map_view.custom_path.is_empty()
	if distance_group.visible:
		var remaining := float(map_view.custom_path.distance) * (1.0 - _current_trip_progress())
		distance_label.text = "%.1f км" % (remaining * VehicleState.TravelRules.DISTANCE_KM_PER_UNIT)


func _update_trip_clock() -> void:
	_refresh_route_distance()
	if not _is_trip_active():
		return
	var total_seconds := floori(_current_trip_elapsed())
	var minutes := total_seconds / 60
	var seconds := total_seconds % 60
	trip_time_label.text = "Время поездки: %02d:%02d" % [minutes, seconds]


func _update_game_time_label() -> void:
	game_time_label.text = clock.time_text()
	if not prologue.active():
		road_bulletins.update_at(clock.total_minutes)
		var refreshed := order_generator.refresh_offers(map_view.routes, clock.total_minutes)
		if order_board.visible:
			if refreshed:
				order_board.show_offers(order_generator.available_offers, clock, order_generator.next_refresh_minutes)
			else:
				order_board.update_clock(clock, order_generator.next_refresh_minutes)


func _on_road_bulletin_changed() -> void:
	map_view.set_road_incident(road_bulletins.road, str(road_bulletins.event.get("title", "")))
	if not _is_trip_active() and map_view.routes.road_stops.has(route_target_city_id) and route_target_city_id != map_view.incident_stop_id:
		route_available = false
		route_is_intercity = false
		route_target_city_id = ""
		route_target_location_id = ""
		map_view.clear_route()
		_refresh_buttons()
		status_label.text = "Сводка перестала действовать."
	if road_bulletins.event.is_empty():
		radio_bulletin.finish_report()
		return
	radio_bulletin.announce("Рация · %s\n%s Сводка до %s." % [
		road_bulletins.road.radio_name, road_bulletins.event.radio_message, clock.format_deadline(road_bulletins.expires_at),
	])


func _refresh_vehicle_controls() -> void:
	var can_use_workshop := _is_workshop_location(current_location_id) and not _is_trip_active()
	trade_button.visible = can_use_workshop or (_place_type(current_location_id) == "store" and not _is_trip_active())
	upgrade_button.visible = can_use_workshop
	upgrade_button.disabled = false
	garage_diagnosis_button.visible = _can_diagnose_in_garage()
	vehicle_condition_label.text = "Состояние машины: %.0f%%" % vehicle.condition_percent
	var at_workshop := (
		_is_workshop_location(current_location_id)
		and not _is_trip_active()
	)
	repair_button.visible = at_workshop
	repair_button.text = "Ремонт деталей — диагностика %.0f кр." % balance_settings.vehicle_inspection_cost_credits
	repair_button.disabled = not at_workshop or money_credits < balance_settings.vehicle_inspection_cost_credits
	hotel_sleep_button.visible = (
		_place_type(current_location_id) == "hotel"
		and not _is_trip_active()
	)
	hotel_sleep_button.disabled = not _can_sleep_at_hotel()
	hotel_meal_button.visible = hotel_sleep_button.visible
	hotel_meal_button.disabled = money_credits < balance_settings.hotel_meal_cost_credits


func _refresh_fuel_controls() -> void:
	fuel_label.text = "%.1f л" % vehicle.fuel_liters
	fuel_label.tooltip_text = "Топливо: %.1f / %.0f л" % [
		vehicle.fuel_liters,
		vehicle.settings.fuel_tank_capacity_liters,
	]
	_refresh_fatigue_controls()
	refuel_button.visible = not _is_trip_active() and _is_fuel_station_location(current_location_id)
	refuel_button.disabled = not refuel_button.visible or _available_refuel_liters() <= 0.0
	var liters := _roadside_fuel_liters()
	roadside_fuel_button.visible = liters > 0.0
	if roadside_fuel_button.visible:
		var cost := balance_settings.roadside_fuel_cost
		roadside_fuel_button.text = "Вызвать подвоз топлива\n%s л · %s кр. · %s мин" % [
			RefuelDialog.format_liters(liters), String.num(cost), String.num(balance_settings.roadside_fuel_minutes),
		]
		roadside_fuel_button.disabled = money_credits < cost
		roadside_fuel_button.tooltip_text = "Для вызова не хватает %s кр." % String.num(cost - money_credits, 2) if roadside_fuel_button.disabled else ""


func _refresh_fatigue_controls() -> void:
	fatigue_label.visible = fatigue.display_value() < 20.0
	needs_label.visible = minf(needs.satiety, needs.water) <= balance_settings.needs_low_threshold
	fatigue_label.text = "Усталость: %.0f" % fatigue.display_value()
	needs_label.text = "Сытость: %.0f\nЗапас воды: %.0f" % [needs.satiety, needs.water]


func _place_data(location_id: String) -> Dictionary:
	var city: Dictionary = map_view.routes.cities_by_id.get(current_city_id, {})
	for place in city.get("places", []):
		if place.id == location_id:
			return place
	return {}


func _place_type(location_id: String) -> String:
	return str(_place_data(location_id).get("type", ""))
