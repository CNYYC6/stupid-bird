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
## 相邻两枚金币的水平间距。金币贴图 84 像素宽，间距必须大于它才不会糊成一坨
@export var coin_spacing: float = 112.0
## 金币离柱子表面至少留出的余量（防止"看得见吃不到"）
@export var coin_pad: float = 70.0
## 弧线中段相对两端抬高多少
@export var coin_arc_lift: float = 42.0

## 柱子贴图宽度的一半。金币必须待在这条线以外，否则就嵌进柱子里了
const HALF_PILLAR: float = 192.0

var _cursor_x: float = 0.0
var _prev_aim: float = 240.0
## 上一个路障的 x，用来算出两根柱子之间的"净空走廊"
var _prev_pattern_x: float = 0.0
var _rng := RandomNumberGenerator.new()
var _player: Node2D = null

## 玩家已推进的距离（米），决定难度
var traveled_meters: float = 0.0


## 由主场景在 _ready 里调用
func begin(player: Node2D, start_x: float) -> void:
	_player = player
	_rng.randomize()
	_prev_pattern_x = start_x
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
	_spawn_coin_arc(_prev_pattern_x, x, aim)
	_prev_pattern_x = x


## 在「上一个路障」和「这一个路障」之间的净空走廊里铺一小段弧线金币。
##
## 以前是固定铺在路障前方 260 像素处：5 枚金币跨度 600 像素，尾巴直接扎进柱子里，
## 那几枚金币看得见、吃不到。现在先算出走廊的左右边界，再按间距反推最多能放几枚，
## 放不下就少放，保证每一枚都真的在两柱之间的空气里。
func _spawn_coin_arc(prev_x: float, obstacle_x: float, center: float) -> void:
	var left: float = prev_x + HALF_PILLAR + coin_pad
	var right: float = obstacle_x - HALF_PILLAR - coin_pad
	var width: float = right - left
	if width < coin_spacing * 0.5:
		return
	var capacity: int = int(width / coin_spacing) + 1
	var count: int = maxi(mini(_rng.randi_range(coin_arc_count_min, coin_arc_count_max),
			capacity), 1)
	var spread: float = coin_spacing * float(count - 1)
	# 整段弧线摆在走廊正中间；万一走廊比弧线还窄，clamp 保证不会越界
	var start_x: float = clampf((left + right - spread) * 0.5, left, right - spread)
	for i in count:
		var f: float = 0.0 if count == 1 else float(i) / float(count - 1)
		var coin := COIN_SCENE.instantiate()
		coin.position = Vector2(start_x + f * spread, center - sin(f * PI) * coin_arc_lift)
		add_child(coin)
		coin.collected.connect(_on_coin_collected)


func _on_obstacle_hit() -> void:
	# 无敌冲刺期间柱子只是穿过去，不算撞上。
	# 这里拦一道而不是改碰撞层：金币靠玩家的 layer 1 判定，动碰撞层会连金币一起废掉。
	if _player != null and _player.has_method("is_invincible") and _player.is_invincible():
		return
	player_hit.emit()


func _on_coin_collected() -> void:
	coin_collected.emit()
