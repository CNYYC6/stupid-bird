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
var _y: float = 0.0


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


func _physics_process(delta: float) -> void:
	if _target == null:
		return
	var desired: Vector2 = _target.global_position + follow_offset

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
