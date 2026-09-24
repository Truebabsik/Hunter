extends RefCounted
class_name BattleTally
## Учёт боя для итога охоты: урон, промахи, идеальные чтения.
##
## Почему не в экране. Эти числа идут в HuntResult, от которого зависят достижения
## («Победа без единого промаха», «Победа одним оружием», «без брони»). Правило
## «что считать промахом» — это правило, а не оформление: экран, решающий его сам,
## задаёт смысл достижения. К тому же рядом уже был второй путь учёта: движок
## складывает урон в события (`monster_damaged.amount`), и два источника одного
## числа расходятся молча — тот же класс, что копии названий типов.
##
## Правило промаха перенесено сюда ДОСЛОВНО, включая неочевидную часть: смена
## инструмента без удара — не промах. Игрок не ошибся, он выбрал не бить.
##
## Урон берётся из исхода, а не из событий, потому что исход отдаёт оба числа
## сразу (damage_to_monster и damage_to_hunter) и уже согласован с движком.

var damage_dealt: int = 0
var damage_taken: int = 0
var misses: int = 0
var perfect_reads: int = 0


func reset() -> void:
	damage_dealt = 0
	damage_taken = 0
	misses = 0
	perfect_reads = 0


## Записать исход хода. Пустой исход игнорируется: так вызывающий может передать
## результат движка не проверяя его на пустоту.
func add(outcome: Dictionary) -> void:
	if outcome.is_empty():
		return
	damage_dealt += int(outcome.get("damage_to_monster", 0))
	damage_taken += int(outcome.get("damage_to_hunter", 0))
	var attack := bool(outcome.get("attack", true))
	if not attack:
		return
	if bool(outcome.get("read_correct", false)):
		if outcome.get("reading", -1) == DamageCalc.Reading.PERFECT:
			perfect_reads += 1
	else:
		misses += 1


## Перенести накопленное в итог охоты. Отдельным методом, потому что часть полей
## итога (каким оружием играл, видел ли подсказку) экран знает сам и передаёт
## параметрами.
func apply_to(result: HuntResult, switched_weapon: bool, saw_hint: bool) -> void:
	result.perfect_reads = perfect_reads
	result.misses = misses
	result.damage_taken = damage_taken
	result.damage_dealt = damage_dealt
	result.switched_weapon = switched_weapon
	result.saw_hint = saw_hint
