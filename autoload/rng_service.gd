extends Node
## Единственный источник случайности в игре.
##
## Зачем сервис, а не randf(): нужна воспроизводимость. Один мастер-сид забега
## даёт одинаковые бои при одинаковых решениях игрока. Отдельный поток для текста
## обязателен — иначе выбор инструмента сдвигает последовательность и ломает
## воспроизводимость бага.

var run_seed: int = 0

var _battle_index: int = 0


func _ready() -> void:
	if run_seed == 0:
		randomize()
		run_seed = randi()


func start_run(seed_value: int = 0) -> void:
	run_seed = seed_value if seed_value != 0 else randi()
	_battle_index = 0


func next_battle() -> void:
	_battle_index += 1


## Поток для механики: выбор сценария, контр-приёмы, адаптация.
## Зависит только от номера боя и раунда — решения игрока его не сдвигают.
func mechanics(round_index: int) -> RandomNumberGenerator:
	return _stream(round_index, &"mechanics")


## Поток для текста: выбор фраз. Отделён от механики намеренно.
func text(round_index: int) -> RandomNumberGenerator:
	return _stream(round_index, &"text")


func _stream(round_index: int, salt: StringName) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	var h := hash("%d:%d:%d:%s" % [run_seed, _battle_index, round_index, salt])
	rng.seed = h
	return rng


func battle_index() -> int:
	return _battle_index
