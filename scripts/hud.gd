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
	"res://art/ui/en/ui_dash_ready.png",
	"res://art/ui/en/ui_dash_active.png",
	"res://art/ui/en/ui_dash_cool.png",
]

const COLOR_READY := Color(1.0, 0.92, 0.30)
const COLOR_ACTIVE := Color(1.0, 0.80, 0.16)
const COLOR_COOLING := Color(0.38, 0.47, 0.58)

## 填充条离槽壁留出的内边距
const FILL_PAD: float = 4.0
## 双人模式里第二条能量条相对第一条上移多少
const ENERGY_STACK: float = 190.0

@onready var _distance: HBoxContainer = $Root/Bar/DistancePlate/Distance/Digits
@onready var _coins: HBoxContainer = $Root/Bar/CoinPlate/Coin/Digits
@onready var _track: Panel = $Energy/Plate/Layout/Track
@onready var _fill: ColorRect = $Energy/Plate/Layout/Track/Fill
@onready var _state: TextureRect = $Energy/Plate/Layout/Head/State
@onready var _tag: TextureRect = $Energy/Plate/Layout/Head/Tag
@onready var _revive: HBoxContainer = $Revive
@onready var _revive_tag: TextureRect = $Revive/Tag
@onready var _revive_digits: HBoxContainer = $Revive/Digits
@onready var _energy: Control = $Energy
@onready var _banner: Control = $Banner
@onready var _banner_title: TextureRect = $Banner/Title
@onready var _banner_sub: TextureRect = $Banner/Sub
@onready var _fever: Control = $Fever
@onready var _fever_digits: HBoxContainer = $Fever/Plate/Row/Digits
@onready var _combo: HBoxContainer = $Combo
@onready var _combo_digits: HBoxContainer = $Combo/Digits
@onready var _power: HBoxContainer = $Power
@onready var _power_icon: TextureRect = $Power/Icon
@onready var _power_digits: HBoxContainer = $Power/Digits

var _textures: Array[Texture2D] = []
## 每个玩家一份能量条（单人只有一条，双人时运行期复制出第二条）
var _bars: Array[Dictionary] = []

## 换世界横幅的剩余显示时间
const BANNER_TIME: float = 2.4
var _banner_left: float = 0.0


func _ready() -> void:
	UiLang.apply(self)
	for path in STATE_TEXTURES:
		_textures.append(load(UiLang.swap_path(path, UiLang.code())))
	# 槽的实际尺寸要等容器布局跑完才靠谱，直接挂 resized 信号最稳
	_track.resized.connect(_refresh_fill)
	_refresh_fill()
	_bars = [{"track": _track, "fill": _fill, "state": _state, "ratio": 1.0, "index": -1}]
	# 单人模式不挂编号牌，双人模式由 setup_players 补上
	_tag.visible = false
	# 没人在倒地状态时，复活倒计时整块不出现
	_revive.visible = false
	_banner.visible = false
	_fever.visible = false
	_combo.visible = false
	_power.visible = false


func _process(delta: float) -> void:
	if _power.visible and not _power_digits.visible:
		_power_left -= delta
		if _power_left <= 0.0:
			_power.visible = false
	if _banner_left <= 0.0:
		return
	_banner_left = maxf(_banner_left - delta, 0.0)
	var t: float = _banner_left / BANNER_TIME
	# 进出各占 15% 时间做淡入淡出，中间保持全不透明
	_banner.modulate.a = clampf(minf((1.0 - t) / 0.15, t / 0.15), 0.0, 1.0)
	if _banner_left <= 0.0:
		_banner.visible = false


## 换世界：飞一张大横幅进来（中文只能烘成贴图，所以标题和副标题都是 PNG）
func show_world_banner(id: String) -> void:
	show_banner(Worlds.title_path(id), Worlds.sub_path(id))


## 随机事件的横幅
func show_event_banner(id: String) -> void:
	show_banner(UiLang.path("ev_title_%s.png" % id), UiLang.path("ev_sub_%s.png" % id))


func show_banner(title_path: String, sub_path: String) -> void:
	var title := load(title_path) as Texture2D
	if title == null:
		return
	var sub := load(sub_path) as Texture2D
	_banner_title.texture = title
	_banner_sub.texture = sub
	_banner_sub.visible = sub != null
	_banner.visible = true
	_banner_left = BANNER_TIME
	_banner.modulate.a = 0.0


## 连击数。低于 5 连不显示（否则画面一直在闪），倍率大于 1 时染成金色提醒。
func set_combo(count: int, multiplier: int) -> void:
	_combo.visible = count >= 5
	if not _combo.visible:
		return
	_combo_digits.set_value(count)
	var tint := COLOR_READY if multiplier > 1 else Color(1, 1, 1)
	_combo.modulate = Color(tint.r, tint.g, tint.b, 1.0)


## 道具状态。kind < 0 = 什么都不显示；
## 磁铁带倒计时，护盾/爆发只显示一小会儿。
const POWER_LABELS: Array[String] = [
	"res://art/ui/en/ui_pu_magnet.png",
	"res://art/ui/en/ui_pu_shield.png",
	"res://art/ui/en/ui_pu_burst.png",
]
var _power_left: float = 0.0


func set_powerup(kind: int, seconds: float) -> void:
	if kind < 0:
		_power_left = 0.0
		_power.visible = false
		return
	_power_icon.texture = load(UiLang.swap_path(POWER_LABELS[clampi(kind, 0, POWER_LABELS.size() - 1)], UiLang.code()))
	_power.visible = true
	if seconds > 0.0:
		_power_left = seconds
		_power_digits.set_value(ceili(seconds))
		_power_digits.visible = true
		$Power/Unit.visible = true
	else:
		# 护盾 / 爆发没有倒计时，靠 _process 里的计时器自己消失
		_power_left = 2.0
		_power_digits.visible = false
		$Power/Unit.visible = false


## 金币维度倒计时：打开时显示剩余秒数，关掉时隐藏
func set_fever(on: bool, seconds_left: float) -> void:
	_fever.visible = on
	if on:
		_fever_digits.set_value(maxi(ceili(seconds_left), 0))


## 飞行距离（米）
func set_distance(meters: float) -> void:
	_distance.set_value(floori(meters))


## 金币数
func set_coins(count: int) -> void:
	_coins.set_value(count)


## 双人模式：把右下角的能量条复制一份往上摞，标成 P2。
## 用 duplicate() 而不是在 .tscn 里再搭一遍 —— 单人玩家完全看不到第二个控件。
func setup_players(count: int) -> void:
	if count < 2:
		return
	# 两条能量条各挂一个 P1 / P2 圆牌，不然双人时根本分不清哪条是谁的
	_tag.visible = true
	_tag.texture = load("res://art/badge_p1.png")
	if _bars.size() >= 2:
		return
	# 先把原控件复制一份留在原位（它会成为 P2 那条），
	# 再把原控件往上挪（它是 P1）—— 这样 P1 在上、P2 在下，和玩家编号顺序一致。
	var second := _energy.duplicate() as Control
	second.name = "Energy2"
	add_child(second)
	_energy.offset_top -= ENERGY_STACK
	_energy.offset_bottom -= ENERGY_STACK
	var t: Panel = second.get_node("Plate/Layout/Track")
	var f: ColorRect = second.get_node("Plate/Layout/Track/Fill")
	var st: TextureRect = second.get_node("Plate/Layout/Head/State")
	var tag: TextureRect = second.get_node("Plate/Layout/Head/Tag")
	tag.visible = true
	# 机哥模式下的二号机玩家还是 P2 的键位，但实际操控者不是人 —— 由 main 覆盖
	tag.texture = load("res://art/badge_p2.png")
	t.resized.connect(func() -> void: _refresh_bar(_bars[1]))
	_bars.append({"track": t, "fill": f, "state": st, "ratio": 1.0, "index": -1})
	_refresh_bar(_bars[1])


## 显示某个玩家的复活倒计时（index 从 0 起）。seconds <= 0 或 index < 0 就整块隐藏。
func set_revive(index: int, seconds: float, bot: bool = false) -> void:
	if index < 0 or seconds <= 0.0:
		_revive.visible = false
		return
	_revive.visible = true
	_revive_tag.texture = load("res://art/badge_%s.png" % ("bot" if bot else "p%d" % (index + 1)))
	# 数字是"还剩几秒"，向上取整 —— 显示 1 的时候真的还有最后一秒
	_revive_digits.set_value(maxi(int(ceil(seconds)), 0))


## 把某一条能量条的编号牌换成别的图（机哥模式把二号机换成 AI 标志）
func set_bar_tag(index: int, path: String) -> void:
	if index < 0 or index >= _bars.size():
		return
	var bar: Dictionary = _bars[index]
	var head: Node = (bar["state"] as Node).get_parent()
	var tag: TextureRect = head.get_node("Tag")
	tag.visible = true
	tag.texture = load(path)


## 第 index 个玩家的能量条。ratio 0~1，state 取 player.gd 的 DashState
func set_dash(index: int, ratio: float, state: int) -> void:
	if index < 0 or index >= _bars.size():
		return
	var bar: Dictionary = _bars[index]
	bar["ratio"] = clampf(ratio, 0.0, 1.0)
	if state != int(bar["index"]):
		bar["index"] = state
		if state >= 0 and state < _textures.size():
			(bar["state"] as TextureRect).texture = _textures[state]
	_refresh_bar(bar)


func _refresh_bar(bar: Dictionary) -> void:
	var track: Panel = bar["track"]
	var inner: Vector2 = track.size - Vector2(FILL_PAD * 2.0, FILL_PAD * 2.0)
	inner.x = maxf(inner.x, 0.0)
	inner.y = maxf(inner.y, 0.0)
	var fill: ColorRect = bar["fill"]
	fill.position = Vector2(FILL_PAD, FILL_PAD)
	fill.size = Vector2(inner.x * float(bar["ratio"]), inner.y)
	match int(bar["index"]):
		1:
			fill.color = COLOR_ACTIVE
		2:
			fill.color = COLOR_COOLING
		_:
			fill.color = COLOR_READY


func _refresh_fill() -> void:
	if not _bars.is_empty():
		_refresh_bar(_bars[0])
