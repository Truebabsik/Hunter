extends RefCounted
class_name ContentValidator
## Проверка инвариантов контента. Запуск:
##   Godot_..._console.exe --headless --path F:\WORK\hunter -- --validate
##
## Это не тесты механики, а защита от авторинга: именно нарушение этих правил
## ломает «правило честности» (GDD 2.2) и делает игру нечестной, а не просто
## несбалансированной.

const SLOTS := ["pose", "gear", "sound", "gaze", "environment"]
const MIN_SYNONYMS := 3


## Имена статусов движка строками — для сообщений проверки.
static func _status_names() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for s in BattleEngine.STATUS_IDS:
		out.append(String(s))
	return out


func validate_all() -> Array:
	var problems: Array = []
	problems.append_array(_check_load_errors())
	problems.append_array(_check_monsters())
	problems.append_array(_check_trails())
	problems.append_array(_check_runes())
	problems.append_array(_check_rune_damage())
	problems.append_array(_check_physical_subtypes())
	problems.append_array(_check_dossier_render())
	problems.append_array(_check_city_tables())
	return problems


## Физический урон разделён на три подтипа (дробящий / режущий / колющий), и это
## обязано быть ПОЛЕЗНО, а не просто названо.
##
## Здесь ловятся четыре тихие поломки:
##  1. тип в таблице вида или в комбо, которым НЕЧЕМ ударить (опечатка или забытый
##     источник типа: физику даёт оружие, магию — руна на нём);
##  2. тип закрыт у вида по ВСЕМ дистанциям: тогда слабость есть, а использовать
##     её нечем — в упор бьют, издалека нет, и наоборот;
##  3. у вида закрыты все три физических подтипа: выбор оружия упирается в тупик;
##  4. оружие, которое не нужно НИ ОДНОМУ виду: позиция в магазине, которую
##     незачем покупать.
func _check_physical_subtypes() -> Array:
	var out: Array = []

	# Чем реально можно ударить: базовые типы оружия плюс типы рун. Магию даёт
	# ТОЛЬКО руна, поэтому без рун в этот список её включать нельзя — иначе
	# проверка объявит недостижимыми все комбо на огонь, лёд и яд.
	var reachable := {}
	var reachable_melee := {}
	var reachable_ranged := {}
	for id in Database.weapons.keys():
		var w: WeaponData = Database.weapons[id]
		for t in CityData.damage_types(w):
			reachable[t] = true
			if w.range_id == MonsterData.RANGE_MELEE:
				reachable_melee[t] = true
			else:
				reachable_ranged[t] = true
	for skill_id in SkillsData.RUNE_SKILLS.keys():
		reachable[StringName(SkillsData.RUNE_SKILLS[skill_id])] = true

	for id in Database.monsters.keys():
		var mon: MonsterData = Database.monsters[id]
		var label := "%s (%s)" % [mon.title, mon.id]

		var shut: Array = []
		for t in MonsterData.PHYSICAL_TYPES:
			var res := mon.type_resist_for(t)
			var weak := mon.is_weak_to_type(t)
			if weak and res > 0:
				out.append("подтипы: %s — «%s» одновременно уязвимость и резист" % [label, t])
			# Полезность: уязвимость обязана быть достижима ХОТЯ БЫ одной
			# дистанцией. Требовать обе нельзя: Громун уязвим к дробящему только
			# в упор и устойчив к дальней дистанции — это его природа, а не
			# ошибка контента. Ошибка — когда нечем ударить ВООБЩЕ.
			if weak:
				if not reachable.has(t):
					out.append("подтипы: %s — уязвим к «%s», но такого урона нет в игре" % [label, t])
				elif not reachable_melee.has(t) and not reachable_ranged.has(t):
					out.append("подтипы: %s — уязвим к «%s», но ни одним оружием этого типа не ударить" % [label, t])
			if res > 0:
				shut.append(t)

		if shut.size() == MonsterData.PHYSICAL_TYPES.size():
			out.append("подтипы: %s — закрыты ВСЕ физические подтипы, выбор оружия тупиковый" % label)

		# Уязвимости, приходящие из фаз (Ламент в истощении), тоже обязаны быть
		# достижимы: иначе фаза открывает слабость, которую нечем использовать.
		for ph in mon.phases:
			for wt in (ph.get("weak_types", PackedStringArray()) as PackedStringArray):
				var t := StringName(wt)
				if not reachable.has(t):
					out.append("подтипы: %s — фаза «%s» открывает тип «%s», которым нечем ударить" % [
						label, str(ph.get("title", "")), t])

		# Комбо тоже требует конкретный тип: он должен существовать.
		for c in mon.combos:
			if c.required_type == &"any":
				continue
			if not reachable.has(c.required_type):
				out.append("подтипы: %s — комбо «%s» требует тип «%s», которым нечем ударить" % [
					label, c.title, c.required_type])

	# Обратная сторона: каждое оружие обязано быть КОМУ-ТО нужно. Иначе в магазине
	# лежит позиция, которую незачем покупать, — а игрок узнаёт об этом, только
	# потратив монеты. Тип оружия считается полезным, если хотя бы один вид к нему
	# уязвим: без уязвимости любой подтип проходит одинаково.
	for id in Database.weapons.keys():
		var w: WeaponData = Database.weapons[id]
		var useful := false
		for monster_id in Database.monsters.keys():
			var m: MonsterData = Database.monsters[monster_id]
			# Уязвимость может открыться фазой (Ламент), поэтому смотрим и фазы.
			if m.is_weak_to_type(w.damage_type):
				useful = true
				break
			for ph in m.phases:
				for wt in (ph.get("weak_types", PackedStringArray()) as PackedStringArray):
					if StringName(wt) == w.damage_type:
						useful = true
						break
				if useful:
					break
			if useful:
				break
		if not useful:
			out.append("подтипы: оружие «%s» (%s) не нужно ни одному виду — нет ни слабости, ни одной атаки такого типа" % [
				w.title, w.damage_type])
		if w.damage_type == &"":
			out.append("подтипы: у оружия «%s» не указан тип урона" % w.title)

	# Полнота ролей НЕ проверяется намеренно. Правило «у каждого типа обязан быть
	# ближний вариант» звучит разумно, но это вопрос дизайна, а не инвариант: вид
	# может быть уязвим к колющему только на дистанции, и это нормально. Проверять
	# надо не наличие вариантов, а достижимость того, что уже записано в контенте
	# (см. выше). Копьё добавлено именно потому, что так удобнее играть, а не
	# потому что этого требует проверка.

	return out


## Досье обязано раскладывать улики ПО ИХ АТАКАМ, а не плоским списком, и не
## показывать то, что игрок ещё не заработал.
##
## Проверка идёт по всем видам и по полному набору знаний: у одного вида связка
## может случайно совпасть, а на шести сразу — уже нет. Именно так ловится
## разъезд данных: подпись сценария переименовали, сигнал перенесли в другую
## атаку — досье при этом молча теряло бы улику, и заметить это было бы нечем.
##
## Проверка структурная, а не строковая. Раньше здесь искались подстроки в
## текстовом рендере досье, и это сторожило функцию, которой не пользовался ни
## один экран: зелёная проверка при сломанном показе. Теперь проверяется ровно
## то, что читает окно вида — view["attacks"], их флаг known и их улики.
##
## Досье игры на время проверки сохраняется и возвращается: валидатор не имеет
## права менять состояние забега.
func _check_dossier_render() -> Array:
	var out: Array = []
	for id in Database.monsters.keys():
		var mon: MonsterData = Database.monsters[id]
		var saved: Dictionary = GameState.dossier_entry(mon.id).duplicate(true)
		# Записываем ВСЁ, что вид может открыть: сигналы, обманы, комбо.
		for scn in mon.scenarios:
			for sig in scn.signals:
				GameState.dossier_add(mon.id, "signals", sig.label)
		for lead in mon.false_leads:
			GameState.dossier_add(mon.id, "decoys", lead.label)
		for c in mon.combos:
			GameState.dossier_add(mon.id, "combos", c.title)

		var label := "%s (%s)" % [mon.title, mon.id]
		var view := CityData.dossier_view(mon)
		var attacks: Array = view["attacks"]

		# Каждая атака вида обязана стоять в разборе ровно один раз, и на полном
		# знании — быть открытой. Иначе часть контента не показывается вовсе.
		if attacks.size() != mon.scenarios.size():
			out.append("досье: %s — атак в разборе %d, а у вида их %d" % [
				label, attacks.size(), mon.scenarios.size()])
		if int(view["unlearned"]) != 0:
			out.append("досье: %s — на полном знании закрыто атак: %d" % [
				label, int(view["unlearned"])])

		# Улики атаки обязаны лежать В ЕЁ блоке. Сравнение по подписи: в досье
		# хранится label, а не id сигнала.
		for scn in mon.scenarios:
			var block: Dictionary = _attack_block(attacks, String(scn.card_label))
			if block.is_empty():
				out.append("досье: %s — атака «%s» не показана, хотя улики записаны" % [
					label, scn.card_label])
				continue
			if not bool(block["known"]):
				out.append("досье: %s — атака «%s» закрыта на полном знании" % [
					label, scn.card_label])
			var shown: PackedStringArray = block["signals"]
			for sig in scn.signals:
				if not shown.has(sig.label):
					out.append("досье: %s — улика «%s» атаки «%s» потеряна" % [
						label, sig.label, scn.card_label])
			if int(block["hidden_signals"]) != 0:
				out.append("досье: %s — у атаки «%s» скрытых улик %d на полном знании" % [
					label, scn.card_label, int(block["hidden_signals"])])

		# Знание не должно утекать: пока не записана НИ ОДНА улика вида, все его
		# атаки обязаны быть закрытыми. Иначе окно показало бы игроку то, что он
		# ещё не заработал боями.
		GameState.dossier[String(mon.id)] = {
			"level": 0, "signals": [], "decoys": [], "scenarios": [],
			"weaknesses": [], "rules": [], "combos": [],
		}
		var empty_view := CityData.dossier_view(mon)
		var shown := 0
		for attack in (empty_view["attacks"] as Array):
			if bool(attack["known"]):
				shown += 1
		if shown > 0:
			out.append("досье: %s — на пустом досье открыто атак: %d" % [label, shown])
		if int(empty_view["unlearned"]) != mon.scenarios.size():
			out.append("досье: %s — закрытых атак %d, а всего их %d" % [
				label, int(empty_view["unlearned"]), mon.scenarios.size()])

		# Возвращаем досье как было: проверка не имеет права оставлять след.
		GameState.dossier[String(mon.id)] = saved
	return out


## Блок атаки по подписи её карточки. Пустой словарь — атаки в разборе нет.
## Если подписи у двух атак совпадут, вернётся первая: это не повод для ошибки,
## проверка улик всё равно пойдёт по каждой атаке отдельно.
func _attack_block(attacks: Array, card_label: String) -> Dictionary:
	for attack in attacks:
		if String(attack["label"]) == card_label:
			return attack
	return {}


func _check_runes() -> Array:
	var out: Array = []
	# Каждая руна обязана быть открываема каким-то навыком из ветки «Оружие»,
	# иначе игрок её не получит никогда.
	for skill_id in SkillsData.RUNE_SKILLS.keys():
		if SkillsData.find_skill(StringName(skill_id)).is_empty():
			out.append("руны: навык «%s» открывает руну, но его нет в списке навыков" % skill_id)
	# «Главный» тип удара: у зачарованного оружия это тип руны. Им пользуется
	# подбор комбо, поэтому проверяем отдельно от показа.
	var probe := WeaponData.new()
	probe.id = &"rune_probe"
	probe.damage_type = MonsterData.TYPE_CRUSH
	if CityData.effective_damage_type(probe) != MonsterData.TYPE_CRUSH:
		out.append("руны: незачарованное оружие бьёт не своим базовым типом")
	probe.rune_type = &"ice"
	if CityData.effective_damage_type(probe) != &"ice":
		out.append("руны: главный тип зачарованного оружия — не тип руны")

	# Показ обязан не терять базовый тип. Это уже было сломано: экран боя и лог
	# брали effective_damage_type() и подписывали удар одним типом руны, хотя
	# урон считается по обоим. Игрок по такой подписи решал, что физическая
	# уязвимость вида ему недоступна.
	var shown := CityData.damage_types(probe)
	if shown.size() != 2 or not shown.has(MonsterData.TYPE_CRUSH) or not shown.has(&"ice"):
		out.append("руны: показ типов теряет базовый тип (%s)" % str(shown))
	var plain := WeaponData.new()
	plain.id = &"plain_probe"
	plain.damage_type = &"fire"
	if CityData.damage_types(plain).size() != 1:
		out.append("руны: у незачарованного оружия показ даёт больше одного типа")
	if CityData.damage_types_title(probe) != "дробящий + лёд":
		out.append("руны: подпись типов читается как «%s», ждали «дробящий + лёд»" % \
			CityData.damage_types_title(probe))

	# Каждое оружие в базе должно быть зачаровываемо: тип руны — один из известных.
	for id in Database.weapons.keys():
		var w: WeaponData = Database.weapons[id]
		if w.rune_type != &"" and not SkillsData.RUNE_SKILLS.values().has(String(w.rune_type)):
			out.append("оружие %s: неизвестная руна «%s»" % [w.id, w.rune_type])
	return out


## Подставной вид для проверки зачарования: уязвим ко льду, устойчив к дробящему,
## без панциря. Так разница урона объясняется ТОЛЬКО типами урона.
##
## Запись «physical» здесь не опечатка: она проверяет СТАРЫЙ способ записи.
## Общая физика обязана покрывать все три подтипа (MonsterData.type_resist_for),
## иначе старые таблицы молча перестали бы защищать зверя.
func _probe_monster() -> MonsterData:
	var mon := MonsterData.new()
	mon.id = &"rune_probe"
	mon.title = "Проба руны"
	mon.max_hp = 20
	mon.armor = 0
	mon.weakness_types = PackedStringArray(["ice"])
	mon.type_resist = {"physical": 1, "ice": 0}
	return mon


## Дифференциальная проверка зачарования: один и тот же бой, два оружия —
## с руной и без. Урон обязан отличаться.
##
## Зачем так, а не «тип руны попал в расчёт»: проверка типа прошла бы и в том
## случае, если бы формула урона руну игнорировала — а именно это и было сломано
## (модификаторы существовали в данных, но в бою не читались нигде). Здесь
## проверяется, что чары ДОХОДЯТ до урона.
##
## Вид уязвим ко льду и устойчив к физике, поэтому руна обязана ДОБАВИТЬ урон:
## по GDD 12.3 руна добавляет второй тип, а не заменяет базовый.
func _check_rune_damage() -> Array:
	var out: Array = []
	var mon := _probe_monster()
	var base_dmg := _damage_with(&"", mon)
	var rune_dmg := _damage_with(&"ice", mon)
	if rune_dmg <= base_dmg:
		out.append(
			"руны: зачарование не влияет на урон (без руны %d, с руной «лёд» %d)" % [
				base_dmg, rune_dmg])
	return out


## Урон по подставному виду оружием с указанной руной, при верном чтении.
## Базовый подтип — дробящий: у подставного вида он нейтрален, поэтому разницу
## урона объясняют ТОЛЬКО чары.
func _damage_with(rune_type: StringName, mon: MonsterData) -> int:
	var w := WeaponData.new()
	w.id = &"rune_probe"
	w.damage_type = MonsterData.TYPE_CRUSH
	w.rune_type = rune_type
	w.base_damage = 3
	w.range_id = MonsterData.RANGE_MELEE
	var res := DamageCalc.player_damage(
		w, mon, DamageCalc.Reading.COUNTER, false, 0, 0, {}, 0.0, null)
	return res.total


## «След» должен существовать для каждого вида: без него охота теряет связку
## «город → бой» (GDD 10.1). Проверяем все четыре фазы.
func _check_trails() -> Array:
	var out: Array = []
	if HuntTrail.entry_count() == 0:
		out.append("след: не загружено ни одной записи из %s" % HuntTrail.TRAIL_PATH)
		return out
	for id in Database.monsters.keys():
		var mon: MonsterData = Database.monsters[id]
		var phases := HuntTrail.phases_for(mon.id)
		for phase in HuntTrail.PHASES:
			if not phases.has(phase):
				out.append("%s (%s): нет ни одного отрывка следа для фазы «%s»" % [
					mon.title, mon.id, phase])
	return out


## Ключи городских таблиц обязаны совпадать с базой видов.
##
## Зачем отдельная проверка. Таблицы вида «id вида → число» читаются через
## `get(key, запасное)`, и опечатка в ключе НЕ падает: она молча подставляет
## запасное значение. На живом контенте это уже случилось — в ADVICE_PRICES
## стоял ключ «sorrow» вместо «skorb», и совет о Скорбе стоил 10 монет вместо 15.
## Ни один экран этого не показывал: цена выглядела обычной.
##
## Проверка идёт в обе стороны, и обе стороны — не украшение:
##  • вид без ключа получает запасную цену (тихая подмена числа);
##  • ключ без вида — мёртвая строка: после переименования вида она остаётся и
##    выглядит как работающая настройка, хотя не делает ничего.
##
## ORDER_RANKS проверяется отдельно: available_monsters() отсеивает виды, которых
## нет в базе, и без этой проверки выпавший вид просто исчезает из доски заказов
## — молча, без единого сообщения.
func _check_city_tables() -> Array:
	var out: Array = []

	for id in Database.monsters.keys():
		if not CityData.ADVICE_PRICES.has(String(id)):
			var mon: MonsterData = Database.monsters[id]
			out.append("город: у вида %s (%s) нет цены совета — подставится запасная %d" % [
				mon.title, id, CityData.advice_price(id)])

	for key in CityData.ADVICE_PRICES.keys():
		if Database.monster(StringName(key)) == null:
			out.append("город: цена совета задана для вида «%s», которого нет в базе" % key)

	for tier in CityData.ORDER_RANKS.keys():
		for m in CityData.ORDER_RANKS[tier]["monsters"]:
			if Database.monster(StringName(m)) == null:
				out.append("город: заказ ранга %d ссылается на вид «%s», которого нет в базе" % [
					int(tier), m])

	return out


func _check_load_errors() -> Array:
	var out: Array = []
	for e in Database.load_errors:
		out.append("загрузка: %s" % e)
	return out


func _check_monsters() -> Array:
	var out: Array = []
	if Database.monsters.is_empty():
		out.append("не загружено ни одного вида — проверь content/monsters/*.tres")
		return out
	for id in Database.monsters.keys():
		var mon: MonsterData = Database.monsters[id]
		out.append_array(_check_monster(mon))
	return out


func _check_monster(mon: MonsterData) -> Array:
	var out: Array = []
	var label := "%s (%s)" % [mon.title, mon.id]

	if mon.scenarios.is_empty():
		out.append("%s: нет ни одного сценария" % label)
		return out
	if mon.max_hp <= 0:
		out.append("%s: max_hp <= 0" % label)

	var dup_slots_seen: Dictionary = {}
	for scn in mon.scenarios:
		var sl := "%s / сценарий %s" % [label, scn.id]
		if scn.id == &"":
			out.append("%s: пустой id сценария" % sl)
		if scn.signals.is_empty():
			out.append("%s: нет опорных сигналов — «гарантированное чтение» невозможно" % sl)
			continue
		if scn.card_label.strip_edges().is_empty():
			out.append("%s: пустая подпись карточки-гипотезы" % sl)

		# Инвариант 1: внутри сценария два сигнала не могут делить слот.
		var slot_owner: Dictionary = {}
		for sig in scn.signals:
			if not SLOTS.has(String(sig.slot)):
				out.append("%s: сигнал %s в неизвестном слоте «%s»" % [sl, sig.id, sig.slot])
			if slot_owner.has(sig.slot):
				out.append("%s: два опорных сигнала в одном слоте «%s» (%s и %s)" % [
					sl, sig.slot, slot_owner[sig.slot], sig.id])
			slot_owner[sig.slot] = sig.id
			if sig.label.strip_edges().is_empty():
				out.append("%s: сигнал %s без label" % [sl, sig.id])
			# Пул фраз: минимум синонимов, иначе текст заест за 10 боёв (GDD 13.2).
			var pool := Database.phrases_for(mon.id, scn.id, sig.slot, Phrase.ROLE_CORE)
			if pool.is_empty():
				out.append("%s: нет ни одной фразы для сигнала %s (слот %s)" % [sl, sig.id, sig.slot])
			elif pool.size() < MIN_SYNONYMS:
				out.append("%s: для %s только %d фраз(ы), нужно минимум %d" % [
					sl, sig.id, pool.size(), MIN_SYNONYMS])
		dup_slots_seen[scn.id] = true

	# Инвариант 2 (GDD 2.2): ложный след не может делить слот с опорным сигналом
	# ТОГО СЦЕНАРИЯ, в котором он подмешивается. Иначе при прозе этого сценария
	# игрок видит два сигнала в одном слоте и не может отличить опору от обмана.
	#
	# Важно: проверка именно по сценарию, а не по виду целиком. Обман, привязанный
	# к другому сценарию, в этом сценарии не участвует — генератор его не берёт.
	for lead in mon.false_leads:
		var lead_scn := mon.find_scenario(lead.scenario_id)
		if lead_scn == null:
			out.append("%s: ложный след %s ссылается на несуществующий сценарий %s" % [
				label, lead.id, lead.scenario_id])
		elif lead_scn.has_slot(lead.slot):
			out.append("%s: ложный след «%s» (слот %s) конфликтует с опорным сигналом сценария %s" % [
				label, lead.label, lead.slot, lead.scenario_id])
		var pool := Database.phrases_for(mon.id, lead.scenario_id, lead.slot, Phrase.ROLE_DECOY)
		if pool.is_empty():
			out.append("%s: нет фраз для ложного следа %s (слот %s)" % [label, lead.id, lead.slot])
		elif pool.size() < MIN_SYNONYMS:
			out.append("%s: для ложного следа %s только %d фраз(ы), нужно минимум %d" % [
				label, lead.id, pool.size(), MIN_SYNONYMS])

	# Инвариант 2б: у каждого сценария должно быть достаточно своих обманов,
	# чтобы наполнить бюджет абзаца (GDD 3.3) и не повторять один и тот же обман.
	var budget := int(TextGenerator.DECOYS_BY_RANK.get(mon.rank, 1))
	for scn in mon.scenarios:
		var usable := 0
		for lead in mon.false_leads:
			if lead.scenario_id == scn.id and not scn.has_slot(lead.slot):
				usable += 1
		if usable < budget:
			out.append("%s: у сценария %s своих обманов без конфликта слотов %d, а бюджет абзаца требует %d" % [
				label, scn.id, usable, budget])

	# Инвариант 3: у комбо должен существовать сценарий, к которому он привязан.
	for c in mon.combos:
		if mon.find_scenario(c.scenario_id) == null:
			out.append("%s: комбо «%s» ссылается на несуществующий сценарий %s" % [
				label, c.title, c.scenario_id])
		if not Database.weapons.has("bow"):
			out.append("%s: нет оружия в базе" % label)
			break

	# Инвариант 3.1: статус комбо обязан быть тем, что движок УМЕЕТ обрабатывать.
	#
	# Проверка появилась потому, что инвариант уже был нарушен: у Пепел-Матери
	# («зверь слепнет») и Тлеуна («зверь открыт на 2 хода») стояли статусы blind и
	# open, которых в движке не существовало ни в одном месте. Игрок видел описание
	# эффекта, а механика не делала ничего. Описание — это обещание, и оно должно
	# быть выполнимо: иначе игрок принимает решение по тексту, которого нет.
	for c in mon.combos:
		var st := String(c.status_id)
		if st.is_empty():
			continue
		if not BattleEngine.STATUS_IDS.has(StringName(st)):
			out.append("%s: комбо «%s» накладывает статус «%s», которого движок не обрабатывает (умеет: %s)" % [
				label, c.title, st, ", ".join(_status_names())])

	# Инвариант 4: уязвимости и резисты не должны противоречить друг другу.
	var weak_t := mon.weakness_types
	for t in mon.type_resist.keys():
		if weak_t.has(String(t)):
			out.append("%s: тип «%s» одновременно уязвимость и резист — правило неоднозначно" % [label, t])
	var weak_r := mon.weakness_ranges
	for r in mon.range_resist.keys():
		if weak_r.has(String(r)):
			out.append("%s: дальность «%s» одновременно уязвимость и резист" % [label, r])

	return out
