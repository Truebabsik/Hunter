extends RefCounted
class_name TextGenerator
## Сборка боевой прозы из сигналов и фраз (GDD 3.1, шесть слоёв).
##
## Возвращает не строку, а размеченную структуру: из неё бесплатно получаются
## подсветка опорного сигнала (навык «Опорный сигнал»), удаление ложного следа
## («Чистая проза»), разбор после боя и счётчик повторов для критерия 13.2.

## Сколько ложных следов добавлять сверх опоры — по рангу вида (GDD 3.3, стартовый = 1).
const DECOYS_BY_RANK := {
	MonsterData.RANK_STARTER: 1,
	MonsterData.RANK_ADVANCED: 2,
	MonsterData.RANK_ELITE: 3,
	MonsterData.RANK_LEGENDARY: 3,
}

## Порядок сборки абзаца по приоритету слота (GDD 3.2).
const SLOT_ORDER: Array[StringName] = [&"pose", &"gear", &"sound", &"gaze", &"environment"]

## Сколько последних фраз не повторять. Критерий 13.2: текст не должен заметно
## повторяться в течение 10 боёв, поэтому окно шире одного боя.
const RECENT_WINDOW := 24

## История использованных фраз. Живёт между боями — специально статическая.
static var _recent: Array[String] = []


static func reset_history() -> void:
	_recent.clear()


## Главная точка входа. rng — ТЕКСТОВЫЙ поток, отдельный от механики:
## иначе выбор инструмента игроком сдвигал бы последовательность фраз.
static func generate(
	monster: MonsterData,
	scenario: ScenarioData,
	rng: RandomNumberGenerator
) -> Dictionary:
	var lines: Array[Dictionary] = []

	# Слой 2: опорные сигналы — гарантированы (правило честности, GDD 2.2).
	var core_slots: Dictionary = {}
	for sig in scenario.signals:
		core_slots[sig.slot] = true
		var phrase := _pick_phrase(monster.id, scenario.id, sig.slot, Phrase.ROLE_CORE, rng)
		if phrase == null:
			lines.append(_fallback_line(sig, Phrase.ROLE_CORE))
			continue
		lines.append(_line(sig, phrase, Phrase.ROLE_CORE))

	# Слой 2б: ложные следы. Инвариант — не занимать слот опорного сигнала,
	# иначе игрок видит два сигнала в одном слоте и «гарантированное чтение» ломается.
	var budget := int(DECOYS_BY_RANK.get(monster.rank, 1))
	var decoy_slots: Dictionary = {}
	for lead in _eligible_decoys(monster, scenario.id, core_slots, decoy_slots):
		if decoy_slots.size() >= budget:
			break
		var phrase := _pick_phrase(monster.id, lead.scenario_id, lead.slot, Phrase.ROLE_DECOY, rng)
		decoy_slots[lead.slot] = true
		if phrase == null:
			lines.append(_fallback_line(lead, Phrase.ROLE_DECOY))
			continue
		lines.append(_line(lead, phrase, Phrase.ROLE_DECOY))

	# Слой 5: порядок по приоритету слота — стабильный ритм, а не случайная мешанина.
	lines.sort_custom(_by_slot_priority)

	var core_labels: PackedStringArray = PackedStringArray()
	for l in lines:
		if l["role"] == Phrase.ROLE_CORE:
			core_labels.append(l["label"])

	var prose := ""
	for l in lines:
		prose += str(l["text"]) + " "

	return {
		"monster_id": monster.id,
		"scenario_id": scenario.id,
		"lines": lines,
		"core_labels": core_labels,
		"prose": prose.strip_edges(),
		"decoy_count": decoy_slots.size(),
	}


## Ложные следы, пригодные для этого сценария.
##
## Приоритет — «свои» следы сценария (тогда у каждого сценария свой обман и текст
## не повторяется от боя к бою). Если у сценария своих нет — берём общие следы вида.
static func _eligible_decoys(
	monster: MonsterData,
	scenario_id: StringName,
	core_slots: Dictionary,
	taken_slots: Dictionary
) -> Array:
	var specific: Array = []
	var generic: Array = []
	for lead in monster.false_leads:
		if core_slots.has(lead.slot) or taken_slots.has(lead.slot):
			continue
		if lead.scenario_id == scenario_id:
			specific.append(lead)
		elif lead.scenario_id == &"":
			generic.append(lead)
	# Свои следы идут первыми, общие добирают бюджет, если своих мало.
	var result: Array = []
	result.append_array(specific)
	result.append_array(generic)
	return result


static func _line(sig: SignalData, phrase: Phrase, role: StringName) -> Dictionary:
	return {
		"slot": sig.slot,
		"role": role,
		"signal_id": sig.id,
		"label": sig.label,
		"phrase_id": phrase.id,
		"text": phrase.text,
	}


static func _fallback_line(sig: SignalData, role: StringName) -> Dictionary:
	return {
		"slot": sig.slot,
		"role": role,
		"signal_id": sig.id,
		"label": sig.label,
		"phrase_id": "",
		"text": sig.label.capitalize() + ".",
		"missing_pool": true,
	}


## Взвешенный выбор фразы с окном антиповтора.
static func _pick_phrase(
	monster_id: StringName,
	scenario_id: StringName,
	slot: StringName,
	role: StringName,
	rng: RandomNumberGenerator
) -> Phrase:
	var pool: Array = Database.phrases_for(monster_id, scenario_id, slot, role)
	if pool.is_empty():
		return null
	var fresh: Array = []
	var stale: Array = []
	for p in pool:
		if _recent.has(p.id):
			stale.append(p)
		else:
			fresh.append(p)
	# Сначала исчерпываем свежие; если пул маленький — берём из старых.
	var source: Array = fresh if not fresh.is_empty() else stale
	if source.is_empty():
		return null
	var total := 0
	for p in source:
		total += p.weight
	var roll := rng.randi_range(1, maxi(1, total))
	var acc := 0
	for p in source:
		acc += p.weight
		if roll <= acc:
			_remember(p.id)
			return p
	var last: Phrase = source[source.size() - 1]
	_remember(last.id)
	return last


static func _remember(phrase_id: String) -> void:
	_recent.append(phrase_id)
	while _recent.size() > RECENT_WINDOW:
		_recent.pop_front()


static func _by_slot_priority(a: Dictionary, b: Dictionary) -> bool:
	return SLOT_ORDER.find(a["slot"]) < SLOT_ORDER.find(b["slot"])
