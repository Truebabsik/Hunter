extends Resource
class_name ScenarioData
## Сценарий поведения зверя — то, что он загадал на раунд (GDD 2.1).
##
## Сценарий сам владеет своими опорными сигналами: так связь «сценарий → сигналы»
## не рвётся при редактировании и файл .tres остаётся читаемым.

@export var id: StringName = &""

## Название для карточки-гипотезы: «Прыгнет», «Ударит клешнёй».
@export var card_label: String = ""

## Описание для досье и разбора после боя.
@export var description: String = ""

## Вес в характерной таблице. Не проценты: проценты считаются от суммы весов,
## чтобы правки не ломали сумму 100.
@export_range(1, 100, 1) var weight: int = 10

## Опорные сигналы сценария. Инвариант: минимум один (GDD 2.2).
@export var signals: Array[SignalData] = []

## Урон этого сценария. 0 = использовать базовый урон зверя.
@export_range(0, 20, 1) var damage_override: int = 0

## Урон не смягчается бронёй вообще (GDD 4.4: «Вой-паралич не пробивается блоком»).
@export var unblockable: bool = false

## Теги сценария: "charge", "grab", "recover", "aoe", "phase".
@export var tags: PackedStringArray = PackedStringArray()


## Урон этого сценария с учётом базового урона вида.
func damage_of(base_damage: int) -> int:
	return damage_override if damage_override > 0 else base_damage


## Частота в процентах. ТОЛЬКО для внутренних отчётов и проверок: игроку частота
## атак не показывается (решение по дизайну), веса — внутренняя механика. Экраны
## не должны выводить это число; см. CityData.dossier_view.
func chance_percent(total_weight: int) -> float:
	if total_weight <= 0:
		return 0.0
	return float(weight) * 100.0 / float(total_weight)


## Есть ли у сценария сигнал, занимающий этот слот.
func has_slot(slot: StringName) -> bool:
	for s in signals:
		if s.slot == slot:
			return true
	return false
