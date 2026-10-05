extends Node
## 显示设置：窗口尺寸 + 全屏，兼管 F11。
##
## 做成 autoload 是为了两件事：
##   1. 启动时自动套用玩家上次的选择（不用每个场景各写一遍）；
##   2. F11 在任何界面都能切全屏，包括跑酷过程中。
##
## 默认 1280x720 窗口而不是 1920x1080 —— 后者的标题栏在很多笔记本上会顶出屏幕。

const RESOLUTIONS: Array[Vector2i] = [
	Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080),
]
const RES_NAMES: Array[String] = ["1280 x 720", "1600 x 900", "1920 x 1080"]
const DEFAULT_RES: int = 0

const KEY_RES: String = "resolution"
const KEY_FULL: String = "fullscreen"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	apply()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_fullscreen"):
		toggle_fullscreen()
		get_viewport().set_input_as_handled()


func res_id() -> int:
	return clampi(RunRecord.load_setting(KEY_RES, DEFAULT_RES), 0, RESOLUTIONS.size() - 1)


func set_res(i: int) -> void:
	RunRecord.save_setting(KEY_RES, clampi(i, 0, RESOLUTIONS.size() - 1))
	if not is_fullscreen():
		_apply_window()


func is_fullscreen() -> bool:
	return RunRecord.load_setting(KEY_FULL, 0) == 1


func set_fullscreen(on: bool) -> void:
	RunRecord.save_setting(KEY_FULL, 1 if on else 0)
	apply()


func toggle_fullscreen() -> void:
	set_fullscreen(not is_fullscreen())


## 把存档里的设置真正作用到窗口上
func apply() -> void:
	if is_fullscreen():
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		_apply_window()


func _apply_window() -> void:
	var size: Vector2i = RESOLUTIONS[res_id()]
	DisplayServer.window_set_size(size)
	# 居中：否则缩小窗口后它会留在屏幕右下角
	var screen: int = DisplayServer.window_get_current_screen()
	var usable: Vector2i = DisplayServer.screen_get_usable_rect(screen).size
	if usable.x <= 0 or usable.y <= 0:
		return
	DisplayServer.window_set_position((usable - size) / 2)
