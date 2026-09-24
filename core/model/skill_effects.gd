extends RefCounted
class_name SkillEffects
## Что навыки ДЕЛАЮТ: единственный источник чисел эффектов на стороне охотника.
##
## Почему отдельный файл. Эти формулы жили в двух местах: в экране боя
## (ui/screens/battle/battle_screen.gd) и свои копии в прогоне баланса
## (core/sim/loop_sim.gd). Копии совпадали — но это ровно та конструкция, из-за
## которой копьё подписывалось «физикой», считаясь колющим: копии в разных слоях
## расходятся молча, потому что ни одна из них не «неправильная» на вид.
##
## И одна копия уже разошлась. Экран боя давал бонус к побегу от навыка «Быстрый
## побег» и от плаща, а прогон баланса не считал побег вообще — то есть измерял
## бой без механики, которая в игре есть. Теперь у побега один источник, и он
## общий с игрой.
##
## Правило: числа эффектов навыков — ЗДЕСЬ. Добавил навык с эффектом — добавь
## сюда, и он появится и в бою, и в прогоне баланса.
##
## Файл читает GameState (какие навыки куплены, что надето) — это допустимо для
## core: он остаётся чистым GDScript без узлов и сцен и работает headless.


## Максимальное HP с учётом ветки «Выживание». Навыки заменяют друг друга:
## третий уровень включает второй, поэтому берём наивысший.
static func hp_bonus() -> int:
	if GameState.has_skill(&"surv_hp3"):
		return 15
	if GameState.has_skill(&"surv_hp2"):
		return 10
	if GameState.has_skill(&"surv_hp1"):
		return 5
	return 0


## Прибавка к поглощению брони. Потолок (HunterState.ABSORPTION_CAP) применяется
## не здесь, а в HunterState: иначе срез считался бы от уже урезанного числа.
static func armor_bonus() -> int:
	if GameState.has_skill(&"surv_armor3"):
		return 3
	if GameState.has_skill(&"surv_armor2"):
		return 2
	if GameState.has_skill(&"surv_armor1"):
		return 1
	return 0


## Прибавка к урону всего оружия.
static func damage_bonus() -> int:
	if GameState.has_skill(&"wpn_dmg3"):
		return 3
	if GameState.has_skill(&"wpn_dmg2"):
		return 2
	if GameState.has_skill(&"wpn_dmg1"):
		return 1
	return 0


## Бонус к шансу побега: навык «Быстрый побег» и Плащ охотника (GDD 7.4, 12.8).
static func escape_bonus() -> float:
	var bonus := 0.0
	if GameState.has_skill(&"surv_escape"):
		bonus += 0.10
	if GameState.equipped_armor == &"cloak":
		bonus += 0.10
	return bonus


## Шанс крита: 10% от «Крит», 20% от «Крит II» (GDD 7.3).
static func crit_chance() -> float:
	if GameState.has_skill(&"wpn_crit2"):
		return 0.20
	if GameState.has_skill(&"wpn_crit"):
		return 0.10
	return 0.0


## Сколько опорных сигналов подсвечивать в прозе (GDD 7.2).
##
## Это эффект навыка чтения, а не оформление: число решает, СКОЛЬКО игрок видит,
## поэтому живёт рядом с остальными эффектами, а не в экране.
static func highlight_count() -> int:
	if GameState.has_skill(&"read_triple"):
		return 3
	if GameState.has_skill(&"read_double"):
		return 2
	if GameState.has_skill(&"read_signal"):
		return 1
	return 0


## Сколько ложных следов скрывать (GDD 7.2). 99 — «все»: третий уровень чистой
## прозы убирает ложные следы целиком, и точное число здесь было бы ложной
## точностью (сколько их в конкретной прозе, зависит от вида).
static func hide_decoy_count() -> int:
	if GameState.has_skill(&"read_clean3"):
		return 99
	if GameState.has_skill(&"read_clean2"):
		return 2
	if GameState.has_skill(&"read_clean"):
		return 1
	return 0


## Готовый охотник по текущему состоянию забега: снаряжение и ВСЕ эффекты навыков
## в одном месте, чтобы бой и прогон баланса не расходились.
##
## Оружие и броня приходят параметрами: экран берёт их из GameState, а прогон
## баланса подставляет свои — правила эффектов от этого не меняются.
##
## `free_swap` — параметр, а не чтение навыка здесь. «Быстрая смена» тратит
## одноразовый флаг за бой, и прогон баланса его не ставит намеренно; если бы
## функция читала навык сама, включение флага в симуляторе изменило бы эталонные
## числа баланса незаметно для того, кто правит эффекты.
static func build_hunter(weapon: WeaponData, armor: ArmorData, free_swap: bool = false) -> HunterState:
	var hunter := HunterState.new()
	hunter.max_hp = 20 + hp_bonus()
	hunter.hp = hunter.max_hp
	hunter.absorption = armor.absorption if armor != null else 1
	hunter.armor_skill_bonus = armor_bonus()
	hunter.damage_skill_bonus = damage_bonus()
	hunter.crit_chance = crit_chance()
	hunter.bonus_escape_chance = escape_bonus()
	hunter.escape_penalty_negated = GameState.has_skill(&"surv_no_penalty")
	hunter.weapon_swap_free = free_swap
	hunter.perfect_read_bonus = 1 if GameState.has_skill(&"wpn_perfect") else 0

	# «Второе дыхание» и «Феникс» (GDD 7.4). Здесь они и включаются.
	#
	# Раньше их не включал НИКТО: движок честно проверял
	# `second_wind_available = hunter.second_wind` и `phoenix_available`, но первое
	# поле не выставлялось ни в одном файле, а второе — даже не читалось из
	# hunter.phoenix. Два навыка по 80 и 100 монет не делали ничего, и в отчёте
	# симулятора это видно: second_wind_rate и phoenix_rate равны 0.0 во ВСЕХ
	# сборках. Механика без включателя — тот же класс, что кнопка без обработчика.
	hunter.second_wind = GameState.has_skill(&"surv_second_wind")
	hunter.phoenix = GameState.has_skill(&"surv_phoenix")

	# Парные навыки веток (GDD 7.5): оружие+выживание, чтение+выживание,
	# чтение+оружие и все три сразу.
	var read := GameState.has_skill(&"read_signal")
	var weapon_skill := GameState.has_skill(&"wpn_dmg1")
	var survive := GameState.has_skill(&"surv_armor1")
	hunter.crit_stuns = weapon_skill and survive
	hunter.dossier_free = read and survive
	hunter.perfect_glory_bonus = read and weapon_skill
	hunter.all_branches_glory_bonus = read and weapon_skill and survive

	if weapon != null:
		hunter.weapon_id = weapon.id
		hunter.initiative_bonus_total = weapon.initiative_bonus
	hunter.initiative_penalty = armor.initiative_penalty if armor != null else 0
	return hunter
