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
## Общий физический тип. Оставлен как ЯРЛЫК КАТЕГОРИИ: в таблицах вида он значит
## «устойчив ко всем трём подтипам сразу» (см. MonsterData.type_resist_for).
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
## Типы урона, которые дают +1 к урону игрока.
@export var weakness_types: PackedStringArray = PackedStringArray()
## Дальности, которые дают +1.
@export var weakness_ranges: PackedStringArray = PackedStringArray()
## Штраф по дальности: {"ranged": 2} — «резист к дальнему 2» (GDD 12.5).
@export var range_resist: Dictionary = {}
## Штраф по типу урона: {"fire": 1}.
@export var type_resist: Dictionary = {}

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
##    "weak_types": ["crush"], "weak_ranges": ["melee"], "note": "..."}
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


## Штраф за дальность инструмента. 0 — если вид к этой дальности не устойчив.
func range_resist_for(range_id: StringName) -> int:
	return int(range_resist.get(String(range_id), 0))


## Штраф за тип урона. 0 — если вид к этому типу не устойчив.
##
## Запись «physical» значит «устойчив ко всем трём физическим подтипам»: так
## писались таблицы до разделения физурона, и это же удобно для зверя, которому
## безразлично, чем его бьют — лишь бы не магией. Конкретный подтип сильнее
## общего: если у вида есть и `slash`, и `physical`, для режущего берётся `slash`.
func type_resist_for(type_id: StringName) -> int:
	var key := String(type_id)
	if type_resist.has(key):
		return int(type_resist[key])
	if is_physical_subtype(type_id) and type_resist.has(String(TYPE_PHYSICAL)):
		return int(type_resist[String(TYPE_PHYSICAL)])
	return 0


## Уязвим ли вид к этому типу. Общая запись «physical» покрывает все три
## физических подтипа, как и в type_resist_for.
func is_weak_to_type(type_id: StringName) -> bool:
	if weakness_types.has(String(type_id)):
		return true
	return is_physical_subtype(type_id) and weakness_types.has(String(TYPE_PHYSICAL))


func is_weak_to_range(range_id: StringName) -> bool:
	return weakness_ranges.has(String(range_id))


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
