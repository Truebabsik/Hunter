extends RefCounted
class_name SkillsData
## Навыки: таблица, ветки и руны.
##
## Вынесено из CityData, потому что навыки — отдельная подсистема со своими
## правилами: покупка ограничена рангом и монетами, ветка даёт уровень, а руна
## — это тоже навык, только эффект у него накладывается на оружие.
##
## Главное правило, ради которого этот файл существует отдельно: требование
## ранга лежит ПОЛЕМ `rank` у каждого навыка, и никакой второй таблицы
## «ветка + уровень → ранг» быть не должно. Навыки одного уровня вправе требовать
## разного ранга, а такая таблица этого не выразит и начнёт лгать.
##
## Порядок в SKILLS — это порядок показа в ветке «Мастер»: он несёт смысл,
## поэтому навыки одной ветки идут подряд от первого уровня к третьему.


## --- Навыки (GDD 7.2, 7.3, 7.4) ---
## id, ветка, уровень, название, эффект, цена, требуемый ранг
const SKILLS := [
	# Чтение
	{"id": "read_signal", "branch": "read", "tier": 1, "title": "Опорный сигнал",
	 "effect": "В прозе выделяется один опорный сигнал", "price": 20, "rank": 0},
	{"id": "read_clean", "branch": "read", "tier": 1, "title": "Чистая проза",
	 "effect": "Один ложный след убирается", "price": 25, "rank": 0},
	{"id": "read_recall", "branch": "read", "tier": 1, "title": "Память сигналов",
	 "effect": "После боя показывается разбор", "price": 15, "rank": 0},
	{"id": "read_double", "branch": "read", "tier": 2, "title": "Двойной опорный",
	 "effect": "Выделяются два опорных сигнала", "price": 40, "rank": 1},
	{"id": "read_clean2", "branch": "read", "tier": 2, "title": "Чистая проза II",
	 "effect": "Ещё один ложный след убирается", "price": 35, "rank": 1},
	{"id": "read_dossier", "branch": "read", "tier": 2, "title": "Досье в бою",
	 "effect": "Досье открывается в бою (1 раз за бой)", "price": 50, "rank": 1},
	{"id": "read_triple", "branch": "read", "tier": 3, "title": "Тройной опорный",
	 "effect": "Выделяются три опорных сигнала", "price": 60, "rank": 2},
	{"id": "read_clean3", "branch": "read", "tier": 3, "title": "Чистая проза III",
	 "effect": "Все ложные следы убираются", "price": 55, "rank": 2},
	{"id": "read_foresee", "branch": "read", "tier": 3, "title": "Предвидение",
	 "effect": "В начале боя показывается один сценарий", "price": 70, "rank": 2},
	# Оружие
	{"id": "wpn_dmg1", "branch": "weapon", "tier": 1, "title": "+1 урон",
	 "effect": "Базовый урон всего оружия +1", "price": 25, "rank": 0},
	{"id": "wpn_swap", "branch": "weapon", "tier": 1, "title": "Быстрая смена",
	 "effect": "Смена оружия проходит вместе с ударом (1 раз за бой)", "price": 30, "rank": 0},
	{"id": "wpn_mod", "branch": "weapon", "tier": 1, "title": "Руна огня",
	 "effect": "Открывает руну огня: зачаруй любое оружие", "price": 20, "rank": 0},
	{"id": "wpn_dmg2", "branch": "weapon", "tier": 2, "title": "+2 урон",
	 "effect": "Базовый урон +2 (заменяет +1)", "price": 45, "rank": 1},
	{"id": "wpn_double_mod", "branch": "weapon", "tier": 2, "title": "Руна льда",
	 "effect": "Открывает руну льда: зачаруй любое оружие", "price": 60, "rank": 1},
	{"id": "wpn_crit", "branch": "weapon", "tier": 2, "title": "Крит",
	 "effect": "10% шанс крита", "price": 50, "rank": 1},
	{"id": "wpn_dmg3", "branch": "weapon", "tier": 3, "title": "+3 урон",
	 "effect": "Базовый урон +3 (заменяет +2)", "price": 70, "rank": 3},
	{"id": "wpn_crit2", "branch": "weapon", "tier": 3, "title": "Руна яда",
	 "effect": "Открывает руну яда: зачаруй любое оружие", "price": 65, "rank": 3},
	{"id": "wpn_perfect", "branch": "weapon", "tier": 3, "title": "Идеальное чтение +",
	 "effect": "Идеальное чтение даёт +2 урона", "price": 55, "rank": 3},
	# Выживание
	{"id": "surv_armor1", "branch": "survival", "tier": 1, "title": "+1 броня",
	 "effect": "Вся броня даёт +1 к поглощению", "price": 25, "rank": 0},
	{"id": "surv_hp1", "branch": "survival", "tier": 1, "title": "+5 HP",
	 "effect": "Максимальное HP +5", "price": 20, "rank": 0},
	{"id": "surv_escape", "branch": "survival", "tier": 1, "title": "Быстрый побег",
	 "effect": "+10% к шансу побега", "price": 15, "rank": 0},
	{"id": "surv_armor2", "branch": "survival", "tier": 2, "title": "+2 броня",
	 "effect": "Вся броня даёт +2 (заменяет +1)", "price": 45, "rank": 1},
	{"id": "surv_hp2", "branch": "survival", "tier": 2, "title": "+10 HP",
	 "effect": "Максимальное HP +10 (заменяет +5)", "price": 40, "rank": 1},
	{"id": "surv_regen", "branch": "survival", "tier": 2, "title": "Регенерация",
	 "effect": "+1 HP после каждого боя", "price": 50, "rank": 1},
	{"id": "surv_no_penalty", "branch": "survival", "tier": 2, "title": "Побег без штрафа",
	 "effect": "Побег не теряет славу", "price": 35, "rank": 1},
	{"id": "surv_armor3", "branch": "survival", "tier": 3, "title": "+3 броня",
	 "effect": "Вся броня даёт +3 (заменяет +2)", "price": 70, "rank": 3},
	{"id": "surv_hp3", "branch": "survival", "tier": 3, "title": "+15 HP",
	 "effect": "Максимальное HP +15 (заменяет +10)", "price": 60, "rank": 3},
	{"id": "surv_second_wind", "branch": "survival", "tier": 3, "title": "Второе дыхание",
	 "effect": "При HP ≤ 3 автоматически +5 HP (1 раз за бой)", "price": 80, "rank": 3},
	{"id": "surv_phoenix", "branch": "survival", "tier": 3, "title": "Феникс",
	 "effect": "При смерти 1 раз за забег возвращаешься с 5 HP", "price": 100, "rank": 3},
]

## Ветки навыков: id ветки → название для показа.
##
## Таблицы BRANCH_TIER_RANK (ветка + уровень → требуемый ранг) здесь больше нет.
## Проверено при аудите: ни одного вызова, таблица была мёртвой. Причина не
## удалять её «на всякий случай»: она НЕ МОЖЕТ выразить то, что уже выражено
## данными. Требование ранга стоит полем `rank` у каждого навыка, а навыки одного
## уровня могут требовать разного ранга — таблица с ключом (ветка, уровень) такое
## не опишет и станет лгать в тот день, когда это понадобится. Два источника
## одного числа, из которых один слабее, — это будущая ошибка, а не страховка.
## Ранг читается полем: SkillsData.can_buy().

const BRANCH_TITLES := {
	"read": "Чтение",
	"weapon": "Оружие",
	"survival": "Выживание",
}


## Руны: навык открывает руну, руна накладывается на ЛЮБОЕ оружие и ДОБАВЛЯЕТ
## второй тип урона к его базовому (GDD 12.3). Ключ — идентификатор навыка,
## который её открывает.
##
## Внимание: здесь НЕ написано «заменяет». Раньше было написано, и это было
## ошибкой: DamageCalc бьёт обоими типами сразу (damage_calc.gd, hit_types), и
## уязвимости с резистами считаются по обоим. Комментарий, обещавший замену,
## стоил часа поисков «бага», которого нет.
const RUNE_SKILLS := {
	"wpn_mod": "fire",
	"wpn_double_mod": "ice",
	"wpn_crit2": "poison",
}

## Все руны, открытые игроку. Порядок — как в ветке «Оружие».
static func known_runes(skills: Dictionary) -> Array[StringName]:
	var out: Array[StringName] = []
	for skill_id in RUNE_SKILLS.keys():
		if skills.has(skill_id):
			out.append(StringName(RUNE_SKILLS[skill_id]))
	return out


## Открыта ли конкретная руна.
static func has_rune(skills: Dictionary, rune_type: StringName) -> bool:
	for skill_id in RUNE_SKILLS.keys():
		if StringName(RUNE_SKILLS[skill_id]) == rune_type:
			return skills.has(skill_id)
	return false


## Ветка по её идентификатору: навыки идут в порядке таблицы, то есть по уровням.
static func skills_of_branch(branch: String) -> Array:
	var out: Array = []
	for s in SKILLS:
		if s["branch"] == branch:
			out.append(s)
	return out


## Навык по идентификатору. Пустой словарь — такого навыка нет; это ловится
## валидатором, потому что таблица рун ссылается на навыки по id.
static func find_skill(skill_id: StringName) -> Dictionary:
	for s in SKILLS:
		if StringName(s["id"]) == skill_id:
			return s
	return {}


## Может ли игрок купить навык: хватает монет, не куплен, ранг достаточен.
##
## Здесь намеренно НЕ вызывается GameState.can_afford(), хотя сравнение похоже.
## Разница принципиальная: монеты приходят ПАРАМЕТРОМ, функция их не читает и не
## тратит, поэтому её можно спросить про любое число — так валидатор проверяет
## таблицу навыков, не трогая забег. Проверка и списание не могут разъехаться
## там, где списания нет. Дублированием это не является.
static func can_buy(skill_id: StringName, coins: int, rank: int, owned: Dictionary) -> Dictionary:
	var s := find_skill(skill_id)
	if s.is_empty():
		return {"ok": false, "reason": "нет такого навыка"}
	if owned.has(String(skill_id)):
		return {"ok": false, "reason": "уже куплено"}
	if rank < int(s["rank"]):
		return {"ok": false, "reason": "закрыто до ранга «%s»" % GameState.rank_title(int(s["rank"]))}
	if coins < int(s["price"]):
		return {"ok": false, "reason": "не хватает %d монет" % (int(s["price"]) - coins)}
	return {"ok": true, "reason": ""}

