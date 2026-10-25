## 可操作战斗场景的**真实输入链路**测试。
##
## 与 [code]test_battle_screen.gd[/code] 的区别：那边直接调 [method BattleScreen._unhandled_input]，
## **绕过了引擎的事件路由**——它能证明处理逻辑对，但证明不了"按键/点击真的能到达这个函数"。
## 这里用 [method Input.parse_input_event] 把事件注入引擎输入系统，走完整链路：
## 输入系统 → 视口 → GUI（Control）→ 未处理输入 → 场景。
##
## 覆盖三件事：
## - **命中几何**：屏幕坐标 → 战场坐标 → 命中哪个单位（含放宽后的判定区），无头即可测；
## - **提示可见**：可点的敌人真的会被点亮（脚下菱形 + 轮廓描边），无头即可测；
## - **事件路由**：鼠标点击、键盘 Q/W/E 与 A/S/D 真能穿过引擎路由到达场景。
##
## ⚠️ **鼠标路由只能在真实窗口下测**：`--headless` 用空显示驱动，视口被压成 64×64、
## `DisplayServer.window_get_size()` 返回 (0, 0)，注入的鼠标事件到不了 [method Node._unhandled_input]
## （键盘事件不受影响）。所以鼠标用例在无头下**显式跳过并打印说明**，不假装通过。
##
## 跑法：
## [codeblock]
## # 无头：几何、提示、键盘路由
## godot --headless --path . --script res://tests/test_battle_input.gd
## # 真实窗口：额外覆盖鼠标路由
## godot --path . --resolution 1280x720 --script res://tests/test_battle_input.gd
## [/codeblock]
##
## @author WorkBuddy AI
## @date 2026-10-01
extends SceneTree

## 待测场景。
const SCREEN_SCENE := preload("res://playgrounds/battle_screen.tscn")

## 驱动流程的最大步数。
const MAX_STEPS := 800


## 入口。
##
## 需要 [code]await[/code] 等界面 [method Node._ready] 与输入事件派发，所以整体是协程。
func _initialize() -> void:
	await _run()


## 依次执行各用例并输出结果。
func _run() -> void:
	var helper := AssertHelper.new()
	await _test_hit_geometry(helper)
	await _test_choice_stage_clickable(helper)
	await _test_markers(helper)
	await _test_click_enemy(helper)
	await _test_attack_keys(helper)
	await _test_defend_keys(helper)
	if helper.failures == 0:
		print("[通过] test_battle_input")
		quit(0)
		return
	push_error("[失败] test_battle_input：共 %d 项断言失败" % helper.failures)
	quit(1)


## 当前是否运行在无头（空显示驱动）下。
##
## @return 无头时为 [code]true[/code]
func _is_headless() -> bool:
	return DisplayServer.get_name() == "headless"


## 用例：点击命中几何——精灵包围盒、外扩余量、脚底边界都要能命中。
##
## 这一项正是玩家反馈的那个 bug 的根因所在：判定区**恰好等于**精灵包围盒时，
## 点歪一点就落空；而 [method Rect2.has_point] 不含右/下边界，连"正好点在脚底"都会被排除。
##
## @param helper 断言辅助
func _test_hit_geometry(helper: AssertHelper) -> void:
	var screen := await _spawn()
	await _drive_to(screen, BattleScreen.Step.PLAYER_TARGET)

	if screen._step != BattleScreen.Step.PLAYER_TARGET:
		helper._assert_true(false, "应能推进到选目标")
		screen.queue_free()
		await process_frame
		return

	var targets := screen._alive_enemies()
	helper._assert_true(not targets.is_empty(), "选目标时应有可选敌人")
	if not targets.is_empty():
		var enemy: BattleUnit = targets[0]
		var feet := screen._field_pos_of(enemy)
		var size: Vector2 = screen._views[enemy]["body_size"]
		var center := feet + Vector2(0.0, -size.y * 0.5)

		helper._assert_eq(screen._unit_at(center, BattleUnit.Team.ENEMY), enemy, "点精灵中心应命中")
		helper._assert_eq(screen._unit_at(feet, BattleUnit.Team.ENEMY), enemy, "点脚底应命中（Rect2 不含下边界，必须靠余量兜住）")
		helper._assert_eq(screen._unit_at(center + Vector2(size.x * 0.5, 0.0), BattleUnit.Team.ENEMY), enemy, "点右边缘应命中（Rect2 不含右边界）")

		# 外扩余量之内仍应命中，之外必须落空。
		# **纵向**取点：横向取点会同时落进邻座的判定区（同排间隔 64px，判定区外扩后互相重叠 10px），
		# 那就变成在测"点缝里归谁"，而不是在测余量。
		var pad := BattleScreen.UNIT_HIT_PADDING
		var above := center + Vector2(0.0, -(size.y * 0.5) - pad * 0.5)
		helper._assert_eq(screen._unit_at(above, BattleUnit.Team.ENEMY), enemy, "外扩余量之内应命中")
		var beyond := center + Vector2(0.0, -(size.y * 0.5) - pad - 6.0)
		helper._assert_true(screen._unit_at(beyond, BattleUnit.Team.ENEMY) == null, "外扩余量之外不应命中")

		# 同一排判定区重叠时，应选中横向更近的那个（不能随字典遍历顺序随机）
		for other in targets:
			if other == enemy:
				continue
			var dx := screen._field_pos_of(other).x - feet.x
			if absf(dx) < 60.0:
				continue
			var probe := Vector2(feet.x + signf(dx) * 30.0, feet.y)
			helper._assert_true(screen._unit_at(probe, BattleUnit.Team.ENEMY) != null, "邻座判定区重叠的缝里应能命中其一")
			helper._assert_eq(screen._unit_at(probe, BattleUnit.Team.ENEMY), enemy, "缝里应选中横向更近的那个，而不是随遍历顺序随机")
			break

		# 我方单位不该被"选敌人"的拾取吃掉
		helper._assert_true(screen._unit_at(screen._field_pos_of(screen._actor) + Vector2(0, -size.y * 0.5), BattleUnit.Team.ENEMY) == null, "按敌方阵营拾取时不应命中我方单位")

	screen.queue_free()
	await process_frame


## 用例：二选一阶段敌人就已经可点，不必先按「进攻」。
##
## 玩家反馈的核心：上一版必须先点右侧面板的「进攻」才能选目标，鼠标点选形同虚设。
##
## @param helper 断言辅助
func _test_choice_stage_clickable(helper: AssertHelper) -> void:
	var screen := await _spawn()
	await _drive_to(screen, BattleScreen.Step.PLAYER_CHOICE)

	if screen._step != BattleScreen.Step.PLAYER_CHOICE:
		helper._assert_true(false, "应能推进到二选一阶段")
		screen.queue_free()
		await process_frame
		return

	for enemy in screen._alive_enemies():
		helper._assert_true(screen._can_click(enemy), "二选一阶段敌人应可直接点选")

	# 直接点敌人 = 进攻 + 选定该目标
	var enemy: BattleUnit = screen._alive_enemies()[0]
	var feet := screen._field_pos_of(enemy)
	var size: Vector2 = screen._views[enemy]["body_size"]
	helper._assert_eq(screen._unit_at(feet + Vector2(0.0, -size.y * 0.5), BattleUnit.Team.ENEMY), enemy, "二选一阶段应能命中敌人")
	screen._on_target_pressed(enemy)
	helper._assert_eq(screen._step, BattleScreen.Step.PLAYER_SYMBOL, "二选一阶段点敌人应直接进入选模组")
	helper._assert_eq(screen._chosen_target, enemy, "点中的敌人应成为攻击目标")

	screen.queue_free()
	await process_frame


## 用例：可点的敌人真的会被点亮，且不可点时提示必须收掉。
##
## @param helper 断言辅助
func _test_markers(helper: AssertHelper) -> void:
	var screen := await _spawn()
	await _drive_to(screen, BattleScreen.Step.PLAYER_CHOICE)

	if screen._step != BattleScreen.Step.PLAYER_CHOICE:
		helper._assert_true(false, "应能推进到二选一阶段")
		screen.queue_free()
		await process_frame
		return

	var enemy: BattleUnit = screen._alive_enemies()[0]
	var highlight: Polygon2D = screen._views[enemy]["highlight"]
	var outline: Sprite2D = screen._views[enemy]["outline"]
	helper._assert_eq(highlight.color, BattleScreen.MARKER_SELECTABLE, "二选一阶段敌人脚下应显示可选提示")
	helper._assert_true(outline.visible, "二选一阶段敌人应带轮廓描边")

	# 悬停换成另一个颜色
	screen._update_hover(enemy)
	helper._assert_eq(highlight.color, BattleScreen.MARKER_HOVER, "悬停中的敌人应用悬停色")

	# 进入不可点状态后提示必须收掉。
	# 直接置状态再刷新，而不是"结算一次行动"——结算会顺带推进流程，落到下一个玩家的
	# PLAYER_CHOICE 上，敌人又变成可点的了，断言会被流程本身干扰。
	screen._step = BattleScreen.Step.IDLE
	screen._refresh_units()
	helper._assert_true(not screen._can_click(enemy), "非选择状态下敌人不应可点")
	helper._assert_eq(highlight.color, BattleScreen.MARKER_NONE, "非选择状态下提示应清空")
	helper._assert_true(not outline.visible, "非选择状态下描边应收起")

	screen.queue_free()
	await process_frame


## 用例：真实鼠标点击战场上的敌人，应选中该目标。
##
## **仅真实窗口下有效**，无头下跳过并打印说明（空显示驱动收不到鼠标事件）。
##
## @param helper 断言辅助
func _test_click_enemy(helper: AssertHelper) -> void:
	if _is_headless():
		print("[跳过] 鼠标点击路由：--headless 下注入的鼠标事件到不了 _unhandled_input，需真实窗口运行")
		return

	var screen := await _spawn()
	await _drive_to(screen, BattleScreen.Step.PLAYER_TARGET)
	helper._assert_eq(screen._step, BattleScreen.Step.PLAYER_TARGET, "应能推进到选目标")

	if screen._step == BattleScreen.Step.PLAYER_TARGET:
		var targets := screen._alive_enemies()
		helper._assert_true(not targets.is_empty(), "选目标时应有可选敌人")
		if not targets.is_empty():
			var enemy: BattleUnit = targets[0]
			await _click(screen, screen._field_pos_of(enemy))
			helper._assert_eq(screen._step, BattleScreen.Step.PLAYER_SYMBOL, "点战场上的敌人应选中目标并进入选模组")
			helper._assert_eq(screen._chosen_target, enemy, "被点中的敌人应成为目标")

	screen.queue_free()
	await process_frame


## 用例：真实按键 Q/W/E 能出进攻模组。
##
## @param helper 断言辅助
func _test_attack_keys(helper: AssertHelper) -> void:
	var screen := await _spawn()
	await _drive_to(screen, BattleScreen.Step.PLAYER_SYMBOL)
	helper._assert_eq(screen._step, BattleScreen.Step.PLAYER_SYMBOL, "应能推进到选进攻模组")

	if screen._step == BattleScreen.Step.PLAYER_SYMBOL:
		# 弹刀键在进攻状态下应当无效
		await _key(KEY_A)
		helper._assert_eq(screen._step, BattleScreen.Step.PLAYER_SYMBOL, "选进攻模组时按 A 不应生效")
		# 进攻键应当生效
		await _key(KEY_Q)
		helper._assert_true(screen._step != BattleScreen.Step.PLAYER_SYMBOL, "选进攻模组时按 Q 应生效")

	screen.queue_free()
	await process_frame


## 用例：真实按键 A/S/D 能弹刀。
##
## **不能拿 [member BattleScreen._reaction_active] 当"本次窗口结没结算"的证据**：
## [method BattleScreen._resolve_reaction] 结算后会**同步**调用 [method BattleScreen._advance]，
## 下一个敌人如果也在进攻我方，会立刻开出一个**新的**窗口，`_reaction_active` 又变回 [code]true[/code]。
## 所以这里改用日志：一次对拼结算必然在日志里留下一行"弹刀"。
##
## @param helper 断言辅助
func _test_defend_keys(helper: AssertHelper) -> void:
	var screen := await _spawn()
	# 把窗口拉到远超用例耗时：本用例测的是"键能不能到"，不是窗口时长（超时另有 test_battle_screen 覆盖）
	screen._reaction_seconds = 60.0
	await _drive_to(screen, BattleScreen.Step.REACTION)
	helper._assert_eq(screen._step, BattleScreen.Step.REACTION, "应能推进到弹刀反应窗口")

	if screen._step == BattleScreen.Step.REACTION:
		var log_before := screen._log.get_parsed_text()
		# 进攻键在弹刀状态下应当无效：窗口不关，也不产生任何结算
		await _key(KEY_Q)
		helper._assert_true(screen._reaction_active, "弹刀时按 Q 不应关闭窗口")
		helper._assert_eq(screen._log.get_parsed_text(), log_before, "弹刀时按 Q 不应产生任何结算")
		# 弹刀键应当生效：本次窗口结算掉
		await _key(KEY_S)
		helper._assert_true(screen._log.get_parsed_text().contains("弹刀"), "弹刀时按 S 应产生对拼结算")

	screen.queue_free()
	await process_frame


## 实例化场景并等界面 [method Node._ready] 跑完。
##
## @return 已就绪的场景实例
func _spawn() -> BattleScreen:
	var screen := SCREEN_SCENE.instantiate() as BattleScreen
	root.add_child(screen)
	await process_frame
	await process_frame
	return screen


## 驱动战斗场景直到进入目标状态。
##
## 场景在玩家决策处会停住等输入，所以要用与自动化测试相同的方式替玩家做决定。
##
## @param screen 战斗场景
## @param target_step 目标状态，取 [enum BattleScreen.Step]
## @return 抵达目标状态时为 [code]true[/code]
func _drive_to(screen: BattleScreen, target_step: int) -> bool:
	var steps := 0
	while steps < MAX_STEPS and not screen._controller.is_finished():
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
				screen._on_symbol_pressed(ClashResolver.Symbol.ROCK)
			BattleScreen.Step.REACTION:
				# 敌方先手时会先进弹刀窗口，用一个固定模组走掉
				screen._on_reaction_pressed(ClashResolver.Symbol.ROCK)
			_:
				pass
		await process_frame
	return screen._step == target_step


## 注入一次真实鼠标左键点击。
##
## **必须给窗口坐标，不是内容坐标。** [method Input.parse_input_event] 注入的事件会被
## [code]Viewport::_make_input_local[/code] 按 [method Viewport.get_final_transform] 的**逆**变换一次，
## 之后才到达 [method Node._unhandled_input]；也就是说注入方要给"变换前"的窗口坐标。
##
## 这一步很容易被漏掉：窗口正好是 1280×720 时 [code]get_final_transform()[/code] 是单位矩阵，
## 给内容坐标也能过；窗口一放大（实测 1920×1080）就全部点偏，而 [method BattleScreen._to_field]
## 本身其实是对的。
##
## @param screen 目标场景
## @param field_point 战场坐标（[code]_field[/code] 局部坐标）下的目标点
func _click(screen: BattleScreen, field_point: Vector2) -> void:
	var content_point: Vector2 = screen._field.get_global_transform_with_canvas() * field_point
	var window_point: Vector2 = root.get_final_transform() * content_point
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = window_point
		event.global_position = window_point
		Input.parse_input_event(event)
	await process_frame
	await process_frame


## 注入一次真实按键。
##
## @param keycode 键码，取 [enum Key]
func _key(keycode: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = keycode
		event.physical_keycode = keycode
		event.pressed = pressed
		Input.parse_input_event(event)
	await process_frame
	await process_frame
