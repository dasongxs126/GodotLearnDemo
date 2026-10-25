## ActionQueue 的排序优先级与指针语义测试。
##
## 覆盖规格书 §三：三级排序优先级，以及"指针跟随当前操作人、位于指针之前的角色本轮跳过且无补偿"。
##
## @author WorkBuddy AI
## @date 2026-10-01
extends SceneTree

## 入口：执行全部用例并输出退出码。
func _initialize() -> void:
	var helper := AssertHelper.new()
	_test_sort_priority(helper)
	_test_first_team_switch(helper)
	_test_pointer_advance(helper)
	_test_swap_current_to_tail(helper)
	_test_spec_example_swap_between_others(helper)
	_test_move(helper)
	_test_remove(helper)
	_report(helper, "test_action_queue")

## 用例：骰子数字大→小、同数字先手方→后手方、同队站位编号小→大。
##
## @param helper 断言辅助
func _test_sort_priority(helper: AssertHelper) -> void:
	var p1 := BattleUnit.new("P1", BattleUnit.Team.PLAYER, 1, 10)
	var p2 := BattleUnit.new("P2", BattleUnit.Team.PLAYER, 2, 10)
	var e1 := BattleUnit.new("E1", BattleUnit.Team.ENEMY, 1, 10)
	var e2 := BattleUnit.new("E2", BattleUnit.Team.ENEMY, 2, 10)
	var units: Array[BattleUnit] = [p2, e2, p1, e1]
	var rolls := {p1: 6, p2: 6, e1: 6, e2: 3}
	var queue := ActionQueue.new()
	queue.setup(units, rolls, BattleUnit.Team.PLAYER)
	helper._assert_eq(_order_text(queue), "P1,P2,E1,E2", "三级排序优先级")

## 用例：先手方切换后，同数字时敌方排在我方之前。
##
## @param helper 断言辅助
func _test_first_team_switch(helper: AssertHelper) -> void:
	var p1 := BattleUnit.new("P1", BattleUnit.Team.PLAYER, 1, 10)
	var p2 := BattleUnit.new("P2", BattleUnit.Team.PLAYER, 2, 10)
	var e1 := BattleUnit.new("E1", BattleUnit.Team.ENEMY, 1, 10)
	var e2 := BattleUnit.new("E2", BattleUnit.Team.ENEMY, 2, 10)
	var units: Array[BattleUnit] = [p1, p2, e1, e2]
	var rolls := {p1: 6, p2: 6, e1: 6, e2: 3}
	var queue := ActionQueue.new()
	queue.setup(units, rolls, BattleUnit.Team.ENEMY)
	helper._assert_eq(_order_text(queue), "E1,P1,P2,E2", "先手方切换后的排序")

## 用例：指针从队首逐位推进，走完后队列耗尽。
##
## @param helper 断言辅助
func _test_pointer_advance(helper: AssertHelper) -> void:
	var a := BattleUnit.new("A", BattleUnit.Team.PLAYER, 1, 10)
	var b := BattleUnit.new("B", BattleUnit.Team.PLAYER, 2, 10)
	var c := BattleUnit.new("C", BattleUnit.Team.PLAYER, 3, 10)
	var units: Array[BattleUnit] = [a, b, c]
	var rolls := {a: 3, b: 2, c: 1}
	var queue := ActionQueue.new()
	queue.setup(units, rolls, BattleUnit.Team.PLAYER)
	helper._assert_eq(queue.current().display_name, "A", "初始指针指向队首")
	helper._assert_true(queue.advance(), "推进到 B 后仍有后续行动")
	helper._assert_eq(queue.current().display_name, "B", "推进后的当前操作人")
	helper._assert_true(queue.advance(), "推进到 C 后仍有后续行动")
	helper._assert_eq(queue.current().display_name, "C", "推进后的当前操作人")
	helper._assert_true(not queue.advance(), "队尾之后再推进则队列耗尽")
	helper._assert_eq(queue.current(), null, "队列耗尽后没有当前操作人")

## 用例：规格书 §三 示例——当前操作人把自己换到队尾，其余角色本轮全部跳过。
##
## @param helper 断言辅助
func _test_swap_current_to_tail(helper: AssertHelper) -> void:
	var a := BattleUnit.new("A", BattleUnit.Team.PLAYER, 1, 10)
	var b := BattleUnit.new("B", BattleUnit.Team.PLAYER, 2, 10)
	var c := BattleUnit.new("C", BattleUnit.Team.PLAYER, 3, 10)
	var d := BattleUnit.new("D", BattleUnit.Team.PLAYER, 4, 10)
	var e := BattleUnit.new("E", BattleUnit.Team.PLAYER, 5, 10)
	var f := BattleUnit.new("F", BattleUnit.Team.PLAYER, 6, 10)
	var units: Array[BattleUnit] = [a, b, c, d, e, f]
	var rolls := {a: 6, b: 5, c: 4, e: 3, d: 2, f: 1}
	var queue := ActionQueue.new()
	queue.setup(units, rolls, BattleUnit.Team.PLAYER)
	helper._assert_eq(_order_text(queue), "A,B,C,E,D,F", "初始队列")
	queue.swap(a, f)
	helper._assert_eq(_order_text(queue), "F,B,C,E,D,A", "A 与 F 交换后的队列")
	helper._assert_eq(queue.current().display_name, "A", "指针跟随当前操作人")
	helper._assert_eq(queue.pointer_index(), 5, "指针落在 A 的新位置")
	helper._assert_true(not queue.advance(), "指针之后再无行动，其余角色本轮跳过")

## 用例：规格书 §三 示例——当前操作人让队列中另外两人换位，指针不动。
##
## @param helper 断言辅助
func _test_spec_example_swap_between_others(helper: AssertHelper) -> void:
	var a := BattleUnit.new("A", BattleUnit.Team.PLAYER, 1, 10)
	var b := BattleUnit.new("B", BattleUnit.Team.PLAYER, 2, 10)
	var c := BattleUnit.new("C", BattleUnit.Team.PLAYER, 3, 10)
	var d := BattleUnit.new("D", BattleUnit.Team.PLAYER, 4, 10)
	var e := BattleUnit.new("E", BattleUnit.Team.PLAYER, 5, 10)
	var f := BattleUnit.new("F", BattleUnit.Team.PLAYER, 6, 10)
	var units: Array[BattleUnit] = [a, b, c, d, e, f]
	var rolls := {a: 6, b: 5, c: 4, e: 3, d: 2, f: 1}
	var queue := ActionQueue.new()
	queue.setup(units, rolls, BattleUnit.Team.PLAYER)
	queue.swap(b, e)
	helper._assert_eq(_order_text(queue), "A,E,C,B,D,F", "B 与 E 交换后的队列")
	helper._assert_eq(queue.pointer_index(), 0, "指针仍指向 A")
	helper._assert_true(queue.advance(), "A 之后仍有行动")
	helper._assert_eq(queue.current().display_name, "E", "下一个行动人是 E")

## 用例：把当前操作人移动到指定下标。
##
## @param helper 断言辅助
func _test_move(helper: AssertHelper) -> void:
	var a := BattleUnit.new("A", BattleUnit.Team.PLAYER, 1, 10)
	var b := BattleUnit.new("B", BattleUnit.Team.PLAYER, 2, 10)
	var c := BattleUnit.new("C", BattleUnit.Team.PLAYER, 3, 10)
	var units: Array[BattleUnit] = [a, b, c]
	var rolls := {a: 3, b: 2, c: 1}
	var queue := ActionQueue.new()
	queue.setup(units, rolls, BattleUnit.Team.PLAYER)
	queue.move(a, 2)
	helper._assert_eq(_order_text(queue), "B,C,A", "A 移动到队尾")
	helper._assert_eq(queue.pointer_index(), 2, "指针跟随 A 移动")
	helper._assert_true(not queue.advance(), "指针之后无行动")

## 用例：移除队列中的单位，指针跟随当前操作人。
##
## @param helper 断言辅助
func _test_remove(helper: AssertHelper) -> void:
	var a := BattleUnit.new("A", BattleUnit.Team.PLAYER, 1, 10)
	var b := BattleUnit.new("B", BattleUnit.Team.PLAYER, 2, 10)
	var c := BattleUnit.new("C", BattleUnit.Team.PLAYER, 3, 10)
	var units: Array[BattleUnit] = [a, b, c]
	var rolls := {a: 3, b: 2, c: 1}
	var queue := ActionQueue.new()
	queue.setup(units, rolls, BattleUnit.Team.PLAYER)
	queue.advance()
	helper._assert_eq(queue.current().display_name, "B", "移除前当前操作人为 B")
	queue.remove(a)
	helper._assert_eq(_order_text(queue), "B,C", "移除 A 后的队列")
	helper._assert_eq(queue.pointer_index(), 0, "指针跟随 B 前移到队首")
	helper._assert_eq(queue.current().display_name, "B", "当前操作人仍是 B")

## 把队列顺序拼成紧凑字符串，便于断言。
##
## @param queue 目标队列
## @return 形如 [code]"A,B,C"[/code] 的显示名串
func _order_text(queue: ActionQueue) -> String:
	var names := PackedStringArray()
	for unit in queue.units():
		names.append(unit.display_name)
	return ",".join(names)

## 输出测试结果并结束进程。
##
## @param helper 断言辅助
## @param suite_name 用例集名称
func _report(helper: AssertHelper, suite_name: String) -> void:
	if helper.failures == 0:
		print("[通过] %s" % suite_name)
		quit(0)
		return
	push_error("[失败] %s：共 %d 项断言失败" % [suite_name, helper.failures])
	quit(1)
