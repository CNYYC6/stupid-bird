extends Camera2D
## 跟随相机。
##
## 为什么不用 Camera2D 自带的 position_smoothing：
## 平滑跟随的稳态滞后是 v / speed。原来 speed = 2.0，小鸟最高 10000 像素/秒，
## 滞后高达 5000 像素——小鸟在高速时会被甩到屏幕右侧之外，而且所有视差图层
## 若按相机节点坐标铺砖，左侧会整整缺一块、露出天空。
## 所以这里水平方向硬跟随，垂直方向自己做一个「死区 + 指数平滑」，
## 既不会上下抖，也不会有滞后。

## 跟随目标（通常指向 Player）
@export var target_path: NodePath

## 相机相对目标的偏移：x 往右看一点（跑酷预判），y 抬一点（多留天空）
@export var follow_offset: Vector2 = Vector2(140.0, -90.0)

## 垂直死区（像素）：目标在这个范围内上下动时相机完全不动
@export var vertical_deadzone: float = 80.0

## 垂直平滑速度（越大越紧跟）
@export var vertical_smooth: float = 7.0

## 相机与目标的垂直距离上限，保证小鸟永远不会跑出画面
@export var vertical_limit: float = 320.0

## true = 垂直方向完全钉死。
## 跑酷必须这么做：如果相机跟着小鸟上下漂，路障也会跟着画面浮沉，
## 玩家没法判断缝隙到底在屏幕的哪个高度。固定住以后垂直视野就是一个稳定的参考系。
@export var fixed_vertical: bool = false
## 钉死时使用的世界 y
@export var fixed_y: float = 330.0

var _target: Node2D
## 多目标模式（双人合作）：相机跟所有"活着"的目标的重心
var _targets: Array[Node2D] = []
var _y: float = 0.0

## 目标集合发生"跳变"的判定阈值（像素/帧）。
## 双人模式里一个人倒地时，重心会从两人平均瞬间变成只剩活着的那个 ——
## 那是几百像素的瞬移，必须平滑掉；而正常飞行时重心每帧只挪十几像素，
## 不会被误判，所以日常跟随仍然是零滞后的硬跟随。
const FOCUS_JUMP: float = 150.0
## 跳变后的过渡速度（越大越快追平）
const FOCUS_BLEND: float = 6.5
## 过渡最多持续多久
const FOCUS_BLEND_MAX: float = 0.9

var _raw_prev: Vector2 = Vector2.ZERO
var _has_prev: bool = false
var _blend_left: float = 0.0
var _focus_pos: Vector2 = Vector2.ZERO


## 双人模式：改成跟随一组目标。传空数组则退回单目标 target_path。
func set_targets(nodes: Array) -> void:
	_targets.clear()
	for n in nodes:
		if n is Node2D:
			_targets.append(n)
	if not _targets.is_empty():
		reset_to(_focus())
	else:
		_target = get_node_or_null(target_path) as Node2D


## 所有存活目标的重心。全倒了就保持原地，等结算界面接管。
func _focus() -> Vector2:
	var sum := Vector2.ZERO
	var n: int = 0
	for t in _targets:
		if not is_instance_valid(t):
			continue
		if t.has_method("is_alive") and not t.is_alive():
			continue
		sum += t.global_position
		n += 1
	if n == 0:
		return global_position
	return sum / float(n)


func _ready() -> void:
	offset = Vector2.ZERO  # 偏移已经并进 global_position，避免 get_screen_center_position 重复计算
	_target = get_node_or_null(target_path) as Node2D
	if _target == null:
		_target = get_parent() as Node2D
	if _target != null:
		reset_to(_target.global_position)


## 立刻把相机贴到目标上（重开一局时用，避免平滑追过去）
func reset_to(target_position: Vector2) -> void:
	_y = fixed_y if fixed_vertical else target_position.y + follow_offset.y
	global_position = Vector2(target_position.x + follow_offset.x, _y)


## 目标集合变化时给出一个平滑过的重心。
## 平时直接返回真值（零滞后），只在检测到跳变后的 FOCUS_BLEND_MAX 秒内做指数过渡。
func _smooth_focus(focus: Vector2, delta: float) -> Vector2:
	if not _has_prev:
		_raw_prev = focus
		_has_prev = true
		_focus_pos = focus
		return focus
	if focus.distance_to(_raw_prev) > FOCUS_JUMP:
		_blend_left = FOCUS_BLEND_MAX
	_raw_prev = focus
	if _blend_left > 0.0:
		_blend_left = maxf(_blend_left - delta, 0.0)
		_focus_pos = _focus_pos.lerp(focus, 1.0 - exp(-FOCUS_BLEND * delta))
		if _blend_left <= 0.0:
			_focus_pos = focus
		return _focus_pos
	_focus_pos = focus
	return focus


func _physics_process(delta: float) -> void:
	var focus: Vector2
	if not _targets.is_empty():
		focus = _smooth_focus(_focus(), delta)
	elif _target != null:
		focus = _target.global_position
	else:
		return
	var desired: Vector2 = focus + follow_offset

	# 水平硬跟随
	global_position.x = desired.x

	if fixed_vertical:
		global_position.y = fixed_y
		return

	# 垂直：只有超出死区才追赶，追赶本身再做指数平滑
	var err: float = desired.y - _y
	if absf(err) > vertical_deadzone:
		var pull: float = (absf(err) - vertical_deadzone) * signf(err)
		_y += pull * (1.0 - exp(-vertical_smooth * delta))
	_y = clampf(_y, desired.y - vertical_limit, desired.y + vertical_limit)
	global_position.y = _y
