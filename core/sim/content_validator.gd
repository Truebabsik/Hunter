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
## Контракт посева пула реакции на удар (D19). Числа-источники — таблица «Посев»
## в `docs/2026-09-25-d19-hit-reaction-design.md` §4 и словарные таблицы §11.10
## `docs/dizain_hunter.md`; они не подобраны под данные.
##
## Три тройки — ТРИ РАЗНЫХ константы, хотя сегодня и равны: за каждой стоит своя
## таблица §11.10, и общая тройка заставила бы менять все три правила сразу, если
## дизайн захочет, скажем, четыре отпечатка (AGENTS.md §4: одно правило — один
## источник). Числа порогов живут ЗДЕСЬ и больше нигде.
##
## Это ПОРОГ, а не точный счёт: посев расширяемый (четвёртый носитель у вида или
## пятая вводная — не поломка). Проверка сторожит дыру, а не замораживает объём:
## без порога она ловила бы только полное обнуление детали, а удаление одной строки
## носителя из трёх оставляло бы её зелёной (измерено).
##
## Три носителя на вид — таблица «`{носитель}`» §11.10.
const REACTION_MIN_CARRIERS := 3
## Три отпечатка удара на оружие — таблица «Отпечаток удара» §11.10.
const REACTION_MIN_WEAPONS := 3
## Три стихийных окраски на руну — таблица «Стихийный слой (руна)» §11.10.
const REACTION_MIN_ELEMENTS := 3
## Четыре глагола на вердикт — таблица трёх категорий исхода §11.10.
const REACTION_MIN_VERB := 4
## Вводные: §4 спеки даёт «4–6 на группу», бриф задачи 2 берёт нижнюю границу — 4.
const REACTION_MIN_INTRO := 4


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
	problems.append_array(_check_reactions())
	problems.append_array(_check_dossier_render())
	problems.append_array(_check_city_tables())
	return problems


## Физический урон разделён на три подтипа (дробящий / режущий / колющий), и это
## обязано быть ПОЛЕЗНО, а не просто названо.
##
## С D23 уязвимость и резист — пара «тип И дистанция», поэтому и проверяются они
## парой, а не координатами порознь. Здесь ловятся пять тихих поломок:
##  1. уязвимость, недостижимая НИ ОДНОЙ парой (тип, дистанция) из арсенала, и тип
##     в комбо, которым нечем ударить (опечатка или забытый источник типа: физику
##     даёт оружие, магию — руна на нём);
##  2. ни одна пара «тип × дистанция» из арсенала не проходит без резиста: тогда
##     выбор оружия ничего не решает — слабость есть, а использовать её нечем;
##  3. запись уязвимости (своя или фазовая) полностью перекрыта резистами: на
##     каждой паре арсенала, где она срабатывает, итог нулевой или минусовой;
##  4. фаза открывает уязвимость, недостижимую ни одним оружием;
##  5. оружие, которое не нужно НИ ОДНОМУ виду: позиция в магазине, которую
##     незачем покупать.
func _check_physical_subtypes() -> Array:
	var out: Array = []

	# Чем реально можно ударить: базовые типы оружия плюс типы рун. Магию даёт
	# ТОЛЬКО руна, поэтому без рун в этот список её включать нельзя — иначе
	# проверка объявит недостижимыми все комбо на огонь, лёд и яд.
	var reachable := {}
	for id in Database.weapons.keys():
		var w: WeaponData = Database.weapons[id]
		for t in CityData.damage_types(w):
			reachable[t] = true
	for skill_id in SkillsData.RUNE_SKILLS.keys():
		reachable[StringName(SkillsData.RUNE_SKILLS[skill_id])] = true

	for id in Database.monsters.keys():
		var mon: MonsterData = Database.monsters[id]
		var label := "%s (%s)" % [mon.title, mon.id]

		# Полезность уязвимости (D23): уязвимость — это пара «тип И дистанция»,
		# поэтому проверять её по одному типу нельзя: у Громунa дробящее работает
		# только в упор, и «уязвим к дробящему» без дистанции — половина правды.
		# Ошибка контента — когда уязвимость недостижима НИ ОДНОЙ парой
		# (тип, дистанция) из существующего оружия.
		#
		# Записи читаются из ПОЛЯ напрямую: переходника `effective_*` больше нет
		# (Task 4), и синтез записей из старых списков снят — иначе о том же
		# самом было бы два источника правды.
		for rule_v in mon.weakness_rules:
			if not (rule_v is Dictionary):
				continue
			if _reachable_by_weapon(rule_v as Dictionary).is_empty():
				out.append("уязвимость: %s — запись «%s» недостижима ни одним оружием" % [
					label, ", ".join(MonsterData.rule_lines([rule_v as Dictionary]))])

		# Уязвимость обязана быть ЧЕМ-ТО использована: иначе вид открыт на бумаге.
		# Частичные пересечения с резистами — замысел (§2.3: у Шипуна яд в упор даёт
		# +1−1 = 0), полное перекрытие — нет: игрок видит слабость, которой нельзя
		# воспользоваться ни одной парой «тип × дистанция».
		for rule_v in mon.weakness_rules:
			if not (rule_v is Dictionary):
				continue
			if not _rule_pays_off(mon, rule_v as Dictionary, {}):
				out.append("%s: запись уязвимости «%s» полностью перекрыта резистами — ни одной пары с плюсом" % [
					label, ", ".join(MonsterData.rule_lines([rule_v as Dictionary]))])

		# Тупик — когда НИ ОДНА пара «тип × дистанция» из арсенала не проходит без
		# резиста: тогда выбор оружия действительно ничего не решает. Так эта
		# проверка и обобщает прежнюю «закрыты все три физических подтипа» на
		# модель записей.
		#
		# Считать её по ОДНОЙ дистанции нельзя: закрытая дальняя дистанция —
		# законный замысел, а не дефект. Громун резистит на дальней всё, что игра
		# туда доставляет (запись без types закрывает любой тип), и берут его в
		# упор — проверка «вся физика закрыта на дальней» называла бы дефектом
		# дизайн. Проверено: она краснела на Громунe.
		var checked_pairs := 0
		var any_open := false
		for range_id in [MonsterData.RANGE_MELEE, MonsterData.RANGE_RANGED]:
			for t in _deliverable_types(StringName(range_id)):
				checked_pairs += 1
				if mon.resist_modifier(t, StringName(range_id)) < 1:
					any_open = true
					break
			if any_open:
				break
		if checked_pairs > 0 and not any_open:
			out.append("подтипы: %s — ни одна пара «тип × дистанция» из арсенала не проходит без резиста: выбор оружия тупиковый" % label)

		# Уязвимости, приходящие из фаз (Ламент в истощении), тоже обязаны быть
		# достижимы: иначе фаза открывает слабость, которую нечем использовать.
		# Ключ читает модель (MonsterData.phase_weak_rules): не-массив она отдаёт
		# пустым списком, а называет это проверка структуры в _check_monster.
		for ph in mon.phases:
			for rule_v in MonsterData.phase_weak_rules(ph):
				if not (rule_v is Dictionary):
					continue
				if _reachable_by_weapon(rule_v as Dictionary).is_empty():
					out.append("подтипы: %s — фаза «%s» открывает запись «%s», недостижимую ни одним оружием" % [
						label, str(ph.get("title", "")),
						", ".join(MonsterData.rule_lines([rule_v as Dictionary]))])
				# И перекрыть её резистами можно так же, как базовую. Резистов фаза
				# не задаёт (D21.E), поэтому считаются базовые резисты вида.
				elif not _rule_pays_off(mon, rule_v as Dictionary, ph):
					out.append("подтипы: %s — запись фазы «%s» «%s» полностью перекрыта резистами — ни одной пары с плюсом" % [
						label, str(ph.get("title", "")),
						", ".join(MonsterData.rule_lines([rule_v as Dictionary]))])

		# Комбо тоже требует конкретный тип: он должен существовать.
		for c in mon.combos:
			if c.required_type == &"any":
				continue
			if not reachable.has(c.required_type):
				out.append("подтипы: %s — комбо «%s» требует тип «%s», которым нечем ударить" % [
					label, c.title, c.required_type])

	# Обратная сторона: каждое оружие обязано быть КОМУ-ТО нужно. Иначе в магазине
	# лежит позиция, которую незачем покупать, — а игрок узнаёт об этом, только
	# потратив монеты. Оружие считается полезным, если уязвимость хотя бы одного
	# вида срабатывает ровно по его паре «тип × дистанция»: без уязвимости в этой
	# паре любой подтип проходит одинаково.
	for id in Database.weapons.keys():
		var w: WeaponData = Database.weapons[id]
		var useful := false
		for monster_id in Database.monsters.keys():
			var m: MonsterData = Database.monsters[monster_id]
			# Полезность считается по ПАРЕ «тип × дистанция»: без уязвимости в
			# этой самой паре любой подтип проходит одинаково. Фазы здесь не
			# смотрим: фаза переопределяет уязвимости, а не создаёт спрос — если
			# оружие не нужно виду в его обычном состоянии, покупать его незачем.
			if m.weakness_modifier(w.damage_type, w.range_id) > 0:
				useful = true
				break
		if not useful:
			out.append("подтипы: оружие «%s» (%s) не нужно ни одному виду — нет ни слабости, ни одной атаки такого типа" % [
				w.title, w.damage_type])
		if w.damage_type == &"":
			out.append("подтипы: у оружия «%s» не указан тип урона" % w.title)

	# Полнота ролей: раньше она НЕ проверялась намеренно. Правило «у каждого типа
	# обязан быть ближний вариант» и правда было вопросом дизайна, а не
	# инвариантом: вид может быть уязвим к колющему только на дистанции, и это
	# нормально. С D20 вопрос перестал быть открытым — дизайн сам объявил каталог
	# матрицей 3×2: шесть стволов и есть все шесть сочетаний (§12.2). Раз каталог
	# ОПРЕДЕЛЁН как полная матрица, пробел в ней и дубль ячейки — уже поломка
	# контента, а не вкусовщина: пробел оставляет роль, которую нечем занять,
	# дубль кладёт в магазин два ствола с одной ролью.
	#
	# Матрица (дальность × физический тип) обязана быть закрыта ровно один раз
	# каждой ячейкой: шесть оружий D20 — это все шесть сочетаний. Дубль означает
	# два ствола с одной ролью (так в каталоге жили два дальних колющих сразу),
	# пробел — роль, которую нечем занять (так не было дальнего дробящего и
	# дальнего режущего).
	#
	# Намеренно проверяются ТОЛЬКО физические подтипы: магию даёт руна, а не
	# ствол, поэтому тройка «дальность × элемент» каталогом не закрывается и
	# ячейкой матрицы не является.
	var cells := {}
	for id in Database.weapons.keys():
		var w: WeaponData = Database.weapons[id]
		if not MonsterData.is_physical_subtype(w.damage_type):
			continue
		var cell := "%s|%s" % [w.range_id, w.damage_type]
		if cells.has(cell):
			out.append("каталог: ячейка «%s» занята дважды — «%s» и «%s»" % [
				cell, cells[cell], w.title])
		cells[cell] = w.title
	for rng in [MonsterData.RANGE_MELEE, MonsterData.RANGE_RANGED]:
		for t in MonsterData.PHYSICAL_TYPES:
			var cell := "%s|%s" % [rng, t]
			if not cells.has(cell):
				out.append("каталог: ячейка «%s» пуста — этой роли нет ни одного оружия" % cell)

	return out


## Покрытие пула реакции на удар (D19). Дыра здесь — не мелочь: без детали сборка
## не имеет права печатать обрубок, а игрок — не получить обещанную фразу, поэтому
## недостающая деталь называется по имени.
##
## Ключи ведёр и слоты берутся из `HitReaction` (`SLOT_*` / `VERDICT_*`), а не
## литералами: те же идентификаторы нужны сборке, и вторая копия строки
## «reaction_verb» разошлась бы с первой молча (AGENTS.md §4). Как ключи
## раскладываются по колонкам CSV и что именно обязано быть покрыто — таблица
## «Посев» в `docs/2026-09-25-d19-hit-reaction-design.md` §4 и шаг сборки в
## `docs/2026-09-25-plan-d19-hit-reaction.md` (Task 3).
##
## Поэтому опечатка в id вида или оружия не молчит, а краснеет по имени: строка с
## опечаткой в CSV остаётся, но её ведро пусто, и здесь называется вид (оружие,
## руна), у которого детали нет.
##
## Роль носителя — пустая (в CSV пустая колонка `role` → `&""`), поэтому и
## спрашивается пустой: иначе строка «есть» в файле и «нет» в базе разошлись бы
## молча, ровно там, где проверка обязана назвать дыру.
##
## Пустое ведро и неполное называются РАЗНЫМИ словами намеренно: «нет ни одного» и
## «только два из трёх» — разные поломки, и по отчёту должно быть видно, какая
## именно. Без порога проверка ловила бы только полное исчезновение детали:
## удаление одной строки носителя из трёх оставляло бы её зелёной (измерено).
func _check_reactions() -> Array:
	var out: Array = []
	# Деталь пула: ключ ведра и порог. Поля читаются ПО ИМЕНИ, а не по индексу:
	# индексы — приглашение к тихой поломке при правке порядка или состава ключей.
	var parts: Array = []
	for v in [HitReaction.VERDICT_RESIST, HitReaction.VERDICT_WEAK, HitReaction.VERDICT_NEUTRAL]:
		parts.append({
			"monster": &"", "scenario": &"", "slot": HitReaction.SLOT_VERB, "role": StringName(v),
			"absent": "нет ни одного глагола для вердикта «%s»" % v,
			"short": "у вердикта «%s» мало глаголов" % v,
			"need": REACTION_MIN_VERB,
		})
		for step in ["", "_again", "_hard"]:
			var role := StringName("%s%s" % [v, step])
			parts.append({
				"monster": &"", "scenario": &"", "slot": HitReaction.SLOT_INTRO, "role": role,
				"absent": "нет вводных для группы «%s»" % role,
				"short": "у группы вводных «%s» мало строк" % role,
				"need": REACTION_MIN_INTRO,
			})
	parts.append({
		"monster": &"", "scenario": &"", "slot": HitReaction.SLOT_INTRO, "role": &"swap",
		"absent": "нет вводных для примерки («swap»)",
		"short": "у примерки («swap») мало вводных",
		"need": REACTION_MIN_INTRO,
	})
	for id in Database.monsters.keys():
		parts.append({
			"monster": StringName(id), "scenario": &"", "slot": HitReaction.SLOT_CARRIER, "role": &"",
			"absent": "у вида «%s» нет носителя" % id,
			"short": "у вида «%s» мало носителей" % id,
			"need": REACTION_MIN_CARRIERS,
		})
	for id in Database.weapons.keys():
		parts.append({
			"monster": &"", "scenario": &"", "slot": HitReaction.SLOT_WEAPON, "role": StringName(id),
			"absent": "у оружия «%s» нет отпечатка удара" % id,
			"short": "у оружия «%s» мало отпечатков удара" % id,
			"need": REACTION_MIN_WEAPONS,
		})
	for rune in SkillsData.RUNE_SKILLS.values():
		parts.append({
			"monster": &"", "scenario": &"", "slot": HitReaction.SLOT_ELEMENT, "role": StringName(rune),
			"absent": "у руны «%s» нет стихийной окраски" % rune,
			"short": "у руны «%s» мало стихийных окрасок" % rune,
			"need": REACTION_MIN_ELEMENTS,
		})
	for part in parts:
		var pool: Array = Database.phrases_for(
			part["monster"], part["scenario"], part["slot"], part["role"])
		var need := int(part["need"])
		if pool.is_empty():
			out.append("реакция: %s" % part["absent"])
		elif pool.size() < need:
			out.append("реакция: %s — только %d, нужно минимум %d" % [
				part["short"], pool.size(), need])
	# Форма детали: после КАЖДОЙ детали шаблон ставит свой разделитель, поэтому
	# деталь, кончающаяся служебным словом, обрывает фразу — «наковальня равнодушен
	# к — опёрённый жгут» (измерено на `rx.verb.resist.04`). Правило одно на все
	# слоты, а не только на глагол: разделитель есть у каждого слота (тире после
	# глагола, точка после стихии, пробел после носителя, запятая стихии у
	# отпечатка, точка после вводной). Список слов — ОДИН и лежит рядом с шаблоном
	# (`HitReaction.DETAIL_STOP_WORDS`); здесь он только спрашивается, потому что
	# вторая копия разошлась бы с первой молча (AGENTS.md §4).
	#
	# Обход идёт по САМОМУ пулу, а не по списку ведёр покрытия выше: тогда деталь
	# ловится в любом ведре, включая то, которого нет ни в одной из проверок
	# покрытия, — форма не зависит от того, знает ли валидатор её роль.
	for key in Database.phrases.keys():
		for phrase_v in (Database.phrases[key] as Array):
			var phrase: Phrase = phrase_v
			if not HitReaction.DETAIL_SLOTS.has(phrase.slot):
				continue
			var last := _last_word(phrase.text)
			if not HitReaction.DETAIL_STOP_WORDS.has(last):
				continue
			out.append(
				"реакция: деталь «%s» кончается служебным словом «%s» — шаблон оборвётся перед %s: «%s»" % [
					phrase.id, last, _separator_after(phrase.slot), phrase.text])
	return out


## Последнее слово детали, приведённое к нижнему регистру, без хвостовых знаков.
## Знаки ставит сборщик, но знак в конце детали не имеет права ПРЯТАТЬ служебное
## слово от сторожа: иначе «…в.» прошло бы зелёным, а обрыв остался бы в игре.
func _last_word(text: String) -> String:
	var words := text.split(" ", false)
	if words.is_empty():
		return ""
	return words[words.size() - 1].rstrip(".,;:!?…—–-\"«»()'").to_lower()


## Что шаблон приставляет после детали этого слота — словом, для сообщения. Знак
## здесь не повторяется: он живёт константой шаблона (`HitReaction.P_*`), и вторая
## копия знака разошлась бы с первой молча (AGENTS.md §4). Имя разделителя, а не
## знак, выбрано ещё и потому, что у отпечатка удара разделителя ДВА: запятая,
## когда руна добавила тип, и точка, когда её нет (§5 спеки). Формулировки
## продолжены тем, что идёт СЛЕДОМ («и носителем», «и глаголом»): иначе сообщение
## читалось бы как «оборвётся перед пробелом перед глаголом».
func _separator_after(slot: StringName) -> String:
	match slot:
		HitReaction.SLOT_INTRO:
			return "точкой и носителем"
		HitReaction.SLOT_CARRIER:
			return "пробелом и глаголом"
		HitReaction.SLOT_VERB:
			return "тире"
		HitReaction.SLOT_WEAPON:
			return "запятой стихии (или точкой, если руны нет)"
		HitReaction.SLOT_ELEMENT:
			return "точкой"
	return "разделителем"


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
	probe.enchant(&"ice")
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
## Тип «physical» в записи резиста здесь не опечатка: он проверяет ЛЕГАСИ-КЛЮЧ,
## покрывающий все три физических подтипа. Общая физика обязана по-прежнему
## защищать зверя, иначе старые таблицы молча перестали бы работать.
func _probe_monster() -> MonsterData:
	var mon := MonsterData.new()
	mon.id = &"rune_probe"
	mon.title = "Проба руны"
	mon.max_hp = 20
	mon.armor = 0
	mon.weakness_rules = [{"types": ["ice"], "ranges": []}]
	mon.resist_rules = [{"types": ["physical"], "ranges": []}]
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
	w.enchant(rune_type)
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

	# Инвариант 4 (D23): запись обязана ограничивать хотя бы одну координату.
	# Пустая запись сработала бы на ЛЮБОЙ удар — это скрытый «резист ко всему»,
	# и увидеть его в таблице было бы нечем.
	#
	# Проверяются САМИ поля вида, а не производное от них представление: сырые
	# `weakness_rules` / `resist_rules` И ЕСТЬ записи, синтеза между ними нет
	# (переходник `effective_*` снят в Task 4), и это единственный источник правды
	# о таблице вида. Проверка действующих записей поэтому не была бы слабее — но
	# она читала бы то же самое через лишний слой, а пустая запись обязана быть
	# названа там, где лежит.
	#
	# Форма записи проверяется ДО разбора её полей: скаляр в «types» или «ranges»
	# роняет расчёт SCRIPT ERROR'ом, а запись-не-словарь — тем более. Валидатор
	# назначен проверяющим структуры, он обязан назвать это сам, а не упасть.
	#
	# Поле вида, которое не является массивом, — СТРАХОВКА, а не рабочая проверка:
	# `weakness_rules`/`resist_rules` объявлены как `Array`, и тип держит значение
	# на всех входах (проверено: `set("weakness_rules", "oops")` оставляет массив,
	# `.tres` с `weakness_rules = "oops"` тоже). Назвать такое состояние движок
	# сегодня не даёт создать; проверка оставлена на случай, если поле перестанет
	# быть типизированным.
	for field_v in [[&"weakness_rules", mon.weakness_rules], [&"resist_rules", mon.resist_rules]]:
		var field_name := String(field_v[0])
		var field_rules: Variant = field_v[1]
		if not (field_rules is Array):
			out.append("%s: %s не является массивом: %s" % [label, field_name, str(field_rules)])
			continue
		for rule_v in (field_rules as Array):
			if not (rule_v is Dictionary):
				out.append("%s: запись уязвимости/резиста не является словарём: %s" % [
					label, str(rule_v)])
				continue
			var rule := rule_v as Dictionary
			if not _fields_are_arrays(rule, label, out):
				continue
			if MonsterData.rule_strings(rule, "types").size() == 0 \
					and MonsterData.rule_strings(rule, "ranges").size() == 0:
				out.append("%s: запись без types и ranges сработала бы на любой удар" % label)

	# Фазы задают ТЕ ЖЕ записи уязвимостей (спека §2.2), значит и запрет на них
	# тот же: пустая запись фазы — скрытое «+1 на любой удар в этой фазе».
	# Ключ фазы читает модель, поэтому не-массив называется здесь, а не молча
	# пропускается: пропустить — значит не проверить ровно то, что сломано.
	for ph in mon.phases:
		var phase_title := str(ph.get("title", ""))
		# Читается через `has`, а не `get(k, [])`: нам важно РАЗЛИЧАТЬ «ключа нет»
		# (законно: фаза уязвимостей не задаёт) и «ключ есть, но значение не
		# массив» (ошибка контента) — второе обязан назвать валидатор.
		var raw_rules: Variant = ph["weak_rules"] if ph.has("weak_rules") else []
		if not (raw_rules is Array):
			out.append("%s: weak_rules фазы «%s» не является массивом: %s" % [
				label, phase_title, str(raw_rules)])
			continue
		for rule_v in (raw_rules as Array):
			if not (rule_v is Dictionary):
				out.append("%s: запись фазы «%s» не является словарём: %s" % [
					label, phase_title, str(rule_v)])
				continue
			var rule := rule_v as Dictionary
			if not _fields_are_arrays(rule, "%s, фаза «%s»" % [label, phase_title], out):
				continue
			if MonsterData.rule_strings(rule, "types").size() == 0 \
					and MonsterData.rule_strings(rule, "ranges").size() == 0:
				out.append("%s: запись фазы «%s» без types и ranges сработала бы на любой удар" % [
					label, phase_title])

	return out


## Поля «types» и «ranges» обязаны быть массивами строк. Возвращает true, если
## форма цела; иначе дописывает в `out` по сообщению на каждую поломку.
##
## Читается через `has`: отсутствие ключа — это пустое множество («любое»), а вот
## ЯВНЫЙ не-массив (строка, число, null) — ошибка авторинга, и её надо назвать.
##
## Проверяются и ЭЛЕМЕНТЫ: `types: [7]` — не список типов, а мусор. Модель такой
## элемент отбрасывает (MonsterData.rule_strings), то есть запись молча
## превратилась бы в «любой тип», и без этой проверки игрок получал бы +1 на всё
## без единого сообщения. `where` — куда относится запись (вид, поле, фаза).
func _fields_are_arrays(rule: Dictionary, where: String, out: Array) -> bool:
	var ok := true
	for field in ["types", "ranges"]:
		var raw: Variant = rule[field] if rule.has(field) else []
		if not (raw is Array):
			out.append("%s: у записи поле «%s» не является массивом: %s" % [
				where, field, str(raw)])
			ok = false
			continue
		for v in (raw as Array):
			if not (v is String or v is StringName):
				out.append("%s: у записи поле «%s» содержит не строку: %s" % [
					where, field, str(v)])
				ok = false
	return ok


## Достаёт ли до этой записи хоть какое-то оружие: существует ли пара «тип удара ×
## дистанция», при которой запись срабатывает. Возвращает название оружия, а
## пустая строка значит «недостижима».
##
## Проверка идёт по ПАРЕ, а не по координатам порознь: у Громунa дробящее работает
## только в упор, поэтому «уязвим к дробящему на дальней» — недостижимая
## уязвимость, хотя и молот, и лук в игре есть.
##
## Тип даёт базовое оружие ИЛИ руна, наложенная на него: магию в игре даёт только
## руна, а наложить её можно на любое оружие (дистанцию руна не меняет).
func _reachable_by_weapon(rule: Dictionary) -> String:
	for id in Database.weapons.keys():
		var w: WeaponData = Database.weapons[id]
		for t in _hittable_types(w):
			if MonsterData.rule_applies(rule, t, w.range_id):
				return w.title
	return ""


## Даёт ли эта запись уязвимости хоть один ПЛЮС: существует ли пара «тип ×
## дистанция», на которой запись срабатывает и итог (уязвимости минус резисты)
## положителен. Пустое множество записи — «любое», поэтому перебираются пары
## арсенала: абстрактная комбинация типа и дистанции игре недоступна.
##
## `phase` — пустой словарь для базовой уязвимости и словарь фазы для weak_rules
## фазы: фаза ЗАМЕНЯЕТ базовые уязвимости, поэтому и считать надо её записями.
func _rule_pays_off(mon: MonsterData, rule: Dictionary, phase: Dictionary) -> bool:
	for id in Database.weapons.keys():
		var w: WeaponData = Database.weapons[id]
		for h in _hittable_types(w):
			var type_id := StringName(h)
			if not MonsterData.rule_applies(rule, type_id, w.range_id):
				continue
			if mon.weakness_modifier(type_id, w.range_id, phase) \
					- mon.resist_modifier(type_id, w.range_id) > 0:
				return true
	return false


## Типы, которыми можно ударить ЭТИМ оружием: его собственный (вместе с уже
## наложенной руной) плюс каждая руна, которую игрок способен наложить.
func _hittable_types(w: WeaponData) -> Array:
	var out: Array = []
	for t in CityData.damage_types(w):
		if not out.has(t):
			out.append(t)
	for skill_id in SkillsData.RUNE_SKILLS.keys():
		var rune_type := StringName(SkillsData.RUNE_SKILLS[skill_id])
		if not out.has(rune_type):
			out.append(rune_type)
	return out


## Типы, которые игра способна доставить на эту дистанцию: всё, чем бьёт оружие
## этой дистанции, вместе с любой наложенной руной.
func _deliverable_types(range_id: StringName) -> Array:
	var out: Array = []
	for id in Database.weapons.keys():
		var w: WeaponData = Database.weapons[id]
		if w.range_id != range_id:
			continue
		for t in _hittable_types(w):
			if not out.has(t):
				out.append(t)
	return out
