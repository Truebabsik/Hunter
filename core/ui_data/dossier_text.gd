extends RefCounted
class_name DossierText
## Досье вида: структура для окна (dossier_view) и подписи для показа.
##
## Вынесено из CityData по одной причине: это не правила города, а ПЕРЕСКАЗ
## состояния игроку. Заказы, слава и цены — правила, они проверяются прогоном
## баланса. Досье — представление: его проверяет валидатор на связность, а
## экраны на то, что структура не потеряла записанное.
##
## Здесь только функции, читающие GameState и данные вида. Никакого UI: окно
## рисует DossierWindow, а структуру собирает этот файл.
##
## Зависимость односторонняя: DossierText читает CityData.type_ru()/range_ru()
## (единственный источник названий типов и дистанций) и CityData.damage_types(),
## а CityData про DossierText не знает — кроме временных делегатов, которые
## удаляются отдельным шагом. Цикла нет.


## Типы урона словами для показа: «физика + огонь». Незачарованное оружие даёт
## один тип, и хвоста «+ …» не появляется.
static func damage_types_title(weapon: WeaponData) -> String:
	var names := PackedStringArray()
	for t in CityData.damage_types(weapon):
		names.append(CityData.type_ru(t))
	return " + ".join(names)


## Названия типов урона через запятую, без «+». Нужно там, где рядом уже стоит
## дальность и «+» читался бы как сложение: «дальний бой, физика, огонь».
static func damage_type_names(weapon: WeaponData) -> String:
	var names := PackedStringArray()
	for t in CityData.damage_types(weapon):
		names.append(CityData.type_ru(t))
	return ", ".join(names)


## Человеческое название руны по типу урона. Пусто — руны нет.
static func rune_title(rune_type: StringName) -> String:
	if rune_type == &"":
		return ""
	match rune_type:
		&"fire":
			return "Огонь"
		&"ice":
			return "Лёд"
		&"poison":
			return "Яд"
		_:
			return String(rune_type)


## Названия типов и дистанций: единственный источник на проект — CityData,
## поэтому здесь ничего своего нет, а вызовы идут прямо туда. Локальных копий
## быть не должно: копия названия типа — ровно та ошибка, из-за которой копьё
## подписывалось «физикой», считаясь колющим.
static func _signals_of(scn: ScenarioData, known: PackedStringArray) -> Array[SignalData]:
	var out: Array[SignalData] = []
	if known.is_empty():
		return out
	for sig in scn.signals:
		if known.has(sig.label):
			out.append(sig)
	return out


## Все улики сценария. Отдельно от _signals_of, потому что «сколько улик у атаки
## всего» нужно и для счётчика незнания, и для проверки связности досье.
static func _signals_all(scn: ScenarioData) -> Array[SignalData]:
	var out: Array[SignalData] = []
	for sig in scn.signals:
		out.append(sig)
	return out


## Есть ли у атаки комбо вообще. Нужно, чтобы отличить «комбо не открыто» от
## «у этой атаки комбо не бывает».
static func _has_combo(mon: MonsterData, scn: ScenarioData) -> bool:
	for c in mon.combos:
		if c.scenario_id == scn.id:
			return true
	return false


## Обманы, которые подмешиваются в этот сценарий и уже замечены игроком.
## Привязка по label: в досье хранится подпись, id теряется при записи.
static func _decoys_of(mon: MonsterData, scn: ScenarioData, known: PackedStringArray) -> PackedStringArray:
	var out := PackedStringArray()
	if known.is_empty():
		return out
	for lead in mon.false_leads:
		if lead.scenario_id == scn.id and known.has(lead.label):
			out.append(lead.label)
	return out


## Чем открывается комбо: приём + дальность и тип, если они не «любые».
static func _combo_requirement(c: ComboData) -> String:
	var bits := PackedStringArray()
	if c.required_range != &"any":
		bits.append(CityData.range_ru(c.required_range))
	if c.required_type != &"any":
		bits.append(CityData.type_ru(c.required_type))
	return ", ".join(bits) if not bits.is_empty() else "любым оружием"


## --- Окно вида: структура, а не строки -------------------------------------
##
## Утилита окна вида возвращает СТРУКТУРУ, а не готовый текст. Причина простая:
## текст проверяется только глазами, а структуру можно проверить прогоном —
## «у каждой атаки есть её улики», «особые правила вида не потерялись».
##
## Ключи: identity (title, epithet, level, level_title, lore), stats, attacks,
## special (особые правила), weaknesses, resists, unlearned (сколько атак закрыто).
##
## У КАЖДОЙ атаки есть флаг `known`. Неизученная атака остаётся в списке, но с
## закрытым названием: игрок видел прозу и знает, что атака существует, однако
## связать её с названием ещё не может. Поэтому её место в разборе сохраняется,
## а текст заменяется знаками вопроса — иначе пропадает и счёт, и ощущение
## «здесь есть что открыть».
static func dossier_view(mon: MonsterData) -> Dictionary:
	var view := {
		"identity": {},
		"stats": {},
		"attacks": [],
		"unlearned": 0,
		"special": [],
		"weaknesses": PackedStringArray(),
		"resists": PackedStringArray(),
	}
	if mon == null:
		return view

	var level := GameState.dossier_level(mon.id)
	var titles := ["не открыто", "НАБЛЮДЕНИЕ", "АНАЛИЗ", "МАСТЕРСТВО"]
	view["identity"] = {
		"title": mon.title,
		"epithet": mon.epithet,
		"level": level,
		"level_title": titles[clampi(level, 0, 3)],
		"lore": mon.lore,
	}
	view["stats"] = {
		"hp": mon.max_hp,
		"armor": mon.armor,
		"damage": mon.base_damage,
		"initiative": mon.initiative,
	}

	var e: Dictionary = GameState.dossier_entry(mon.id)
	var known_signals := _strings(e["signals"])
	var known_decoys := _strings(e["decoys"])
	var known_combos := _strings(e["combos"])

	# Уязвимости и резисты — зеркала друг друга, и оба нужны вместе: без резистов
	# окно обещало бы урон, которого не будет.
	var weak := PackedStringArray()
	for t in mon.weakness_types:
		weak.append(CityData.type_ru(StringName(t)))
	for r in mon.weakness_ranges:
		weak.append(CityData.range_ru(StringName(r)))
	view["weaknesses"] = weak

	var res := PackedStringArray()
	for t in mon.type_resist.keys():
		var amount := int(mon.type_resist[t])
		if amount > 0:
			res.append("%s −%d" % [CityData.type_ru(StringName(t)), amount])
	for r in mon.range_resist.keys():
		var ramount := int(mon.range_resist[r])
		if ramount > 0:
			res.append("%s −%d" % [CityData.range_ru(StringName(r)), ramount])
	view["resists"] = res

	for scn in mon.scenarios:
		var mine := _signals_of(scn, known_signals)
		var decoys := _decoys_of(mon, scn, known_decoys)
		# Атака без единой записанной улики остаётся в списке ЗАКРЫТОЙ: место
		# сохраняется, название и улики прячутся. Так игрок видит, сколько ещё
		# осталось, и что именно он пока не связал.
		var known_attack := not mine.is_empty()
		if not known_attack:
			view["unlearned"] = int(view["unlearned"]) + 1

		var combos: Array = []
		if known_attack and level >= 3:
			for c in mon.combos:
				if c.scenario_id == scn.id and known_combos.has(c.title):
					combos.append({
						"title": c.title,
						"requirement": _combo_requirement(c),
						"bonus": c.damage_bonus,
						"effect": c.effect_text,
					})

		view["attacks"].append({
			"known": known_attack,
			"label": scn.card_label,
			# Описания сценария здесь НЕТ намеренно: оно дословно повторяло
			# формулировки опорных сигналов, и игрок принимал его за подсказку.
			# В бою проза выдаёт ОДИН сигнал из списка, а описание статично.
			# Поле осталось в ScenarioData — им пользуется разбор после боя.
			"signals": _signal_texts(mine),
			"hidden_signals": _signals_all(scn).size() - mine.size(),
			"decoys": decoys,
			"damage": scn.damage_of(mon.base_damage),
			"unblockable": scn.unblockable,
			"combos": combos,
			"has_combo": _has_combo(mon, scn),
		})

	# Особые правила: без них окно не отвечает на «что этот зверь делает иначе».
	# Все четыре механики уже лежат в данных вида, но раньше их не читал никто.
	if level >= 2:
		if mon.fog_enabled:
			view["special"].append({
				"title": mon.fog_title if not mon.fog_title.is_empty() else "Туман обзора",
				"text": mon.fog_text,
			})
		if mon.ticking_damage > 0:
			view["special"].append({
				"title": mon.ticking_text if not mon.ticking_text.is_empty() else "Тлеющий урон",
				"text": "Каждый ход −%d HP, пока не прочитан ключевой сценарий." % mon.ticking_damage,
			})
		for phase in mon.phases:
			view["special"].append({
				"title": "Фаза: %s" % str(phase.get("title", "")),
				"text": _phase_text(phase),
			})
		for adapt in mon.adaptations:
			view["special"].append({
				"title": "Привыкание после %d раундов" % int(adapt.get("after_round", 0)),
				"text": _adaptation_text(mon, adapt),
			})

	if level >= 3 and not mon.counter_title.is_empty():
		view["special"].append({
			"title": "Контр-приём: %s" % mon.counter_title,
			"text": "%s Порог — %d верных чтений." % [mon.counter_text, mon.counter_threshold],
		})

	# Обманы без своей атаки (`scenario_id == &""`) подмешиваются в прозу любой
	# атаки, поэтому под конкретной им места нет. Показываем отдельно: молча
	# потерять записанное нельзя, а сейчас таких обманов в контенте нет — значит,
	# без этой ветки потеря прошла бы незамеченной.
	var unbound_decoys := PackedStringArray()
	for d in known_decoys:
		var bound := false
		for lead in mon.false_leads:
			if lead.label == String(d) and lead.scenario_id != &"":
				bound = true
				break
		if not bound:
			unbound_decoys.append(String(d))
	view["unbound_decoys"] = unbound_decoys

	return view


static func _signal_texts(signals: Array[SignalData]) -> PackedStringArray:
	var out := PackedStringArray()
	for s in signals:
		out.append(s.label)
	return out


## Фаза по доле HP. Список в данных идёт от низкого порога к высокому, поэтому
## пересказываем его как «при каком HP что меняется», а не как сырые доли.
static func _phase_text(phase: Dictionary) -> String:
	var weak_types := PackedStringArray()
	for t in (phase.get("weak_types", PackedStringArray()) as PackedStringArray):
		weak_types.append(CityData.type_ru(StringName(t)))
	for r in (phase.get("weak_ranges", PackedStringArray()) as PackedStringArray):
		weak_types.append(CityData.range_ru(StringName(r)))
	var bits := PackedStringArray()
	var note := str(phase.get("note", ""))
	if not note.is_empty():
		bits.append(note)
	if weak_types.is_empty():
		bits.append("Уязвимостей в этой фазе нет.")
	else:
		bits.append("Открыт для: %s." % ", ".join(weak_types))
	var noise := float(phase.get("noise", 1.0))
	if not is_equal_approx(noise, 1.0):
		bits.append("Шум ×%.1f." % noise)
	return " ".join(bits)


static func _adaptation_text(mon: MonsterData, adapt: Dictionary) -> String:
	var scn := mon.find_scenario(StringName(adapt.get("scenario", "")))
	var who := scn.card_label if scn != null else String(adapt.get("scenario", ""))
	var percent := roundi((float(adapt.get("multiplier", 1.0)) - 1.0) * 100.0)
	return "Зверь привыкает: «%s» чаще на %d%%." % [who, percent]


static func _strings(arr: Array) -> PackedStringArray:
	var out := PackedStringArray()
	for x in arr:
		out.append(str(x))
	return out

