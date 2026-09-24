extends RefCounted
class_name CityData
## Логика города: заказы, цены, советы Старика, навыки, снаряжение.
##
## Здесь только правила и числа — никакого UI. Экраны города читают отсюда,
## поэтому баланс города можно проверить в headless-прогоне, как и бой.

## --- Арт: тонкие делегаты в ArtPaths ----------------------------------------
##
## Сами пути и подбор расширения живут в core/ui_data/art_paths.gd. Делегаты
## оставлены на время переноса: экраны и документация зовут CityData.location_art()
## и CityData.LOCATION_ART, и ломать эти имена в одном шаге с переносом значило бы
## смешать две правки в одну — а тогда непонятно, что именно сломалось, если
## сломается. Делегаты удаляются отдельным шагом, когда вызывающие перейдут на
## ArtPaths.

const LOCATION_ART := ArtPaths.LOCATION_ART
const CITY_OVERVIEW_ART := ArtPaths.CITY_OVERVIEW_ART
const PREP_ART := ArtPaths.PREP_ART
const ART_EXTENSIONS := ArtPaths.ART_EXTENSIONS


static func location_art(tab: String) -> String:
	return ArtPaths.location_art(tab)


static func overview_art() -> String:
	return ArtPaths.overview_art()


static func prep_art() -> String:
	return ArtPaths.prep_art()


const ORDER_RANKS := {
	0: {"title": "стартовый", "monsters": ["hruz", "shipun"]},
	1: {"title": "продвинутый", "monsters": ["gromun", "tleun"]},
	2: {"title": "элитный", "monsters": ["skorb", "ashmother"]},
	3: {"title": "легендарный", "monsters": ["lament"]},
}

## Слава за победу по рангу заказа (GDD 8.2).
const GLORY_BY_TIER := {0: 1, 1: 2, 2: 4, 3: 10}

## Штраф славы за смерть = ранг заказа × 3 (GDD 8.4).
const DEATH_PENALTY_PER_RANK := 3

## Цена похода в днях (GDD 1.3.1). Богиня дала срок: стать легендой за N дней,
## и дни — единственный ресурс, который нельзя вернуть. Поэтому поход стоит не
## один день, а три: дорога туда, сама охота и возврат в город. Тогда возврат
## в город — это выбор с ценой (день за дорогу), а не бесплатное действие.
const DAYS_ROAD := 1
const DAYS_HUNT := 1
const DAYS_RETURN := 1

## Сколько дней стоит один поход целиком. Смерть внутри похода отдельной платы
## не требует: дни уже потрачены дорогой и охотой, а материю забирает сама смерть.
static func days_per_hunt() -> int:
	return DAYS_ROAD + DAYS_HUNT + DAYS_RETURN

## Совет Старика: monster_id -> цена (GDD 9.3).
const ADVICE_PRICES := {
	"hruz": 0,
	"shipun": 5,
	"gromun": 10,
	"tleun": 10,
	"skorb": 15,
	"ashmother": 15,
	"lament": 25,
}

## Доступные заказы по текущему рангу.
## Ранг открывает заказы один за другим: 1 → продвинутые, 2 → элитные,
## 3 → легендарный. Иначе всё, кроме стартовых, оказывается заперто до «Мастера»,
## и прогрессия упирается в потолок: слава за стартовый заказ — 1, а до Легенды
## нужно 100.
##
## Виды, которых нет в базе, отсеиваются: заказ на ненаписанный вид лучше не
## показывать вовсе, чем отдавать игроку пустой экран.
static func available_monsters(rank: int) -> Array:
	var out: Array = []
	var max_tier := clampi(rank, 0, 3)
	for tier in ORDER_RANKS.keys():
		if int(tier) > max_tier:
			continue
		for m in ORDER_RANKS[tier]["monsters"]:
			if Database.monster(StringName(m)) == null:
				continue
			out.append({"monster_id": m, "tier": int(tier), "tier_title": ORDER_RANKS[tier]["title"]})
	return out


## Штраф славы за смерть на заказе этого ранга (GDD 8.4) с учётом защиты от спирали.
static func death_penalty(order_rank: int, first_time: bool, side_encounter: bool) -> int:
	var penalty := order_rank * DEATH_PENALTY_PER_RANK
	if first_time and order_rank >= 3:
		penalty = int(penalty / 2.0)
	if side_encounter:
		penalty = int(penalty / 2.0)
	return penalty


## Слава за победу (GDD 8.2) с учётом знака ранга.
static func victory_glory(order_rank: int, perfect: bool, no_damage: bool, sign_bonus: bool) -> int:
	var base := int(GLORY_BY_TIER.get(order_rank, 1))
	if perfect:
		base += 1
	if no_damage:
		base += 2
	if sign_bonus:
		base += 1
	return base


static func advice_price(monster_id: StringName) -> int:
	return int(ADVICE_PRICES.get(String(monster_id), 10))


## Название ранга заказа по числу: «стартовый», «продвинутый» и так далее.
static func order_tier_title(tier: int) -> String:
	if ORDER_RANKS.has(tier):
		return str(ORDER_RANKS[tier]["title"])
	return "неизвестный"


## --- Навыки: реализация в SkillsData ----------------------------------------
##
## Таблица навыков, ветки, руны и правила покупки живут в
## core/ui_data/skills_data.gd, и вызывающие зовут SkillsData напрямую. Делегатов
## здесь нет намеренно: три копии одного имени (реализация, делегат, вызов) — это
## ровно тот источник расхождений, из-за которого тип урона подписывался неверно.
## Один навык — одно место.


## ВСЕ типы урона удара: базовый тип оружия плюс тип руны, если она есть и
## отличается. Руна ДОБАВЛЯЕТ второй тип, а не заменяет базовый (GDD 12.3), и
## DamageCalc считает уязвимости и резисты по обоим типам сразу.
##
## Зачем отдельная функция. Для показа игроку одного типа МАЛО: подпись «огонь» на
## зачарованном клинке скрывает, что физика тоже работает. По такой подписи игрок
## решает, что физическая уязвимость вида ему недоступна, и отказывается от
## выгодного удара, — а механика при этом считает удар двойным. Это уже было:
## экран боя и лог брали effective_damage_type() и показывали один тип.
static func damage_types(weapon: WeaponData) -> Array[StringName]:
	if weapon == null:
		return [MonsterData.TYPE_PHYSICAL]
	return weapon.damage_types()


## --- Подписи для показа: в DossierText ---------------------------------------
##
## damage_types_title(), damage_type_names(), rune_title() и весь рендер досье
## живут в core/ui_data/dossier_text.gd. Отсюда остаются только делегаты, чтобы
## вызывающие работали до отдельного шага перевода на DossierText.


static func damage_types_title(weapon: WeaponData) -> String:
	return DossierText.damage_types_title(weapon)


static func damage_type_names(weapon: WeaponData) -> String:
	return DossierText.damage_type_names(weapon)


static func rune_title(rune_type: StringName) -> String:
	return DossierText.rune_title(rune_type)


## Каким типом урона бьёт оружие С УЧЁТОМ зачарования. Отвечает про ОДИН тип (тип
## руны, если она есть) — этого достаточно валидатору и тем местам, где нужен
## «главный» тип удара.
##
## Для показа игроку НЕ ИСПОЛЬЗОВАТЬ: удар несёт оба типа, см.
## DossierText.damage_types_title(). Руна ДОБАВЛЯет тип, а не заменяет: раньше
## здесь в комментарии стояло «заменяет», и это увело бы в ошибку при следующей
## правке.
static func effective_damage_type(weapon: WeaponData) -> StringName:
	if weapon == null:
		return MonsterData.TYPE_PHYSICAL
	if weapon.rune_type != &"":
		return weapon.rune_type
	return weapon.damage_type


## --- Названия типов и дистанций: ОДИН источник на весь проект ---------------
##
## Здесь, а не в DossierText, и это важно. Раньше функция существовала в ЧЕТЫРЁХ
## копиях (экран боя, подготовка, город, DamageCalc, DossierRecorder), и
## `_range_ru` — в ШЕСТИ. Копии разъехались ровно так, как и должны были: когда
## физический урон разделили на подтипы, обновили три копии из четырёх, и экран
## боя начал подписывать копьё «физикой», хотя считал его колющим. Игрок видел
## один тип, а урон шёл по другому.
##
## Правило: добавил тип урона — добавь его ЗДЕСЬ, и он появится везде.
static func type_ru(type_id: StringName) -> String:
	match type_id:
		&"crush":
			return "дробящий"
		&"slash":
			return "режущий"
		&"pierce":
			return "колющий"
		&"fire":
			return "огонь"
		&"ice":
			return "лёд"
		&"poison":
			return "яд"
		_:
			return "физика"


## Название дистанции. Полная форма («ближний бой») — для предложений, краткая
## («ближний») — для подписей в скобках.
static func range_ru(range_id: StringName, full: bool = false) -> String:
	if full:
		return "дальний бой" if range_id == MonsterData.RANGE_RANGED else "ближний бой"
	return "дальний" if range_id == MonsterData.RANGE_RANGED else "ближний"


## --- Досье: реализация в DossierText -----------------------------------------
##
## Структуру окна вида собирает core/ui_data/dossier_text.gd. Здесь остаётся
## делегат, чтобы вызывающие (окно вида, экран подготовки, экран боя, город,
## валидатор, проверки) работали без правок в одном шаге с переносом.
##
## Строкового рендера досье (dossier_lines) больше нет: его звали только
## валидатор и проверка --prep, а город и подготовка строят окно из
## dossier_view(). Функция, которую не зовёт ни один экран, но которую
## «проверяют», даёт ложную уверенность: тест зелёный, а игрок видит другое.
static func dossier_view(mon: MonsterData) -> Dictionary:
	return DossierText.dossier_view(mon)


## Диагностика: что доступно на каждом ранге. Пишет файлом, потому что пайп
## в headless-режиме ненадёжен.
static func debug_orders() -> void:
	var out: PackedStringArray = PackedStringArray()
	for r in 6:
		var ms := available_monsters(r)
		var names: PackedStringArray = PackedStringArray()
		for m in ms:
			names.append("%s(t%d)" % [m["monster_id"], m["tier"]])
		out.append("ранг %d: %d заказов — %s" % [r, ms.size(), ", ".join(names)])
	out.append("ключи ORDER_RANKS: %s" % str(ORDER_RANKS.keys()))
	var f := FileAccess.open("F:/WORK/hunter/_orders.txt", FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(out))
		f.close()
