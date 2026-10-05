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
@onready var _mode_button: TextureButton = $UI/Buttons/BottomRow/ModeButton
@onready var _dress_button: TextureButton = $UI/Buttons/BottomRow/DressButton
@onready var _dressup: Control = $Overlay/Dressup

## 每种模式对应的一整套按钮贴图（normal / hover / pressed）
const MODE_TEX: Array[Array] = [
	["res://art/ui_btn_solo.png", "res://art/ui_btn_solo_hover.png",
	 "res://art/ui_btn_solo_pressed.png"],
	["res://art/ui_btn_coop.png", "res://art/ui_btn_coop_hover.png",
	 "res://art/ui_btn_coop_pressed.png"],
]

## 0 = 单人闯关，1 = 双人合作
var _mode: int = 0


func _ready() -> void:
	Audio.start_music()
	_start_button.pressed.connect(_on_start_pressed)
	_quit_button.pressed.connect(_on_quit_pressed)
	_mode = RunRecord.load_mode()
	_refresh_mode()
	_mode_button.pressed.connect(_on_mode_pressed)
	_dress_button.pressed.connect(_on_dress_pressed)
	_dressup.closed.connect(func() -> void: _start_button.grab_focus())
	_start_button.grab_focus()
	_best_distance.set_value(RunRecord.load_best())
	_best_coins.set_value(RunRecord.load_best_coins())


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept"):
		get_viewport().set_input_as_handled()
		_on_start_pressed()


## 切换单人 / 双人，立刻写盘，下一局主场景直接按这个模式摆人
func _on_mode_pressed() -> void:
	Audio.play("ui")
	_mode = 1 - _mode
	RunRecord.save_mode(_mode)
	_refresh_mode()


## 打开换装间。菜单背景里那 25 只小鸟不跟着换 —— 它们只是氛围，
## 真正的换装效果在开局之后才看得到（免得每点一下就要重建 25 份贴图）。
func _on_dress_pressed() -> void:
	Audio.play("ui")
	_dressup.open()


func _refresh_mode() -> void:
	var set: Array = MODE_TEX[_mode]
	_mode_button.texture_normal = load(set[0])
	_mode_button.texture_hover = load(set[1])
	_mode_button.texture_pressed = load(set[2])


func _on_start_pressed() -> void:
	Audio.play("ui")
	get_tree().change_scene_to_file(game_scene)


func _on_quit_pressed() -> void:
	Audio.play("ui")
	get_tree().quit()
