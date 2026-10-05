extends Node2D
## 无限关卡生成器。
##
## 在镜头右侧不断"铺"出路障与金币，并把落在身后的回收掉。三种图案：
##   GATE 上下都挡，中间留缝      —— 必须从缝里穿过去
##   LOW  只挡下面                —— 必须飞过去
##   HIGH 只挡上面                —— 必须压低飞
## 难度随飞行距离上升：缝隙变窄、图案间隔按当前速度换算成固定时间。
##
## 间隔用的是「时间」而不是「距离」：这样无论玩家加速还是刹车，
## 两次路障之间的反应时间都差不多，速度带来的只是视觉压迫感和容错变小。

signal player_hit
signal coin_collected

const OBSTACLE_SCENE: PackedScene = preload("res://scenes/obstacle.tscn")
const COIN_SCENE: PackedScene = preload("res://scenes/coin.tscn")

enum Kind { GATE, LOW, HIGH }

@export_group("场地")
## 路面高度（世界 y）
@export var road_y: float = 693.0
## 悬挂柱向上延伸到的高度，必须远高于玩家能飞到的最高点，
## 否则玩家可以从所有路障上方绕过去
@export var sky_top: float = -720.0
## 出生后到第一个路障的安全距离
@export var first_pattern_x: float = 1600.0
## 提前生成多远
@export var spawn_margin: float = 1500.0

@export_group("节奏与难度")
## 两次路障之间的时间间隔（秒）。
## 间隔按"时间"而不是"距离"算：玩家加速时路障自动拉开，刹车时自动收紧，
## 保证不管什么速度，两次路障之间的反应时间都差不多。
@export var pattern_interval: float = 1.35
@export var spacing_min: float = 700.0
@export var spacing_max: float = 1250.0
@export var gap_easy: float = 340.0
@export var gap_hard: float = 285.0
## 相邻两个路障的目标高度最大落差。
## 这是关卡"可通过性"的硬约束：玩家在两次路障之间最多只能升降这么多像素，
## 超过就会出现物理上躲不掉的组合（曾经实测到 323 像素落差 + 480 像素间隔，
## 小鸟根本来不及下降，直接撞上）。
@export var max_aim_delta: float = 250.0
## 多少米之后难度到顶
@export var difficulty_distance: float = 2600.0
## 缝隙中心可以出现的范围（世界 y，越小越高）
@export var gap_center_top: float = 80.0
@export var gap_center_bottom: float = 400.0

@export_group("金币")
@export var coin_arc_count_min: int = 3
@export var coin_arc_count_max: int = 5
## 金币弧线放在路障之前多远
@export var coin_lead: float = 260.0

var _cursor_x: float = 0.0
var _prev_aim: float = 240.0
var _rng := RandomNumberGenerator.new()
var _player: Node2D = null

## 玩家已推进的距离（米），决定难度
var traveled_meters: float = 0.0


## 由主场景在 _ready 里调用
func begin(player: Node2D, start_x: float) -> void:
	_player = player
	_rng.randomize()
	_cursor_x = start_x + first_pattern_x


func _physics_process(_delta: float) -> void:
	var cam := get_viewport().get_camera_2d()
	if cam == null:
		return
	var center_x: float = cam.get_screen_center_position().x
	_fill(center_x)
	_recycle(center_x)


func _fill(center_x: float) -> void:
	var right: float = center_x + get_viewport_rect().size.x * 0.5 + spawn_margin
	while _cursor_x < right:
		_spawn_pattern(_cursor_x)
		_cursor_x += _next_spacing()


func _next_spacing() -> float:
	var speed: float = 620.0
	if _player != null:
		speed = maxf(absf(_player.velocity.x), 200.0)
	return clampf(speed * pattern_interval, spacing_min, spacing_max)


func _recycle(center_x: float) -> void:
	var cutoff: float = center_x - get_viewport_rect().size.x * 0.5 - 800.0
	for child in get_children():
		if child is Node2D and (child as Node2D).position.x < cutoff:
			child.queue_free()


func _difficulty() -> float:
	return clampf(traveled_meters / difficulty_distance, 0.0, 1.0)


func _spawn_pattern(x: float) -> void:
	var t: float = _difficulty()
	var gap: float = lerpf(gap_easy, gap_hard, t)

	# 先决定"希望玩家飞到哪个高度"，再据此反推上下柱该长多高。
	# 相邻目标的高度落差必须限制住，否则会生成物理上躲不掉的组合。
	var aim: float = clampf(_rng.randf_range(gap_center_top, gap_center_bottom),
			_prev_aim - max_aim_delta, _prev_aim + max_aim_delta)
	aim = clampf(aim, gap_center_top, gap_center_bottom)
	_prev_aim = aim

	# 前期只出「飞过去」和「压低飞」，缝门中后期才逐渐占多数
	var kind: Kind = Kind.GATE
	var roll: float = _rng.randf()
	if roll < 0.34 - t * 0.14:
		kind = Kind.LOW
	elif roll < 0.62 - t * 0.22:
		kind = Kind.HIGH

	var clearance: float = gap * 0.5
	var gap_top: float = aim - clearance
	var gap_bottom: float = aim + clearance
	if kind == Kind.LOW:
		gap_top = sky_top - 10.0                 # 高度为负 -> 悬挂柱整个隐藏
		gap_bottom = aim + clearance
	elif kind == Kind.HIGH:
		gap_bottom = road_y + 10.0               # 高度为负 -> 地面柱整个隐藏
		gap_top = aim - clearance

	var obstacle := OBSTACLE_SCENE.instantiate()
	obstacle.position = Vector2(x, 0.0)
	add_child(obstacle)
	obstacle.configure(gap_top, gap_bottom, road_y, sky_top)
	obstacle.hit.connect(_on_obstacle_hit)

	# 金币弧线铺在目标高度上，等于把"该飞哪"直接画给玩家看
	_spawn_coin_arc(x - coin_lead, aim)


## 在缺口正前方铺一小段弧线金币，顺手把玩家"引"到正确的线路上
func _spawn_coin_arc(x: float, center: float) -> void:
	var count: int = _rng.randi_range(coin_arc_count_min, coin_arc_count_max)
	# 金币贴图宽 144 像素，间距必须大于它，否则几个金币会糊成一坨
	var spread: float = 150.0 * float(count - 1)
	for i in count:
		var f: float = 0.0 if count == 1 else float(i) / float(count - 1)
		var coin := COIN_SCENE.instantiate()
		coin.position = Vector2(x + (f - 0.5) * spread, center - sin(f * PI) * 55.0)
		add_child(coin)
		coin.collected.connect(_on_coin_collected)


func _on_obstacle_hit() -> void:
	player_hit.emit()


func _on_coin_collected() -> void:
	coin_collected.emit()
