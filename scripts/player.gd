extends CharacterBody2D
## 玩家（小鸟）—— 反应型跑酷的操作手感参数。
##
## 相对最初版本的关键改动：
##  1. 速度整体下调约一个数量级。原来最高 10000 像素/秒，路障 0.19 秒就穿过屏幕，
##     根本来不及反应；现在巡航 660，两次路障之间的反应时间稳定在 1 秒以上。
##  2. 【已删除】A/D 左右加减速。这是横版跑酷，小鸟的 x 是自动向前的，
##     "左右操作"按下去没有任何反馈，只会让玩家以为游戏坏了。现在固定在巡航速度。
##  3. 升力正比于当前速度：速度越快爬升越猛，慢下来连高度都维持不住。
##  4. 所有加速度都乘 delta（原版把每帧增量当常数，帧率一变手感就变）。
##  5. rotation 用 lerp_angle + wrapf（原版 velocity.angle() 在 ±PI 跳变会打转）。
##  6. 新增 ENTER「无敌冲刺」：短时间无敌 + 穿柱 + 全身镀金，用完进入冷却。

## 无敌冲刺的三个阶段，HUD 的能量条按它换颜色和状态字
enum DashState { READY, ACTIVE, COOLING }

@export_group("水平")
## 自动巡航速度（像素/秒）。本作没有左右操作，水平速度只有一个目标值。
@export var cruise_speed: float = 660.0
## 向巡航速度靠拢的加速度
@export var accel_forward: float = 300.0
## 冲刺加速和冲刺结束后回落的速度（要比巡航加速度快得多，否则 3 秒还没提上速）
@export var dash_accel: float = 1800.0

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

@export_group("无敌冲刺")
## 一次冲刺的无敌时长（秒）。能量条会在这段时间里从满放到空。
@export var dash_duration: float = 3.0
## 冲刺结束后额外保留的缓冲无敌时间（秒）。
## 存在的意义：万一无敌刚好在柱子里面用完，不会立刻被判撞毁。
@export var dash_grace: float = 3.0
## 能量条放空后要等多久才能再次使用（秒）
@export var dash_cooldown: float = 15.0
## 冲刺时的速度倍率
@export var dash_speed_scale: float = 1.5

@export_group("姿态")
@export var turn_speed: float = 9.0
@export var land_turn_speed: float = 16.0

var lift: float = 0.0
var alive: bool = true

## 冲刺无敌是否正在生效（不含结束后的缓冲时间）
var dash_active: bool = false

var _dash_left: float = 0.0
var _grace_left: float = 0.0
var _cooldown_left: float = 0.0
var _golden: bool = false

@onready var _sprite: AnimatedSprite2D = $AnimatedSprite2D

var _tilt: float = 0.0


func _physics_process(delta: float) -> void:
	if not alive:
		return
	_tick_dash(delta)
	_apply_gravity(delta)
	_apply_input(delta)
	_apply_attitude(delta)
	move_and_slide()


# ------------------------------------------------------------------ 无敌冲刺
## 是否处于无敌状态。路障的判定要问这个（含冲刺结束后的缓冲时间）。
func is_invincible() -> bool:
	return dash_active or _grace_left > 0.0


## 现在能不能按 ENTER 起冲刺
func dash_ready() -> bool:
	return alive and not dash_active and _grace_left <= 0.0 and _cooldown_left <= 0.0


## 能量条进度 0~1：冲刺时从满放到空，冷却时从空回满，其余时间恒为满
func dash_ratio() -> float:
	if dash_active:
		return clampf(_dash_left / maxf(dash_duration, 0.001), 0.0, 1.0)
	if _cooldown_left > 0.0:
		return clampf(1.0 - _cooldown_left / maxf(dash_cooldown, 0.001), 0.0, 1.0)
	return 1.0


func dash_state() -> DashState:
	if dash_active:
		return DashState.ACTIVE
	if _grace_left > 0.0 or _cooldown_left > 0.0:
		return DashState.COOLING
	return DashState.READY


func start_dash() -> bool:
	if not dash_ready():
		return false
	dash_active = true
	_dash_left = dash_duration
	_grace_left = 0.0
	_cooldown_left = 0.0
	Audio.play("dash", 1.0)
	return true


func _tick_dash(delta: float) -> void:
	if dash_active:
		_dash_left -= delta
		if _dash_left <= 0.0:
			# 能量刚好放空：立刻进入冷却，同时留一段缓冲无敌
			dash_active = false
			_dash_left = 0.0
			_grace_left = dash_grace
			_cooldown_left = dash_cooldown
	elif _grace_left > 0.0:
		_grace_left = maxf(_grace_left - delta, 0.0)
	if not dash_active and _cooldown_left > 0.0:
		_cooldown_left = maxf(_cooldown_left - delta, 0.0)
	_refresh_gold()


## 镀金只改贴图材质，不碰碰撞体，也不换 SpriteFrames —— 零成本、零抖动的整体变色
func _refresh_gold() -> void:
	var on: bool = is_invincible()
	if _sprite == null or _sprite.material == null:
		_golden = on
		return
	if on:
		# 呼吸式脉冲，让"我现在是金的"这件事在高速下也一眼能看出来
		var t: float = float(Time.get_ticks_msec()) * 0.001
		_sprite.material.set_shader_parameter("pulse", 0.5 + 0.5 * sin(t * 11.0))
	if on == _golden:
		return
	_golden = on
	_sprite.material.set_shader_parameter("golden", on)
	if not on:
		_sprite.material.set_shader_parameter("pulse", 0.0)


# ------------------------------------------------------------------ 物理
func _apply_gravity(delta: float) -> void:
	if is_on_floor():
		velocity.y = 0.0
	elif velocity.y < fall_speed_max:
		velocity.y = minf(velocity.y + gravity * delta, fall_speed_max)


func _apply_input(delta: float) -> void:
	if Input.is_action_just_pressed("dash"):
		start_dash()
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
	var target: float = cruise_speed * (dash_speed_scale if dash_active else 1.0)
	# 冲刺提上去、以及冲刺后落回来，都用更快的加速度，否则 3 秒的冲刺大半浪费在提速上
	var rate: float = dash_accel if (dash_active or velocity.x > target) else accel_forward
	velocity.x = move_toward(velocity.x, target, rate * delta)


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


## 撞上路障：立刻停住，不再响应输入
func die() -> void:
	alive = false
	dash_active = false
	_dash_left = 0.0
	_grace_left = 0.0
	_cooldown_left = 0.0
	_refresh_gold()
	velocity = Vector2.ZERO


func reset_run(spawn: Vector2) -> void:
	global_position = spawn
	velocity = Vector2.ZERO
	_tilt = 0.0
	if _sprite != null:
		_sprite.rotation = 0.0
	lift = 0.0
	alive = true
	# 新一局能量条是满的，开局就能按 ENTER
	dash_active = false
	_dash_left = 0.0
	_grace_left = 0.0
	_cooldown_left = 0.0
	_golden = false
	if _sprite != null and _sprite.material != null:
		_sprite.material.set_shader_parameter("golden", false)
		_sprite.material.set_shader_parameter("pulse", 0.0)
