extends RigidBody2D
## 开始界面里的「无动力小鸟」。
##
## 就是一块纯刚体：没有输入、没有升力、没有 AI，只受重力和碰撞影响。
## 唯一的介入是限速 —— 25 只鸟挤在一块会上下砸的板子上，物理求解器偶尔会
## 把某一帧的冲量算得很大，速度一旦飙起来就会穿墙、画面糊成一团。限速是安全阀。

## 速度上限（像素/秒）。60Hz 下一帧最多走 1400/60 ≈ 23 像素，
## 远小于墙体厚度（120 像素），所以不会隧穿。
const MAX_SPEED: float = 1400.0
## 自转上限（弧度/秒）
const MAX_SPIN: float = 14.0


## 开始界面那只鸟也用皮肤：飞行器换整套 SpriteFrames，驾驶员换贴图。
## 和 player.gd 的 apply_skin 是同一套 Skins 数据，所以菜单里看到的
## 就是游戏里能选到的样子。
func apply_skin(aircraft: int, pilot: int) -> void:
	var sprite: AnimatedSprite2D = get_node("AnimatedSprite2D")
	sprite.sprite_frames = Skins.frames(aircraft)
	sprite.play("fly_bird")
	var pilot_node: Sprite2D = sprite.get_node("Pilot")
	var tex: Texture2D = Skins.pilot_texture(pilot)
	pilot_node.texture = tex
	pilot_node.visible = tex != null


func _integrate_forces(state: PhysicsDirectBodyState2D) -> void:
	var v: Vector2 = state.linear_velocity
	var speed: float = v.length()
	if speed > MAX_SPEED:
		state.linear_velocity = v * (MAX_SPEED / speed)
	var spin: float = state.angular_velocity
	if absf(spin) > MAX_SPIN:
		state.angular_velocity = signf(spin) * MAX_SPIN
