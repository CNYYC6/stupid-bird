extends Node2D
## 世界（生物群系）切换器。
##
## 负责三件事：
##   1. 按飞行距离轮换世界 —— 换掉天空 / 4 层视差 / 地面 / 路障皮肤；
##   2. 「上下颠倒」世界靠相机 zoom.y 取负整屏翻转（顺带把天空层 flip_v）；
##   3. 把当前世界的重力倍率告诉玩家，并广播换世界事件给 HUD 放横幅。
##
## 传送门事件会临时借道这里强制切到金币维度，事件结束再切回来，
## 所以对外只有 apply() / restore() 两个动作。

signal world_changed(index: int, id: String)
signal banner_requested(id: String)

@export_group("节点")
@export var sky_path: NodePath
@export var ground_path: NodePath
@export var camera_path: NodePath
@export var course_path: NodePath
@export var player_path: NodePath
## 4 层视差，顺序必须是 远 → 近
@export var layer_paths: Array[NodePath] = []

@export_group("节奏")
## 出发后多少**秒**换第一个世界
@export var first_switch_seconds: float = 30.0
## 之后每隔多少**秒**换一次
##
## 按时间而不是按距离：玩家加速/冲刺时距离涨得快得多（660 → 990 像素/秒），
## 用距离当间隔会导致"跑得越快换得越勤"，同一段世界待的时长飘忽不定。
@export var switch_every_seconds: float = 30.0

var index: int = 0

var _sky: ParallaxStrip
var _layers: Array[ParallaxStrip] = []
var _ground: ParallaxStrip
var _cam: Camera2D
var _course: Node2D
var _player: Node2D

var _step: int = 0
## 本局已经跑了多少秒（世界轮换用）
var _elapsed: float = 0.0
var _next_at: float = 0.0
## 事件强制占用世界时记下原来的索引，事件结束后恢复
var _borrowed: bool = false


func _ready() -> void:
	_sky = get_node_or_null(sky_path) as ParallaxStrip
	_ground = get_node_or_null(ground_path) as ParallaxStrip
	_cam = get_node_or_null(camera_path) as Camera2D
	_course = get_node_or_null(course_path) as Node2D
	_player = get_node_or_null(player_path) as Node2D
	for p in layer_paths:
		var n := get_node_or_null(p) as ParallaxStrip
		if n != null:
			_layers.append(n)
	_next_at = first_switch_seconds
	apply(0, false)


func _physics_process(delta: float) -> void:
	if _borrowed:
		return
	_elapsed += delta
	if _elapsed < _next_at:
		return
	_next_at = _elapsed + switch_every_seconds
	_step += 1
	apply(Worlds.rotation_index(_step), true)


## 切到第 i 个世界并立刻生效
func apply(i: int, announce: bool = true) -> void:
	index = wrapi(i, 0, Worlds.LIST.size())
	var d: Dictionary = Worlds.get_def(index)

	if _sky != null:
		_sky.texture = load(d["sky"])
		# 天空现在也是世界里的视差条（相机锁死、垂直完全跟随），
		# 所以相机翻转不会带上它，得自己翻
		_sky.flip_v = bool(d.get("flip", false))

	var keys: Array = ["clouds", "far", "mid", "near"]
	for k in mini(_layers.size(), keys.size()):
		_layers[k].texture = load(d[keys[k]])

	if _ground != null:
		_ground.texture = load(d["ground"])

	if _course != null and _course.has_method("set_skin"):
		_course.set_skin(d)

	if _cam != null:
		# 用 abs 保住原始缩放，重复切换不会把 zoom 累积成 0
		_cam.zoom.y = -absf(_cam.zoom.y) if bool(d.get("flip", false)) else absf(_cam.zoom.y)

	# 换世界同时换 BGM，Audio 里做交叉淡化，所以听起来是丝滑过去的
	Audio.play_world_bgm(str(d["id"]))

	if announce:
		world_changed.emit(index, str(d["id"]))
		banner_requested.emit(str(d["id"]))


## 事件临时占用世界（例如传送门把画面切进金币维度）
func borrow(i: int, announce: bool = true) -> void:
	_borrowed = true
	apply(i, announce)


## 事件结束，把常规轮换的世界切回来
func restore() -> void:
	_borrowed = false
	apply(Worlds.rotation_index(_step), true)


## 当前世界的重力倍率（事件想改重力时拿它当基准）
func base_gravity_scale() -> float:
	return float(Worlds.get_def(index).get("gravity", 1.0))
