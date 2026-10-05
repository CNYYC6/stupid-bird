extends Node2D
## 无限地面碰撞。
##
## 原来主场景里只有两块 1925 宽的 StaticBody2D，玩家一加速（最高 10000+ 像素/秒）
## 不到一秒就冲出地面掉进虚空。
##
## 这里维持一条「连续的」碰撞块链：只要链的右端没覆盖到镜头右缘的余量之外，
## 就把最左边那块搬到最右边；左端同理。块的宽度是 1920，一帧最多搬一块
## （1920 像素）远大于最高速时的每帧位移（约 167 像素），所以永远追得上。
##
## 判据用的是 camera.get_screen_center_position()，也就是相机真正看向的位置。
## 用 camera.global_position 是错的：一旦开了 position_smoothing，两者能差上千像素。
##
## 路面视觉由 Ground（ParallaxStrip, scroll_factor = 1）绘制，两者都是世界坐标
## 且地面贴图左右无缝，所以视觉和物理永远咬合。

## 单块地面的宽度，必须和 ParallaxStrip 的地面贴图宽度一致
@export var chunk_width: float = 1920.0

## 视野左右各额外多覆盖的距离
@export var margin: float = 1500.0

var _chunks: Array[Node2D] = []


func _ready() -> void:
	for child in get_children():
		if child is Node2D:
			_chunks.append(child)
	_layout()


## 初始铺在玩家左侧一块开始，保证出生瞬间左边不会露空
func _layout() -> void:
	var start: float = -chunk_width
	for i in _chunks.size():
		_chunks[i].position = Vector2(start + i * chunk_width, 0.0)


func _physics_process(_delta: float) -> void:
	if _chunks.size() < 2:
		return
	var cam := get_viewport().get_camera_2d()
	if cam == null:
		return

	var center: Vector2 = cam.get_screen_center_position()
	var half_view: float = get_viewport_rect().size.x * 0.5 / maxf(cam.zoom.x, 0.001)
	var need_left: float = center.x - half_view - margin
	var need_right: float = center.x + half_view + margin

	# 总覆盖 = n * chunk_width，必须大于 need_right - need_left + chunk_width，
	# 否则会在左右之间来回搬运而抖动。主场景放了 4 块。
	for _i in _chunks.size():
		var leftmost: int = 0
		var rightmost: int = 0
		for j in _chunks.size():
			if _chunks[j].position.x < _chunks[leftmost].position.x:
				leftmost = j
			if _chunks[j].position.x > _chunks[rightmost].position.x:
				rightmost = j

		if _chunks[rightmost].position.x + chunk_width < need_right:
			_chunks[leftmost].position.x = _chunks[rightmost].position.x + chunk_width
		elif _chunks[leftmost].position.x > need_left:
			_chunks[rightmost].position.x = _chunks[leftmost].position.x - chunk_width
		else:
			break
