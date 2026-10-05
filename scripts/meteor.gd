extends Area2D
## 陨石雨事件的陨石：从画面上方斜着砸下来，碰到就撞毁，落地碎成金币。
##
## 它走自己的 _physics_process 而不是 RigidBody2D —— 陨石要"完全可预测"，
## 玩家躲的是落点，不是物理模拟。随机性放在生成时的位置和速度上。

signal hit(body: Node2D)

const FALL_SPEED: float = 470.0
const DRIFT_SPEED: float = -150.0
## 掉到这个高度就碎掉（地面 y = 693）
const GROUND_Y: float = 700.0
## 碎掉时炸出几枚金币
@export var coin_reward: int = 3

const COIN_SCENE: PackedScene = preload("res://scenes/coin.tscn")

@onready var _sprite: Sprite2D = $Sprite

var velocity: Vector2 = Vector2(DRIFT_SPEED, FALL_SPEED)
var _spin: float = 0.0
var _dead: bool = false


func _ready() -> void:
	add_to_group("meteor")
	# 贴图已经 6 倍放大过（108x108），不要再乘
	_sprite.rotation = randf_range(-PI, PI)
	_spin = randf_range(-3.0, 3.0)
	body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	if _dead:
		return
	position += velocity * delta
	_sprite.rotation += _spin * delta
	if position.y > GROUND_Y:
		_shatter()


func _on_body_entered(body: Node2D) -> void:
	if _dead or not body.is_in_group("player"):
		return
	hit.emit(body)


## 落地：碎成一堆金币，算是"躲过去"的奖励
func _shatter() -> void:
	_dead = true
	for i in coin_reward:
		var coin := COIN_SCENE.instantiate()
		coin.position = position + Vector2(randf_range(-70.0, 70.0), randf_range(-40.0, 10.0))
		get_parent().add_child(coin)
	queue_free()
