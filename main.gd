extends Node
## Точка входа. Одна и та же для игры и для headless-прогонов.
##
## ЗАДАЧА ЭТОГО ФАЙЛА — РАЗОБРАТЬ АРГУМЕНТЫ И ПОЗВАТЬ. Здесь не должно быть
## проверок: они лежат в `core/sim/checks/logic_checks.gd` (те, что считаются на
## ядре) и `ui/checks/ui_checks.gd` (те, которым нужны сцены). Раньше проверки
## занимали больше половины этого файла и были перемешаны с рантаймом.
##
## Запуск игры:      Godot_..._console.exe --path F:\WORK\hunter
## Симулятор:        ... --headless --path F:\WORK\hunter -- --sim --battles 1000
## Инварианты:       ... -- --validate
## Ход и смена:      ... -- --swap
## Экран подготовки: ... -- --prep
## Дым экрана боя:   ... -- --smoke
## Полный цикл:      ... -- --loop 10
## Метрики арта:     ... -- --art
## Замер окон:       ... -- --ui          (БЕЗ --headless: нужен размер окна)
## Скриншоты:        ... -- --shots       (БЕЗ --headless)
##
## ВАЖНО: этот файл должен парситься даже когда часть системы ещё не написана.
## Поэтому внешние скрипты грузятся через load(), а не preload(): ошибка парсинга
## в _ready() оставила бы Godot в бесконечном цикле без quit().
##
## ВАЖНО ПРО ЗАПУСК: результаты режимов пишутся в файлы самим Godot (FileAccess),
## а не читаются из stdout. Перенаправление вывода на этой машине подвешивает
## процесс: powershell -RedirectStandardOutput ждёт закрытия канала, которого не
## происходит, и Godot выглядит «зависшим без вывода», хотя на самом деле уже
## отработал и записал отчёт. Отсюда правило: запускать без перенаправления, а
## результат читать из файла (_art_out.txt и т.д.).
##
## ВАЖНО ПРО РАЗДЕЛИТЕЛЬ «--»: режим обязан идти ПОСЛЕ «--». Без него Godot
## считает флаг своим, OS.get_cmdline_user_args() остаётся пустым, _ready() не
## находит режима и уходит в _open_game() — а в headless игра крутится вечно:
## ни вывода, ни отчёта, ни quit(). Выглядит как «движок завис на старте», хотя
## движок исправен. Правильно:
##     ... --headless --path F:\WORK\hunter -- --prep --log-file ...\_glog.txt
## Проверено: без «--» процесс висит, с «--» режим отрабатывает и пишет отчёт.
##
## Запускать проверки через tools/run_headless.ps1: он ставит «--» сам, гасит
## процесс через --quit-after (страховка от вечного цикла) и печатает отчёты.

const GAME_ROOT := "res://ui/game_root.tscn"


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var mode := _mode_of(args)

	# Режимы, которым нужны сцены: они получают `self` как хост и сами ждут кадры.
	match mode:
		"--prep":
			print(await UiChecks.prep(self))
			get_tree().quit()
			return
		"--smoke":
			print(await UiChecks.smoke(self))
			get_tree().quit()
			return
		"--ui":
			print(await UiChecks.measure_ui(self))
			get_tree().quit()
			return
		"--shots":
			print(await UiChecks.capture_shots(self))
			get_tree().quit()
			return
		"--orders":
			CityData.debug_orders()
			get_tree().quit()
			return

	# Режимы, которые считаются на ядре и не трогают дерево узлов.
	var line := ""
	match mode:
		"--validate":
			line = LogicChecks.validate()
		"--outcomes":
			line = LogicChecks.outcomes()
		"--swap":
			line = LogicChecks.swap()
		"--art":
			line = LogicChecks.art()
		"--repeat":
			line = LogicChecks.repeats()
		"--prose":
			line = LogicChecks.prose()
		"--probe":
			line = LogicChecks.probe()
		"--sim":
			line = LogicChecks.sim(args)
		"--loop":
			line = LogicChecks.loop(args)
		_:
			_open_game()
			return

	print(line)
	get_tree().quit()


## Режим из аргументов: первый флаг, который знает точка входа. Именно ФЛАГ, а не
## значение: `--loop 10` задаёт режим «loop», а `10` — его параметр.
func _mode_of(args: PackedStringArray) -> String:
	for a in args:
		if a.begins_with("--"):
			return a
	return ""


func _open_game() -> void:
	if not ResourceLoader.exists(GAME_ROOT):
		push_warning("Корневая сцена ещё не собрана: %s" % GAME_ROOT)
		return
	var packed: PackedScene = load(GAME_ROOT)
	if packed == null:
		return
	add_child(packed.instantiate())
