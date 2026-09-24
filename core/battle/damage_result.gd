extends RefCounted
class_name DamageResult
## Результат расчёта урона. Хранит не только число, но и все слагаемые:
## без этого не выполнить принцип прозрачности (GDD 12.1) и не показать
## игроку «откуда взялся урон».

var weapon_damage: int = 0
var reading_bonus: int = 0
var combo_bonus: int = 0
var type_multiplier: int = 0
var monster_armor: int = 0
var crit_bonus: int = 0
var crit: bool = false
## Зверь «открыт» (статус open): уязвим для любого удара, +1. Отдельное слагаемое,
## а не добавка к типовому множителю: открытость не про тип урона, и складывать её
## с уязвимостями значило бы обещать игроку в разборе то, чего нет.
var open_bonus: int = 0
var total: int = 0
var min_clamped: bool = false

## Почему типовой бонус такой: «огонь +1», «слабость: лёд +1», «резист: огонь −1».
var type_reasons: PackedStringArray = PackedStringArray()


func breakdown() -> String:
	var parts: PackedStringArray = PackedStringArray()
	parts.append("оружие %d" % weapon_damage)
	if reading_bonus != 0:
		parts.append("чтение %+d" % reading_bonus)
	if combo_bonus != 0:
		parts.append("комбо %+d" % combo_bonus)
	if open_bonus != 0:
		parts.append("открыт %+d" % open_bonus)
	for r in type_reasons:
		parts.append(r)
	if monster_armor != 0:
		parts.append("панцирь −%d" % monster_armor)
	var tail := ""
	if min_clamped:
		tail = " → минимум 1"
	return "%d (%s)%s" % [total, ", ".join(parts), tail]
