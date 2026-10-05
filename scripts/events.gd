extends Node2D
## 随机事件导演。
##
## 每隔十几二十秒抽一个事件丢给玩家。事件分两类：
##   * **瞬时型**（传送门、陨石雨）—— 生成实体就不管了，实体自己负责后续；
##   * **持续型**（月球重力、无敌狂飙、金币双倍）—— 记一段剩余时间，到点自动收摊。
##
## 所有持续型事件在收摊时都必须把状态**精确还原**，不能靠"再设一次默认值"糊过去，
## 因为世界本身也有重力倍率（太空 0.62），还原时要乘回当前世界的基准值。

signal banner(id: String)
signal fever_changed(on: bool, seconds_left: float)
signal coin_multiplier_changed(mult: int)
## 要发免费冲刺了。双人模式里必须发给**所有人**，所以广播出去由 main 转发。
signal turbo_granted(seconds: float)

enum Ev { PORTAL, COIN_RAIN, LOW_G, HIGH_G, TURBO, METEOR, DOUBLE }

const PORTAL_SCENE: PackedScene = preload("res://scenes/portal.tscn")
const METEOR_SCENE: PackedScene = preload("res://scenes/meteor.tscn")

## 每个事件的抽取权重（越大越常出现）
const WEIGHTS: Dictionary = {
	Ev.PORTAL: 34, Ev.COIN_RAIN: 14, Ev.LOW_G: 10, Ev.HIGH_G: 10,
	Ev.TURBO: 12, Ev.METEOR: 14, Ev.DOUBLE: 12,
}

@export_group("节点")
@export var course_path: NodePath
@export var player_path: NodePath
@export var worlds_path: NodePath
@export var camera_path: NodePath

@export_group("节奏")
## 开局多久之后才可能出第一个事件
@export var first_delay: float = 8.0
@export var gap_min: float = 15.0
@export var gap_max: float = 24.0

@export_group("数值")
## 传送门的金币空间持续多少秒
@export var fever_seconds: float = 20.0
## 金币雨 / 月球重力 / 狂飙 / 双倍 各自的持续时间
@export var coin_rain_seconds: float = 8.0
@export var low_g_seconds: float = 8.0
@export var high_g_seconds: float = 6.0
@export var turbo_seconds: float = 6.0
@export var double_seconds: float = 11.0
## 金币维度里金币的倍率
@export var fever_multiplier: int = 3

## 当前的重力倍率（1 = 不变）。世界自己的重力是另一个乘数，
## 由 main.gd 每帧把两者相乘再推给所有玩家 —— 双人模式下"所有玩家"不止一个，
## 所以这里不再直接去戳玩家。
var gravity_multiplier: float = 1.0

var enabled: bool = true

var _course: Node2D
var _player: Node2D
var _worlds: Node2D
var _cam: Camera2D
var _rng := RandomNumberGenerator.new()

var _gap_left: float = 0.0
var _active: Ev = Ev.PORTAL
var _active_left: float = 0.0
var _running: bool = false

## 金币维度（传送门）状态
var fever_left: float = 0.0
var _multiplier: int = 1
var _meteors_left: int = 0
var _meteor_delay: float = 0.0


func _ready() -> void:
	_rng.randomize()
	_course = get_node_or_null(course_path)
	_player = get_node_or_null(player_path)
	_worlds = get_node_or_null(worlds_path)
	_cam = get_node_or_null(camera_path)
	_gap_left = first_delay


func _physics_process(delta: float) -> void:
	if not enabled:
		return

	if fever_left > 0.0:
		fever_left = maxf(fever_left - delta, 0.0)
		fever_changed.emit(true, fever_left)
		if fever_left <= 0.0:
			_end_fever()

	if _running:
		_active_left -= delta
		if _active_left <= 0.0:
			_finish_active()

	if _meteors_left > 0:
		_meteor_delay -= delta
		if _meteor_delay <= 0.0:
			_spawn_meteor()
			_meteors_left -= 1
			_meteor_delay = _rng.randf_range(0.18, 0.45)

	if fever_left > 0.0:
		return          # 金币空间里不再叠加其他事件
	_gap_left -= delta
	if _gap_left <= 0.0:
		_fire()


# ------------------------------------------------------------------ 抽取
func _fire() -> void:
	_active = _pick()
	_gap_left = _rng.randf_range(gap_min, gap_max)
	match _active:
		Ev.PORTAL:
			_spawn_portal()
		Ev.COIN_RAIN:
			_begin(Ev.COIN_RAIN, coin_rain_seconds)
			_course.coin_bonus = true
			banner.emit("coin_rain")
		Ev.LOW_G:
			_begin(Ev.LOW_G, low_g_seconds)
			_apply_gravity(0.32)
			banner.emit("low_g")
		Ev.HIGH_G:
			_begin(Ev.HIGH_G, high_g_seconds)
			_apply_gravity(2.3)
			banner.emit("high_g")
		Ev.TURBO:
			_begin(Ev.TURBO, turbo_seconds)
			turbo_granted.emit(turbo_seconds)
			banner.emit("turbo")
		Ev.METEOR:
			_begin(Ev.METEOR, 5.0)
			_meteors_left = 7
			_meteor_delay = 0.35
			banner.emit("meteor")
		Ev.DOUBLE:
			_begin(Ev.DOUBLE, double_seconds)
			_set_multiplier(2)
			banner.emit("double")


func _pick() -> Ev:
	var total: int = 0
	for k in WEIGHTS:
		total += int(WEIGHTS[k])
	var roll: int = _rng.randi_range(1, total)
	for k in WEIGHTS:
		roll -= int(WEIGHTS[k])
		if roll <= 0:
			return k as Ev
	return Ev.PORTAL


func _begin(ev: Ev, seconds: float) -> void:
	_running = true
	_active = ev
	_active_left = seconds


## 持续型事件到点收摊
func _finish_active() -> void:
	_running = false
	match _active:
		Ev.COIN_RAIN:
			_course.coin_bonus = false
		Ev.LOW_G, Ev.HIGH_G:
			_apply_gravity(1.0)
		Ev.TURBO:
			pass                      # 狂飙自己会结束
		Ev.DOUBLE:
			_set_multiplier(1)
		_:
			pass


func _apply_gravity(scale: float) -> void:
	gravity_multiplier = scale


func _set_multiplier(m: int) -> void:
	_multiplier = m
	coin_multiplier_changed.emit(m)


## 当前金币倍率（main.gd 每吃一枚金币问一次）
func coin_multiplier() -> int:
	return _multiplier * (fever_multiplier if fever_left > 0.0 else 1)


# ------------------------------------------------------------------ 传送门
func _spawn_portal() -> void:
	if _cam == null:
		return
	var p := PORTAL_SCENE.instantiate() as Area2D
	# 放在镜头前方 1200 像素、缝隙高度上 —— 玩家看得见，也来得及调整高度
	p.position = Vector2(_cam.get_screen_center_position().x + 1200.0,
			_rng.randf_range(140.0, 420.0))
	add_child(p)
	p.entered.connect(_start_fever)
	banner.emit("portal")


func _start_fever() -> void:
	fever_left = fever_seconds
	_course.set_coin_fever(true)
	if _worlds != null:
		_worlds.borrow(Worlds.COIN_INDEX, false)
	# 进去先白送一次冲刺，20 秒里想怎么飞就怎么飞
	turbo_granted.emit(fever_seconds + 0.5)
	_set_multiplier(1)
	banner.emit("fever")
	fever_changed.emit(true, fever_left)


func _end_fever() -> void:
	_course.set_coin_fever(false)
	if _worlds != null:
		_worlds.restore()
	fever_changed.emit(false, 0.0)


# ------------------------------------------------------------------ 陨石雨
func _spawn_meteor() -> void:
	if _cam == null:
		return
	var m := METEOR_SCENE.instantiate() as Area2D
	m.position = Vector2(_cam.get_screen_center_position().x
			+ _rng.randf_range(1000.0, 1500.0), _rng.randf_range(-320.0, -140.0))
	m.hit.connect(_on_meteor_hit)
	add_child(m)


func _on_meteor_hit(body: Node2D) -> void:
	meteor_hit.emit(body)


signal meteor_hit(body: Node2D)
