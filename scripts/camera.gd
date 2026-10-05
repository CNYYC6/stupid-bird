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

## 重心平滑速度（越大跟得越紧）。
##
## 这里**始终**对重心做指数平滑，而不是"检测到跳变才平滑"。原因是阈值法很脆：
## 双人模式下两台飞行器本来就有一个 x 偏移，一个人倒地时重心只会挪半个偏移量
## （比如 85 像素），刚好落在阈值以下 —— 于是照样瞬移。
##
## 平滑的是**目标点**而不是相机自身，所以稳态只是一个固定的小偏移
## （最高速时 v / FOCUS_SMOOTH ≈ 76 像素），不会像早期版本那样累积成几千像素的滞后。
## 那个坑是 position_smoothing_speed = 2.0 配 10000 像素/秒的速度，完全不是一回事。
const FOCUS_SMOOTH: float = 13.0

## 是否连倒地/阵亡的目标也一起跟。
## 分屏的小画面用 true —— 队友倒了你得看得见他躺哪儿；
## 主相机用 false —— 有人倒地时视角应该让给还活着的人。
@export var follow_dead: bool = false

## 分屏时两名玩家相对相机的最大横向偏离（世界像素）。
## 关卡生成和视差铺砖都要按它加宽 —— 否则靠后的那名玩家会看到
## 空掉的背景、以及身后已经被回收掉的柱子。
var view_spread: float = 0.0

var _focus_pos: Vector2 = Vector2.ZERO
var _has_focus: bool = false


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
		if not follow_dead and t.has_method("is_alive") and not t.is_alive():
			continue
		sum += t.global_position
		n += 1
	if n == 0:
		# 一个都不剩：保持原地。
		# 这里必须**减掉 follow_offset** —— 调用方随后还会再加一次，
		# 不减的话相机每帧都会往右挪一个 follow_offset，自己一路飘走。
		return global_position - follow_offset
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
	# 平滑器的内部状态也要一起归零，否则初始那段会从旧位置慢慢爬过来
	_focus_pos = target_position
	_has_focus = true


## 重心的一阶低通。任何变化（有人倒地退出重心、复活加入重心、两台分开）
## 都会走这里，所以视角永远是滑过去的，不会瞬移。
func _smooth_focus(focus: Vector2, delta: float) -> Vector2:
	if not _has_focus:
		_focus_pos = focus
		_has_focus = true
		return focus
	_focus_pos = _focus_pos.lerp(focus, 1.0 - exp(-FOCUS_SMOOTH * delta))
	return _focus_pos


## 世界坐标重定基时跟着一起平移内部状态。
## 否则平滑器会以为目标瞬移了 26 万像素，要花很久才追回来。
func shift_x(dx: float) -> void:
	global_position.x -= dx
	_focus_pos.x -= dx


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
