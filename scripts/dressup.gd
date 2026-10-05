extends Control
## 换装间：全屏浮层，两排可点方块（飞行器 / 驾驶员）。
##
## 方块是运行期生成的 —— 12 个 TextureButton 手写进 .tscn 又长又难改，
## 而 Skins 里已经有一张表，直接照着表铺就行，以后加飞机只改那张表。

signal closed
signal skin_changed(aircraft: int, pilot: int)

const DIM_BG := Color(0.03, 0.05, 0.09, 0.72)
const SELECTED := Color(1, 1, 1, 1)
const UNSELECTED := Color(0.45, 0.47, 0.52, 1)

@onready var _air_row: HBoxContainer = $Panel/Layout/AirRow
@onready var _pilot_row: HBoxContainer = $Panel/Layout/PilotRow
@onready var _close: TextureButton = $Panel/Layout/CloseButton

var aircraft: int = 0
var pilot: int = 0

var _air_buttons: Array[TextureButton] = []
var _pilot_buttons: Array[TextureButton] = []


func _ready() -> void:
	hide()
	_build(_air_row, "bird", Skins.AIRCRAFT.size(), _air_buttons, _on_aircraft)
	_build(_pilot_row, "pilot", Skins.PILOTS.size(), _pilot_buttons, _on_pilot)
	_close.pressed.connect(_on_close)


func _build(row: HBoxContainer, kind: String, count: int,
		into: Array[TextureButton], handler: Callable) -> void:
	for i in count:
		var b := TextureButton.new()
		b.texture_normal = load(Skins.preview_path(kind, i))
		b.stretch_mode = TextureButton.STRETCH_KEEP_CENTERED
		b.pressed.connect(handler.bind(i))
		row.add_child(b)
		into.append(b)


## 打开浮层时同步一次当前选择
func open(a: int, p: int) -> void:
	aircraft = Skins.clamp_aircraft(a)
	pilot = Skins.clamp_pilot(p)
	_refresh()
	show()
	_close.grab_focus()


func _on_aircraft(i: int) -> void:
	Audio.play("ui")
	aircraft = i
	_refresh()
	skin_changed.emit(aircraft, pilot)


func _on_pilot(i: int) -> void:
	Audio.play("ui")
	pilot = i
	_refresh()
	skin_changed.emit(aircraft, pilot)


func _on_close() -> void:
	Audio.play("ui")
	hide()
	closed.emit()


func _refresh() -> void:
	for i in _air_buttons.size():
		_air_buttons[i].modulate = SELECTED if i == aircraft else UNSELECTED
	for i in _pilot_buttons.size():
		_pilot_buttons[i].modulate = SELECTED if i == pilot else UNSELECTED


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_on_close()
