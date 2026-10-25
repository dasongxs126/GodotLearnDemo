## 战斗控制器。
##
## 驱动回合循环、行动循环与阶段管线（规格书 §二 / §五 / §八）。
##
## 设计要点：
## - 纯逻辑、不依赖场景树，可在无显示环境下确定性地跑完整场战斗，便于自动化测试；
## - 决策通过 [member action_choice_provider] 等 [Callable] 注入，默认行为为"全体进攻 + 等概率随机模组"；
## - 每个阶段通过 [signal phase_entered] 广播，任意时刻窗口通过 [signal window_opened] 广播；
## - **同步执行，不用协程**。GDScript 会把含 [code]await[/code] 的函数静态标记为协程并要求调用方
##   [code]await[/code]，一旦引入就会传染整个调用链（测试、UI、[method Node._ready] 全部要改），
##   所以这里改为在"等待对抗模组"这一个点上做定点拆分：
##   [method begin_action] 走到弹刀判定前停下，由调用方调用 [method resolve_attack] 提交对抗模组，
##   再调用 [method end_action] 收尾。自动战斗走 [method run_action] 一步到位。
##
## @author WorkBuddy AI
## @date 2026-10-01
class_name BattleController
extends RefCounted

## 单次行动的抉择类型（规格书 §五，二选一）。
enum ActionChoice {
	## 进攻，走进攻链，包含弹刀结算。
	ATTACK,
	## 防御，走防御链，回血并回资源点，没有弹刀阶段。
	DEFEND,
}

## 进入某个回合管线阶段。
##
## @param phase 阶段编号，取 [enum BattlePhase.Id]
## @param actor 当前行动单位；轮次级阶段为 [code]null[/code]
signal phase_entered(phase: int, actor: BattleUnit)

## 打开一个任意时刻窗口（技能生效前 / 技能生效后 / 资源点变动 / 行动序列变动）。
##
## @param phase 窗口编号，取 [enum BattlePhase.Id]
## @param actor 相关单位，无特定单位时为 [code]null[/code]
signal window_opened(phase: int, actor: BattleUnit)

## 开局抛硬币完成，先手方已确定。
##
## @param first_team 先手阵营，取 [enum BattleUnit.Team]
signal coin_flipped(first_team: int)

## 一轮开始。
##
## @param round_index 轮次序号，从 1 开始
signal round_started(round_index: int)

## 一轮结束，即行动队列走完。
##
## @param round_index 轮次序号
signal round_finished(round_index: int)

## 一次行动开始。
##
## @param actor 行动单位
signal action_started(actor: BattleUnit)

## 一次行动结束。
##
## @param actor 行动单位
signal action_finished(actor: BattleUnit)

## 行动序列发生变动，队列顺序与指针已更新。
signal queue_changed()

## 某个单位的资源点发生变动。
##
## @param unit 目标单位
## @param before 变动前资源点
## @param after 变动后资源点
signal resource_changed(unit: BattleUnit, before: int, after: int)

## 一次弹刀结算完成。
##
## @param attacker 进攻方
## @param defender 防守方
## @param attacker_symbol 进攻方模组，取 [enum ClashResolver.Symbol]
## @param defender_symbol 防守方模组，取 [enum ClashResolver.Symbol] 或 [constant ClashResolver.NO_CONTEST]
## @param outcome 对拼结果，取 [enum ClashResolver.Outcome]
## @param damaged 受伤方，取 [enum ClashResolver.Side]
signal clash_resolved(attacker: BattleUnit, defender: BattleUnit, attacker_symbol: int, defender_symbol: int, outcome: int, damaged: int)

## 防御时的回血量。
##
## 伤害与疗愈数值属于有意留白（规格书 §十一 🚫），此处为骨架占位值。
const DEFEND_HEAL := 2

## 防御时回复的资源点（规格书 §四）。
const DEFEND_RESOURCE_GAIN := 1

## 弹刀成功一方回复的资源点（规格书 §四）。
##
## 规格书只就我方表述（"我方当前进攻角色弹刀成功 +1"），敌方是否同样回复未明确，
## 骨架先按对称处理（胜负双方谁赢谁回），待确认后调整。
const CLASH_WIN_RESOURCE_GAIN := 1

## 弹刀失败方的受伤量。
##
## 伤害模型属于有意留白（规格书 §十一 🚫），此处为骨架占位值。
const PLACEHOLDER_DAMAGE := 1

## 单场战斗的轮数安全上限，避免双方都无法击杀时死循环。
const MAX_ROUNDS := 99

## 行动抉择提供者，签名 [code]func(actor: BattleUnit) -> ActionChoice[/code]。
##
## 未设置时默认恒为 [constant ActionChoice.ATTACK]。
var action_choice_provider: Callable = Callable()

## 攻击目标提供者，签名 [code]func(actor: BattleUnit) -> BattleUnit[/code]。
##
## 未设置、或返回 [code]null[/code]、或返回已阵亡单位时，默认取敌方首个存活单位。
var target_provider: Callable = Callable()

## 进攻方模组提供者，签名 [code]func(actor: BattleUnit) -> int[/code]。
##
## 未设置时默认等概率随机，取 [enum ClashResolver.Symbol]。
var attacker_symbol_provider: Callable = Callable()

## 防守方模组提供者，签名 [code]func(defender: BattleUnit) -> int[/code]。
##
## 未设置时默认等概率随机四选一（含不对抗），取 [enum ClashResolver.Symbol] 或 [constant ClashResolver.NO_CONTEST]。
var defender_symbol_provider: Callable = Callable()

## 玩家方单位。
var _player_units: Array[BattleUnit] = []
## 敌方单位。
var _enemy_units: Array[BattleUnit] = []
## 本局先手方，取 [enum BattleUnit.Team]。
var _first_team: int = BattleUnit.Team.PLAYER
## 行动队列。
var _queue := ActionQueue.new()
## 指定骰子；为 [code]null[/code] 时每轮按场上人数自动创建。
var _dice_override: BattleDice = null
## 随机源，种子固定时整场战斗可复现。
var _rng := RandomNumberGenerator.new()
## 当前轮次序号，从 0 开始递增。
var _round_index: int = 0
## 战斗是否已结束。
var _finished: bool = false
## 待结算弹刀的进攻方；为 [code]null[/code] 表示当前没有待结算弹刀。
var _pending_attacker: BattleUnit = null
## 待结算弹刀的防守方。
var _pending_defender: BattleUnit = null
## 待结算弹刀的进攻方模组。
var _pending_attacker_symbol: int = 0

## 初始化一场战斗。
##
## @param player_units 玩家方单位
## @param enemy_units 敌方单位
## @param first_team 先手方，取 [enum BattleUnit.Team]；UI 场景可在之后调用 [method flip_coin] 改为抛硬币决定
## @param rng_seed 随机种子，相同种子可复现同一场战斗
## @param dice 指定骰子；为 [code]null[/code] 时每轮按场上人数自动创建
func setup(player_units: Array[BattleUnit], enemy_units: Array[BattleUnit], first_team: int = BattleUnit.Team.PLAYER, rng_seed: int = 0, dice: BattleDice = null) -> void:
	_player_units = player_units.duplicate()
	_enemy_units = enemy_units.duplicate()
	_first_team = first_team
	_dice_override = dice
	_rng = RandomNumberGenerator.new()
	_rng.seed = rng_seed
	_queue = ActionQueue.new()
	_round_index = 0
	_finished = false
	_clear_pending_clash()

## 开局抛硬币决定先手方，覆盖 [method setup] 传入的值并广播结果。
##
## @return 先手阵营，取 [enum BattleUnit.Team]
func flip_coin() -> int:
	_first_team = _rng.randi_range(BattleUnit.Team.PLAYER, BattleUnit.Team.ENEMY)
	coin_flipped.emit(_first_team)
	return _first_team

## 当前先手方。
##
## @return 阵营，取 [enum BattleUnit.Team]
func first_team() -> int:
	return _first_team

## 开始新的一轮：进入掷骰前阶段、掷骰并生成行动队列。
##
## @return 战斗可以继续时为 [code]true[/code]；已结束或无法继续时为 [code]false[/code]
func begin_round() -> bool:
	if _finished:
		return false
	_round_index += 1
	round_started.emit(_round_index)
	_phase(BattlePhase.Id.ROLL_BEFORE)
	_roll_and_build_queue()
	_phase(BattlePhase.Id.ROLL_AFTER)
	return true

## 一轮结束时调用：广播回合结束阶段并刷新战斗结束标记。
func end_round() -> void:
	_phase(BattlePhase.Id.ROUND_AFTER)
	round_finished.emit(_round_index)
	_update_finished()

## 把指针向后推进一位。
##
## @return 本轮仍有可行动单位时为 [code]true[/code]
func advance_pointer() -> bool:
	return _queue.advance()

## 执行当前指针所指单位的一次行动，并把指针向后推进一位。
##
## @return 本轮仍有后续行动时为 [code]true[/code]
func step_action() -> bool:
	if _finished:
		return false
	var actor := _queue.current()
	if actor == null:
		return false
	run_action(actor)
	advance_pointer()
	return _queue.current() != null

## 执行一次完整行动：行动开始前 → 进攻链或防御链二选一 → 行动结束。
##
## 进攻链中的弹刀会自动结算，适用于自动战斗、测试与敌方行动；
## 需要玩家提交对抗模组时请改用 [method begin_action] / [method resolve_attack] / [method end_action]。
##
## @param actor 行动单位
func run_action(actor: BattleUnit) -> void:
	begin_action(actor)
	if has_pending_clash():
		resolve_attack_auto()
	end_action(actor)

## 开始一次行动：进入行动开始前阶段，走完抉择与（进攻链到弹刀判定前 / 防御链）。
##
## 返回后若 [method has_pending_clash] 为 [code]true[/code]，说明本次进攻停在等待对抗模组处，
## 调用方必须先用 [method resolve_attack] 或 [method resolve_attack_auto] 结算，再调用 [method end_action]。
##
## @param actor 行动单位
func begin_action(actor: BattleUnit) -> void:
	if actor == null or not actor.is_alive():
		return
	action_started.emit(actor)
	_phase(BattlePhase.Id.ACTION_BEFORE, actor)
	if _decide(actor) == ActionChoice.DEFEND:
		_run_defend(actor)
	else:
		_run_attack_begin(actor)

## 结束一次行动：进入行动结束阶段。
##
## 若仍有未结算的弹刀，会以默认策略自动结算，避免阶段缺失（自动兜底，正常流程不应触发）。
##
## @param actor 行动单位
func end_action(actor: BattleUnit) -> void:
	if has_pending_clash():
		resolve_attack_auto()
	if actor == null:
		return
	_phase(BattlePhase.Id.ACTION_AFTER, actor)
	action_finished.emit(actor)

## 是否存在待结算的弹刀。
##
## @return 停在等待对抗模组处时为 [code]true[/code]
func has_pending_clash() -> bool:
	return _pending_attacker != null

## 待结算弹刀的进攻方。
##
## @return 进攻方；无待结算弹刀时为 [code]null[/code]
func pending_attacker() -> BattleUnit:
	return _pending_attacker

## 待结算弹刀的防守方。
##
## @return 防守方；无待结算弹刀时为 [code]null[/code]
func pending_defender() -> BattleUnit:
	return _pending_defender

## 用指定的对抗模组结算待处理的进攻，并推进到进攻后阶段。
##
## @param defender_symbol 对抗模组，取 [enum ClashResolver.Symbol] 或 [constant ClashResolver.NO_CONTEST]
func resolve_attack(defender_symbol: int) -> void:
	if _pending_attacker == null:
		return
	var attacker := _pending_attacker
	var defender := _pending_defender
	var attacker_symbol := _pending_attacker_symbol
	_clear_pending_clash()
	var outcome := ClashResolver.resolve(attacker_symbol, defender_symbol)
	_apply_clash(attacker, defender, attacker_symbol, defender_symbol, outcome)
	_phase(BattlePhase.Id.CLASH_CHECK_AFTER, attacker)
	_phase(BattlePhase.Id.ATTACK_AFTER, attacker)

## 用默认策略（[member defender_symbol_provider]，默认等概率随机四选一）自动结算待处理的进攻。
func resolve_attack_auto() -> void:
	if _pending_defender == null:
		return
	resolve_attack(_pick_defender_symbol(_pending_defender))

## 跑完一整轮，并广播回合结束阶段。
func run_round() -> void:
	if _finished:
		return
	if not begin_round():
		return
	while step_action():
		if _is_battle_over():
			break
	end_round()

## 跑完整场战斗，受 [constant MAX_ROUNDS] 保护。
func run_battle() -> void:
	while not _finished and _round_index < MAX_ROUNDS:
		run_round()

## 当前轮次序号。
##
## @return 轮次序号，从 1 开始；尚未开始时为 0
func round_index() -> int:
	return _round_index

## 战斗是否已结束。
##
## @return 任一方全灭或达到轮数上限时为 [code]true[/code]
func is_finished() -> bool:
	return _finished

## 行动队列。
##
## @return 当前队列对象，外部可读取顺序但不应直接改动
func queue() -> ActionQueue:
	return _queue

## 玩家方单位。
##
## @return 单位数组副本
func player_units() -> Array[BattleUnit]:
	return _player_units.duplicate()

## 敌方单位。
##
## @return 单位数组副本
func enemy_units() -> Array[BattleUnit]:
	return _enemy_units.duplicate()

## 取获胜方。
##
## @return 获胜阵营，取 [enum BattleUnit.Team]；未分胜负时返回 [code]-1[/code]
func winner_team() -> int:
	if _alive_units_of(BattleUnit.Team.PLAYER).is_empty():
		return BattleUnit.Team.ENEMY
	if _alive_units_of(BattleUnit.Team.ENEMY).is_empty():
		return BattleUnit.Team.PLAYER
	return -1

## 掷骰并生成行动队列。
func _roll_and_build_queue() -> void:
	var alive := _alive_units()
	var dice := _dice_override
	if dice == null:
		dice = BattleDice.create_for_battle(alive.size(), _rng)
	var rolls := {}
	for unit in alive:
		rolls[unit] = dice.roll()
	_queue.setup(alive, rolls, _first_team)
	queue_changed.emit()
	_window(BattlePhase.Id.QUEUE_CHANGED)

## 执行一次防御行动，走防御链。
##
## @param actor 行动单位
func _run_defend(actor: BattleUnit) -> void:
	_phase(BattlePhase.Id.DEFEND_BEFORE, actor)
	actor.heal(DEFEND_HEAL)
	_gain_resource(actor, DEFEND_RESOURCE_GAIN)
	_phase(BattlePhase.Id.DEFEND_AFTER, actor)

## 进攻链前半段：进入进攻前阶段、选定目标、进入弹刀判定前阶段，并停在等待对抗模组处。
##
## @param actor 进攻方
func _run_attack_begin(actor: BattleUnit) -> void:
	_phase(BattlePhase.Id.ATTACK_BEFORE, actor)
	var target := _pick_target(actor)
	if target == null:
		return
	_pending_attacker = actor
	_pending_defender = target
	_pending_attacker_symbol = _pick_attacker_symbol(actor)
	_phase(BattlePhase.Id.CLASH_CHECK_BEFORE, actor)

## 清空待结算弹刀。
func _clear_pending_clash() -> void:
	_pending_attacker = null
	_pending_defender = null
	_pending_attacker_symbol = 0

## 结算一次弹刀：按受伤方扣血，并给胜方回复资源点。
##
## @param attacker 进攻方
## @param defender 防守方
## @param attacker_symbol 进攻方模组
## @param defender_symbol 防守方模组
## @param outcome 对拼结果
func _apply_clash(attacker: BattleUnit, defender: BattleUnit, attacker_symbol: int, defender_symbol: int, outcome: int) -> void:
	var damaged := ClashResolver.damaged_side(outcome)
	match damaged:
		ClashResolver.Side.ATTACKER:
			attacker.take_damage(PLACEHOLDER_DAMAGE)
		ClashResolver.Side.DEFENDER:
			defender.take_damage(PLACEHOLDER_DAMAGE)
	if outcome == ClashResolver.Outcome.WIN:
		_gain_resource(attacker, CLASH_WIN_RESOURCE_GAIN)
	elif outcome == ClashResolver.Outcome.LOSE:
		_gain_resource(defender, CLASH_WIN_RESOURCE_GAIN)
	clash_resolved.emit(attacker, defender, attacker_symbol, defender_symbol, outcome, damaged)

## 增加资源点，并在真正发生变动时广播资源点变动窗口。
##
## @param unit 目标单位
## @param amount 增加量
func _gain_resource(unit: BattleUnit, amount: int) -> void:
	var before := unit.resource
	unit.gain_resource(amount)
	if unit.resource == before:
		return
	_window(BattlePhase.Id.RESOURCE_CHANGED, unit)
	resource_changed.emit(unit, before, unit.resource)

## 进入一个回合管线阶段。
##
## @param phase 阶段编号
## @param actor 当前行动单位；轮次级阶段省略
func _phase(phase: int, actor: BattleUnit = null) -> void:
	phase_entered.emit(phase, actor)

## 打开一个任意时刻窗口。
##
## @param phase 窗口编号
## @param actor 相关单位；无特定单位时省略
func _window(phase: int, actor: BattleUnit = null) -> void:
	window_opened.emit(phase, actor)

## 询问当前行动单位本次选择进攻还是防御。
##
## @param actor 行动单位
## @return 抉择结果，取 [enum ActionChoice]
func _decide(actor: BattleUnit) -> int:
	if action_choice_provider.is_valid():
		return action_choice_provider.call(actor)
	return ActionChoice.ATTACK

## 选出攻击目标。
##
## @param actor 行动单位
## @return 目标单位；无可选目标时为 [code]null[/code]
func _pick_target(actor: BattleUnit) -> BattleUnit:
	if target_provider.is_valid():
		var candidate: BattleUnit = target_provider.call(actor)
		if candidate != null and candidate.is_alive():
			return candidate
	return _first_alive_opponent(actor)

## 取进攻方模组。
##
## @param actor 行动单位
## @return 模组编号，取 [enum ClashResolver.Symbol]
func _pick_attacker_symbol(actor: BattleUnit) -> int:
	if attacker_symbol_provider.is_valid():
		return attacker_symbol_provider.call(actor)
	return ClashResolver.random_symbol(_rng)

## 取防守方模组。
##
## @param defender 防守单位
## @return 模组编号，取 [enum ClashResolver.Symbol] 或 [constant ClashResolver.NO_CONTEST]
func _pick_defender_symbol(defender: BattleUnit) -> int:
	if defender_symbol_provider.is_valid():
		return defender_symbol_provider.call(defender)
	return ClashResolver.random_defender_symbol(_rng)

## 取敌方首个存活单位。
##
## @param actor 行动单位
## @return 存活对手；对手全灭时为 [code]null[/code]
func _first_alive_opponent(actor: BattleUnit) -> BattleUnit:
	var pool := _enemy_units if actor.team == BattleUnit.Team.PLAYER else _player_units
	for unit in pool:
		if unit.is_alive():
			return unit
	return null

## 取某阵营的存活单位。
##
## @param team 阵营
## @return 存活单位数组
func _alive_units_of(team: int) -> Array[BattleUnit]:
	var pool := _player_units if team == BattleUnit.Team.PLAYER else _enemy_units
	var result: Array[BattleUnit] = []
	for unit in pool:
		if unit.is_alive():
			result.append(unit)
	return result

## 取场上全部存活单位。
##
## @return 存活单位数组
func _alive_units() -> Array[BattleUnit]:
	var result: Array[BattleUnit] = _alive_units_of(BattleUnit.Team.PLAYER)
	result.append_array(_alive_units_of(BattleUnit.Team.ENEMY))
	return result

## 判断战斗是否已分出胜负。
##
## @return 任一方全灭时为 [code]true[/code]
func _is_battle_over() -> bool:
	return _alive_units_of(BattleUnit.Team.PLAYER).is_empty() or _alive_units_of(BattleUnit.Team.ENEMY).is_empty()

## 更新战斗结束标记。
func _update_finished() -> void:
	if _is_battle_over():
		_finished = true
	elif _round_index >= MAX_ROUNDS:
		_finished = true
