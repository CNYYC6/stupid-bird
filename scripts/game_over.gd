extends CanvasLayer
## 撞毁后的结算面板。
##
## process_mode = ALWAYS：死亡时整棵树被 pause，这个界面仍然要能响应按钮。

signal retry_requested
signal menu_requested

@onready var _distance: HBoxContainer = $Panel/Layout/DistanceRow/Digits
@onready var _coins: HBoxContainer = $Panel/Layout/CoinRow/Digits
@onready var _retry_button: TextureButton = $Panel/Layout/Buttons/RetryButton
@onready var _menu_button: TextureButton = $Panel/Layout/Buttons/MenuButton


func _ready() -> void:
	UiLang.apply(self)
	hide()
	_retry_button.pressed.connect(func() -> void:
		Audio.play("ui")
		retry_requested.emit())
	_menu_button.pressed.connect(func() -> void:
		Audio.play("ui")
		menu_requested.emit())


func show_result(distance_meters: float, coin_count: int) -> void:
	_distance.set_value(floori(distance_meters))
	_coins.set_value(coin_count)
	show()
	_retry_button.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("restart") or event.is_action_pressed("ui_accept"):
		get_viewport().set_input_as_handled()
		Audio.play("ui")
		retry_requested.emit()
