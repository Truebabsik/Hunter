extends RefCounted
class_name SeedSource
## Воспроизводимый источник случайности для боя.
##
## Зачем отдельный объект: глобальный RNGService даёт один поток на бой, а раунду
## нужен свой. Кроме того, симулятору нужна независимость от глобального состояния,
## иначе порядок прогонов влияет на результат.
##
## Схема: seed_round = hash(run_seed, battle_index, round, salt).
## Потоки механики и текста разведены солью — решения игрока не сдвигают фразы.

var run_seed: int
var battle_index: int


func _init(p_run_seed: int, p_battle_index: int) -> void:
	run_seed = p_run_seed
	battle_index = p_battle_index


func round_rng(round_index: int, salt: StringName) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%d:%d:%d:%s" % [run_seed, battle_index, round_index, salt])
	return rng
