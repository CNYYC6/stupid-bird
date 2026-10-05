class_name ParallaxStrip
extends Node2D
## 世界空间的无缝横向视差条带。
##
## 为什么没有用内置的 Parallax2D：
## 本作的地平线必须和地面碰撞面在世界坐标里永远对齐。Parallax2D 工作在
## CanvasLayer 的屏幕空间里，镜头一上下移动，山脊和地面就会错开、露出接缝。
## 这里让所有图层的 y 固定在世界坐标，只在 x 方向按 scroll_factor 产生视差，
## 因此不管玩家飞多高，树线永远站在地面线上。
##
## 水平公式： position.x = camera.x * (1 - scroll_factor) + auto_offset
##   scroll_factor = 0 -> 完全跟随镜头（无限远，画面里几乎不动）
##   scroll_factor = 1 -> 与地面同速（等价于纯世界空间）
##
## 贴图会按 tile_width 横向复制若干份并循环取位，所以只要贴图本身左右无缝，
## 就能无限滚动。生成脚本 gen_backgrounds.py 里带了接缝自动检测。

## 平铺用的贴图，宽度即一个循环周期
@export var texture: Texture2D:
	set(value):
		texture = value
		if is_inside_tree():
			_rebuild()

## 平铺宽度（世界像素），<= 0 时自动取贴图宽度
@export var tile_width: float = 0.0

## 视差系数：0 = 无限远，1 = 与地面同速
@export_range(0.0, 1.0, 0.001) var scroll_factor: float = 0.5

## 额外的自动漂移速度（像素/秒），云层和开始界面靠它产生流动感
@export var auto_speed: float = 0.0

## 垂直方向跟随镜头的程度：
##   0 = 锁死在世界坐标（默认，和地面一起动）
##   1 = 锁死在屏幕上（贴在画面上不动，像天空）
@export_range(0.0, 1.0, 0.001) var vertical_follow: float = 0.0

## 在基准高度上再叠加的 y 偏移（世界像素）。
## 开始界面用它把「山腰 / 树线 / 地面」这三层一起上下推，做出地面起伏。
## 必须是偏移量而不是直接改 position.y —— 下面 _physics_process 每帧都会重算 position.y。
@export var y_offset: float = 0.0
## 水平方向的固定偏移。天空靠它把贴图对齐到屏幕正中（-半个屏宽）
@export var x_offset: float = 0.0
## 视野之外左右各多铺这么宽。
## 分屏时子视口的相机在主相机两侧最多能偏出上千像素，天空这类
## scroll_factor=0（锁死相机）的条带必须多铺一点，否则那半屏顶部会露黑边。
@export var coverage_margin: float = 0.0
## 上下翻转整条（"上下颠倒"那个世界用）
@export var flip_v: bool = false:
	set(v):
		flip_v = v
		for t in _tiles:
			t.flip_v = v

var _tiles: Array[Sprite2D] = []
var _auto_offset: float = 0.0
var _base_y: float = 0.0


func _ready() -> void:
	_base_y = position.y
	_rebuild()


func _rebuild() -> void:
	for t in _tiles:
		t.queue_free()
	_tiles.clear()
	if texture == null:
		push_warning("ParallaxStrip「%s」没有设置 texture" % name)
		return
	if tile_width <= 0.0:
		tile_width = float(texture.get_width())
	if tile_width <= 0.0:
		return
	var need: int = int(ceil((_visible_width() + coverage_margin * 2.0) / tile_width)) + 2
	for i in need:
		var s := Sprite2D.new()
		s.texture = texture
		s.centered = false
		s.position = Vector2(i * tile_width, 0.0)
		s.flip_v = flip_v
		add_child(s)
		_tiles.append(s)


## 当前可见的世界宽度（考虑相机 zoom）
func _visible_width() -> float:
	var vw: float = get_viewport_rect().size.x
	var cam := get_viewport().get_camera_2d()
	if cam == null:
		return vw
	return vw / maxf(cam.zoom.x, 0.001)


## 相机真正看向的世界坐标。
##
## 必须用 get_screen_center_position()，不能用 camera.global_position：
## 后者不含 offset / 平滑 / drag 的影响，本作相机的水平偏移就靠它才能算对，
## 否则铺砖整体偏移，画面左侧会缺一整块、露出天空。
func _camera_center() -> Vector2:
	var cam := get_viewport().get_camera_2d()
	if cam == null:
		return Vector2.ZERO
	return cam.get_screen_center_position()


func _physics_process(delta: float) -> void:
	if _tiles.is_empty():
		return

	_auto_offset = fmod(_auto_offset + auto_speed * delta, tile_width)

	var center := _camera_center()

	position.x = center.x * (1.0 - scroll_factor) + _auto_offset + x_offset
	position.y = _base_y + center.y * vertical_follow + y_offset

	# 把整排贴图对齐到「左边界再往左一个周期」，保证视野内始终被铺满
	var left: float = center.x - _visible_width() * 0.5 - coverage_margin
	var base: float = floor((left - position.x) / tile_width) * tile_width
	for i in _tiles.size():
		_tiles[i].position.x = base + i * tile_width
