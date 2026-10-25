## ClashResolver 的弹刀判定测试。
##
## 覆盖规格书 §六：三系互克、平局无伤、失败方受伤，以及防守方"不对抗"。
##
## @author WorkBuddy AI
## @date 2026-10-01
extends SceneTree

## 抽样次数，用于验证随机模组取值范围与覆盖度。
const SAMPLE_COUNT := 600

## 入口：执行全部用例并输出退出码。
func _initialize() -> void:
	var helper := AssertHelper.new()
	_test_win_relations(helper)
	_test_lose_relations(helper)
	_test_draw(helper)
	_test_no_contest(helper)
	_test_random_defender_symbol(helper)
	_test_random_symbol(helper)
	_report(helper, "test_clash")

## 用例：三系各自的克制关系都判为进攻方胜，受伤方为防守方。
##
## @param helper 断言辅助
func _test_win_relations(helper: AssertHelper) -> void:
	var pairs := [
		[ClashResolver.Symbol.ROCK, ClashResolver.Symbol.SCISSORS],
		[ClashResolver.Symbol.SCISSORS, ClashResolver.Symbol.PAPER],
		[ClashResolver.Symbol.PAPER, ClashResolver.Symbol.ROCK],
	]
	for pair in pairs:
		var outcome := ClashResolver.resolve(pair[0], pair[1])
		helper._assert_eq(outcome, ClashResolver.Outcome.WIN, "克制关系应判为进攻方胜")
		helper._assert_eq(ClashResolver.damaged_side(outcome), ClashResolver.Side.DEFENDER, "进攻方胜时防守方受伤")

## 用例：被克制时判为进攻方负，受伤方为进攻方。
##
## @param helper 断言辅助
func _test_lose_relations(helper: AssertHelper) -> void:
	var pairs := [
		[ClashResolver.Symbol.SCISSORS, ClashResolver.Symbol.ROCK],
		[ClashResolver.Symbol.PAPER, ClashResolver.Symbol.SCISSORS],
		[ClashResolver.Symbol.ROCK, ClashResolver.Symbol.PAPER],
	]
	for pair in pairs:
		var outcome := ClashResolver.resolve(pair[0], pair[1])
		helper._assert_eq(outcome, ClashResolver.Outcome.LOSE, "被克制时应判为进攻方负")
		helper._assert_eq(ClashResolver.damaged_side(outcome), ClashResolver.Side.ATTACKER, "进攻方负时进攻方受伤")

## 用例：双方模组相同时判为平局，且无人受伤。
##
## @param helper 断言辅助
func _test_draw(helper: AssertHelper) -> void:
	for symbol in [ClashResolver.Symbol.ROCK, ClashResolver.Symbol.PAPER, ClashResolver.Symbol.SCISSORS]:
		var outcome := ClashResolver.resolve(symbol, symbol)
		helper._assert_eq(outcome, ClashResolver.Outcome.DRAW, "同模组应判为平局")
		helper._assert_eq(ClashResolver.damaged_side(outcome), ClashResolver.Side.NONE, "平局无伤")

## 用例：防守方不对抗时，进攻方直接成功。
##
## @param helper 断言辅助
func _test_no_contest(helper: AssertHelper) -> void:
	for symbol in [ClashResolver.Symbol.ROCK, ClashResolver.Symbol.PAPER, ClashResolver.Symbol.SCISSORS]:
		var outcome := ClashResolver.resolve(symbol, ClashResolver.NO_CONTEST)
		helper._assert_eq(outcome, ClashResolver.Outcome.WIN, "不对抗时进攻方直接成功")
		helper._assert_eq(ClashResolver.damaged_side(outcome), ClashResolver.Side.DEFENDER, "不对抗时防守方受伤")

## 用例：随机防守模组四选一，四个取值都会出现。
##
## @param helper 断言辅助
func _test_random_defender_symbol(helper: AssertHelper) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261001
	var seen := {}
	for i in SAMPLE_COUNT:
		var symbol := ClashResolver.random_defender_symbol(rng)
		helper._assert_between(symbol, ClashResolver.NO_CONTEST, ClashResolver.Symbol.SCISSORS, "随机防守模组取值范围")
		seen[symbol] = true
	helper._assert_eq(seen.size(), 4, "%d 次抽样应覆盖四个取值（含不对抗）" % SAMPLE_COUNT)

## 用例：随机进攻模组只取三系，不含不对抗。
##
## @param helper 断言辅助
func _test_random_symbol(helper: AssertHelper) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261001
	var seen := {}
	for i in SAMPLE_COUNT:
		var symbol := ClashResolver.random_symbol(rng)
		helper._assert_between(symbol, ClashResolver.Symbol.ROCK, ClashResolver.Symbol.SCISSORS, "随机进攻模组取值范围")
		seen[symbol] = true
	helper._assert_eq(seen.size(), 3, "%d 次抽样应覆盖三个取值" % SAMPLE_COUNT)
	helper._assert_true(not seen.has(ClashResolver.NO_CONTEST), "随机进攻模组不含不对抗")

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
