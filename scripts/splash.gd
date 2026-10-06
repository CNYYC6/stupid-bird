extends Control
## 开屏：蓝天白云 + 飘动的云和上升的金币，"YYCHRER" 七个字母依次弹出。
##
## 全程控制在两秒内 —— 开屏是"露个脸"，不是让人等的东西。
## 字母位置手算而不是用容器：容器会在动画期间反复重排，和 scale 打架。

const LETTERS := 7
const TEXT_W: float = 1400.0     ## 整词宽度（1920 的 73%）
const GAP: float = 26.0          ## 字母间距（原生像素）
const STEP: float = 0.15         ## 相邻字母的出现间隔
const POP: float = 0.28          ## 单个字母弹出的时长
const HOLD: float = 0.30         ## 全部出现后停留多久
const FADE: float = 0.25         ## 淡出时长
## 合计 ≈ 7*0.15 + 0.28 + 0.30 + 0.25 = 1.88 秒

## 金币的数量和下落速度 —— 要的就是"下金币雨"的密度
const COIN_COUNT: int = 46
const COIN_SPEED_MIN: float = 190.0
const COIN_SPEED_MAX: float = 430.0

var _letters: Array[TextureRect] = []
var _coins: Array[Sprite2D] = []
var _coin_vy: Array[float] = []
var _coin_spin: Array[float] = []
var _elapsed: float = 0.0
var _done: bool = false


func _ready() -> void:
	var vp: Vector2 = get_viewport().get_visible_rect().size
	_build_backdrop(vp)
	_build_letters(vp)

	var hint: TextureRect = $Hint
	hint.modulate.a = 0.0
	create_tween().tween_property(hint, "modulate:a", 0.8, 0.35).set_delay(0.9)

	UiLang.apply(self)
	_pulse()


## 蓝天背景 + 从天而降的金币雨
func _build_backdrop(vp: Vector2) -> void:
	var sky := TextureRect.new()
	sky.texture = load("res://art/bg_sky.png")
	sky.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sky.stretch_mode = TextureRect.STRETCH_SCALE
	sky.size = vp
	sky.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sky.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(sky)
	move_child(sky, 0)

	# 金币雨：从屏幕上方落下来，出了下边界就从顶上重新开始。
	# 起始 y 随机散布在"屏幕上方一屏"的范围内，所以一开始就是满屏在下，
	# 而不是等它们慢慢落进来。
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for i in COIN_COUNT:
		var s := Sprite2D.new()
		s.texture = load("res://art/coin_%d.png" % (i % 4))
		s.position = Vector2(rng.randf_range(20.0, vp.x - 20.0),
			rng.randf_range(-vp.y, vp.y))
		s.scale = Vector2.ONE * rng.randf_range(0.42, 1.0)
		s.modulate.a = rng.randf_range(0.6, 1.0)
		s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		add_child(s)
		_coins.append(s)
		_coin_vy.append(rng.randf_range(COIN_SPEED_MIN, COIN_SPEED_MAX))
		_coin_spin.append(rng.randf_range(-2.6, 2.6))


## 七个字母摆到屏幕中间，先缩到 0.72 倍并全透明
func _build_letters(vp: Vector2) -> void:
	var tex: Array[Texture2D] = []
	for i in LETTERS:
		tex.append(load("res://art/logo/letter_%d.png" % i))
	var total: float = 0.0
	for t in tex:
		total += t.get_width()
	total += GAP * (LETTERS - 1)
	var k: float = TEXT_W / total

	var x: float = (vp.x - TEXT_W) * 0.5
	var cy: float = vp.y * 0.46
	for i in LETTERS:
		var r := TextureRect.new()
		r.texture = tex[i]
		r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		r.stretch_mode = TextureRect.STRETCH_SCALE
		r.size = tex[i].get_size() * k
		r.position = Vector2(x, cy - r.size.y * 0.5)
		r.pivot_offset = r.size * 0.5
		r.scale = Vector2(0.72, 0.72)
		r.modulate.a = 0.0
		r.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		add_child(r)
		_letters.append(r)
		x += r.size.x + GAP * k


func _pulse() -> void:
	for i in _letters.size():
		var r: TextureRect = _letters[i]
		var y0: float = r.position.y
		var t := create_tween().set_parallel(true)
		t.tween_property(r, "modulate:a", 1.0, POP).set_delay(i * STEP)
		t.tween_property(r, "scale", Vector2.ONE, POP) \
			.set_delay(i * STEP).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		t.tween_property(r, "position:y", y0 - 12.0, POP) \
			.set_delay(i * STEP).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _process(delta: float) -> void:
	# 金币：下落 + 自转，穿出底部就回到顶上，循环不停
	var vh: float = get_viewport().get_visible_rect().size.y
	for i in _coins.size():
		var s: Sprite2D = _coins[i]
		s.position.y += _coin_vy[i] * delta
		s.rotation += _coin_spin[i] * delta
		if s.position.y > vh + 100.0:
			s.position.y = -100.0

	if _done:
		return
	_elapsed += delta
	if _elapsed >= LETTERS * STEP + POP + HOLD:
		_finish()


func _unhandled_input(event: InputEvent) -> void:
	if _done:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		_finish()
	elif event is InputEventJoypadButton and event.pressed:
		_finish()
	elif event is InputEventMouseButton and event.pressed:
		_finish()


func _finish() -> void:
	if _done:
		return
	_done = true
	Audio.play("ui")
	var t := create_tween()
	t.tween_property(self, "modulate:a", 0.0, FADE)
	t.tween_callback(func() -> void:
		get_tree().change_scene_to_file("res://scenes/start_menu.tscn"))
