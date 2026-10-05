extends Control
## 设置面板：语言 / 窗口模式 / 分辨率。
##
## 和换装间一个套路 —— 每组选项是"选一个"，选中的亮、没选中的压暗。
## 点下去立刻生效并写盘，不用确认按钮。

signal closed
signal changed

const ON := Color(1, 1, 1, 1)
const OFF := Color(0.45, 0.47, 0.52, 1)

@onready var _close: TextureButton = $Panel/Layout/CloseButton
@onready var _lang: Array[TextureButton] = [
	$Panel/Layout/LangRow/OptEn, $Panel/Layout/LangRow/OptZh,
]
@onready var _win: Array[TextureButton] = [
	$Panel/Layout/WinRow/OptWindowed, $Panel/Layout/WinRow/OptFullscreen,
]
@onready var _res: Array[TextureButton] = [
	$Panel/Layout/ResRow/Opt0, $Panel/Layout/ResRow/Opt1, $Panel/Layout/ResRow/Opt2,
]


func _ready() -> void:
	hide()
	for i in _lang.size():
		_lang[i].pressed.connect(_on_lang.bind(i))
	for i in _win.size():
		_win[i].pressed.connect(_on_win.bind(i))
	for i in _res.size():
		_res[i].pressed.connect(_on_res.bind(i))
	_close.pressed.connect(_on_close)


func open() -> void:
	_refresh()
	show()
	_lang[0].grab_focus()


func _on_lang(i: int) -> void:
	Audio.play("ui")
	UiLang.set_lang(i)
	# 换语言要把整棵界面树重刷一遍（文字是烘在贴图里的）
	UiLang.apply(get_tree().current_scene)
	_refresh()
	changed.emit()


func _on_win(i: int) -> void:
	Audio.play("ui")
	Screen.set_fullscreen(i == 1)
	_refresh()
	changed.emit()


func _on_res(i: int) -> void:
	Audio.play("ui")
	Screen.set_res(i)
	_refresh()
	changed.emit()


func _on_close() -> void:
	Audio.play("ui")
	hide()
	closed.emit()


func _refresh() -> void:
	var lang: int = UiLang.lang_id()
	for i in _lang.size():
		_lang[i].modulate = ON if i == lang else OFF
	var full: int = 1 if Screen.is_fullscreen() else 0
	for i in _win.size():
		_win[i].modulate = ON if i == full else OFF
	# 全屏时改分辨率没有意义（画面会被拉伸到屏幕），压暗并禁用
	var res: int = Screen.res_id()
	for i in _res.size():
		_res[i].modulate = (ON if i == res else OFF) if full == 0 else OFF
		_res[i].disabled = full == 1


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_on_close()
