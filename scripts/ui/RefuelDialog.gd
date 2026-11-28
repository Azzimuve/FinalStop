extends Control

signal fuel_requested(liters: float)
signal finished(liters: float, cost: float)

enum Phase { DOCKED, CONNECTED }

@export_range(0.1, 60.0, 0.1, "suffix:л/с") var liters_per_second := 6.0
@onready var pick: TextureButton = %PickNozzle
@onready var supply: TextureButton = %Supply
@onready var stage: Control = %Station
@onready var holder: TextureButton = %ReturnNozzle
@onready var plunger: Polygon2D = %Plunger
@onready var balance_value: Label = %Balance
@onready var balance_refresh: Timer = %BalanceRefresh
var phase := Phase.DOCKED
var amount := 0.0
var cost := 0.0
var unit_price := 0.0
var remaining_credits := 0.0
var held := false
var station_open := false
var button_motion: Tween
var cutoff_message := ""

func _ready() -> void:
	var mask := BitMap.new()
	mask.create_from_image_alpha((%NozzleArt as Sprite2D).texture.get_image(), 0.2)
	pick.texture_click_mask = mask
	pick.pressed.connect(_connect_hose)
	holder.pressed.connect(_return_nozzle)
	supply.button_down.connect(_start_flow)
	supply.button_up.connect(_stop_flow)
	supply.focus_exited.connect(_stop_flow)
	get_window().focus_exited.connect(_stop_flow)
	%Leave.pressed.connect(close)
	balance_refresh.timeout.connect(_show_balance)
	resized.connect(_fit_station)
	visibility_changed.connect(_visibility_changed)
	set_process(false)
	_fit_station()

func _fit_station() -> void:
	var factor := minf(size.x / stage.size.x, size.y / stage.size.y)
	stage.scale = Vector2.ONE * factor
	stage.position = ((size - stage.size * factor) * 0.5).round()

func open(price: float, credits: float) -> void:
	if station_open:
		return
	station_open = true
	cutoff_message = ""
	amount = 0.0
	cost = 0.0
	unit_price = price
	%Tariff.text = "%s кр./л" % ("%.2f" % price).trim_suffix(".00").replace(".", ",")
	remaining_credits = credits
	_show_balance()
	# Резервируем место на весь визит по начальному, наибольшему остатку.
	balance_value.custom_minimum_size.x = balance_value.get_minimum_size().x + 4.0
	_update_meters()
	_update_button()
	_set_connection(false)
	show()
	_fit_station()
	pick.grab_focus()

func _set_connection(connected: bool) -> void:
	phase = Phase.CONNECTED if connected else Phase.DOCKED
	%DockedFrame.visible = not connected
	%ConnectedFrame.visible = connected
	pick.visible = not connected
	holder.visible = connected
	supply.disabled = not connected or not cutoff_message.is_empty()
	if not cutoff_message.is_empty():
		%Hint.text = cutoff_message
	elif connected:
		%Hint.text = "Удерживайте кнопку «Подача»"
	else:
		%Hint.text = "Снимите пистолет с колонки"

func _connect_hose() -> void:
	if not station_open or phase != Phase.DOCKED:
		return
	_set_connection(true)
	if supply.disabled:
		holder.grab_focus()
	else:
		supply.grab_focus()

func _return_nozzle() -> void:
	if not station_open or phase != Phase.CONNECTED:
		return
	_stop_flow()
	_set_connection(false)
	pick.grab_focus()

func _start_flow() -> void:
	if phase != Phase.CONNECTED or supply.disabled or not station_open:
		return
	held = true
	balance_refresh.start()
	%Hint.text = "Идёт заправка"
	_update_button()
	set_process(true)

func _stop_flow() -> void:
	if not held:
		return
	held = false
	balance_refresh.stop()
	_show_balance()
	set_process(false)
	_update_meters()
	_update_button()
	%Hint.text = "Подача остановлена"

func _process(delta: float) -> void:
	if not is_processing_input() or not is_visible_in_tree():
		_stop_flow()
		return
	if held:
		fuel_requested.emit(delta * liters_per_second)

func record_delivery(liters: float, paid: float, credits: float, full: bool) -> void:
	amount += liters
	cost += paid
	remaining_credits = credits
	if full or (unit_price > 0.0 and credits <= 0.0) or liters == 0.0:
		_stop_flow()
		supply.disabled = true
		cutoff_message = "Бак полон" if full else "Подача остановлена"
		if not full and credits <= 0.0:
			cutoff_message = "Деньги закончились"
		%Hint.text = cutoff_message
	_update_meters()

func _show_balance() -> void:
	balance_value.text = ("%.2f" % remaining_credits).replace(".", ",") + " кр."

func _update_meters() -> void:
	%Liters.display(amount, held)
	%Cost.display(cost, held)

func _update_button() -> void:
	%Pilot.visible = held
	plunger.self_modulate = Color.WHITE if held else Color(0.69, 0.65, 0.59)
	if button_motion:
		button_motion.kill()
	button_motion = create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	button_motion.tween_property(plunger, "position", Vector2(4, 5) if held else Vector2.ZERO, 0.08)
	button_motion.tween_property(plunger, "scale", Vector2.ONE * 0.89 if held else Vector2.ONE, 0.08)

func close() -> void:
	if station_open:
		hide()

func _visibility_changed() -> void:
	if is_visible_in_tree() or not station_open:
		return
	station_open = false
	_stop_flow()
	_set_connection(false)
	finished.emit(amount, cost)

func _input(event: InputEvent) -> void:
	if not station_open:
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_stop_flow()

func _notification(what: int) -> void:
	if what == NOTIFICATION_PAUSED and held:
		_stop_flow()

static func format_liters(liters: float) -> String:
	return "< 0,001" if liters > 0.0 and liters < 0.001 else String.num(liters, 3).replace(".", ",")
