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

const CLOUD_SPEED: float = 30.0
const COIN_COUNT: int = 9
const COIN_SPEED: float = 46.0

var _letters: Array[TextureRect] = []
var _clouds: Array[TextureRect] = []
var _coins: Array[Sprite2D] = []
var _coin_vy: Array[float] = []
var _coin_spin: Array[float] = []
var _cloud_x: float = 0.0
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


## 蓝天 + 两层飘动的云
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

	var cloud_tex: Texture2D = load("res://art/bg_clouds.png")
	var cw: float = cloud_tex.get_width()
	for i in 2:
		var c := TextureRect.new()
		c.texture = cloud_tex
		c.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		c.stretch_mode = TextureRect.STRETCH_SCALE
		c.size = Vector2(cw, cloud_tex.get_height())
		c.position = Vector2(cw * i, vp.y * 0.30)
		c.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(c)
		_clouds.append(c)

	# 上升的金币，给画面添点"这是游戏"的信息
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for i in COIN_COUNT:
		var s := Sprite2D.new()
		s.texture = load("res://art/coin_%d.png" % (i % 4))
		s.position = Vector2(rng.randf_range(60.0, vp.x - 60.0), vp.y + rng.randf_range(0.0, 500.0))
		s.scale = Vector2.ONE * rng.randf_range(0.5, 0.95)
		s.modulate.a = rng.randf_range(0.45, 0.8)
		add_child(s)
		_coins.append(s)
		_coin_vy.append(COIN_SPEED * rng.randf_range(0.7, 1.5))
		_coin_spin.append(rng.randf_range(-2.2, 2.2))


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
	# 云：向左飘，走出屏幕就绕回右侧，永远无缝
	var w: float = 1920.0
	_cloud_x = fmod(_cloud_x - CLOUD_SPEED * delta, w)
	for i in _clouds.size():
		_clouds[i].position.x = _cloud_x + w * i

	# 金币：慢慢上升 + 自转，飘出顶部就从底下重生
	var vh: float = get_viewport().get_visible_rect().size.y
	for i in _coins.size():
		var s: Sprite2D = _coins[i]
		s.position.y -= _coin_vy[i] * delta
		s.rotation += _coin_spin[i] * delta
		if s.position.y < -90.0:
			s.position.y = vh + 90.0

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
