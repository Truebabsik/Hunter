extends Resource
class_name MonsterData
## Вид зверя. Всё, что нужно бою, живёт здесь — включая арт-поля, даже если
## картинок пока нет: позже они подключаются без правок в ядре.

# --- Ключи, которыми пользуется ядро. Держим их строками, а не enum, чтобы
# .tres-файлы читались и правились руками.
#
# Физический урон разделён на ТРИ подтипа: дробящий, режущий, колющий. Это делает
# выбор оружия выбором подтипа, а не только дальности: панцирного зверя не
# разрубить, но можно разбить.
const TYPE_CRUSH := &"crush"
const TYPE_SLASH := &"slash"
const TYPE_PIERCE := &"pierce"
## Общий физический тип. Оставлен как ЯРЛЫК КАТЕГОРИИ: в записи вида он значит
## «устойчив ко всем трём подтипам сразу» (см. MonsterData.rule_applies).
## Новый контент должен писать конкретный подтип — иначе выбор оружия не работает.
const TYPE_PHYSICAL := &"physical"
const TYPE_FIRE := &"fire"
const TYPE_ICE := &"ice"
const TYPE_POISON := &"poison"
## Все физические подтипы. Порядок — для стабильного вывода и перебора.
const PHYSICAL_TYPES: Array[StringName] = [TYPE_CRUSH, TYPE_SLASH, TYPE_PIERCE]
const RANGE_MELEE := &"melee"
const RANGE_RANGED := &"ranged"
const RANK_STARTER := &"starter"
const RANK_ADVANCED := &"advanced"
const RANK_ELITE := &"elite"
const RANK_LEGENDARY := &"legendary"


## Физический ли это подтип (дробящий / режущий / колющий).
static func is_physical_subtype(type_id: StringName) -> bool:
	return PHYSICAL_TYPES.has(type_id)

@export_group("Личность")
@export var id: StringName = &""
@export var title: String = ""
@export var epithet: String = ""
@export var rank: StringName = RANK_STARTER

## Что гильдия знает о звере, словами охотника (2–3 строки). Это НЕ подсказка по
## механике: числа и сигналы живут ниже в досье отдельными строками. Здесь только
## то, что знает о виде любой, кто выжил после встречи, — поэтому текст не
## меняется от уровня досье и не должен выдавать слабость или повадку.
@export_multiline var lore: String = ""

@export_group("Бой")
@export_range(1, 200, 1) var max_hp: int = 12

## Панцирь — плоская защита ЗВЕРЯ. Вычитается из урона игрока (GDD 12.5).
## Не путать с бронёй игрока: та живёт в ArmorData.
@export_range(0, 10, 1) var armor: int = 0

@export_range(0, 20, 1) var base_damage: int = 3

## Инициатива вида (GDD 12.9).
@export_range(0, 20, 1) var initiative: int = 4

@export_group("Уязвимости")
## Записи уязвимостей: [{"types": ["ice"], "ranges": ["ranged"]}].
## Пустое множество = «любой». Запись срабатывает, когда ТИП удара входит
## в types И дистанция входит в ranges (D23, GDD 12.3.1).
## Каждая запись даёт ровно +1.
@export var weakness_rules: Array = []
## Записи резистов — та же форма; каждая даёт −1.
@export var resist_rules: Array = []

@export_group("Поведение")
@export var scenarios: Array[ScenarioData] = []
## Ложные следы вида. Наследуются всеми сценариями, если у сценария нет своих.
@export var false_leads: Array[SignalData] = []

@export_group("Приёмы")
@export var combos: Array[ComboData] = []
## Порог повтора, после которого зверь отвечает контр-приёмом (GDD 6.3).
@export_range(2, 10, 1) var counter_threshold: int = 3
@export var counter_title: String = ""
@export var counter_text: String = ""

@export_group("Особые механики")
## Туман обзора (GDD 11.5, Тлеун): пока игрок не прочитает сценарий-ключ,
## карточки-гипотезы скрыты, а проза остаётся.
@export var fog_enabled: bool = false
## Сценарий, верное чтение которого рассеивает туман.
@export var fog_key_scenario: StringName = &""
@export var fog_title: String = ""
@export var fog_text: String = ""

## Тикающий урон, пока не прочитан ключевой сценарий (GDD 4.7, Пепел-Мать).
@export_range(0, 5, 1) var ticking_damage: int = 0
@export var ticking_key_scenario: StringName = &""
@export var ticking_text: String = ""

## Фазы босса по долям HP (GDD 4.8). Список словарей:
##   {"id": "rage", "title": "Бешенство", "hp_below": 0.7, "noise": 2.0,
##    "weak_rules": [{"types": [], "ranges": ["melee"]}], "note": "..."}
## Фаза переопределяет ТОЛЬКО уязвимости: ключа резистов у неё нет вовсе
## (D21.E — резист действует все три фазы одинаково).
@export var phases: Array[Dictionary] = []

## Адаптация: после N раундов вес сценария умножается (GDD 6.4).
## Список словарей: {"scenario": "rebuild", "after_round": 5, "multiplier": 1.1}
@export var adaptations: Array[Dictionary] = []

@export_group("Награда")
@export var trophy_names: PackedStringArray = PackedStringArray()
@export var trophy_prices: PackedInt32Array = PackedInt32Array()

@export_group("Арт")
## Карточка для досье и экрана боя. Пусто = текстовый плейсхолдер.
@export var portrait: Texture2D
## Поза по сценарию: {"pounce": Texture2D}. Контракт «сценарий → картинка»
## ложится на уже существующую модель поведения (GDD 3.2: поза и снаряжение).
@export var by_scenario: Dictionary = {}
## Силуэт для «следа» и списка заказов: тёмный контур без деталей.
@export var silhouette: Texture2D
## Цвет вида строкой («#7a6849»): в .tres он читаем, а конвертация — здесь.
## Числовой конструктор Color(...) в ресурсе требует четырёх float и ломает парсер.
@export var accent_color: String = "#8d8578"
## Размер вида в кадре: «массивный» Хруз и «низкий» Шипун должны отличаться.
@export_range(0.3, 2.0, 0.05) var art_scale: float = 1.0
## Смещение силуэта в кадре: зверь у воды стоит ниже, летающий — выше.
@export var art_offset: Vector2 = Vector2.ZERO


## Цвет акцента как Color. Пустая или битая строка даёт нейтральный серый.
func accent() -> Color:
	if accent_color.strip_edges().is_empty():
		return Color("#8d8578")
	return Color.from_string(accent_color, Color("#8d8578"))


func find_scenario(id: StringName) -> ScenarioData:
	for s in scenarios:
		if s.id == id:
			return s
	return null


func total_weight() -> int:
	var sum := 0
	for s in scenarios:
		sum += s.weight
	return sum


## Уязвим ли вид к этому типу на этой дистанции. Нужно валидатору.
## Пустая дистанция значит «любая»: так зовут читатели, которым дистанция
## неизвестна (досье спрашивает только тип).
func is_weak_to_type(type_id: StringName, range_id: StringName = &"") -> bool:
	if range_id == &"":
		return weakness_modifier(type_id, RANGE_MELEE) > 0 \
			or weakness_modifier(type_id, RANGE_RANGED) > 0
	return weakness_modifier(type_id, range_id) > 0


## Первый тип уязвимости — подсказка для бота, когда точной пары нет.
## Пустая строка, если уязвимостей нет.
##
## Поля записи разбирает модель (rule_strings), а не сама эта функция: скаляр
## в поле приходит из .tres руками, и PackedStringArray() на нём уронил бы
## выбор инструмента SCRIPT ERROR'ом. Назвать форму поля обязан валидатор.
func weakness_type_hint() -> StringName:
	for rule_v in weakness_rules:
		if not (rule_v is Dictionary):
			continue
		var types := rule_strings(rule_v as Dictionary, "types")
		if types.size() > 0:
			return StringName(types[0])
	return &""


## --- Записи уязвимостей и резистов (D23, GDD 12.3.1) -----------------------

## Срабатывает ли запись по этой координате удара. Пустое множество = «любой».
## Список строк из поля записи («types» или «ranges»). Не-массив читается как
## ПУСТОЙ список: поле приходит из .tres руками, и скаляр в нём ронял расчёт
## SCRIPT ERROR'ом. Пустой список — это «любое», то есть самое широкое чтение;
## назвать форму поля обязан валидатор, а бой и показ падать не имеют права.
static func rule_strings(rule: Dictionary, key: String) -> PackedStringArray:
	var raw: Variant = rule.get(key, [])
	var out := PackedStringArray()
	if not (raw is Array):
		return out
	for v in (raw as Array):
		if v is String or v is StringName:
			out.append(String(v))
	return out


static func rule_applies(rule: Dictionary, type_id: StringName, range_id: StringName) -> bool:
	var types := rule_strings(rule, "types")
	if types.size() > 0:
		var hit := false
		for t in types:
			if _type_matches(StringName(t), type_id):
				hit = true
				break
		if not hit:
			return false
	var ranges := rule_strings(rule, "ranges")
	if ranges.size() > 0:
		if not ranges.has(String(range_id)):
			return false
	return true


## Совпадает ли записанный тип с типом удара. Легаси-ключ "physical"
## покрывает все три физических подтипа — на нём держатся фазы и часть контента.
## Конкретный подтип общую запись НЕ отменяет: в модели каждая запись
## срабатывает сама по себе, а не «сильнейшая из двух».
static func _type_matches(recorded: StringName, hit: StringName) -> bool:
	if recorded == hit:
		return true
	return recorded == TYPE_PHYSICAL and is_physical_subtype(hit)


## Типы записи, переведённые в читаемые названия («лёд»), для текстов.
static func rule_types_ru(rule: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	for t in rule_strings(rule, "types"):
		out.append(CityData.type_ru(StringName(t)))
	return out


## Записи уязвимостей фазы. Ключ читает МОДЕЛЬ: во-первых, структуру записи
## разбирает только она; во-вторых, ключ приходит из .tres и может оказаться чем
## угодно, а падать на чужой ошибке контента экран не имеет права.
##
## Не-массив читается как пустой список — назвать это обязан валидатор.
##
## Читается через `has`, а не `get(k, [])`: нам важно РАЗЛИЧАТЬ «ключа нет»
## (законно: фаза уязвимостей не задаёт) и «ключ есть, но значение не массив»
## (ошибка контента). `has` называет это прямо, без догадок о поведении `get`.
static func phase_weak_rules(phase: Dictionary) -> Array:
	var raw: Variant = phase["weak_rules"] if phase.has("weak_rules") else []
	if not (raw is Array):
		return []
	return raw


## Сумма уязвимостей по координате удара. Фаза ЗАМЕНЯЕТ базовые уязвимости,
## если у неё задан weak_rules (GDD 4.8: «в истощении он открыт»).
##
## Записи, которые не являются словарями, пропускаются: это мусор в контенте, и
## его обязан назвать валидатор — а бой падать из-за него не имеет права.
func weakness_modifier(type_id: StringName, range_id: StringName, phase: Dictionary = {}) -> int:
	var rules: Array = weakness_rules
	if phase.has("weak_rules"):
		rules = phase_weak_rules(phase)
	var sum := 0
	for r in rules:
		if not (r is Dictionary):
			continue
		if rule_applies(r as Dictionary, type_id, range_id):
			sum += 1
	return sum


## Сумма резистов по координате удара. Резисты фаза НЕ меняет: D21.E говорит,
## что резист действует все три фазы одинаково, а таблица фаз §4.8 колонки
## резистов не имеет вовсе.
func resist_modifier(type_id: StringName, range_id: StringName) -> int:
	var sum := 0
	for r in resist_rules:
		if not (r is Dictionary):
			continue
		if rule_applies(r as Dictionary, type_id, range_id):
			sum += 1
	return sum


## Модификатор по всем типам одного удара (базовый тип оружия и элемент руны)
## плюс причины для разбора. Один источник правила: и число, и текст.
##
## КЛЮЧЕВОЕ: каждая запись срабатывает НЕ БОЛЕЕ ОДНАЖДЫ на удар. Если запись
## покрывает и физический тип, и элемент руны (`types:[physical]` плюс удар
## дробящим с руной огня), наивный перебор по типам выдал бы две строки и +2 —
## ровно тот дефект, ради которого вводится модель. Поэтому по типам ищем
## совпадение, а причину добавляем одну.
func modifier_reasons(types_hit: Array, range_id: StringName, phase: Dictionary = {}) -> Array[String]:
	var out: Array[String] = []
	var weak_rules_used: Array = weakness_rules
	if phase.has("weak_rules"):
		weak_rules_used = phase_weak_rules(phase)
	for rule_v in weak_rules_used:
		if not (rule_v is Dictionary):
			continue
		var rule := rule_v as Dictionary
		var rtype := _matching_type(rule, types_hit, range_id)
		if rtype != &"":
			out.append("слабость: %s +1" % _rule_label(rule, rtype, types_hit, range_id))
	for rule_v in resist_rules:
		if not (rule_v is Dictionary):
			continue
		var rule := rule_v as Dictionary
		var rtype := _matching_type(rule, types_hit, range_id)
		if rtype != &"":
			out.append("резист: %s −1" % _rule_label(rule, rtype, types_hit, range_id))
	return out


## Первый тип удара (в порядке перебора), на котором запись срабатывает.
## Пустая строка, если запись не срабатывает вовсе. Нужна, чтобы запись
## срабатывала один раз, а не по разу на каждый совпавший тип.
func _matching_type(rule: Dictionary, types_hit: Array, range_id: StringName) -> StringName:
	for type_v in types_hit:
		var type_id := StringName(type_v)
		if rule_applies(rule, type_id, range_id):
			return type_id
	return &""


## Короткая подпись координаты для разбора: у руны помечаем «(руна)».
## Руна — всё, что не первый тип удара: первый всегда базовый тип оружия.
func _hit_label(type_id: StringName, types_hit: Array) -> String:
	var is_base := types_hit.size() > 0 and StringName(types_hit[0]) == type_id
	var ru := CityData.type_ru(type_id)
	return ru if is_base else "%s (руна)" % ru


## Короткая подпись записи для разбора. Называет координату, которая запись
## ОГРАНИЧИВАЕТ: у записи без types это дистанция, а не тип удара — иначе игрок
## видит «резист: колющий −1» там, где сработала дальность (GDD 12.1).
##
## Две записи остаются ДВУМЯ строками: ядро берёт знак слагаемого из текста
## причины (см. DamageCalc.player_damage), поэтому «схлопнуть» их в одну
## строку «дальний −2» нельзя — число разошлось бы с разбором.
func _rule_label(rule: Dictionary, rtype: StringName, types_hit: Array, range_id: StringName) -> String:
	if rule_strings(rule, "types").size() == 0:
		return CityData.range_ru(range_id) if range_id != &"" else _hit_label(rtype, types_hit)
	return _hit_label(rtype, types_hit)


## Уязвимости строками для досье и совета: одна строка на запись.
func weakness_lines() -> PackedStringArray:
	return rule_lines(weakness_rules)


## Резисты строками для досье и совета: одна строка на запись.
func resist_lines() -> PackedStringArray:
	return rule_lines(resist_rules)


## Строки записей для показа: одна строка на запись, внутри записи — «+».
##
## Разделитель ВНУТРИ записи — «+», а не запятая, и это не украшение. Запись
## «лёд + дальний» значит «нужен И лёд, И дальний»; запятая читалась бы как два
## независимых совета — ровно то, ради чего вводилась модель (D23).
##
## Статический, потому что разметку фаз зовут снаружи модели, а второй разбор
## структуры записи в проекте запрещён: структуру читает только MonsterData.
static func rule_lines(rules: Array) -> PackedStringArray:
	var out := PackedStringArray()
	for rule_v in rules:
		# Запись, которая не словарь, — не запись. Молча пропускаем: назвать её
		# обязан валидатор (проверка структуры), а показ падать не имеет права.
		if not (rule_v is Dictionary):
			continue
		var rule := rule_v as Dictionary
		var parts := rule_types_ru(rule)
		for r in rule_strings(rule, "ranges"):
			parts.append(CityData.range_ru(StringName(r)))
		out.append(" + ".join(parts))
	return out


## --- Фазы (GDD 4.8). Возвращает фазу по текущей доле HP или пустой словарь.
func phase_for_hp(hp: int) -> Dictionary:
	if phases.is_empty() or max_hp <= 0:
		return {}
	var fraction := float(hp) / float(max_hp)
	# Фазы заданы порогом «ниже»: идём от самой глубокой к начальной.
	var best: Dictionary = {}
	var best_threshold := 2.0
	for p in phases:
		var threshold := float(p.get("hp_below", 1.0))
		if fraction <= threshold and threshold < best_threshold:
			best = p
			best_threshold = threshold
	return best


## Множитель веса сценария от адаптации к указанному раунду (GDD 6.4).
func adaptation_multiplier(scenario_id: StringName, round_index: int) -> float:
	var mult := 1.0
	for a in adaptations:
		if StringName(a.get("scenario", "")) != scenario_id:
			continue
		if round_index >= int(a.get("after_round", 999)):
			mult *= float(a.get("multiplier", 1.0))
	return mult
