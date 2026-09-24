extends Resource
class_name ComboData
## Комбо-приём: идеальное чтение + конкретный инструмент (GDD 6.2).

@export var id: StringName = &""
@export var title: String = ""

## Сценарий, который нужно прочитать.
@export var scenario_id: StringName = &""

## Требуемая дальность: melee / ranged / any.
@export var required_range: StringName = &"any"

## Требуемый тип урона: crush / slash / pierce / fire / ice / poison / any.
@export var required_type: StringName = &"any"

## Бонус урона. По 12.5 базовое значение +2.
@export_range(0, 10, 1) var damage_bonus: int = 2

## Текст эффекта для лога: «заморозка на 1 ход».
@export var effect_text: String = ""

## Статус, который накладывается на зверя. Пусто = нет.
@export var status_id: StringName = &""


# Подбор комбо живёт в BattleEngine._match_combo, а не здесь: условие «подходит ли
# приём» зависит от ВСЕХ типов удара оружия (руна добавляет второй), а не только от
# одного типа. Метод matches() принимал один тип и потому терял второй — его
# убрали вместе с этой ошибкой, чтобы не осталось второго, неверного способа. Здесь
# лежат только данные приёма.
