extends CharacterBody2D
## 玩家（小鸟）—— 反应型跑酷的操作手感参数。
##
## 相对最初版本的关键改动：
##  1. 速度整体下调约一个数量级。原来最高 10000 像素/秒，路障 0.19 秒就穿过屏幕，
##     根本来不及反应；现在巡航 620、最高 1180，两次路障之间的反应时间稳定在 1 秒以上。
##  2. 松开按键不再减速到 0，而是回落到「巡航速度」——否则玩家可以原地停下，
##     路障就永远撞不到他，跑酷不成立。
##  3. 升力正比于当前速度：速度越快爬升越猛，慢下来连高度都维持不住。
##     这让"加速抢时间"和"减速保命"形成真实取舍。
##  4. 所有加速度都乘 delta（原版把每帧增量当常数，帧率一变手感就变）。
##  5. rotation 用 lerp_angle + wrapf（原版 velocity.angle() 在 ±PI 跳变会打转）。

signal speed_changed(speed: float)

@export_group("水平")
## 前进加速度（像素/秒²）
@export var accel_forward: float = 220.0
## 松开按键时向巡航速度回落的速度
@export var decel_idle: float = 300.0
## 按住左键时的额外刹车
@export var brake_extra: float = 360.0
## 什么都不按时自动维持的巡航速度
@export var cruise_speed: float = 660.0
## 可以刹到的最低速度
@export var speed_min: float = 520.0
## 按住右键可以达到的最高速度
@export var speed_max_forward: float = 900.0

@export_group("垂直")
@export var gravity: float = 1800.0
## 最大下落速度
@export var fall_speed_max: float = 900.0
## 最大上升速度
@export var rise_speed_max: float = 620.0

@export_group("扇翅膀")
## 触发升力所需的最低水平速度
@export var lift_min_speed: float = 200.0
## 升力系数：向上加速度 = 当前速度 * lift_gain
@export var lift_gain: float = 5.2
## 软天花板：高过这里升力完全消失
@export var lift_ceiling_y: float = -300.0
## 升力从这个高度开始线性衰减
@export var lift_fade_range: float = 260.0

@export_group("姿态")
@export var turn_speed: float = 9.0
@export var land_turn_speed: float = 16.0

var lift: float = 0.0
var alive: bool = true

@onready var _sprite: AnimatedSprite2D = $AnimatedSprite2D

var _tilt: float = 0.0
var _last_reported_speed: float = -1.0


func _physics_process(delta: float) -> void:
	if not alive:
		return
	_apply_gravity(delta)
	_apply_input(delta)
	_apply_attitude(delta)
	move_and_slide()
	_report_speed()


func _apply_gravity(delta: float) -> void:
	if is_on_floor():
		velocity.y = 0.0
	elif velocity.y < fall_speed_max:
		velocity.y = minf(velocity.y + gravity * delta, fall_speed_max)


func _apply_input(delta: float) -> void:
	if Input.is_action_just_pressed("pull_up"):
		# 只在按下的那一瞬播：本作是"按住持续爬升"，每帧都播会变成噪音
		Audio.play("flap")
	_apply_lift(delta)
	_apply_horizontal(delta)


## 按住空格 -> 按当前速度产生升力，速度越快爬升越猛。
## 接近软天花板时升力线性衰减（"空气变稀"），玩家会自然掉回来，不需要硬墙。
func _apply_lift(delta: float) -> void:
	if not Input.is_action_pressed("pull_up") or velocity.x <= lift_min_speed:
		lift = 0.0
		return
	var thin_air: float = 1.0
	if global_position.y <= lift_ceiling_y:
		thin_air = 0.0
	elif global_position.y < lift_ceiling_y + lift_fade_range:
		thin_air = (global_position.y - lift_ceiling_y) / lift_fade_range
	if thin_air <= 0.0:
		lift = 0.0
		return
	lift = velocity.x * lift_gain * thin_air
	velocity.y = maxf(velocity.y - lift * delta, -rise_speed_max)


func _apply_horizontal(delta: float) -> void:
	var direction: float = Input.get_axis("left", "right")
	if direction > 0.0:
		velocity.x = move_toward(velocity.x, speed_max_forward, accel_forward * delta)
	elif direction < 0.0:
		velocity.x = move_toward(velocity.x, speed_min, (decel_idle + brake_extra) * delta)
	else:
		velocity.x = move_toward(velocity.x, cruise_speed, decel_idle * delta)


## 俯仰只作用在贴图上，绝不旋转 CharacterBody2D。
## 旋转碰撞体的话，竖直爬升时判定盒会从 156x73 变成 73x156，实际判定高度凭空翻倍，
## 玩家会觉得"明明穿过缝隙却撞了"。判定盒必须始终是轴对齐且固定的。
func _apply_attitude(delta: float) -> void:
	var target: float = _tilt
	if is_on_floor():
		if velocity.angle() >= 0.0:
			target = 0.0
			_tilt = lerp_angle(_tilt, 0.0, _smoothing(land_turn_speed, delta))
	elif velocity.length() > 30.0:
		target = velocity.angle()
		_tilt = lerp_angle(_tilt, target, _smoothing(turn_speed, delta))
	_tilt = wrapf(_tilt, -PI, PI)
	_sprite.rotation = _tilt


## 帧率无关的指数插值系数
static func _smoothing(speed: float, delta: float) -> float:
	return 1.0 - exp(-speed * delta)


func _report_speed() -> void:
	var speed: float = velocity.length()
	if absf(speed - _last_reported_speed) < 1.0:
		return
	_last_reported_speed = speed
	speed_changed.emit(speed)


## 撞上路障：立刻停住，不再响应输入
func die() -> void:
	alive = false
	velocity = Vector2.ZERO


func reset_run(spawn: Vector2) -> void:
	global_position = spawn
	velocity = Vector2.ZERO
	_tilt = 0.0
	if _sprite != null:
		_sprite.rotation = 0.0
	lift = 0.0
	alive = true
	_last_reported_speed = -1.0
