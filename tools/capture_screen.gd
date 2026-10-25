## 把某个场景离屏跑几帧后截图存盘，用于人工核对表现层。
##
## 用法（**不要加 [code]--headless[/code]**，空渲染器拿不到图像）：
## [codeblock]
## godot --path . --resolution 1280x720 --script res://tools/capture_screen.gd
## [/codeblock]
## 可选参数（放在 [code]--[/code] 之后）：
## - 第 1 个：待截图的场景路径，默认 [code]res://playgrounds/battle_screen.tscn[/code]
## - 第 2 个：输出 PNG 路径，默认 [code]res://tmp_preview/screen.png[/code]
## - 第 3 个：截图前先跑多少帧，默认 30（等布局与 _ready 跑完）
## - 第 4 个：攻击演出的定格进度（0~1）。给了就调场景的 [code]_debug_hold_reaction()[/code]
##   把演出停在指定位置——靠帧数很难稳定停在演出中段，因为玩家决策处流程会停住。
## - 第 5 个：要驱动的目标状态，[code]reaction[/code]（默认）/ [code]symbol[/code] / [code]choice[/code]。
##   场景在玩家决策处会停住等输入，所以要截图某个中间状态就得替玩家做决定。
##
## @author WorkBuddy AI
## @date 2026-10-01
extends SceneTree

## 默认待截图场景。
const DEFAULT_SCENE := "res://playgrounds/battle_screen.tscn"

## 默认输出路径。
const DEFAULT_OUTPUT := "res://tmp_preview/screen.png"

## 默认预热帧数。
const DEFAULT_FRAMES := 30


## 入口。
##
## 需要 [code]await[/code] 等渲染帧，所以整体是协程。
func _initialize() -> void:
	await _run()


## 载入场景、驱动到目标状态、截图存盘。
func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var scene_path := args[0] if args.size() > 0 else DEFAULT_SCENE
	var output_path := args[1] if args.size() > 1 else DEFAULT_OUTPUT
	var frames := int(args[2]) if args.size() > 2 else DEFAULT_FRAMES
	var hold := float(args[3]) if args.size() > 3 else -1.0
	var target_name := args[4] if args.size() > 4 else "reaction"

	var packed := load(scene_path) as PackedScene
	if packed == null:
		push_error("无法载入场景：%s" % scene_path)
		quit(1)
		return
	var instance := packed.instantiate()
	root.add_child(instance)

	for i in frames:
		await process_frame

	if instance is BattleScreen:
		await _drive_to_step(instance, _step_id(target_name))

	if hold >= 0.0 and instance.has_method("_debug_hold_reaction"):
		if not instance.call("_debug_hold_reaction", hold):
			push_warning("没有正在进行的攻击演出，定格被跳过")

	await RenderingServer.frame_post_draw

	var image := root.get_texture().get_image()
	var absolute := ProjectSettings.globalize_path(output_path)
	var error := image.save_png(absolute)
	if error != OK:
		push_error("截图保存失败（%d）：%s" % [error, absolute])
		quit(1)
		return
	print("已截图 %s  %dx%d" % [output_path, image.get_width(), image.get_height()])
	quit(0)


## 把状态名转成 [enum BattleScreen.Step] 的值。
##
## @param name 状态名
## @return 状态编号；不认识的名字回退到防守反应窗口
func _step_id(name: String) -> int:
	match name:
		"symbol":
			return BattleScreen.Step.PLAYER_SYMBOL
		"choice":
			return BattleScreen.Step.PLAYER_CHOICE
		_:
			return BattleScreen.Step.REACTION


## 驱动战斗场景直到进入目标状态。
##
## 场景在玩家决策处会**停住等输入**，所以"跑够多少帧"到不了中间状态——
## 这里用与自动化测试相同的方式替玩家做决定。
##
## @param screen 战斗场景
## @param target_step 目标状态，取 [enum BattleScreen.Step]
## @param max_steps 最大步数，防止意外死循环
## @return 抵达目标状态时为 [code]true[/code]
func _drive_to_step(screen: BattleScreen, target_step: int, max_steps: int = 600) -> bool:
	var steps := 0
	while steps < max_steps and not screen._controller.is_finished():
		if screen._step == target_step:
			return true
		steps += 1
		match screen._step:
			BattleScreen.Step.PLAYER_CHOICE:
				screen._on_attack_pressed()
			BattleScreen.Step.PLAYER_TARGET:
				var targets := screen._alive_enemies()
				if targets.is_empty():
					return false
				screen._on_target_pressed(targets[0])
			BattleScreen.Step.PLAYER_SYMBOL:
				# 已经走到选模组却还没到目标状态，说明目标不是它，用一个固定模组走开
				screen._on_symbol_pressed(ClashResolver.Symbol.ROCK)
			BattleScreen.Step.REACTION:
				# 敌方先手时流程会先进弹刀窗口，用固定模组把它走掉
				screen._on_reaction_pressed(ClashResolver.Symbol.ROCK)
			_:
				pass
		await process_frame
	return screen._step == target_step
