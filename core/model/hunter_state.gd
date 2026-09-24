extends RefCounted
class_name HunterState
## Состояние охотника в бою. Чистые данные, никаких нод.

## Потолок поглощения урона бронёй.
##
## GDD 12.8 разрешает броню 1–3 плюс навык +1/+2/+3, то есть до 6. Симулятор
## показал, что это ломает игру: поглощение выше урона зверя даёт max(1, урон) = 1,
## и охотник становится непобедим при любой точности чтения.
##
## Потолок 3 выбран по двум границам сразу:
##   - он НИЖЕ максимального урона сценария любого вида (у Хруза прыжок 4,
##     у Ламента захват 7), поэтому ни одна сборка не обнуляет урон;
##   - он равен базовому поглощению тяжёлой брони, то есть тяжёлая броня
##     остаётся пределом, а навык «+3 броня» перестаёт складываться линейно.
##
## Проверено симулятором: при 4 «мастерская» сборка получала 0 урона в 100% боёв.
const ABSORPTION_CAP := 3

var max_hp: int = 20
var hp: int = 20

## Броня игрока: поглощение урона. Складывается со навыком ветки «Выживание».
var absorption: int = 1

## Навык «+1/+2/+3 броня».
var armor_skill_bonus: int = 0

## Навык «+1/+2/+3 урон».
var damage_skill_bonus: int = 0

## Навык «Быстрая смена»: одна смена оружия за бой не тратит ход (GDD 7.3).
## Флаг одноразовый — движок снимает его при первом использовании.
var weapon_swap_free: bool = false

## Дополнительный бонус к «идеальному чтению» (навык «Идеальное чтение +»).
##
## Поля `initiative_bonus` здесь больше нет: оно только записывалось и никем не
## читалось (проверено grep), а инициативу считает initiative_bonus_total.
var perfect_read_bonus: int = 0

## «Второе дыхание»: при HP ≤ 3 автоматически +5 HP, один раз за бой (GDD 7.4).
var second_wind: bool = false

## «Феникс»: при смерти один раз за забег возвращаешься с 5 HP (GDD 7.4).
var phoenix: bool = false

## Бонус к шансу побега: навык «Быстрый побег» (+10%) и плащ охотника (GDD 7.4, 12.8).
var bonus_escape_chance: float = 0.0

## Навык «Побег без штрафа»: побег не теряет славу (GDD 7.4).
var escape_penalty_negated: bool = false

## Сумма бонусов инициативы: оружие плюс знаки ранга (GDD 12.9).
var initiative_bonus_total: int = 0

## Штраф инициативы от брони: тяжёлая даёт −1 (GDD 12.9).
var initiative_penalty: int = 0

## Шанс крита: 0.10 от навыка «Крит», 0.20 от «Крит II» (GDD 7.3).
var crit_chance: float = 0.0

## «Оружие + Выживание»: крит оглушает зверя на 1 ход (GDD 7.5).
var crit_stuns: bool = false

## «Чтение + Выживание»: досье в бою не тратит использование (GDD 7.5).
var dossier_free: bool = false

## «Чтение + Оружие»: идеальное чтение даёт +1 славы (GDD 7.5).
var perfect_glory_bonus: bool = false

## «Все три»: +1 ко всем бонусам славы (GDD 7.5).
var all_branches_glory_bonus: bool = false


## Инициатива охотника: 5 + бонус оружия + знаки − штраф брони (GDD 2.6, 12.9).
func initiative() -> int:
	return 5 + initiative_bonus_total - initiative_penalty


## Кто бьёт первым. По GDD при равенстве первым бьёт игрок — значит монстр
## опережает его только при СТРОГО большей инициативе.
func monster_acts_first(monster: MonsterData) -> bool:
	return monster.initiative > initiative()

var weapon_id: StringName = &"bow"

## Накопленные статусы: id -> ходов осталось. -1 = до конца боя.
var statuses: Dictionary = {}


## Итоговое поглощение с учётом навыка и потолка.
func total_absorption() -> int:
	return mini(ABSORPTION_CAP, absorption + armor_skill_bonus)


## Поглощение без потолка — для отображения игроку, чтобы он видел срез.
func raw_absorption() -> int:
	return absorption + armor_skill_bonus


func is_capped() -> bool:
	return raw_absorption() > ABSORPTION_CAP


func is_alive() -> bool:
	return hp > 0


func take_damage(amount: int) -> int:
	var applied: int = maxi(0, amount)
	hp = maxi(0, hp - applied)
	return applied


func heal(amount: int) -> int:
	var before := hp
	hp = mini(max_hp, hp + amount)
	return hp - before


## ВНИМАНИЕ: пара snapshot()/from_snapshot() НЕ РАБОТАЕТ и сейчас никем не
## вызывается (проверено grep: ни одного вызова в проекте).
##
## Три поломки, и каждая сломала бы сохранение молча:
##  1. snapshot() пишет `absorption` как total_absorption() — уже с бонусом навыка
##     и потолком, — а from_snapshot() кладёт это в БАЗОВОЕ `absorption`. При
##     загрузке armor_skill_bonus применится ВТОРОЙ раз;
##  2. snapshot() сохраняет second_wind и phoenix, а from_snapshot() их не читает:
##     два навыка по 80 и 100 монет исчезли бы после загрузки;
##  3. statuses в HunterState не трогает движок (у него свои monster_statuses),
##     поэтому сохраняется и восстанавливается поле, которое ни на что не влияет.
##
## Решать вместе с сохранением игры: либо переписать пару целиком (и тогда
## переносить СЫРЫЕ поля, а не производные), либо удалить. Оставлять как есть
## нельзя — выглядит рабочим.
func snapshot() -> Dictionary:
	return {
		"hp": hp,
		"max_hp": max_hp,
		"absorption": total_absorption(),
		"weapon_id": String(weapon_id),
		"statuses": statuses.duplicate(),
		"second_wind": second_wind,
		"phoenix": phoenix,
	}


static func from_snapshot(data: Dictionary) -> HunterState:
	var s := HunterState.new()
	s.hp = int(data.get("hp", 20))
	s.max_hp = int(data.get("max_hp", 20))
	s.absorption = int(data.get("absorption", 1))
	s.weapon_id = StringName(data.get("weapon_id", "bow"))
	var st: Dictionary = data.get("statuses", {})
	s.statuses = st.duplicate()
	return s
