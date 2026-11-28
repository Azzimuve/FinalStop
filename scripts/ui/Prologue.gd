extends PanelContainer

const Order = preload("res://scripts/orders/DeliveryOrder.gd")
const Box = preload("res://resources/items/test_crate.tres")
const COMPANY := "company_city"
const NEAR := "nearby_settlement"
const NORTH := "northern_settlement"
enum Step { OFFICE, LOAD, FUEL, DELIVERY, SHOP, SECOND_ORDER, BOARD, DROPOFF, INSPECT, REPORT, CHOICE, OFFER, RETURN, AGENCY, FREE }
const TARGETS := {
	Step.OFFICE: [COMPANY, "company_office"], Step.LOAD: [COMPANY, "company_depot"],
	Step.FUEL: [COMPANY, "company_fuel_station"], Step.DELIVERY: [NEAR, "settlement_delivery"],
	Step.SHOP: [NEAR, "settlement_shop"], Step.SECOND_ORDER: [COMPANY, "company_office"],
	Step.BOARD: [COMPANY, "company_station"], Step.DROPOFF: [NORTH, "north_busstop"],
	Step.INSPECT: [NORTH, "northern_settlement_workshop"], Step.RETURN: [COMPANY, "company_garage"]
}

@export var radio_lines: Dictionary[String, String]
## Сюжетный досмотр на въезде в Соседний посёлок в первом грузовом рейсе.
@export var checkpoint_event: Dictionary
## Через сколько секунд свернуть журнал после обучения. Разговор по рации закрывает игрок.
@export_range(2.0, 30.0, 0.5, "suffix:с") var reading_seconds := 8.0
@export_group("Условия смены")
@export var advance_credits := 600
@export_range(1, 100) var initial_condition := 34
@export_range(0.1, 0.9) var fuel_fraction := 0.55
@export_range(1, 1440) var return_minutes := 120
@export var company_price := 1800
@export_range(1, 365) var deferred_days := 7
@export var agency_price := 3600
@export_range(1, 48) var installments := 6
@export_range(1, 365) var installment_days := 30
@export var agency_vehicle: PackedScene = preload("res://scenes/vehicle/Vehicle.tscn")

var game
var last_radio_step := -1
var reading_left := 0.0
var owns_reading_pause := false
var was_traveling := false
@onready var radio_home := get_parent()
@onready var recall: Button = $"../RadioRecall"
@onready var dismiss: Button = $Row/Text/Actions/Dismiss
var step := Step.OFFICE
var incident_seen := false
var checkpoint_cleared := false
var repair_quote := 0.0
var deadline := 0.0
var ownership := "company"
var balance_due := 0
var next_payment := 0.0
var payment_size := 0
var pack
var highlight: Control
var original_color := Color.WHITE
var offer: Order
@onready var first: Button = $Row/Text/Actions/First
@onready var second: Button = $Row/Text/Actions/Second
@onready var line: Label = $Row/Text/Line

func start(main) -> void:
	game = main
	game.current_city_id = COMPANY
	game.current_location_id = "company_garage"
	game.money_credits = advance_credits
	game.vehicle.fuel_liters = game.vehicle.settings.fuel_tank_capacity_liters * fuel_fraction
	for slot in game.vehicle.PART_NAMES:
		var part = game.vehicle.get_part(slot)
		if part:
			part.condition_percent = initial_condition
	recall.pressed.connect(_open_radio)
	dismiss.pressed.connect(_close_radio)
	first.pressed.connect(_first)
	second.pressed.connect(_second)
	game.store_trade.interaction.transferred.connect(_trade)
	game.order_board.visibility_changed.connect(_on_board_visibility_changed)
	game.passenger_desk.visibility_changed.connect(_on_passenger_desk_visibility_changed)
	visibility_changed.connect(_sync_reading_pause)
	_refresh()

func active() -> bool:
	return step != Step.FREE

func _at(target: Array) -> bool:
	return not game._is_trip_active() and game.current_city_id == target[0] and game.current_location_id == target[1]

func can_travel() -> bool:
	return step not in [Step.AGENCY, Step.CHOICE, Step.OFFER, Step.REPORT]

func can_handle_order() -> bool:
	if not active():
		return true
	return step in [Step.LOAD, Step.DELIVERY, Step.BOARD, Step.DROPOFF]

func open_orders() -> void:
	if step not in [Step.OFFICE, Step.SECOND_ORDER] or not _at(TARGETS[step]):
		return
	if not offer:
		var passenger := step == Step.SECOND_ORDER
		var start: Array = TARGETS[Step.BOARD if passenger else Step.LOAD]
		var end: Array = TARGETS[Step.DROPOFF if passenger else Step.DELIVERY]
		offer = Order.new()
		var cities: Dictionary = game.map_view.routes.cities_by_id
		offer.pickup_city_id = start[0]
		offer.pickup_location_id = start[1]
		offer.pickup_city_name = cities[start[0]].name
		offer.delivery_city_id = end[0]
		offer.delivery_location_id = end[1]
		offer.delivery_city_name = cities[end[0]].name
		for place in cities[start[0]].places:
			if place.id == start[1]:
				offer.pickup_name = place.name
		for place in cities[end[0]].places:
			if place.id == end[1]:
				offer.delivery_name = place.name
		offer.passenger_count = int(passenger)
		if not passenger:
			var parcel = Box.duplicate(true)
			parcel.title = "Коробка по накладной"
			offer.cargo.append(parcel)
		offer.passenger_name = "Илья Серов" if passenger else ""
		offer.title = "Пассажир: Илья Серов" if passenger else "Коробка для Соседнего посёлка"
		offer.distance_km = game.map_view.routes.get_route_distance(start[0], start[1], end[0], end[1]) * game.vehicle.TravelRules.DISTANCE_KM_PER_UNIT
		offer.reward = roundi(offer.distance_km / game.vehicle.TravelRules.DISTANCE_KM_PER_UNIT / 100.0 * game.balance_settings.order_payment_per_100_distance_units)
		offer.deadline_total_minutes = game.clock.total_minutes + 300
	var orders: Array[Order] = [offer]
	game.order_board.show_offers(orders, game.clock)

func _on_board_visibility_changed() -> void:
	if game.order_board.visible and offer != null:
		# Основной HUD скрыт модальным окном. Переносим ту же рацию к карточке.
		game.order_board.radio_space.show()
		game.order_board.process_mode = Node.PROCESS_MODE_ALWAYS
		_move_radio_to(game.order_board.radio_space)
		_open_radio()
	elif get_parent() == game.order_board.radio_space:
		game.order_board.process_mode = Node.PROCESS_MODE_INHERIT
		_move_radio_to(radio_home)
		game.order_board.radio_space.hide()
		_close_radio()

func remind_to_recheck_passenger() -> void:
	_move_radio_to(game.passenger_desk)
	_refresh()
	_open_radio()

func _on_passenger_desk_visibility_changed() -> void:
	if not game.passenger_desk.visible and get_parent() == game.passenger_desk:
		_move_radio_to(radio_home)
		_close_radio()

func _move_radio_to(parent: Control) -> void:
	if get_parent() != parent:
		reparent(parent, false)
		recall.reparent(parent, false)

func order_accepted(order: Order) -> void:
	if offer != null and order == offer:
		step = Step.BOARD if order.is_passenger_order() else Step.LOAD
		offer = null

func order_delivered(order: Order) -> void:
	if step == Step.DROPOFF and order.is_passenger_order():
		step = Step.INSPECT
	elif step == Step.DELIVERY and not order.is_passenger_order():
		step = Step.SHOP

func refueled() -> void:
	if step == Step.FUEL and _at(TARGETS[step]):
		step = Step.DELIVERY

func trigger_incident(phase) -> bool:
	if step != Step.DELIVERY or incident_seen or phase != game.intercity_trip or phase.progress < 0.18:
		return false
	incident_seen = true
	game.travel_events.active_event = {
		"title": "Осыпь на дороге", "description": "Щебень закрыл полосу. Навстречу идёт грузовик.",
		"actions": [
			{"text":"Подождать встречный · 5 мин", "minutes":5, "outcomes":[{"text":"Грузовик прошёл. Вы объехали щебень по свободной полосе."}]},
			{"text":"Проехать по краю · износ колеса", "outcomes":[{"text":"Коробка цела. На правой передней шине остался порез.", "wheel_wear":2.0}]}
		]}
	game.travel_events.resolved = false
	return true

func expects_entry_inspection() -> bool:
	return step == Step.DELIVERY and not checkpoint_cleared

func begin_entry_inspection() -> bool:
	if not expects_entry_inspection():
		return false
	game.travel_events.active_event = checkpoint_event
	game.travel_events.resolved = false
	return true

func travel_event_finished(event: Dictionary) -> void:
	if step == Step.DELIVERY and is_same(event, checkpoint_event):
		checkpoint_cleared = true
		_refresh()
		_open_radio()

func _trade(item, buying: bool) -> void:
	if buying and item.item_id == "cigarettes" and step == Step.SHOP and _at(TARGETS[step]):
		pack = item
		step = Step.SECOND_ORDER

func inspected() -> void:
	if step == Step.INSPECT and _at(TARGETS[step]):
		repair_quote = 0.0
		for slot in game.vehicle.PART_NAMES:
			repair_quote += game.vehicle.repair_cost(slot)
		step = Step.REPORT

func _process(delta: float) -> void:
	if game == null or game.action_progress.visible or (get_tree().paused and not owns_reading_pause):
		return
	if step == Step.LOAD and game.current_order and game.order_state == game.OrderState.TRAVELLING:
		step = Step.FUEL
	elif step == Step.BOARD and game.current_order and game.current_order.passengers_picked_up:
		step = Step.DROPOFF
	elif step == Step.REPORT and not game.vehicle_status_dialog.visible:
		deadline = game.clock.total_minutes + return_minutes
		step = Step.CHOICE
	if step in [Step.CHOICE,Step.OFFER,Step.RETURN]:
		if game.clock.total_minutes > deadline:
			ownership = "stolen"
			step = Step.FREE
		elif step == Step.RETURN and _at(TARGETS[Step.RETURN]):
			hand_back()
	_refresh()
	if not active() and is_visible_in_tree():
		reading_left -= delta
		if reading_left <= 0.0:
			_close_radio()

func _open_radio() -> void:
	reading_left = reading_seconds
	show()
	recall.hide()
	_sync_reading_pause()
	if owns_reading_pause:
		_focus_radio_action.call_deferred()

func _close_radio() -> void:
	hide()
	recall.show()

func _sync_reading_pause() -> void:
	if not is_inside_tree():
		return
	var tree := get_tree()
	if active() and is_visible_in_tree():
		if not tree.paused:
			owns_reading_pause = true
			tree.paused = true
	elif owns_reading_pause:
		owns_reading_pause = false
		tree.paused = false

func _focus_radio_action() -> void:
	if owns_reading_pause and is_visible_in_tree():
		(dismiss if dismiss.visible else first).grab_focus()

func _exit_tree() -> void:
	if owns_reading_pause:
		owns_reading_pause = false
		get_tree().paused = false

func hand_back() -> void:
	ownership = "returned"
	if pack and game.vehicle.inventory.contains(pack):
		game.vehicle.inventory.remove(pack)
		game.money_credits += pack.price_credits
		game._refresh_buttons()
	step = Step.AGENCY

func _refresh() -> void:
	var target: Array = TARGETS.get(step, [])
	var at := not target.is_empty() and _at(target)
	var action: Control = null
	var buttons: Array[String] = []
	var message := ""
	match step:
		Step.OFFICE:
			message = radio_lines["OFFICE"]
			action = game.view_orders_button
		Step.LOAD:
			message = radio_lines["LOAD"]
			action = game.accept_button
		Step.FUEL:
			message = radio_lines["FUEL"]
			action = game.refuel_button
		Step.DELIVERY:
			message = radio_lines["AFTER_CHECKPOINT" if checkpoint_cleared else "DELIVERY"]
			action = game.accept_button
		Step.SHOP:
			message = radio_lines["SHOP"]
			action = game.trade_button
		Step.SECOND_ORDER:
			message = radio_lines["SECOND_ORDER"]
			action = game.view_orders_button
		Step.BOARD:
			message = radio_lines["RECHECK_PASSENGER"] if get_parent() == game.passenger_desk else radio_lines["BOARD"]
			action = game.accept_button
		Step.DROPOFF:
			message = radio_lines["DROPOFF"]
			action = game.accept_button
		Step.INSPECT, Step.REPORT:
			message = radio_lines["INSPECT"]
			action = game.repair_button
		Step.CHOICE:
			message = radio_lines["CHOICE"] % [repair_quote, game.clock.format_deadline(deadline)]
			buttons.assign(["Промолчать", "А если я её выкуплю?"])
		Step.OFFER:
			message = radio_lines["OFFER"] % [company_price,deferred_days]
			buttons.assign(["Подписать договор", "Вернуть машину"])
		Step.RETURN:
			message = radio_lines["RETURN"] % game.clock.format_deadline(deadline)
		Step.AGENCY:
			message = radio_lines["AGENCY"] % [agency_price, ceili(float(agency_price)/installments), installment_days, game.clock.format_deadline(game.clock.total_minutes + installment_days*1440)]
			buttons.assign(["Оформить кредит и забрать Урал"])
		Step.FREE:
			message = "Компания объявила машину в розыск." if ownership == "stolen" else "Автомобиль в твоей собственности."
			if balance_due > 0:
				message += " Долг %d кр. Очередной платёж %d кр. к %s." % [balance_due, mini(payment_size,balance_due), game.clock.format_deadline(next_payment)]
				buttons.assign(["Внести платёж"])
			else:
				buttons.assign(["Закрыть"])
	var navigate: bool = not target.is_empty() and not at and not game._is_trip_active()
	if navigate:
		buttons.assign(["Показать на карте"])
		action = game.travel_button if game.route_available and game.route_target_city_id == target[0] and game.route_target_location_id == target[1] else null
	elif not at:
		action = null
	if game.inventory_window.visible and step == Step.LOAD:
		action = game.inventory_window.close_button if game.inventory_window.warehouse.placements.is_empty() else game.inventory_window.auto_button
	if step in [Step.OFFICE, Step.SECOND_ORDER] and offer != null and game.order_board.visible:
		if game.order_board.waybill != null and game.order_board.waybill.order == offer:
			action = game.order_board.choose_button
		if offer.is_passenger_order():
			message = radio_lines["PASSENGER_OFFER"] % [offer.passenger_name, offer.reward]
		else:
			message = radio_lines["CARGO_OFFER"] % [offer.reward, game.clock.format_deadline(offer.deadline_total_minutes)]
	var needs_answer: bool = step in [Step.CHOICE, Step.OFFER, Step.AGENCY]
	dismiss.visible = not needs_answer
	dismiss.text = "Продолжить" if active() else "Свернуть"
	recall.text = "Журнал" if step == Step.FREE else "Рация"
	if step == Step.RETURN:
		recall.text = "Рация · до %s" % game.clock.format_deadline(deadline)
	_mark(action)
	game.map_view.guide_to(target[0] if navigate else "", target[1] if navigate else "")
	line.text = message
	$Row/Text/Speaker.text = "Агентство · рация" if step == Step.AGENCY else ("Журнал водителя" if step == Step.FREE else "Босс · рация")
	$Row/Portrait.visible = step != Step.FREE
	$Row/Portrait/Boss.visible = step != Step.AGENCY
	$Row/Portrait/Agency.visible = step == Step.AGENCY
	first.visible = buttons.size() > 0
	second.visible = buttons.size() > 1
	if first.visible:
		first.text = buttons[0]
		first.disabled = step == Step.FREE and balance_due > 0 and game.money_credits < mini(payment_size,balance_due)
	if second.visible:
		second.text = buttons[1]
	var traveling: bool = game._is_trip_active()
	if step != last_radio_step:
		last_radio_step = step
		_open_radio()
	elif not active() and traveling and not was_traveling:
		_close_radio()
	was_traveling = traveling

func _mark(control: Control) -> void:
	if is_instance_valid(highlight) and highlight == control:
		return
	if is_instance_valid(highlight):
		highlight.self_modulate = original_color
	highlight = control
	if control:
		original_color = control.self_modulate
		control.self_modulate = Color(1.0, 0.83, 0.36)

func _first() -> void:
	match step:
		Step.CHOICE: step = Step.RETURN
		Step.OFFER:
			ownership = "purchased"
			balance_due = company_price
			payment_size = balance_due
			next_payment = game.clock.total_minutes + deferred_days*1440
			step = Step.FREE
		Step.AGENCY:
			var old = game.vehicle
			var replacement = agency_vehicle.instantiate()
			var parent = old.get_parent()
			old.name = "ReturnedVehicle"
			parent.add_child(replacement)
			replacement.name = "Vehicle"
			replacement.position = old.position
			replacement.inventory = old.inventory
			game.vehicle = replacement
			game.map_view.vehicle = replacement
			old.queue_free()
			ownership = "agency_credit"
			balance_due = agency_price
			payment_size = ceili(float(agency_price)/installments)
			next_payment = game.clock.total_minutes + installment_days*1440
			step = Step.FREE
			game.map_view._refresh_visuals()
			game._refresh_interface()
		Step.FREE:
			if balance_due == 0:
				recall.hide()
				hide()
				set_process(false)
				return
			var amount := mini(payment_size, balance_due)
			if game.money_credits >= amount:
				game.money_credits -= amount
				balance_due -= amount
				next_payment += installment_days*1440
				game._refresh_buttons()
		_:
			var target: Array = TARGETS.get(step, [])
			if not target.is_empty():
				game.map_view._focus_city(target[0])
				_close_radio()
	_refresh()

func _second() -> void:
	if step == Step.CHOICE:
		step = Step.OFFER
	elif step == Step.OFFER:
		step = Step.RETURN
	_refresh()
