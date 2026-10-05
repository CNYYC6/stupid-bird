extends Node2D
## 路障：一根地面柱 + 一根悬挂柱，中间留出可以通过的缝隙。
##
## 柱子用「一张纵向可平铺的长贴图 + region_rect 截取」来画，所以任意高度都只占
## 一个 Sprite2D，不需要堆一摞节点，也不会出现非整数缩放导致的像素抖动。
## 贴图做成 1200 像素高，比关卡里任何一根柱子都高，因此不依赖 region 的重复采样行为。

signal hit

const PILLAR_W: float = 384.0        # 贴图宽度（已是 6 倍放大后的像素）
const PILLAR_TEX_H: float = 1200.0
const CAP_H: float = 84.0

@onready var _bottom: Node2D = $Bottom
@onready var _bottom_shaft: Sprite2D = $Bottom/Shaft
@onready var _bottom_cap: Sprite2D = $Bottom/Cap
@onready var _top: Node2D = $Top
@onready var _top_shaft: Sprite2D = $Top/Shaft
@onready var _top_cap: Sprite2D = $Top/Cap
@onready var _bottom_shape: CollisionShape2D = $Hitbox/BottomShape
@onready var _top_shape: CollisionShape2D = $Hitbox/TopShape

## 缝隙上下沿与中心的世界 y，供 AI/测试脚本判断该往哪飞
var gap_center: float = 0.0
var gap_top_edge: float = 0.0
var gap_bottom_edge: float = 0.0


func _ready() -> void:
	add_to_group("obstacle")
	# .tscn 里的 sub_resource 默认被所有实例共享！不复制的话，每根柱子调整自己的
	# 碰撞盒尺寸会把其他所有路障的一起改掉，判定框和看到的路障完全对不上。
	_bottom_shape.shape = _bottom_shape.shape.duplicate()
	_top_shape.shape = _top_shape.shape.duplicate()
	$Hitbox.body_entered.connect(_on_body_entered)


## gap_top / gap_bottom 是缝隙上下沿的世界 y（y 轴向下）。
## road_y 是路面高度，sky_top 是悬挂柱向上延伸到的高度（远在画面之上）。
func configure(gap_top: float, gap_bottom: float, road_y: float, sky_top: float) -> void:
	gap_top_edge = gap_top
	gap_bottom_edge = gap_bottom
	# "安全飞行高度"：上下都挡时取缝隙中点；只挡一边时贴着缺口内沿留出余量，
	# 用几何中点会得到毫无意义的值（只挡下面时缝隙上沿在画面之上，中点在天上）
	var clearance: float = 130.0
	if gap_top <= sky_top + 1.0:
		gap_center = gap_bottom - clearance
	elif gap_bottom >= road_y - 1.0:
		gap_center = gap_top + clearance
	else:
		gap_center = (gap_top + gap_bottom) * 0.5
	# 地面柱：从缝隙下沿一直长到路面，端头在上
	_setup_column(_bottom, _bottom_shaft, _bottom_cap, _bottom_shape,
			gap_bottom, road_y, true)
	# 悬挂柱：从画面之上一直垂到缝隙上沿，端头在下
	_setup_column(_top, _top_shaft, _top_cap, _top_shape,
			sky_top, gap_top, false)


## 一根柱子：从 from_y 长到 to_y。cap_at_start = true 表示端头在上方（地面柱）。
func _setup_column(root: Node2D, shaft: Sprite2D, cap: Sprite2D, shape: CollisionShape2D,
		from_y: float, to_y: float, cap_at_start: bool) -> void:
	var height: float = to_y - from_y
	if height < 4.0:
		# 这类路障不需要这一半，整个隐藏（"只挡下面"和"只挡上面"两种图案靠它实现）
		root.visible = false
		shape.disabled = true
		return

	root.visible = true
	shape.disabled = false
	var shaft_h: float = minf(height - CAP_H, PILLAR_TEX_H)
	var cap_y: float = from_y if cap_at_start else to_y - CAP_H
	var shaft_y: float = from_y + CAP_H if cap_at_start else to_y - CAP_H - shaft_h

	cap.centered = false
	cap.position = Vector2(0.0, cap_y)

	shaft.centered = false
	shaft.position = Vector2(0.0, shaft_y)
	shaft.region_enabled = true
	shaft.region_rect = Rect2(0.0, 0.0, PILLAR_W, shaft_h)

	shape.position = Vector2(PILLAR_W * 0.5, from_y + height * 0.5)
	var rect := shape.shape as RectangleShape2D
	rect.size = Vector2(PILLAR_W, height)


func _on_body_entered(body: Node2D) -> void:
	if not body.is_in_group("player"):
		return
	hit.emit()
