extends Node
## Состояние игрока между боями: досье, слава, ранг, монеты, навыки, снаряжение.
##
## Отсюда берётся вся прогрессия и сюда же она сохраняется. Бой получает копию
## нужных полей (HunterState + досье), а не ссылку на этот объект: ядро не должно
## уметь менять мета-состояние по побочному эффекту.

## --- Ранги (GDD 8.1). Порог славы для каждого ранга.
const RANKS := [
	{"id": 0, "title": "Ученик", "glory": 0},
	{"id": 1, "title": "Подмастерье", "glory": 5},
	{"id": 2, "title": "Охотник", "glory": 15},
	{"id": 3, "title": "Ветеран", "glory": 35},
	{"id": 4, "title": "Мастер", "glory": 60},
	{"id": 5, "title": "Легенда", "glory": 100},
]

## Знаки ранга (GDD 8.7) — пассивные бонусы.
const RANK_SIGNS := {
	1: {"title": "Медный жетон", "bonus": "+1 к шансу побега"},
	2: {"title": "Серебряный жетон", "bonus": "+1 к урону по элите"},
	3: {"title": "Золотой жетон", "bonus": "+1 к урону по всем"},
	4: {"title": "Платиновый жетон", "bonus": "+1 к славе за победу"},
	5: {"title": "Венок легенды", "bonus": "+1 ко всем комбо"},
}

var glory: int = 0
var coins: int = 0
var rank: int = 0

## Досье: monster_id -> {level, signals, decoys, scenarios, weaknesses, combos}
var dossier: Dictionary = {}

## Ноша охотника: monster_id -> [количество по каждому предмету вида].
## Добыча НЕ продаётся автоматически: монеты приходят только от Лиса на рынке.
## Поэтому ноша — это риск: при побеге часть её бросаешь, при смерти теряешь всю.
## Формат и все операции — в MarketData.
var bag: Dictionary = {}

## Купленные навыки: skill_id -> true. Навыки не сгорают при смерти (GDD 7.1).
var skills: Dictionary = {}

## Купленное снаряжение.
##
## Полей owned_modifiers / equipped_modifier здесь больше нет: они остались от
## модификаторов типов урона (огнём, льдом, ядом), которых в игре нет — модификатор
## заменён руной, а руна живёт на оружии. Поля не читал и не писал никто, кроме
## reset(): grep по всему проекту давал четыре строки — два объявления и два
## обнуления. Мёртвое поле хуже отсутствующего: оно выглядит как готовая
## механика, и следующая правка может начать в него писать.
var owned_weapons: Array[StringName] = []
var owned_armors: Array[StringName] = []

var equipped_weapon: StringName = &"bow"
var equipped_armor: StringName = &"light"

## Текущий заказ.
var current_monster_id: StringName = &""
var current_order_rank: int = 0

## Счётчики для славы (GDD 8.2).
var win_streak: int = 0
var counters := {
	"kills": 0,            ## всего побед
	"perfect_reads": 0,    ## идеальных чтений
	"deaths": 0,
	"bought_any_skill": 0,
	"kills_no_armor": 0,   ## побед без брони
	"kills_one_weapon": 0, ## побед одним оружием
}

## Достижения: id -> true. Порядок и условия — в Achievements.
var achievements: Dictionary = {}

## Журнал славы: каждое событие отдельной записью. Нужен для экрана истории
## с фильтрами (победы / смерти / повышения / откаты) — GDD 11.8.
var fame_log: Array[Dictionary] = []

## День забега: растёт с каждой охотой, нужен для датировки Хроники.
var day: int = 0

## Самый низкий ранг после падения: по нему считается «восстановление
## с превосхождением» (GDD 11.8). -1 значит «падений ещё не было».
var lowest_rank_after_fall: int = -1

## Срок богини в днях (GDD 1.3.1). Пока отсчёт идёт — она воскрешает, и смерть
## стоит только материи. Отсчёт вышел — воскрешения больше нет, и следующая
## смерть окончательная. N — ручка сложности: измерено, что Легенда достигается
## за 30–45 дней, поэтому 45 это верхняя граница разброса (умелый проходит всегда).
const SURVIVAL_DAYS := 45

## Одноразовый флаг: игрок уже узнал, что отсчёт кончился. Нужен, чтобы событие
## «ты стал смертен» показали ровно один раз и его нельзя было пропустить.
var grace_ended_seen: bool = false


## Сколько дней осталось до конца срока. Может быть 0 и меньше — срок вышел.
func days_left() -> int:
	return SURVIVAL_DAYS - day


## Идёт ли ещё благодать: пока идёт, смерть обратима.
func grace_active() -> bool:
	return day < SURVIVAL_DAYS


func _ready() -> void:
	reset()


func reset() -> void:
	glory = 0
	coins = 0
	rank = 0
	dossier.clear()
	bag.clear()
	skills.clear()
	owned_weapons = [&"bow", &"mace"]
	owned_armors = [&"light"]
	equipped_weapon = &"bow"
	equipped_armor = &"light"
	current_monster_id = &""
	current_order_rank = 0
	win_streak = 0
	achievements.clear()
	fame_log.clear()
	day = 0
	lowest_rank_after_fall = -1
	grace_ended_seen = false
	counters = {
		"kills": 0, "perfect_reads": 0, "deaths": 0, "bought_any_skill": 0,
		"kills_no_armor": 0, "kills_one_weapon": 0,
	}


func next_day() -> void:
	day += 1


## Записать событие в Хронику. kind: победа / смерть / повышение / откат.
func log_fame(kind: String, title: String, subtitle: String, delta: int, note: String = "") -> void:
	fame_log.append({
		"day": day,
		"kind": kind,
		"title": title,
		"subtitle": subtitle,
		"delta": delta,
		"glory_after": glory,
		"note": note,
	})


## Последние события, свежие сверху — для главного экрана доски славы.
func recent_fame(count: int = 5) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var start := maxi(0, fame_log.size() - count)
	for i in range(fame_log.size() - 1, start - 1, -1):
		out.append(fame_log[i])
	return out


func unlocked_achievements() -> int:
	return achievements.size()


func rank_title(r: int = -1) -> String:
	var idx := rank if r < 0 else r
	return str(RANKS[clampi(idx, 0, RANKS.size() - 1)]["title"])


func rank_sign() -> String:
	if RANK_SIGNS.has(rank):
		return str(RANK_SIGNS[rank]["title"])
	return "—"


## Сколько славы до следующего ранга. -1, если ранг максимальный.
func glory_to_next() -> int:
	if rank >= RANKS.size() - 1:
		return -1
	return maxi(0, int(RANKS[rank + 1]["glory"]) - glory)


func next_rank_glory() -> int:
	if rank >= RANKS.size() - 1:
		return int(RANKS[rank]["glory"])
	return int(RANKS[rank + 1]["glory"])


## Пересчёт ранга по славе. Возвращает true, если ранг вырос.
func refresh_rank() -> bool:
	var new_rank := rank
	for r in RANKS.size():
		if glory >= int(RANKS[r]["glory"]):
			new_rank = r
	if new_rank > rank:
		rank = new_rank
		return true
	rank = new_rank
	return false


## --- Досье (GDD 5.1)
func dossier_entry(monster_id: StringName) -> Dictionary:
	var key := String(monster_id)
	if not dossier.has(key):
		dossier[key] = {
			"level": 0,
			"signals": [],
			"decoys": [],
			"scenarios": [],
			"weaknesses": [],
			"rules": [],
			"combos": [],
		}
	return dossier[key]


func dossier_level(monster_id: StringName) -> int:
	return int(dossier_entry(monster_id)["level"])


## Записать в досье новый факт. Возвращает true, если факт действительно новый —
## сообщение «Досье пополнено» показывается только тогда (GDD 5.2).
func dossier_add(monster_id: StringName, section: String, value: String) -> bool:
	var entry := dossier_entry(monster_id)
	if not entry.has(section):
		entry[section] = []
	var list: Array = entry[section]
	if list.has(value):
		return false
	list.append(value)
	_refresh_dossier_level(monster_id)
	return true


## Уровень досье по объёму знаний (GDD 5.1):
##   Наблюдение — есть сигналы; Анализ — есть уязвимости и правила; Мастерство — комбо.
func _refresh_dossier_level(monster_id: StringName) -> void:
	var e := dossier_entry(monster_id)
	var level := 0
	if not (e["signals"] as Array).is_empty() or not (e["scenarios"] as Array).is_empty():
		level = 1
	if not (e["weaknesses"] as Array).is_empty() and (e["signals"] as Array).size() >= 3:
		level = 2
	if not (e["combos"] as Array).is_empty():
		level = 3
	e["level"] = maxi(int(e["level"]), level)


func has_skill(skill_id: StringName) -> bool:
	return skills.has(String(skill_id))


func buy_skill(skill_id: StringName, price: int) -> bool:
	if has_skill(skill_id) or not spend_coins(price):
		return false
	skills[String(skill_id)] = true
	counters["bought_any_skill"] = int(counters["bought_any_skill"]) + 1
	return true


## Хватает ли монет. Отдельно от spend_coins, чтобы можно было СПРОСИТЬ, не тратя:
## так решается показ цены в магазине и выбор покупки в прогоне баланса.
## Заменяет копии «coins >= price», разошедшиеся по экранам и симулятору.
func can_afford(cost: int) -> bool:
	return cost >= 0 and coins >= cost


## Потратить монеты. ЕДИНСТВЕННЫЙ способ убрать монеты из кошелька, кроме
## намеренного обнуления при смерти (hunt_result._apply_defeat, GDD 1.3).
##
## Зачем отдельная функция. Раньше «хватает ли монет» решалось в ЧЕТЫРЁХ копиях:
## три в экране города (оружие, броня, совет) и одна в прогоне баланса. Пока
## копии совпадали, всё работало; разойтись они могли в любой правке, и тогда
## покупка ушла бы в минус молча — как ключ «sorrow» тихо подставлял цену 10.
## Теперь проверка и списание неразделимы: нельзя проверить в одном месте, а
## списать в другом.
##
## Возвращает false, если монет не хватает или цена отрицательна. Вызывающий
## ОБЯЗАН проверить результат: молча проигнорированный false означает «купил
## бесплатно», потому что побочные действия (выдать оружие, записать навык) он
## выполнит всё равно.
##
## Счётчик трат живёт в counters: reset() пересоздаёт словарь, поэтому он
## обнуляется на новый забег сам, без отдельной строки сброса. Нужен он затем,
## чтобы отчёт мог сказать «трат было N» — иначе проверка «монеты не ушли в
## минус» была бы зелёной и на прогоне, где не куплено ничего.
func spend_coins(cost: int) -> bool:
	if cost < 0 or coins < cost:
		return false
	coins -= cost
	counters["coins_spent"] = int(counters.get("coins_spent", 0)) + 1
	return true


func add_glory(amount: int) -> void:
	glory = maxi(0, glory + amount)
	refresh_rank()


func kill_counts(monster_id: StringName) -> int:
	return int(counters.get("kill_%s" % monster_id, 0))


## --- Ноша -----------------------------------------------------------------
## Добыча падает в ношу, а монеты появляются только когда её продал Лис.
## Логика целиком в MarketData: здесь только доступ к состоянию забега.

## Положить добычу с побеждённого вида. Возвращает стоимость добычи.
func add_drop(mon: MonsterData) -> int:
	return MarketData.add_drop(bag, mon)


## Стоимость всей ноши — «сколько монет лежит в сумке».
func bag_value() -> int:
	return MarketData.total_value(bag)


## Продать один предмет вида. Возвращает выручку.
func sell_trophy(monster_id: StringName, index: int) -> int:
	var price := MarketData.sell_one(bag, monster_id, index)
	coins += price
	return price


## Продать всю ношу. Возвращает выручку.
func sell_all_trophies() -> int:
	var total := MarketData.sell_all(bag)
	coins += total
	return total


## Потерять часть ноши при побеге. target_value — сколько стоимости брошено.
## Возвращает фактически потерянную стоимость: она может быть меньше, если
## ноша дешевле, чем требует штраф.
func drop_bag_part(target_value: int) -> int:
	var items := MarketData.escape_loss(bag, target_value)
	var lost := MarketData.remove_items(bag, items)
	# Пустые виды убираем, иначе ноша копит мусорные ключи и врёт в отчётах.
	for key in bag.keys():
		var counts: Array = bag[key]
		var any := false
		for c in counts:
			if int(c) > 0:
				any = true
				break
		if not any:
			bag.erase(key)
	return lost


## Потерять всю ношу: охотник погиб, добыча осталась там, где он её бросил.
func drop_bag_all() -> int:
	var lost := bag_value()
	bag.clear()
	return lost


## Подпись в арт-слоте, пока картинки нет. Формулировка важна: это не ошибка,
## а честная заглушка — так экран остаётся читаемым до появления арта.
func art_stub_note() -> String:
	return "здесь будет арт"


## Доступ к арту локации по виду: «след» и экран боя берут фон отсюда.
func location_art_path(monster_id: StringName) -> String:
	var location := HuntTrail.location_for(monster_id)
	match location:
		"берег":
			return "res://art/locations/shore.svg"
		"болото":
			return "res://art/locations/swamp.svg"
		"скалы":
			return "res://art/locations/cliffs.svg"
		"кости":
			return "res://art/locations/bones.svg"
		"рой":
			return "res://art/locations/swarm.svg"
		"тьма":
			return "res://art/locations/dark.svg"
		_:
			return ""


func register_kill(monster_id: StringName, rank_tier: int) -> void:
	var key := "kill_%s" % monster_id
	counters[key] = int(counters.get(key, 0)) + 1
	counters["kills"] = int(counters["kills"]) + 1
	win_streak += 1
	current_order_rank = rank_tier

