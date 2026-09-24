extends Control
## Корневой экран: держит переходы между городом, «следом» и боем.
##
## Экраны не знают друг о друге — только этот узел. Так каждый экран можно
## проверить отдельно, а порядок переходов задаётся в одном месте.

const CITY_SCENE := "res://ui/screens/city/city_screen.tscn"
const TRAIL_SCENE := "res://ui/screens/trail/trail_screen.tscn"
const BATTLE_SCENE := "res://ui/screens/battle/battle_screen.tscn"
const RESULT_SCENE := "res://ui/screens/result/result_screen.tscn"
const PREP_SCENE := "res://ui/screens/prep/prep_screen.tscn"

var current: Node = null

## Контекст текущей охоты.
var trail_stages: Array[Dictionary] = []
var hunt_monster_id: StringName = &""
var hunt_order_rank: int = 0
var hunt_side_encounter: bool = false
var last_result: HuntResult = null


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color("#0d0c0b")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	_show_city()


func _swap(path: String) -> Node:
	if current != null:
		current.queue_free()
		current = null
	var packed: PackedScene = load(path)
	if packed == null:
		push_error("Экран не собран: %s" % path)
		return null
	var inst: Node = packed.instantiate()
	add_child(inst)
	current = inst
	return inst


func _show_city() -> void:
	var scr := _swap(CITY_SCENE)
	if scr == null:
		return
	scr.order_taken.connect(_on_order_taken)
	scr.quit_requested.connect(_on_quit_requested)


func _on_quit_requested() -> void:
	get_tree().quit()


func _on_order_taken(monster_id: StringName, order_rank: int, side_encounter: bool) -> void:
	hunt_monster_id = monster_id
	hunt_order_rank = order_rank
	hunt_side_encounter = side_encounter
	GameState.current_monster_id = monster_id
	GameState.current_order_rank = order_rank

	var mon: MonsterData = Database.monster(monster_id)
	if mon == null:
		push_error("Заказ на неизвестный вид: %s" % monster_id)
		_show_city()
		return

	# Тон «следа»: повторная охота даёт вариант «знакомый» (GDD 10.6).
	var is_repeat := GameState.kill_counts(monster_id) > 0
	var rng := RNGService.mechanics(0)
	trail_stages = HuntTrail.build(mon, is_repeat, side_encounter, rng)
	if trail_stages.is_empty():
		_start_battle()
		return
	var scr := _swap(TRAIL_SCENE)
	if scr == null:
		return
	scr.stages = trail_stages
	# Фон локации ставим ПОСЛЕ инстанцирования: узлы сцены создаются в её _ready(),
	# и до этого обращаться к ним нельзя.
	scr.setup_location(mon)
	scr.trail_finished.connect(_show_prep)
	scr.trail_aborted.connect(_show_city)


## Подготовка перед боем (GDD 10.2, фаза 5): здесь оружие и руны меняются
## бесплатно, потому что это подготовка, а не ход. В бою смена тоже не стоит
## отдельного хода: удар в этом ходу просто идёт новым оружием.
func _show_prep() -> void:
	var scr := _swap(PREP_SCENE)
	if scr == null:
		return
	# setup_location после инстанцирования: узлы сцены создаются в её _ready().
	scr.setup_location(Database.monster(hunt_monster_id))
	scr.prep_finished.connect(_start_battle)


func _start_battle() -> void:
	var scr := _swap(BATTLE_SCENE)
	if scr == null:
		return
	scr.battle_finished.connect(_on_battle_finished)
	scr.setup_hunt(hunt_monster_id, hunt_order_rank)

func _on_battle_finished(result: HuntResult) -> void:
	result.order_rank = hunt_order_rank
	result.apply(hunt_side_encounter)
	last_result = result
	var outcome := Outcome.resolve(
		result.victory, result.fled, result.run_over, result.rank_down)
	_show_result(outcome)


## Показать экран исхода. Переходы задаются ЗДЕСЬ и только здесь: экраны не
## знают друг о друге, поэтому порядок можно прочитать в одном месте.
func _show_result(outcome: StringName) -> void:
	var scr := _swap(RESULT_SCENE)
	if scr == null:
		return
	scr.result = last_result
	scr.outcome = outcome
	if outcome == Outcome.DEFEAT:
		# Падение — два такта: сначала боль, потом дар (docs/OUTCOMES.md §2).
		scr.continue_requested.connect(_show_resurrection)
	elif outcome == Outcome.RESURRECTION:
		# После воскрешения забег не кончается, но и в бой игрок не возвращается:
		# он идёт в город обобранным, а контракт остаётся незакрытым.
		scr.continue_requested.connect(_show_city)
	elif outcome == Outcome.RUN_OVER:
		scr.continue_requested.connect(_on_new_run)
	else:
		scr.continue_requested.connect(_show_city)


func _show_resurrection() -> void:
	_show_result(Outcome.RESURRECTION)


func _on_new_run() -> void:
	GameState.reset()
	_show_city()
