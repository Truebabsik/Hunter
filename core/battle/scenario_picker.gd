extends RefCounted
class_name ScenarioPicker
## Скрытый такт зверя: выбор сценария по характерной таблице (GDD 2.2, шаг 1).

## История выбранных сценариев за бой — для контр-приёмов (GDD 6.3).
var history: Array[StringName] = []

## Штраф к повторяющемуся сценарию после срабатывания контр-приёма.
## Контр-приём наказывает не выбор, а предсказуемость: после ответа зверь
## старается уйти от задолбавшего его сценария.
var suppressed: Dictionary = {}

var _last_counter_round: int = -99


## Выбрать сценарий на раунд. rng — поток МЕХАНИКИ (не текста).
func pick(monster: MonsterData, rng: RandomNumberGenerator, round_index: int) -> ScenarioData:
	var pool: Array[ScenarioData] = []
	var weights: PackedFloat32Array = PackedFloat32Array()
	for s in monster.scenarios:
		var w := float(s.weight)
		# Адаптация: чем дольше бой, тем чаще зверь повторяет свой коронный приём
		# (GDD 6.4). Это давление по времени, а не случайность.
		w *= monster.adaptation_multiplier(s.id, round_index)
		if suppressed.has(s.id):
			# Подавление действует 2 раунда и снижает вес вчетверо, но не в ноль:
			# зверь не должен становиться предсказуемым в обратную сторону.
			var until_round := int(suppressed[s.id])
			if round_index <= until_round:
				w = maxf(1.0, w / 4.0)
		pool.append(s)
		weights.append(w)

	var total := 0.0
	for w in weights:
		total += w
	var roll := rng.randf_range(0.0, maxf(0.001, total))
	var acc := 0.0
	var chosen: ScenarioData = pool[0]
	for i in pool.size():
		acc += weights[i]
		if roll <= acc:
			chosen = pool[i]
			break
	history.append(chosen.id)
	return chosen


## Сколько раз подряд (с конца) повторяется этот сценарий.
func repeat_streak(scenario_id: StringName) -> int:
	var streak := 0
	for i in range(history.size() - 1, -1, -1):
		if history[i] == scenario_id:
			streak += 1
		else:
			break
	return streak


## Триггер контр-приёма: игрок трижды подряд сыграл на одном сценарии
## (GDD 6.1: «Контр-приём — монстр, при 3× повторе»).
func should_counter(monster: MonsterData, scenario_id: StringName, round_index: int) -> bool:
	if monster.counter_threshold <= 0:
		return false
	if round_index - _last_counter_round <= 2:
		return false
	return repeat_streak(scenario_id) >= monster.counter_threshold


func mark_counter_used(scenario_id: StringName, round_index: int, suppress_rounds: int = 2) -> void:
	_last_counter_round = round_index
	suppressed[scenario_id] = round_index + suppress_rounds


func clear() -> void:
	history.clear()
	suppressed.clear()
	_last_counter_round = -99
