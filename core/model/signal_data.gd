extends Resource
class_name SignalData
## Опорный сигнал или ложный след.
##
## Один сигнал = один слот прозы (см. GDD 3.2). Фразы ищутся в пуле по полям
## monster_id + scenario_id + slot + role.

## Уникальный ключ, например "hruz.pose.crouch". По нему симулятор считает,
## сколько раз сигнал выпадал — критерий «текст не повторяется» (GDD 13.2).
@export var id: StringName = &""

## Какой слот прозы занимает сигнал.
@export var slot: StringName = &""

## Короткая формулировка для досье и разбора: «припадает к земле».
@export var label: String = ""

## К какому виду относится. Пусто = общий сигнал любого вида (среда, погода).
@export var monster_id: StringName = &""

## К какому сценарию относится. Пусто = общий ложный след вида.
@export var scenario_id: StringName = &""

## Теги для правил совместимости: "action", "comparison", "sound", "conflict:expand"...
@export var tags: PackedStringArray = PackedStringArray()
