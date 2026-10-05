extends Control
## 开始界面。
##
## 背景直接复用游戏里的同一批视差图层（无相机时相机坐标按 0 处理，
## 只靠各层不同的 auto_speed 产生视差），所以开始界面和游戏内画面完全同源。

@export_file("*.tscn") var game_scene: String = "res://scenes/main.tscn"

## 小鸟上下浮动的幅度与频率
@export var bob_amplitude: float = 18.0
@export var bob_speed: float = 2.2

@onready var _start_button: TextureButton = $UI/Buttons/StartButton
@onready var _quit_button: TextureButton = $UI/Buttons/QuitButton
@onready var _best_distance: HBoxContainer = $UI/Best/DistanceBest/Digits
@onready var _best_coins: HBoxContainer = $UI/Best/CoinBest/Digits
@onready var _bird: AnimatedSprite2D = $World/Bird

var _bird_origin_y: float = 0.0
var _time: float = 0.0


func _ready() -> void:
	Audio.start_music()
	_bird_origin_y = _bird.position.y
	_start_button.pressed.connect(_on_start_pressed)
	_quit_button.pressed.connect(_on_quit_pressed)
	_start_button.grab_focus()
	_best_distance.set_value(RunRecord.load_best())
	_best_coins.set_value(RunRecord.load_best_coins())


func _process(delta: float) -> void:
	_time += delta
	_bird.position.y = _bird_origin_y + sin(_time * bob_speed) * bob_amplitude


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept"):
		get_viewport().set_input_as_handled()
		_on_start_pressed()


func _on_start_pressed() -> void:
	Audio.play("ui")
	get_tree().change_scene_to_file(game_scene)


func _on_quit_pressed() -> void:
	Audio.play("ui")
	get_tree().quit()
