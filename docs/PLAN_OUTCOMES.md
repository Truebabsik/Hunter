# Экраны исхода — план реализации

> **Для исполнителя:** обязательный сабскилл — `executing-plans` (или `subagent-driven-development`).
> Шаги помечены чекбоксами `- [ ]`. План адаптирован под проект: **тестового фреймворка нет**,
> роль тестов играют headless-режимы и контроль суммы. Скрипты не обязательно компилируются
> в headless-режиме — там ошибки Godot остаются только в логе движка, поэтому **каждая
> проверка идёт через `--log-file`** (см. «Глобальные ограничения»).

**Цель:** заменить один экран исхода с двумя состояниями на пять состояний
(победа, побег, падение, воскрешение, конец забега), где выбор экрана решает
чистая функция в ядре, а правило двух цен смерти живёт в одной строке.

**Архитектура:** `Outcome` — чистый статический резолвер в `core/ui_data/`.
`HuntResult` остаётся числами и получает три новых поля. `result_screen.gd`
остаётся **одним** экраном и рендерит пять состояний по `outcome`.
`game_root.gd` держит переходы и знает об экранах только он.

**Стек:** Godot 4.7.2, GDScript, `gl_compatibility`. Проверка — headless-прогоны.

**Спека:** `docs/OUTCOMES.md`

## Глобальные ограничения

- **Godot:** `F:\WORK\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe`
- **Проект:** `F:\WORK\hunter`
- **Все прогоны — с логом движка:** `--log-file F:\WORK\hunter\_glog.txt`.
  Без него ошибки скриптов не видны вообще (проверено: прогон «выродился» в 4 строки,
  а причина была только в логе).
- **Не перенаправлять вывод:** `Start-Process -RedirectStandardOutput` подвешивает
  процесс. Запускать через `Start-Process -PassThru -WindowStyle Hidden` и читать отчёты из файлов.
- **Перед прогоном:** закрыть редактор Godot; осиротевшие процессы искать по точному
  имени (`Godot_v4.7.2-stable_win64`), **не** по маске `*odot*` — под неё попадает MCP-сервер.
- **Ядро без движка:** `core/` не использует `Node`, `get_tree()` и сцены. Правило проекта.
- **Числа в `core/`** — только константами, как `MarketData.PRICE_MULTIPLIER`.
- **Godot 4:** у `Dictionary` нет `empty()`, только `is_empty()`. Эта ошибка уже
  роняла сборку молча — при правках проверять `--log-file`.
- **`.tres`:** `load_steps` = внешние + подресурсы + 1. Здесь не трогаем, но помним.
- **Язык:** комментарии, тексты экранов и отчётов — по-русски, как весь проект.
- **Коммитов нет:** рабочий каталог не git-репозиторий. Вместо коммита — отметка
  в конце задачи и строка в `docs/WORKPLAN.md`.

---

### Task 1: Чистый резолвер исхода + режим проверки

**Файлы:**
- Создать: `core/ui_data/outcome.gd`
- Изменить: `main.gd` (добавить обработку `--outcomes` в `_ready`)
- Проверка: `_outcomes_out.txt`

**Интерфейсы:**
- Consumes: ничего
- Produces: `Outcome.VICTORY`, `Outcome.ESCAPE`, `Outcome.DEFEAT`, `Outcome.RESURRECTION`, `Outcome.RUN_OVER` (все `StringName`); `Outcome.resolve(victory: bool, fled: bool, run_over: bool, rank_dropped: bool) -> StringName`

- [ ] **Шаг 1: Написать проверку, которая падает**

Создать `core/ui_data/outcome.gd` с одними константами, без `resolve`:

```gdscript
extends RefCounted
class_name Outcome

const VICTORY := &"victory"
const ESCAPE := &"escape"
const DEFEAT := &"defeat"
const RESURRECTION := &"resurrection"
const RUN_OVER := &"run_over"
```

Добавить в `main.gd` в `_ready()` перед веткой `--probe`:

```gdscript
	if args.has("--outcomes"):
		_check_outcomes()
		get_tree().quit()
		return
```

И сам режим — в конец `main.gd`:

```gdscript
## Таблица решений резолвера исхода. Проверяет ровно то, что легко сломать
## правкой вёрстки: какой экран показывать после боя.
func _check_outcomes() -> void:
	var out: Array[String] = []
	var cases := [
		# победа, побег, конец забега, откат ранга, ожидаемый экран
		[true,  false, false, false, Outcome.VICTORY],
		[false, true,  false, false, Outcome.ESCAPE],
		[false, false, false, true,  Outcome.DEFEAT],
		[false, false, false, false, Outcome.DEFEAT],
		[false, false, true,  true,  Outcome.RUN_OVER],
	]
	var failed := 0
	for c in cases:
		var got: StringName = Outcome.resolve(c[0], c[1], c[2], c[3])
		var ok: bool = got == c[4]
		if not ok:
			failed += 1
		out.append("%s: победа=%s побег=%s конец=%s откат=%s → %s (ждали %s)" % [
			"ок" if ok else "ПРОВАЛ", c[0], c[1], c[2], c[3], got, c[4]])
	out.append("")
	out.append("ПРОВАЛОВ: %d" % failed)
	_write_out("F:/WORK/hunter/_outcomes_out.txt", out)
```

- [ ] **Шаг 2: Прогнать и убедиться, что падает**

```powershell
$godot='F:\WORK\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe'
Remove-Item 'F:\WORK\hunter\_outcomes_out.txt','F:\WORK\hunter\_glog.txt' -EA SilentlyContinue
$p=Start-Process -FilePath $godot -ArgumentList @('--headless','--log-file','F:\WORK\hunter\_glog.txt','--path','F:\WORK\hunter','--','--outcomes') -PassThru -WindowStyle Hidden
$p | Wait-Process -Timeout 120 -EA SilentlyContinue
Select-String -Path 'F:\WORK\hunter\_glog.txt' -Pattern 'SCRIPT ERROR|Parse Error' | ForEach-Object { $_.Line }
```

Ожидается: в логе `Function "resolve()" not found in base GDScript` (или `Invalid call`),
файл `_outcomes_out.txt` не создан либо пуст.

- [ ] **Шаг 3: Реализовать `resolve`**

Дописать в `core/ui_data/outcome.gd`:

```gdscript
## Какой экран показать после боя. Чистая функция: только по состоянию исхода,
## без побочных эффектов и без обращения к UI.
##
## run_over — смерть была окончательной (срок богини вышел). Он важнее победы
## и побега: если забег кончился, показывать надо именно конец.
static func resolve(victory: bool, fled: bool, run_over: bool, _rank_dropped: bool) -> StringName:
	if run_over:
		return RUN_OVER
	if victory:
		return VICTORY
	if fled:
		return ESCAPE
	return DEFEAT
```

**Почему `rank_dropped` не влияет на выбор экрана.** По спеке (§3) он нужен
только чтобы выбрать текст внутри экрана поражения: «РАНГ ПОНИЖЕН» или
«Ранг сохранён». Подпись оставлена намеренно, чтобы интерфейс функции не менялся,
когда это понадобится в Task 4.

- [ ] **Шаг 4: Обновить кэш классов и прогнать**

Новый глобальный класс (`Outcome`) не виден движку, пока не обновлён кэш —
это уже ловилось на `MarketData` (вырожденный прогон без ошибок):

```powershell
$p=Start-Process -FilePath $godot -ArgumentList @('--headless','--path','F:\WORK\hunter','--import') -PassThru -WindowStyle Hidden
$p | Wait-Process -Timeout 180 -EA SilentlyContinue
```

Затем повторить команду Шага 2. Ожидается `ПРОВАЛОВ: 0` и по одной строке «ок» на каждый случай.

- [ ] **Шаг 5: Отметить задачу**

Дописать в `docs/WORKPLAN.md` в раздел «Что дальше» строку о сделанном:
резолвер исхода готов и проверяется режимом `--outcomes` (5 случаев, 0 провалов).

---

### Task 2: Поля исхода в `HuntResult`

**Файлы:**
- Изменить: `core/ui_data/hunt_result.gd`
- Проверка: `_outcomes_out.txt` (расширяется), `--loop`

**Интерфейсы:**
- Consumes: `GameState.grace_active()` (есть), `GameState.days_left()` (есть)
- Produces: `HuntResult.coins_lost: int`, `HuntResult.run_over: bool`

- [ ] **Шаг 1: Добавить поля**

В `core/ui_data/hunt_result.gd` рядом с `bag_lost`:

```gdscript
## Сколько монет сгорело при падении. Отдельно от bag_lost: монеты и ноша
## теряются по-разному, и на экране поражения это две разные строки.
var coins_lost: int = 0
## Смерть была окончательной: срок богини вышел, воскрешения не будет.
var run_over: bool = false
```

- [ ] **Шаг 2: Заполнить `coins_lost` при поражении**

В `_apply_defeat` перед `GameState.coins = 0`:

```gdscript
	coins_lost = GameState.coins
	GameState.coins = 0
```

- [ ] **Шаг 3: Заполнить `run_over` — правило двух цен в одной строке**

В `_apply_defeat` сразу после `coins_lost`:

```gdscript
	# Правило двух цен (GDD 1.3.1): срок идёт — богиня вернёт, смерть обратима.
	# Срок вышел — возвращать некому, и это конец забега. Логика только здесь,
	# чтобы её нельзя было рассинхронизировать с экраном.
	run_over = not GameState.grace_active()
```

- [ ] **Шаг 4: Прогнать цикл и убедиться, что поля не ломают прогон**

```powershell
Remove-Item 'F:\WORK\hunter\_loop_out.txt' -EA SilentlyContinue
$p=Start-Process -FilePath $godot -ArgumentList @('--headless','--log-file','F:\WORK\hunter\_glog.txt','--path','F:\WORK\hunter','--','--loop','10') -PassThru -WindowStyle Hidden
$p | Wait-Process -Timeout 300 -EA SilentlyContinue
Select-String -Path 'F:\WORK\hunter\_glog.txt' -Pattern 'SCRIPT ERROR|Parse Error' | ForEach-Object { $_.Line }
Select-String -Path 'F:\WORK\hunter\_loop_out.txt' -Pattern 'ЛЕГЕНДА|дней' | Select-Object -First 4 | ForEach-Object { $_.Line }
```

Ожидается: ошибок нет; дни по-прежнему 30 при 10 охотах.

---

### Task 3: Счётчики исходов и контроль суммы в прогоне цикла

**Файлы:**
- Изменить: `core/sim/loop_sim.gd`
- Проверка: `_loop_out.txt`

**Интерфейсы:**
- Consumes: `HuntResult.run_over` (Task 2)
- Produces: строки отчёта «исходы: …» и «контроль исходов: …»

- [ ] **Шаг 1: Завести счётчики**

В `_run_player`, рядом с `victories`/`defeats`/`escapes`:

```gdscript
	## Сколько боёв закончилось окончательной смертью. Нужен для контроля суммы:
	## каждый бой обязан дать ровно один исход.
	var run_overs := 0
```

- [ ] **Шаг 2: Считать исходы после `result.apply`**

В блоке, где считаются `victories`/`escapes`/`defeats`:

```gdscript
		if result.run_over:
			run_overs += 1
		if result.victory:
			victories += 1
		elif result.fled:
			escapes += 1
		else:
			defeats += 1
```

- [ ] **Шаг 3: Добавить контроль суммы в отчёт**

После строки с «рынок: …» в конце `_run_player`:

```gdscript
	var outcomes_total := victories + escapes + defeats
	out.append("исходы: побед %d, побегов %d, поражений %d (из них окончательных %d)" % [
		victories, escapes, defeats, run_overs])
	# Контроль суммы: каждый бой даёт ровно один исход. Та же защита, что поймала
	# симулятор, считавший побег поражением («100 поражений» при 71 побеге).
	# Боёв ровно столько же, сколько исходов, поэтому сравниваем с hunt_no.
	out.append("контроль исходов: сумма исходов %d, боёв %d — %s" % [
		outcomes_total, hunt_no, "сходится" if outcomes_total == hunt_no else "РАСХОЖДЕНИЕ"])
```

- [ ] **Шаг 4: Прогнать и проверить сходимость**

Повторить команду Task 2 Шаг 4 и убедиться, что в отчёте есть обе строки
и написано «сходится».

---

### Task 4: Экран исхода на пять состояний

**Файлы:**
- Изменить: `ui/screens/result/result_screen.gd`
- Изменить: `ui/game_root.gd`
- Проверка: `--smoke`, живой прогон через MCP

**Интерфейсы:**
- Consumes: `Outcome.*` (Task 1), `HuntResult.coins_lost`, `HuntResult.run_over` (Task 2), `GameState.days_left()`, `GameState.bag_value()`, `GameState.fame_log`
- Produces: `result_screen.gd` с полем `outcome: StringName`

- [ ] **Шаг 1: Добавить поле состояния и заголовки**

В `result_screen.gd` заменить блок `_render` целиком:

```gdscript
## Какой экран показывать. Ставит game_root через Outcome.resolve — сам экран
## решение не принимает, иначе его нельзя проверить прогоном.
var outcome: StringName = Outcome.VICTORY

const HEADLINES := {
	&"victory": ["ПОБЕДА", "#d8b45a"],
	&"escape": ["ТЫ УШЁЛ", "#9fb08a"],
	&"defeat": ["ТЫ ПАЛ", "#c96a4a"],
	&"resurrection": ["ТЕБЯ ВЕРНУЛИ", "#c8b48a"],
	&"run_over": ["ЗАБЕГ ОКОНЧЕН", "#8d8578"],
}

const BUTTONS := {
	&"victory": "ПРОДОЛЖИТЬ",
	&"escape": "ПРОДОЛЖИТЬ",
	&"defeat": "ДАЛЬШЕ",
	&"resurrection": "ВЕРНУТЬСЯ В ГОРОД",
	&"run_over": "НОВЫЙ ЗАБЕГ",
}
```

- [ ] **Шаг 2: Прокрутка и кнопка по состоянию**

В `_build` обернуть `body` в прокрутку и выставить текст кнопки по состоянию:

```gdscript
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(scroll)

	body = RichTextLabel.new()
	body.bbcode_enabled = true
	body.fit_content = true
	body.custom_minimum_size = Vector2(0, 400)
	body.add_theme_font_size_override("normal_font_size", 18)
	scroll.add_child(body)

	btn = Button.new()
	btn.text = str(BUTTONS.get(outcome, "ПРОДОЛЖИТЬ"))
	btn.pressed.connect(_on_primary)
	col.add_child(btn)
```

Объявить `var btn: Button` рядом с `body` и `headline`.

- [ ] **Шаг 3: Собрать содержимое по состоянию**

```gdscript
func _render() -> void:
	var head: Array = HEADLINES.get(outcome, ["—", "#ffffff"])
	headline.text = str(head[0])
	headline.add_theme_color_override("font_color", Color(str(head[1])))
	if result == null:
		body.text = ""
		return
	match outcome:
		Outcome.RESURRECTION:
			body.text = _text_resurrection()
		Outcome.RUN_OVER:
			body.text = _text_run_over()
		Outcome.ESCAPE:
			body.text = _text_escape()
		Outcome.DEFEAT:
			body.text = _text_defeat()
		_:
			body.text = _text_victory()
```

- [ ] **Шаг 4: Написать пять сборщиков текста**

```gdscript
func _mon_name() -> String:
	var mon: MonsterData = Database.monster(result.monster_id)
	return mon.title if mon != null else String(result.monster_id)


## Победа: награда и подтверждение чтения. Строка «Он задумывал» закрывает
## критерий GDD 13.2 — игрок должен видеть, что было на самом деле.
func _text_victory() -> String:
	var lines: PackedStringArray = PackedStringArray()
	lines.append("[b]%s[/b] — повержен" % _mon_name())
	lines.append("")
	lines.append("Слава: %+d" % result.glory_delta)
	# Добычи может не быть вовсе (победа над видом без трофеев) — тогда строку
	# не показываем, а не печатаем «Добыча:  → в ношу».
	if not result.trophies.is_empty():
		lines.append("Добыча: %s → в ношу" % ", ".join(result.trophies))
	lines.append("")
	lines.append("[color=#d8b45a][b]ДОСЬЕ ПОПОЛНЕНО[/b][/color]")
	if not result.last_scenario_label.is_empty():
		lines.append("  Он задумывал: «%s»" % result.last_scenario_label)
	lines.append("  Новых фактов: %d" % result.dossier_gained)
	lines.append("")
	lines.append("Слава: %d / %d" % [GameState.glory, GameState.next_rank_glory()])
	return "\n".join(lines)


## Побег: не осуждаем. По GDD отступление стоит материи, а не репутации.
func _text_escape() -> String:
	var lines: PackedStringArray = PackedStringArray()
	lines.append("[b]%s[/b] — остался позади" % _mon_name())
	lines.append("")
	lines.append("Брошено добычи: %d монет" % result.bag_lost)
	lines.append("В ноше осталось: на %d монет" % GameState.bag_value())
	lines.append("[color=#9fb08a]Слава не пострадала: отступление не позор.[/color]")
	return "\n".join(lines)


## Падение: три удара по порядку боли. Ранг — настоящая цена, потому что
## жизнью игрок больше не платит (GDD 1.3.1).
func _text_defeat() -> String:
	var lines: PackedStringArray = PackedStringArray()
	lines.append("[b]%s[/b]" % _mon_name())
	lines.append("")
	lines.append("Монеты сгорели: %d" % result.coins_lost)
	lines.append("Ноша осталась там: %d" % result.bag_lost)
	lines.append("Слава: %+d" % result.glory_delta)
	if result.rank_down:
		lines.append("[color=#c96a4a][b]РАНГ ПОНИЖЕН: %s[/b][/color]" % GameState.rank_title())
		lines.append("Клеймо на знаке ранга.")
	else:
		lines.append("Ранг сохранён: %s" % GameState.rank_title())
	lines.append("")
	lines.append("[i]«Ты выжил. Гильдия помнит. Возвращайся.»[/i]")
	return "\n".join(lines)


## Воскрешение: уже не боль, а дар. Остаток дней обязателен — здесь срок
## становится осязаемым, игрок видит его прямо сейчас, а не «45 в начале».
func _text_resurrection() -> String:
	var lines: PackedStringArray = PackedStringArray()
	lines.append("Богиня не объясняет. Она просто не дала умереть.")
	lines.append("")
	var days := GameState.days_left()
	if days > 0:
		lines.append("[b]Осталось дней: %d[/b]" % days)
	else:
		lines.append("[color=#c96a4a][b]СРОК ВЫШЕЛ. Дольше она ждать не будет.[/b][/color]")
	lines.append("Этот поход стоил %d дн." % CityData.days_per_hunt())
	lines.append("")
	lines.append("Не сгорело:")
	lines.append("  • Досье: фактов %d" % _dossier_facts())
	lines.append("  • Навыков: %d" % GameState.skills.size())
	return "\n".join(lines)


## Конец забега: итог пути, а не «ты проиграл». Хроника в обратном порядке —
## сводка говорит, ЧТО успел, хроника — КАК жил.
func _text_run_over() -> String:
	var lines: PackedStringArray = PackedStringArray()
	lines.append("Богиня больше не отвечает.")
	lines.append("")
	lines.append("Ранг: %s        Слава: %d" % [GameState.rank_title(), GameState.glory])
	lines.append("Прожито дней: %d из %d" % [GameState.day, GameState.SURVIVAL_DAYS])
	lines.append("Достижений: %d из %d" % [
		GameState.unlocked_achievements(), Achievements.total()])
	lines.append("")
	lines.append("[b]ХРОНИКА (%d записей)[/b]" % GameState.fame_log.size())
	# Последние 40 записей, новые сверху. Обрез обязателен и обязан быть назван:
	# молчаливое усечение читается как «хроника оборвалась».
	var shown := 0
	for i in range(GameState.fame_log.size() - 1, -1, -1):
		if shown >= 40:
			break
		var e: Dictionary = GameState.fame_log[i]
		lines.append("День %d  ▸ %s   %s" % [e["day"], str(e["kind"]).to_upper(), e["title"]])
		shown += 1
	if GameState.fame_log.size() > shown:
		lines.append("[color=#8d8578]…и ещё %d записей раньше[/color]" % (
			GameState.fame_log.size() - shown))
	return "\n".join(lines)


## Сколько фактов накоплено в досье по всем видам.
func _dossier_facts() -> int:
	var total := 0
	for id in GameState.dossier.keys():
		var e: Dictionary = GameState.dossier[id]
		for section in ["signals", "decoys", "scenarios", "weaknesses", "combos"]:
			total += (e[section] as Array).size()
	return total


## Основная кнопка. На «конце забега» она сбрасывает забег, на «поражении» —
## ведёт на экран воскрешения; остальное уходит в город. Решение о переходе
## принимает game_root, здесь только сигнал.
func _on_primary() -> void:
	continue_requested.emit()
```

- [ ] **Шаг 5: Провести переходы в `game_root.gd`**

Заменить `_on_battle_finished` и добавить переход «падение → воскрешение»:

```gdscript
func _on_battle_finished(result: HuntResult) -> void:
	result.order_rank = hunt_order_rank
	result.apply(hunt_side_encounter)
	last_result = result
	var outcome := Outcome.resolve(
		result.victory, result.fled, result.run_over, result.rank_down)
	_show_result(outcome)


func _show_result(outcome: StringName) -> void:
	var scr := _swap(RESULT_SCENE)
	if scr == null:
		return
	scr.result = last_result
	scr.outcome = outcome
	if outcome == Outcome.RESURRECTION:
		# После воскрешения забег не кончается, но и в бой игрок не возвращается:
		# он идёт в город обобранным, а контракт остаётся незакрытым.
		scr.continue_requested.connect(_show_city)
	elif outcome == Outcome.RUN_OVER:
		scr.continue_requested.connect(_on_new_run)
	elif outcome == Outcome.DEFEAT:
		# Падение — два такта: сначала боль, потом дар (см. docs/OUTCOMES.md).
		scr.continue_requested.connect(_show_resurrection)
	else:
		scr.continue_requested.connect(_show_city)


func _show_resurrection() -> void:
	_show_result(Outcome.RESURRECTION)


func _on_new_run() -> void:
	GameState.reset()
	_show_city()
```

- [ ] **Шаг 6: Проверить, что всё парсится и бой не сломан**

```powershell
Remove-Item 'F:\WORK\hunter\_smoke_out.txt' -EA SilentlyContinue
$p=Start-Process -FilePath $godot -ArgumentList @('--headless','--log-file','F:\WORK\hunter\_glog.txt','--path','F:\WORK\hunter','--','--smoke') -PassThru -WindowStyle Hidden
$p | Wait-Process -Timeout 180 -EA SilentlyContinue
Select-String -Path 'F:\WORK\hunter\_glog.txt' -Pattern 'SCRIPT ERROR|Parse Error' | ForEach-Object { $_.Line }
Get-Content 'F:\WORK\hunter\_smoke_out.txt' -Encoding UTF8 | Select-Object -Last 4
```

Ожидается: ошибок нет, `--smoke` пишет итог боя.

- [ ] **Шаг 7: Проверить экран в живой игре**

Через MCP (`godot_runtime_play_scene` → `godot_runtime_find_ui_elements`) дойти
до экрана исхода и прочитать его тексты. Это единственная часть, которую прогон
не проверяет.

---

### Task 5: Сводная проверка и документация

**Файлы:**
- Изменить: `README.md`, `docs/WORKPLAN.md`
- Проверка: все режимы

**Интерфейсы:**
- Consumes: всё предыдущее
- Produces: ничего

- [ ] **Шаг 1: Прогнать все режимы и убедиться, что зелено**

```powershell
$modes = @('--validate','--art','--repeat','--orders','--smoke','--prose','--outcomes')
foreach ($m in $modes) {
  $p=Start-Process -FilePath $godot -ArgumentList @('--headless','--log-file','F:\WORK\hunter\_glog.txt','--path','F:\WORK\hunter','--',$m) -PassThru -WindowStyle Hidden
  $p | Wait-Process -Timeout 300 -EA SilentlyContinue
  if (-not $p.HasExited) { Stop-Process -Id $p.Id -Force }
  "$m код=$($p.ExitCode)"
}
$p=Start-Process -FilePath $godot -ArgumentList @('--headless','--log-file','F:\WORK\hunter\_glog.txt','--path','F:\WORK\hunter','--','--loop','10') -PassThru -WindowStyle Hidden
$p | Wait-Process -Timeout 400 -EA SilentlyContinue
Select-String -Path 'F:\WORK\hunter\_glog.txt' -Pattern 'SCRIPT ERROR|Parse Error' | ForEach-Object { $_.Line }
```

Ожидается: пустой вывод последней команды (ошибок нет) и «сходится» в контроле исходов.

- [ ] **Шаг 2: Обновить документацию**

- `docs/WORKPLAN.md`: перенести «экраны исхода» из планов в сделанное, с числами
  (5 состояний, 0 провалов в таблице, контроль суммы сходится).
- `README.md`: в разделе о бое упомянуть, что исходов четыре и показываются они
  пятью состояниями одного экрана, а решение принимает `Outcome.resolve`.

- [ ] **Шаг 3: Отметить выполнение**

Записать в `docs/WORKPLAN.md` строку о том, что спека `docs/OUTCOMES.md`
реализована, и перечислить, что осталось (вёрстка экранов на реальных шрифтах,
арт для фонов следа — `docs/ART_TRAIL.md`).

---

## Что этот план НЕ делает

- **Не рисует фоны** для фаз следа: промпты отдельно, в `docs/ART_TRAIL.md`.
- **Не делает экран снаряжения на следe**: это следующая отдельная работа
  (см. `docs/WORKPLAN.md`, раздел про модификаторы).
- **Не чинит достижения**, если те считают побег поражением. Отмечено как открытый
  вопрос в спеке (§10), проверяется отдельной задачей.
- **Не сохраняет хронику между забегами**: в текущем дизайне забег один.
