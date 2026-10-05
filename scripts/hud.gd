extends CanvasLayer
## HUD：飞行距离、金币数，以及右下角的「无敌冲刺」能量条。
##
## 速度读数被删掉了：跑酷里距离和金币才是目标，速度是玩家能直接感觉到的，
## 而且三块读数并排会超出 1920 宽度。速度仍然在后台驱动升力。
##
## 能量条放在右下角，离小鸟（画面左侧 1/4）和上方的距离/金币都最远，
## 高速飞行时不会和主要读数抢注意力。

## 状态贴图的下标必须和 player.gd 的 DashState 枚举一致
const STATE_TEXTURES: Array[String] = [
	"res://art/ui_dash_ready.png",
	"res://art/ui_dash_active.png",
	"res://art/ui_dash_cool.png",
]

const COLOR_READY := Color(1.0, 0.92, 0.30)
const COLOR_ACTIVE := Color(1.0, 0.80, 0.16)
const COLOR_COOLING := Color(0.38, 0.47, 0.58)

## 填充条离槽壁留出的内边距
const FILL_PAD: float = 4.0

@onready var _distance: HBoxContainer = $Root/Bar/DistancePlate/Distance/Digits
@onready var _coins: HBoxContainer = $Root/Bar/CoinPlate/Coin/Digits
@onready var _track: Panel = $Energy/Plate/Layout/Track
@onready var _fill: ColorRect = $Energy/Plate/Layout/Track/Fill
@onready var _state: TextureRect = $Energy/Plate/Layout/Head/State

var _textures: Array[Texture2D] = []
var _ratio: float = 1.0
var _state_index: int = -1


func _ready() -> void:
	for path in STATE_TEXTURES:
		_textures.append(load(path))
	# 槽的实际尺寸要等容器布局跑完才靠谱，直接挂 resized 信号最稳
	_track.resized.connect(_refresh_fill)
	_refresh_fill()
	set_dash(1.0, 0)


## 飞行距离（米）
func set_distance(meters: float) -> void:
	_distance.set_value(floori(meters))


## 金币数
func set_coins(count: int) -> void:
	_coins.set_value(count)


## 能量条。ratio 是 0~1 的进度，state 取 player.gd 的 DashState（0 就绪 / 1 发动 / 2 冷却）
func set_dash(ratio: float, state: int) -> void:
	_ratio = clampf(ratio, 0.0, 1.0)
	if state != _state_index:
		_state_index = state
		if state >= 0 and state < _textures.size():
			_state.texture = _textures[state]
	_refresh_fill()


func _refresh_fill() -> void:
	var inner: Vector2 = _track.size - Vector2(FILL_PAD * 2.0, FILL_PAD * 2.0)
	inner.x = maxf(inner.x, 0.0)
	inner.y = maxf(inner.y, 0.0)
	_fill.position = Vector2(FILL_PAD, FILL_PAD)
	_fill.size = Vector2(inner.x * _ratio, inner.y)
	match _state_index:
		1:
			_fill.color = COLOR_ACTIVE
		2:
			_fill.color = COLOR_COOLING
		_:
			_fill.color = COLOR_READY
