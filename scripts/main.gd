extends Node2D
## 主场景装配 + 单局状态（距离 / 金币 / 记录）+ 死亡结算 + 世界坐标重定基。

## 世界像素换算成"米"的比例
const METERS_PER_PIXEL: float = 0.1

## 每收集这么多金币就播一次"哇哦"
const WOW_EVERY: int = 30

## 世界坐标重定基步长。
## 相机和所有世界物体用的是 float32 变换，坐标涨到几百万像素后像素吸附会开始抖动；
## 这里在超过一个步长时把整个世界整体平移回去。取 2 的幂保证平移量精确可表示。
const REBASE_STEP: float = 262144.0

@export_file("*.tscn") var start_menu_scene: String = "res://scenes/start_menu.tscn"
@export var spawn_point: Vector2 = Vector2(91.0, 657.0)

@onready var _player: CharacterBody2D = $Player
@onready var _camera: Camera2D = $Camera
@onready var _road: Node2D = $Road
@onready var _course: Node2D = $Course
@onready var _hud: CanvasLayer = $Hud
@onready var _game_over: CanvasLayer = $GameOver

var distance_px: float = 0.0
var coins: int = 0
var alive: bool = true

var _shown_meters: int = -1


func _ready() -> void:
	Audio.start_music()
	_course.begin(_player, spawn_point.x)
	_course.player_hit.connect(_on_player_hit)
	_course.coin_collected.connect(_on_coin_collected)
	_game_over.retry_requested.connect(retry)
	_game_over.menu_requested.connect(_go_to_menu)
	_hud.set_distance(0.0)
	_hud.set_coins(0)


func _physics_process(delta: float) -> void:
	if alive:
		_track_distance(delta)
		_course.traveled_meters = distance_px * METERS_PER_PIXEL
	# 能量条每帧跟一次：冲刺 3 秒内要从满放到空，靠信号触发反而要做插值
	_hud.set_dash(_player.dash_ratio(), int(_player.dash_state()))
	_rebase_world()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_commit_record()


func _track_distance(delta: float) -> void:
	if _player.velocity.x > 0.0:
		distance_px += _player.velocity.x * delta
	var meters: int = int(distance_px * METERS_PER_PIXEL)
	if meters == _shown_meters:
		return
	_shown_meters = meters
	_hud.set_distance(float(meters))


## 世界坐标整体平移，把玩家拉回原点附近（详见 REBASE_STEP 注释）
func _rebase_world() -> void:
	var steps: float = floorf(_player.global_position.x / REBASE_STEP)
	if steps < 1.0:
		return
	var dx: float = steps * REBASE_STEP
	_player.global_position.x -= dx
	_camera.global_position.x -= dx
	for node in [_road, _course]:
		for child in node.get_children():
			if child is Node2D:
				child.position.x -= dx


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_go_to_menu()
	elif event.is_action_pressed("restart"):
		get_viewport().set_input_as_handled()
		retry()


func _on_coin_collected() -> void:
	coins += 1
	_hud.set_coins(coins)
	# 轻微随机音高，连吃一串金币时不会像复读机
	Audio.play("coin", 0.0, randf_range(0.94, 1.08))
	if coins % WOW_EVERY == 0:
		Audio.play("wow", 3.0)


func _on_player_hit() -> void:
	if not alive:
		return
	alive = false
	_player.die()
	Audio.play("hit", 2.0)
	_commit_record()
	_game_over.show_result(distance_px * METERS_PER_PIXEL, coins)
	# 冻结整棵树；GameOver 的 process_mode = ALWAYS，仍然能响应按钮和按键
	get_tree().paused = true


## 重开一局：直接重载场景，保证路障/金币/物理状态全部干净
func retry() -> void:
	_commit_record()
	get_tree().paused = false
	get_tree().reload_current_scene()


func _go_to_menu() -> void:
	_commit_record()
	get_tree().paused = false
	get_tree().change_scene_to_file(start_menu_scene)


func _commit_record() -> void:
	RunRecord.save_best(int(distance_px * METERS_PER_PIXEL), coins)
