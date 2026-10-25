## 弹刀结算器。
##
## 底层机制为剪刀石头布：攻防各出一枚模组，按克制关系判定胜、平、负（规格书 §六）。
## 防守方额外可以选择"不对抗"，即不出模组，进攻方直接成功。
## 结算只给出结果与受伤方，不计算具体伤害数值（伤害模型为有意留白 🚫）。
##
## @author WorkBuddy AI
## @date 2026-10-01
class_name ClashResolver
extends RefCounted

## 对拼模组。
##
## 三系互相克制。**名称为机制名（占位）**：正式名待结合世界观确定（规格书 §六 ⏳），
## 界面与日志暂用"石头 / 剪刀 / 布"，因为这三个名字玩家本来就懂，不需要额外学习。
enum Symbol {
	## 石头，克制剪刀。
	ROCK,
	## 布，克制石头。
	PAPER,
	## 剪刀，克制布。
	SCISSORS,
}

## 防守方"不对抗"：不出模组，进攻方直接成功。
const NO_CONTEST := -1

## 对拼结果，以进攻方视角表达。
enum Outcome {
	## 进攻方胜。
	WIN,
	## 平局。
	DRAW,
	## 进攻方负。
	LOSE,
}

## 受伤方。
enum Side {
	## 无伤。
	NONE,
	## 进攻方受伤。
	ATTACKER,
	## 防守方受伤。
	DEFENDER,
}

## 克制关系，键克制值。
const BEATS := {
	Symbol.ROCK: Symbol.SCISSORS,
	Symbol.SCISSORS: Symbol.PAPER,
	Symbol.PAPER: Symbol.ROCK,
}

## 判定对拼结果。
##
## @param attacker_symbol 进攻方模组，取 [enum Symbol]
## @param defender_symbol 防守方模组，取 [enum Symbol] 或 [constant NO_CONTEST]
## @return 以进攻方视角的 [enum Outcome]
static func resolve(attacker_symbol: int, defender_symbol: int) -> int:
	if defender_symbol == NO_CONTEST:
		return Outcome.WIN
	if attacker_symbol == defender_symbol:
		return Outcome.DRAW
	if BEATS.get(attacker_symbol, -2) == defender_symbol:
		return Outcome.WIN
	return Outcome.LOSE

## 把对拼结果翻译为受伤方。
##
## @param outcome 对拼结果，取 [enum Outcome]
## @return 受伤方，取 [enum Side]
static func damaged_side(outcome: int) -> int:
	match outcome:
		Outcome.WIN:
			return Side.DEFENDER
		Outcome.LOSE:
			return Side.ATTACKER
		_:
			return Side.NONE

## 等概率随机一个进攻方模组，不含不对抗。
##
## @param rng 随机源
## @return 随机模组，取 [enum Symbol]
static func random_symbol(rng: RandomNumberGenerator) -> int:
	return rng.randi_range(Symbol.ROCK, Symbol.SCISSORS)

## 等概率随机一个防守方模组，四选一，含"不对抗"。
##
## @param rng 随机源
## @return 随机模组，取 [enum Symbol] 或 [constant NO_CONTEST]
static func random_defender_symbol(rng: RandomNumberGenerator) -> int:
	var pick := rng.randi_range(0, 3)
	if pick == 3:
		return NO_CONTEST
	return pick

## 取模组的中文名，用于日志与调试。
##
## 返回的是**机制名**（石头 / 剪刀 / 布），正式名待定（规格书 §六 ⏳）。
##
## @param symbol 模组，取 [enum Symbol] 或 [constant NO_CONTEST]
## @return 中文名
static func symbol_name(symbol: int) -> String:
	match symbol:
		NO_CONTEST:
			return "不对抗"
		Symbol.ROCK:
			return "石头"
		Symbol.PAPER:
			return "布"
		Symbol.SCISSORS:
			return "剪刀"
		_:
			return "未知模组"

## 取对拼结果的中文名，用于日志与调试。
##
## @param outcome 对拼结果
## @return 中文名
static func outcome_name(outcome: int) -> String:
	match outcome:
		Outcome.WIN:
			return "进攻方胜"
		Outcome.DRAW:
			return "平局"
		Outcome.LOSE:
			return "进攻方负"
		_:
			return "未知结果"
