extends Resource
class_name ArmorData
## Броня. По GDD 12.8: лёгкая / тяжёлая / функциональная.
## ВАЖНО: «броня» — это поглощение урона ИГРОКОМ. Защита зверя называется
## «панцирь» и живёт в MonsterData.armor.

@export var id: StringName = &""
@export var title: String = ""

## Слот: light / heavy / functional.
@export var slot: StringName = &"light"

@export_range(0, 10, 1) var absorption: int = 0

## Штраф инициативы (GDD 12.9).
@export_range(-3, 0, 1) var initiative_penalty: int = 0

@export_range(0, 200, 1) var price: int = 0

## Текст особого эффекта для функциональной брони.
@export var effect_text: String = ""

@export var icon: Texture2D
## Цвет акцента строкой («#8d8578»): так он читаем в .tres.
@export var accent_color: String = "#8d8578"


func accent() -> Color:
	return Color.from_string(accent_color, Color("#8d8578"))
