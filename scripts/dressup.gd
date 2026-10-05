extends Control
## 换装间：全屏浮层，两名玩家**分开**编辑各自的飞行器和驾驶员。
##
## 方块是运行期生成的 —— 12 个 TextureButton 手写进 .tscn 又长又难改，
## 而 Skins 里已经有一张表，直接照着表铺就行，以后加飞机只改那张表。
##
## 存档键按玩家号分：aircraft1/pilot1 与 aircraft2/pilot2。
## 两个人可以选同一架飞机，也可以完全不同。

signal closed

const DIM_BG := Color(0.03, 0.05, 0.09, 0.72)
const SELECTED := Color(1, 1, 1, 1)
const UNSELECTED := Color(0.45, 0.47, 0.52, 1)
const TAB_ON := Color(1, 1, 1, 1)
const TAB_OFF := Color(0.55, 0.57, 0.62, 1)

@onready var _air_row: HBoxContainer = $Panel/Layout/AirRow
@onready var _pilot_row: HBoxContainer = $Panel/Layout/PilotRow
@onready var _close: TextureButton = $Panel/Layout/CloseButton
@onready var _tab_p1: TextureButton = $Panel/Layout/PlayerRow/P1
@onready var _tab_p2: TextureButton = $Panel/Layout/PlayerRow/P2

## 正在编辑几号机（0 = P1，1 = P2）
var editing: int = 0
## 两名玩家各自的选择
var _air: Array[int] = [0, 1]
var _pilot: Array[int] = [0, 0]

var _air_buttons: Array[TextureButton] = []
var _pilot_buttons: Array[TextureButton] = []


func _ready() -> void:
	hide()
	_build(_air_row, "bird", Skins.AIRCRAFT.size(), _air_buttons, _on_aircraft)
	_build(_pilot_row, "pilot", Skins.PILOTS.size(), _pilot_buttons, _on_pilot)
	_close.pressed.connect(_on_close)
	_tab_p1.pressed.connect(_on_pick_player.bind(0))
	_tab_p2.pressed.connect(_on_pick_player.bind(1))


func _build(row: HBoxContainer, kind: String, count: int,
		into: Array[TextureButton], handler: Callable) -> void:
	for i in count:
		var b := TextureButton.new()
		b.texture_normal = load(Skins.preview_path(kind, i))
		b.stretch_mode = TextureButton.STRETCH_KEEP_CENTERED
		b.pressed.connect(handler.bind(i))
		row.add_child(b)
		into.append(b)


## 打开浮层：从存档把两个人的选择都读出来
func open() -> void:
	for i in 2:
		_air[i] = Skins.clamp_aircraft(
				RunRecord.load_setting("aircraft%d" % (i + 1), Skins.default_for(i)))
		_pilot[i] = Skins.clamp_pilot(RunRecord.load_setting("pilot%d" % (i + 1), 0))
	editing = 0
	_refresh()
	show()
	_close.grab_focus()


## 当前预览用的选择（主菜单拿它去显示）
func selection(player: int) -> Vector2i:
	return Vector2i(_air[clampi(player, 0, 1)], _pilot[clampi(player, 0, 1)])


func _on_pick_player(i: int) -> void:
	Audio.play("ui")
	editing = i
	_refresh()


func _on_aircraft(i: int) -> void:
	Audio.play("ui")
	_air[editing] = i
	_store()
	_refresh()


func _on_pilot(i: int) -> void:
	Audio.play("ui")
	_pilot[editing] = i
	_store()
	_refresh()


## 每次点选立刻写盘，退出游戏也不会丢
func _store() -> void:
	RunRecord.save_setting("aircraft%d" % (editing + 1), _air[editing])
	RunRecord.save_setting("pilot%d" % (editing + 1), _pilot[editing])


func _on_close() -> void:
	Audio.play("ui")
	hide()
	closed.emit()


func _refresh() -> void:
	_tab_p1.modulate = TAB_ON if editing == 0 else TAB_OFF
	_tab_p2.modulate = TAB_ON if editing == 1 else TAB_OFF
	for i in _air_buttons.size():
		_air_buttons[i].modulate = SELECTED if i == _air[editing] else UNSELECTED
	for i in _pilot_buttons.size():
		_pilot_buttons[i].modulate = SELECTED if i == _pilot[editing] else UNSELECTED


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_on_close()
