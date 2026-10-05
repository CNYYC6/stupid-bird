extends Control
## 开始界面。
##
## 背景直接复用游戏里的同一批视差图层（无相机时相机坐标按 0 处理，
## 只靠各层不同的 auto_speed 产生视差），所以开始界面和游戏内画面完全同源。
##
## 画面里的活物交给 `menu_birds.gd`：25 只无动力刚体小鸟从天而降，
## 在会上下往复的地面上互相碰撞翻滚。这里原本那只「上下浮动」的装饰鸟已经删掉了——
## 一个匀速正弦来回的贴图，比一群真在撞的东西要假得多。

@export_file("*.tscn") var game_scene: String = "res://scenes/main.tscn"

@onready var _start_button: TextureButton = $UI/Buttons/StartButton
@onready var _quit_button: TextureButton = $UI/Buttons/BottomRow/QuitButton
@onready var _best_distance: HBoxContainer = $UI/Best/DistanceBest/Digits
@onready var _best_coins: HBoxContainer = $UI/Best/CoinBest/Digits
@onready var _mode_button: TextureButton = $UI/Buttons/TopRow/ModeButton
@onready var _level_button: TextureButton = $UI/Buttons/TopRow/LevelButton
@onready var _dress_button: TextureButton = $UI/Buttons/BottomRow/DressButton
@onready var _settings_button: TextureButton = $UI/Buttons/BottomRow/SettingsButton
@onready var _settings: Control = $Overlay/Settings
@onready var _dressup: Control = $Overlay/Dressup

## 每种模式对应的一整套按钮贴图（normal / hover / pressed）
const MODE_TEX: Array[Array] = [
	["res://art/ui/en/ui_btn_solo.png", "res://art/ui/en/ui_btn_solo_hover.png",
	 "res://art/ui/en/ui_btn_solo_pressed.png"],
	["res://art/ui/en/ui_btn_coop.png", "res://art/ui/en/ui_btn_coop_hover.png",
	 "res://art/ui/en/ui_btn_coop_pressed.png"],
	["res://art/ui/en/ui_btn_bot.png", "res://art/ui/en/ui_btn_bot_hover.png",
	 "res://art/ui/en/ui_btn_bot_pressed.png"],
]
## 机哥的三档难度
const LEVEL_TEX: Array[Array] = [
	["res://art/ui/en/ui_btn_lv0.png", "res://art/ui/en/ui_btn_lv0_hover.png",
	 "res://art/ui/en/ui_btn_lv0_pressed.png"],
	["res://art/ui/en/ui_btn_lv1.png", "res://art/ui/en/ui_btn_lv1_hover.png",
	 "res://art/ui/en/ui_btn_lv1_pressed.png"],
	["res://art/ui/en/ui_btn_lv2.png", "res://art/ui/en/ui_btn_lv2_hover.png",
	 "res://art/ui/en/ui_btn_lv2_pressed.png"],
]

## 0 = 单人闯关，1 = 双人合作，2 = 机哥带你飞
var _mode: int = 0
## 机哥模式的难度
var _level: int = 1


func _ready() -> void:
	# 进场先按当前语言把整棵界面树（含换装间和设置面板）刷一遍
	UiLang.apply(self)
	Audio.start_music()
	_start_button.pressed.connect(_on_start_pressed)
	_quit_button.pressed.connect(_on_quit_pressed)
	# 每次启动都从「单人闯关」开始：模式不跨启动记忆。
	# 难度和换装仍然记着 —— 那两个是"口味"，模式是"这一局想怎么玩"。
	_mode = 0
	RunRecord.save_mode(_mode)
	_level = RunRecord.load_bot_level()
	_refresh_mode()
	_mode_button.pressed.connect(_on_mode_pressed)
	_level_button.pressed.connect(_on_level_pressed)
	_dress_button.pressed.connect(_on_dress_pressed)
	_settings_button.pressed.connect(_on_settings_pressed)
	_settings.closed.connect(_start_button.grab_focus)
	# 换了语言，模式/难度按钮上的文字也要跟着重刷（它们是代码赋的贴图）
	_settings.changed.connect(_refresh_mode)
	_dressup.closed.connect(func() -> void: _start_button.grab_focus())
	_start_button.grab_focus()
	_best_distance.set_value(RunRecord.load_best())
	_best_coins.set_value(RunRecord.load_best_coins())


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept"):
		get_viewport().set_input_as_handled()
		_on_start_pressed()


## 单人 -> 双人 -> 机哥 -> 单人，立刻写盘，下一局主场景直接按这个模式摆人
func _on_mode_pressed() -> void:
	Audio.play("ui")
	_mode = (_mode + 1) % MODE_TEX.size()
	RunRecord.save_mode(_mode)
	_refresh_mode()


## 机哥模式才有意义的三档难度。其它模式下按钮留着但压暗禁用，
## 这样按钮行的宽度不会跳来跳去。
func _on_level_pressed() -> void:
	Audio.play("ui")
	_level = (_level + 1) % LEVEL_TEX.size()
	RunRecord.save_bot_level(_level)
	_refresh_mode()


## 打开换装间。菜单背景里那 25 只小鸟不跟着换 —— 它们只是氛围，
## 真正的换装效果在开局之后才看得到（免得每点一下就要重建 25 份贴图）。
func _on_dress_pressed() -> void:
	Audio.play("ui")
	_dressup.open()


func _refresh_mode() -> void:
	var set: Array = MODE_TEX[_mode]
	_mode_button.texture_normal = load(UiLang.swap_path(set[0], UiLang.code()))
	_mode_button.texture_hover = load(UiLang.swap_path(set[1], UiLang.code()))
	_mode_button.texture_pressed = load(UiLang.swap_path(set[2], UiLang.code()))
	var lv: Array = LEVEL_TEX[_level]
	_level_button.texture_normal = load(UiLang.swap_path(lv[0], UiLang.code()))
	_level_button.texture_hover = load(UiLang.swap_path(lv[1], UiLang.code()))
	_level_button.texture_pressed = load(UiLang.swap_path(lv[2], UiLang.code()))
	var is_bot: bool = _mode == 2
	_level_button.disabled = not is_bot
	_level_button.modulate = Color(1, 1, 1, 1) if is_bot else Color(0.55, 0.55, 0.6, 1)


func _on_settings_pressed() -> void:
	Audio.play("ui")
	_settings.open()


func _on_start_pressed() -> void:
	Audio.play("ui")
	get_tree().change_scene_to_file(game_scene)


func _on_quit_pressed() -> void:
	Audio.play("ui")
	get_tree().quit()
