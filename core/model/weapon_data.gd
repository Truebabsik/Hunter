extends Resource
class_name WeaponData
## Оружие. Дальность и тип урона — характеристики снаряжения, не магии (GDD 2.3).

@export var id: StringName = &""
@export var title: String = ""

## melee / ranged.
@export var range_id: StringName = &"melee"

## Базовый тип урона: дробящий (crush) / режущий (slash) / колющий (pierce) либо
## магический — огонь, лёд, яд (GDD 12.3). Физический урон разделён на подтипы,
## поэтому выбор оружия — это выбор подтипа, а не только дальности.
@export var damage_type: StringName = &"crush"

## Зачарование оружия руной (GDD 11.6, 12.3). Пустая строка — оружие не зачаровано
## и бьёт своим базовым подтипом. Руна ДОБАВЛЯЕТ второй тип урона, а не заменяет
## базовый: удар несёт и подтип оружия, и тип руны, а уязвимости с резистами
## считаются по обоим (см. DamageCalc и CityData.damage_types).
##
## Почему зачарование живёт на оружии, а не «на игроке»: насадку носят в сумке,
## а чары оказываются на предмете. Отсюда и обмен за ход в бою, и подготовка
## на следe: раскладываешь чары по оружию заранее.
@export var rune_type: StringName = &""

@export_range(1, 20, 1) var base_damage: int = 3

## Бонус инициативы (GDD 12.9).
@export_range(-2, 3, 1) var initiative_bonus: int = 0

@export_range(0, 200, 1) var price: int = 0

## Арт: иконка в выборе инструмента.
@export var icon: Texture2D
## Цвет акцента строкой («#8d8578»): так он читаем в .tres.
@export var accent_color: String = "#8d8578"


func accent() -> Color:
	return Color.from_string(accent_color, Color("#8d8578"))


## ВСЕ типы урона удара этим оружием: базовый подтип плюс тип руны, если она есть и
## отличается. Руна ДОБАВЛЯЕТ второй тип (GDD 12.3), поэтому зачарованный молот бьёт
## и дробящим, и огнём — а не «становится огненным».
##
## Метод живёт на ОРУЖИИ, а не в данных интерфейса: это свойство предмета, и им
## пользуются и расчёт урона, и подбор комбо, и показ. Раньше список типов собирался
## в CityData, из-за чего ядро зависело от модуля интерфейса, а подбор комбо брал
## «главный» тип и терял второй.
func damage_types() -> Array[StringName]:
	var out: Array[StringName] = [damage_type]
	if rune_type != &"" and rune_type != damage_type:
		out.append(rune_type)
	return out
