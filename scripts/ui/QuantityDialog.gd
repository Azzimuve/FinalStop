extends ConfirmationDialog

func _ready() -> void:
	for button: Button in [get_ok_button(), get_cancel_button()]:
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.size_flags_stretch_ratio = 2.0


func open_slider() -> void:
	popup_centered()
	$Body/Content/Slider.grab_focus()
