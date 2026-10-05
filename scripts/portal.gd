extends Area2D
## 传送门：飞进去就被吸进「金币维度」。
##
## 帧贴图放在 static 数组里共享（和 coin.gd 一样的手法），不建 SpriteFrames 资源。
## 判定盒做得比视觉略大一圈，玩家"擦着边"飞过去也算进 —— 这是个奖励，
## 不该让人因为 3 像素的误差错过 20 秒的金币狂欢。

signal entered

const FRAME_PATHS: Array[String] = [
	"res://art/ev_portal_0.png", "res://art/ev_portal_1.png",
	"res://art/ev_portal_2.png", "res://art/ev_portal_3.png",
]
const FRAME_TIME: float = 0.08
## 上下浮动的幅度与频率，让它看起来是"活"的
const BOB_AMP: float = 22.0
const BOB_SPEED: float = 2.6

static var _frames: Array[Texture2D] = []

@onready var _sprite: Sprite2D = $Sprite

var used: bool = false
var _t: float = 0.0
var _i: int = 0
var _base_y: float = 0.0
var _fade: float = 1.0


func _ready() -> void:
	add_to_group("portal")
	if _frames.is_empty():
		for path in FRAME_PATHS:
			_frames.append(load(path))
	_sprite.texture = _frames[0]
	_base_y = position.y
	# 贴图在 gen_events.py 里已经按 S=6 放大过（216x360 屏幕像素），代码里不能再乘
	body_entered.connect(_on_body_entered)


func _process(delta: float) -> void:
	_t += delta
	if _t >= FRAME_TIME:
		_t = 0.0
		_i = (_i + 1) % _frames.size()
		_sprite.texture = _frames[_i]
	position.y = _base_y + sin(Time.get_ticks_msec() * 0.001 * BOB_SPEED) * BOB_AMP
	if used:
		# 被吸进去之后快速缩小消失，给一个"关上了"的反馈
		_fade = maxf(_fade - delta * 3.2, 0.0)
		_sprite.scale = Vector2.ONE * _fade
		if _fade <= 0.0:
			queue_free()


func _on_body_entered(body: Node2D) -> void:
	if used or not body.is_in_group("player"):
		return
	used = true
	# 必须 deferred：Godot 不允许在 Area2D 的信号回调里直接改 monitoring
	set_deferred("monitoring", false)
	entered.emit()
