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

## 这是第几个玩家（0 = 一号机，1 = 二号机）。决定它听哪一组按键。
@export var player_index: int = 0

## 冲刺无敌是否正在生效（不含结束后的缓冲时间）
var dash_active: bool = false

## 护盾：能挡一次撞击，用完就没了
var shield: bool = false

## 「倒地」：双人模式里被撞了但队友还活着，处于等待复活的状态。
## 和 alive = false 的区别是它还有救，所以不能走完整的死亡流程。
var downed: bool = false
## 倒地后还要等多久复活
var revive_left: float = 0.0
## 倒地复活的基准时长（revive_progress 用它做分母）
var revive_seconds: float = 5.0

## 本机实际监听的动作名。
## 单人：空格。双人：一号机 W、二号机 ↑（空格只在单人模式生效）。
var _act_up: StringName = &"pull_up"
var _act_dash: StringName = &"dash"
## 是否处于双人模式（决定头顶要不要挂 P1/P2 标志）
var _coop: bool = false
## 是否由 AI 代打（机哥模式下的二号机）
var is_bot: bool = false

## 「虚拟按键」：AI 不去伪造 InputEvent，而是直接把意图写在这里。
## 这样 AI 和真人走的是同一条物理路径，手感、升力、音效完全一致。
var virtual_up: bool = false
var _virtual_up_prev: bool = false

var _dash_left: float = 0.0
## 「无敌狂飙」事件送的免费冲刺剩余时间：这段时间里冲刺不耗能、不进冷却
var _turbo_left: float = 0.0
var _grace_left: float = 0.0
var _cooldown_left: float = 0.0
var _golden: bool = false

@onready var _sprite: AnimatedSprite2D = $AnimatedSprite2D
## 骑在飞行器背上的驾驶员（没有驾驶员时隐藏）
@onready var _pilot: Sprite2D = $AnimatedSprite2D/Pilot
## 护盾生效时罩在身上的泡泡（挂在根节点上，所以不会跟着俯仰一起转）
@onready var _bubble: Sprite2D = $Shield

## 头顶的玩家编号牌
@onready var _badge: Sprite2D = $Badge
## 这台飞行器自己的循环飞行声
@onready var _engine: AudioStreamPlayer = $Engine

var _tilt: float = 0.0


## 由主场景在生成时调用：指定自己是几号机、出生在哪
func _ready() -> void:
	# player.tscn 里的金色材质是一个**共享的 .tres 资源**：两个玩家实例指向的是
	# 同一个 ShaderMaterial，改它的 shader 参数会两个人一起变金 —— 冲刺就不分人了。
	# 每个实例复制一份自己的（Pilot 走 use_parent_material，复制父级即可两处都独立）。
	if _sprite != null and _sprite.material != null:
		_sprite.material = _sprite.material.duplicate()


func configure(index: int, spawn: Vector2, coop: bool = false, bot: bool = false) -> void:
	player_index = index
	_coop = coop
	is_bot = bot and index == 1
	_act_up = &"pull_up"
	_act_dash = &"dash"
	if coop:
		# 双人 / 机哥模式：空格让出来。一号机 W，二号机 ↑。
		_act_up = &"pull_up_p1" if index == 0 else &"pull_up_p2"
		# 冲刺也分开：一号机 E，二号机 ENTER。单人模式仍然是 ENTER。
		_act_dash = &"dash_p1" if index == 0 else &"dash"
	if _badge != null:
		_badge.visible = coop
		if coop:
			if is_bot:
				_badge.texture = load("res://art/badge_bot.png")
			else:
				_badge.texture = load("res://art/badge_p%d.png" % (index + 1))
	reset_run(spawn)


## 换飞行器时顺便换飞行声
func apply_engine(aircraft_id: String) -> void:
	if _engine == null:
		return
	_engine.stream = Audio.engine_stream(aircraft_id)
	_sync_engine()


## 让飞行声跟着状态走：死了/倒地就停，活着且拿到速度就播
func _sync_engine() -> void:
	if _engine == null or _engine.stream == null:
		return
	var should_play: bool = alive and not downed
	if should_play and not _engine.playing:
		_engine.play()
	elif not should_play and _engine.playing:
		_engine.stop()


func is_alive() -> bool:
	return alive


func give_shield() -> void:
	shield = true
	if _bubble != null:
		_bubble.visible = true


## 挡下一次撞击。返回 true 表示这次撞击被吃掉了，不该判死。
func consume_shield() -> bool:
	if not shield:
		return false
	shield = false
	if _bubble != null:
		_bubble.visible = false
	# 破盾之后给一小段无敌，免得贴着柱子连撞两次直接死
	_grace_left = maxf(_grace_left, 1.2)
	_refresh_gold()
	return true


## 换装：飞行器换整套 SpriteFrames，驾驶员换一张贴图。
## 两者都是原生分辨率的像素画（32x32 一帧 / 16x16），整体那层 6 倍放大在场景实例上，
## 所以这里不需要再缩放，像素颗粒和别的东西一致。
func apply_skin(aircraft: int, pilot: int) -> void:
	if _sprite != null:
		_sprite.sprite_frames = Skins.frames(aircraft)
		# 换了 SpriteFrames 要重新播一次，否则动画会停在旧帧上
		_sprite.play("fly_bird")
	if _pilot != null:
		var tex: Texture2D = Skins.pilot_texture(pilot)
		_pilot.texture = tex
		_pilot.visible = tex != null


func _physics_process(delta: float) -> void:
	if downed:
		_tick_down(delta)
		return
	if not alive:
		return
	_tick_dash(delta)
	_apply_gravity(delta)
	_apply_input(delta)
	_apply_attitude(delta)
	move_and_slide()
	# 飞行声跟着速度微微变调，低速时听起来像快要熄火
	if _engine != null and _engine.playing:
		_engine.pitch_scale = clampf(absf(velocity.x) / maxf(cruise_speed, 1.0), 0.82, 1.35)


# ------------------------------------------------------------------ 无敌冲刺
## 是否处于无敌状态。路障的判定要问这个（含冲刺结束后的缓冲时间）。
func is_invincible() -> bool:
	return dash_active or _grace_left > 0.0


## 现在能不能按 ENTER 起冲刺
func dash_ready() -> bool:
	return alive and not dash_active and _grace_left <= 0.0 and _cooldown_left <= 0.0


## 能量条进度 0~1：冲刺时从满放到空，冷却时从空回满，其余时间恒为满
func dash_ratio() -> float:
	# 狂飙（事件白送的冲刺）期间能量条要显示满的 —— 它是免费的，
	# 条子要是往下掉，看起来就像在消耗能量，和"免费"自相矛盾。
	if _turbo_left > 0.0:
		return 1.0
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


## 吃金币给冲刺冷却减一点。只作用于**捡到那枚金币的玩家**。
## 正在冲刺时不用减（冷却本来就是 0），免得把一段冲刺"续"成两段。
func reduce_dash_cooldown(seconds: float) -> void:
	if dash_active or _cooldown_left <= 0.0:
		return
	_cooldown_left = maxf(_cooldown_left - seconds, 0.0)


## 事件用：白送一段无敌冲刺（能量条不算数）
func grant_turbo(seconds: float) -> void:
	_turbo_left = maxf(_turbo_left, seconds)
	dash_active = true
	_dash_left = maxf(_dash_left, 0.2)
	_cooldown_left = 0.0


func _tick_dash(delta: float) -> void:
	if _turbo_left > 0.0:
		_turbo_left = maxf(_turbo_left - delta, 0.0)
		# 狂飙期间维持冲刺状态，但结束的那一帧不要触发 grace/冷却
		dash_active = true
		_dash_left = maxf(_dash_left, 0.15)
		_cooldown_left = 0.0
		if _turbo_left > 0.0:
			_refresh_gold()
			return
		# 狂飙刚刚结束：干净地退出冲刺，**不进冷却**。
		# 以前这里直接往下走，落到普通的冲刺结算里 —— 于是"免费送的冲刺"
		# 一结束就立刻开始转冷却，等于白送了个寂寞。
		dash_active = false
		_dash_left = 0.0
		_cooldown_left = 0.0
		_grace_left = maxf(_grace_left, 0.6)
		_refresh_gold()
		return
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
## 世界重力倍率（太空 0.62、梦幻 0.78……），由 WorldDirector 设置。
## 改的是重力而不是初速度，所以低重力世界手感是"飘"，不是"被弹了一下"。
var gravity_scale: float = 1.0


func set_gravity_scale(scale: float) -> void:
	gravity_scale = maxf(scale, 0.05)


func _apply_gravity(delta: float) -> void:
	if is_on_floor():
		velocity.y = 0.0
	elif velocity.y < fall_speed_max:
		velocity.y = minf(velocity.y + gravity * gravity_scale * delta, fall_speed_max)


func _apply_input(delta: float) -> void:
	if Input.is_action_just_pressed(_act_dash):
		start_dash()
	# AI 靠 virtual_up 驱动，所以"刚按下"要把虚拟键也算进来
	var up_now: bool = Input.is_action_pressed(_act_up) or virtual_up
	var up_edge: bool = up_now and not _virtual_up_prev and not is_bot
	_virtual_up_prev = up_now
	if Input.is_action_just_pressed(_act_up) or up_edge:
		# 只在按下的那一瞬播：本作是"按住持续爬升"，每帧都播会变成噪音。
		# 机哥不播 —— 两台飞行器一起扇翅膀会吵成一团。
		Audio.play("flap")
	_apply_lift(delta)
	_apply_horizontal(delta)


## 按住空格 -> 按当前速度产生升力，速度越快爬升越猛。
## 接近软天花板时升力线性衰减（"空气变稀"），玩家会自然掉回来，不需要硬墙。
func _apply_lift(delta: float) -> void:
	if not (Input.is_action_pressed(_act_up) or virtual_up) or velocity.x <= lift_min_speed:
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


## 双人模式：被撞了但队友还活着 —— 进入倒地状态，等队友撑住一段时间再复活。
## 这段时间里不再吃碰撞（layer 清 0），否则会一直贴着柱子反复触发。
func go_down(revive_seconds: float) -> void:
	alive = false
	downed = true
	self.revive_seconds = maxf(revive_seconds, 0.001)
	revive_left = self.revive_seconds
	dash_active = false
	_dash_left = 0.0
	_grace_left = 0.0
	_cooldown_left = 0.0
	_refresh_gold()
	velocity = Vector2.ZERO
	collision_layer = 0
	if _sprite != null:
		_sprite.modulate = Color(0.45, 0.45, 0.5, 0.85)
	_sync_engine()


## 倒地中：只受重力往下掉，不响应输入
func _tick_down(delta: float) -> void:
	revive_left = maxf(revive_left - delta, 0.0)
	velocity.x = move_toward(velocity.x, 0.0, 900.0 * delta)
	velocity.y = minf(velocity.y + gravity * gravity_scale * delta, fall_speed_max)
	# 相机跟着还活着的队友飞走了，脚下早就没有地面，不兜住会一路掉到无穷远
	if global_position.y > 1500.0:
		global_position.y = 1500.0
		velocity.y = 0.0
	move_and_slide()
	_sprite.rotation = wrapf(_sprite.rotation + delta * 6.0, -PI, PI)


## 队友撑住了，复活
func revive(at: Vector2) -> void:
	downed = false
	revive_left = 0.0
	alive = true
	global_position = at
	velocity = Vector2.ZERO
	collision_layer = 1
	if _sprite != null:
		_sprite.modulate = Color.WHITE
		_sprite.rotation = 0.0
	# 复活后给一小段无敌，免得刚站起来就又被同一根柱子撞死
	_grace_left = 1.6
	_tilt = 0.0
	_sync_engine()


## 倒地复活的进度（0 = 刚倒地，1 = 马上复活）
func revive_progress() -> float:
	return 1.0 - clampf(revive_left / maxf(revive_seconds, 0.001), 0.0, 1.0)


## 撞上路障：立刻停住，不再响应输入
func die() -> void:
	alive = false
	downed = false
	dash_active = false
	_dash_left = 0.0
	_grace_left = 0.0
	_cooldown_left = 0.0
	_refresh_gold()
	velocity = Vector2.ZERO
	if _sprite != null:
		_sprite.modulate = Color(0.6, 0.6, 0.6, 0.9)
	_sync_engine()


func reset_run(spawn: Vector2) -> void:
	shield = false
	if _bubble != null:
		_bubble.visible = false
	global_position = spawn
	velocity = Vector2.ZERO
	_tilt = 0.0
	if _sprite != null:
		_sprite.rotation = 0.0
	lift = 0.0
	alive = true
	downed = false
	revive_left = 0.0
	virtual_up = false
	_virtual_up_prev = false
	collision_layer = 1
	if _sprite != null:
		_sprite.modulate = Color.WHITE
	# 新一局能量条是满的，开局就能按 ENTER
	dash_active = false
	_dash_left = 0.0
	_grace_left = 0.0
	_cooldown_left = 0.0
	_golden = false
	if _sprite != null and _sprite.material != null:
		_sprite.material.set_shader_parameter("golden", false)
		_sprite.material.set_shader_parameter("pulse", 0.0)
