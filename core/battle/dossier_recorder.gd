extends RefCounted
class_name DossierRecorder
## Сбор фактов для досье во время боя (GDD 5.2).
##
## Вынесено из экрана боя, потому что тот же сбор нужен симулятору полного цикла.
## Дублировать эту логику нельзя: ранг «Мастерство» в досье зависит от того, какие
## факты записаны, и расхождение между игрой и прогоном сделало бы прогон
## недостоверным — что и произошло, когда сбор жил только в экране.

var monster_id: StringName
var _monster: MonsterData
var _known: Dictionary = {}

## Накопленное за бой.
var new_signals: Array[String] = []
var new_decoys: Array[String] = []
var new_scenarios: Array[String] = []
var new_weaknesses: Array[String] = []


## Снимок досье на начало боя передаётся сюда: тогда «новое» считается
## относительно того, что игрок уже знал, а не относительно пустоты.
func begin(p_monster: MonsterData, known_at_start: Dictionary) -> void:
	_monster = p_monster
	monster_id = p_monster.id
	_known.clear()
	new_signals.clear()
	new_decoys.clear()
	new_scenarios.clear()
	new_weaknesses.clear()
	for section in ["signals", "decoys", "scenarios", "weaknesses"]:
		for value in (known_at_start.get(section, []) as Array):
			_known["%s:%s" % [section, value]] = true


## Записать исход раунда.
func record(outcome: Dictionary) -> void:
	var scenario := str(outcome.get("fact_scenario", ""))
	if not scenario.is_empty() and not _seen("scenarios", scenario):
		new_scenarios.append(_scenario_label(scenario))

	if bool(outcome.get("read_correct", false)):
		# Верное чтение открывает опорные сигналы, которые были в прозе.
		for sig in (outcome.get("fact_signals", PackedStringArray()) as PackedStringArray):
			if not _seen("signals", str(sig)):
				new_signals.append(str(sig))
		# Идеальное чтение открывает уязвимость (GDD 5.2).
		if outcome["reading"] == DamageCalc.Reading.PERFECT:
			var weakness := _weakness_text()
			if not weakness.is_empty() and not _seen("weaknesses", weakness):
				new_weaknesses.append(weakness)
	else:
		# Промах открывает ложный след, который увёл игрока.
		var decoy := str(outcome.get("fact_decoy", ""))
		if not decoy.is_empty() and not _seen("decoys", decoy):
			new_decoys.append(decoy)


## Записать всё накопленное в досье GameState. Возвращает число новых фактов.
func commit() -> int:
	var gained := 0
	for s in new_scenarios:
		if GameState.dossier_add(monster_id, "scenarios", s):
			gained += 1
	for s in new_signals:
		if GameState.dossier_add(monster_id, "signals", s):
			gained += 1
	for d in new_decoys:
		if GameState.dossier_add(monster_id, "decoys", d):
			gained += 1
	for w in new_weaknesses:
		if GameState.dossier_add(monster_id, "weaknesses", w):
			gained += 1
	return gained


func _seen(section: String, value: String) -> bool:
	var key := "%s:%s" % [section, value]
	if _known.has(key):
		return true
	_known[key] = true
	return false


func _scenario_label(scenario_id: String) -> String:
	if _monster == null:
		return scenario_id
	var s := _monster.find_scenario(StringName(scenario_id))
	return s.card_label if s != null else scenario_id


func _weakness_text() -> String:
	if _monster == null:
		return ""
	var parts: PackedStringArray = PackedStringArray()
	for t in _monster.weakness_types:
		parts.append(CityData.type_ru(StringName(t)))
	for r in _monster.weakness_ranges:
		parts.append(CityData.range_ru(StringName(r)))
	return ", ".join(parts)
