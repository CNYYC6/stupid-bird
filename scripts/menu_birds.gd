extends Node2D
## 开始界面的「小鸟雨」。
##
## 25 只无动力刚体小鸟从画面之上自由落体，砸到一块**会上下往复的碰撞地面**上。
## 地面每半个周期就把动能重新灌回系统，小鸟之间又是带弹性的碰撞，
## 所以整群鸟会长期维持在无规则的上下左右翻滚状态，不会慢慢瘫成一堆。
##
## 视觉地面和碰撞地面必须是同一条线，否则会出现「鸟停在半空」或「鸟陷进土里」。
## gen_ground_layers 里那三层（山腰 / 树线 / 地面）用同一个 y_offset 跟着推，
## 因为地面贴图只有 100 像素的下沉余量，单独动地面会露出天空。

const BIRD_SCENE: PackedScene = preload("res://scenes/menu_bird.tscn")

## 分组里挂的是要跟着地面一起上下动的视差图层
const GROUND_GROUP: StringName = &"menu_ground"

@export var bird_count: int = 25

@export_group("地面")
## 碰撞地面的世界 y（= 视觉地面层的顶边）
@export var floor_y: float = 700.0
@export var floor_amplitude: float = 90.0
@export var floor_period: float = 1.25

@export_group("出生")
## 出生高度范围：都在画面之上（y < 0），所以是真的「从天而降」
@export var spawn_top: float = -620.0
@export var spawn_bottom: float = -120.0

@onready var _floor: AnimatableBody2D = $"../Physics/Floor"

var _ground_layers: Array[Node] = []
var _time: float = 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	_ground_layers = get_tree().get_nodes_in_group(GROUND_GROUP)
	_spawn_flock()
	_place_floor(0.0, 0.0)


func _physics_process(delta: float) -> void:
	_time += delta
	var omega: float = TAU / maxf(floor_period, 0.05)
	var phase: float = omega * _time
	_place_floor(sin(phase) * floor_amplitude, cos(phase) * floor_amplitude * omega)


## 把碰撞地面和视觉地面层推到同一个高度。
## velocity 只喂给 constant_linear_velocity —— 物理引擎靠它算摩擦，
## 真正推动刚体的是 AnimatableBody2D 的 sync_to_physics 位移。
func _place_floor(offset: float, velocity: float) -> void:
	_floor.position.y = floor_y + offset
	_floor.constant_linear_velocity = Vector2(0.0, velocity)
	for layer in _ground_layers:
		if is_instance_valid(layer):
			layer.y_offset = offset


func _spawn_flock() -> void:
	var view_w: float = get_viewport_rect().size.x
	for i in bird_count:
		var bird: RigidBody2D = BIRD_SCENE.instantiate()
		bird.position = Vector2(
				_rng.randf_range(80.0, view_w - 80.0),
				_rng.randf_range(spawn_top, spawn_bottom))
		bird.rotation = _rng.randf_range(-PI, PI)
		# 一点点初始横向速度和自转，让它们一开始就不是垂直往下掉
		bird.linear_velocity = Vector2(
				_rng.randf_range(-160.0, 160.0),
				_rng.randf_range(-40.0, 140.0))
		bird.angular_velocity = _rng.randf_range(-6.0, 6.0)
		add_child(bird)
		# 25 只鸟共用同一份 SpriteFrames，如果都从第 0 帧同速播，看起来像复制粘贴
		var anim: AnimatedSprite2D = bird.get_node("AnimatedSprite2D")
		anim.frame = _rng.randi_range(0, 3)
		anim.speed_scale = _rng.randf_range(0.8, 1.3)
