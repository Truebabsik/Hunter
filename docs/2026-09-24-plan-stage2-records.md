# Этап 2 переноса (2а и 2б) — план реализации

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development (recommended) or executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Заменить независимые списки уязвимостей и резистов моделью записей «тип **и** дистанция», довести восемь мест чтения до новой модели и привести таблицы семи видов к решению D21.

**Architecture:** Запись — `{types, ranges}` с пустым множеством в значении «любой». Вся арифметика модификаторов и тексты причин живут в `MonsterData` — одном источнике на правило. Читатели (`damage_calc`, валидатор, досье, совет, выбор инструмента ботом) перестают знать про структуру записи и спрашивают у модели. Данные переводятся **после** кода, чтобы каждый коммит оставлял игру играбельной.

**Tech Stack:** Godot 4.7.2, GDScript. Проверки — headless-режимы движка, отчёты читаются файлами.

**Spec:** `docs/2026-09-24-migration-to-v1.10-design.md` (§2 модель, §2.3 целевые данные, §3 этапы 2а/2б)
**Дизайн:** `docs/dizain_hunter.md` §12.3.1 и `docs/delta-D23-resist-records-2026-09-24.md`

## Global Constraints

- Движок: `F:\WORK\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe`, проект `F:\WORK\hunter`.
- Разделитель `--` перед режимом **обязателен**, иначе `main.gd` не найдёт режим.
- Результат читать **из файла отчёта**, не из консоли; в PowerShell — `Get-Content <файл> -Encoding UTF8`.
- **Перед каждым прогоном удалять файл отчёта**: стухший отчёт выглядит как успех.
- `core/` — чистый GDScript: ни `Node`, ни `SceneTree`, ни сцен.
- Отступы — **табы**. Правки `.gd` и `.tres` — только инструментом `edit` (`Set-Content -Encoding UTF8` добавляет BOM и пачкает дифф).
- **Проверка, не показавшая красного на сломанном поведении, не считается проверкой.** Красное обязано быть на **достижимом** состоянии — объяснить в отчёте.
- Коммит после каждой задачи, сообщение по-русски с объяснением «почему».
- Только ветка `migration/v1.10-stage2` (создать от `main`). Не трогать `docs/dizain_hunter_old.md` — не отслеживается намеренно.

## Что уже сделано и на что опираться

- Этап 1 закрыт и влит в `main`: минимум 1 урона зверя, фазы Ламента, симметрия рун (D04), снятие бонуса оружия к инициативе (D20).
- `--probe` входит в прогон всех режимов (`tools/run_checks.cmd`), и `SKIP` теперь ломает вердикт.
- В `--probe` живут четыре сторожа этапа 1; их не переписывать.
- Открытый дефект Д1 из спеки §7.8 (знак штрафа инициативы тяжёлой брони) чинится в Task 5 этого плана.

---

## Файловая структура

| Файл | Ответственность | Что с ним |
|---|---|---|
| `core/model/monster_data.gd` | Модель записей и вся арифметика модификаторов | Основная правка |
| `core/battle/damage_calc.gd` | Формула урона; спрашивает модель | Переписать блок уязвимостей/резистов |
| `core/sim/content_validator.gd` | Инварианты контента | Три проверки + запрет пустой записи |
| `core/sim/loop_sim.gd` | Выбор инструмента ботом | Иначе бот собирает несуществующую слабость |
| `core/ui_data/dossier_text.gd` | Строки уязвимостей/резистов для досье | Построчный вывод записей |
| `ui/screens/city/city_screen.gd` | Совет Старика | То же |
| `core/battle/dossier_recorder.gd` | Запись слабости в досье | То же |
| `content/monsters/*.tres` (7) | Данные видов | Переписать записи |
| `core/sim/checks/logic_checks.gd` | Сторожа | Новый блок: связка по семи видам |

**Порядок намеренный: код → данные.** Новая модель читает записи; если сначала переписать `.tres`, игра сломается до правки читателей. Поэтому в Task 1 у старых полей остаётся временный переходник, который снимается в Task 2.

---

## Task 1: Модель записей и её API (этап 2а, часть 1)

**Files:**
- Modify: `core/model/monster_data.gd`
- Modify: `content/monsters/lament_monster.tres` (только имена ключей фаз — их читает новый API)
- Test: `core/sim/checks/logic_checks.gd` (функция `_status_mechanics`, блок в конец перед `return out`)

**Interfaces:**
- Consumes: `MonsterData.PHYSICAL_TYPES`, `TYPE_PHYSICAL`.
- Produces (этим пользуются Task 2–5):
  - `weakness_rules: Array`, `resist_rules: Array` — записи `{"types": Array, "ranges": Array}`
  - `static func rule_applies(rule: Dictionary, type_id: StringName, range_id: StringName) -> bool`
  - `static func rule_types_ru(rule: Dictionary) -> PackedStringArray`
  - `func weakness_modifier(type_id, range_id, phase: Dictionary = {}) -> int`
  - `func resist_modifier(type_id, range_id) -> int`
  - `func modifier_reasons(types_hit: Array, range_id, phase: Dictionary = {}) -> Array[String]`
  - `func weakness_lines() -> PackedStringArray`, `func resist_lines() -> PackedStringArray`
  - `func is_weak_to_type(type_id, range_id) -> bool`
  - `func weakness_type_hint() -> StringName` (добавляется в Task 4 для бота)
  - фаза: ключ `weak_rules` вместо `weak_types`/`weak_ranges`; `resist_types`/`resist_ranges` в фазах больше не читаются
  - внутренние (не для внешних вызовов): `_type_matches`, `_matching_type`, `_hit_label`, `_rule_lines`

- [ ] **Step 1: Написать падающую проверку связки**

Добавить в конец `_status_mechanics()` перед `return out`:

```gdscript
	# D23: запись уязвимости/резиста — пара множеств {types, ranges}. Связка
	# «тип И дистанция» обязана работать: при старом коде (два независимых
	# списка) «лёд (дальний)» давал +2, потому что срабатывали обе координаты.
	#
	# Достижимое состояние: Хруз, праща (дробящее, дальняя) с руной льда.
	# Цель D21 — +1; старый код давал +2.
	var d23_mon := MonsterData.new()
	d23_mon.id = &"d23_hruz_probe"
	d23_mon.title = "Проба связки"
	d23_mon.max_hp = 12
	d23_mon.armor = 0
	d23_mon.weakness_rules = [
		{"types": ["ice"], "ranges": ["ranged"]},
		{"types": ["poison"], "ranges": []},
	]
	d23_mon.resist_rules = []
	var d23_sling := WeaponData.new()
	d23_sling.id = &"d23_sling"
	d23_sling.range_id = MonsterData.RANGE_RANGED
	d23_sling.damage_type = MonsterData.TYPE_CRUSH
	d23_sling.base_damage = 3
	d23_sling.rune_type = MonsterData.TYPE_ICE
	var d23_hit := DamageCalc.player_damage(
		d23_sling, d23_mon, DamageCalc.Reading.COUNTER, false, 0, 0, {}, 0.0, null)
	var d23_reasons := ", ".join(d23_hit.type_reasons)
	out.append("D23 связка: урон %d, разбор [%s]" % [d23_hit.total, d23_reasons])
	# Три требования сразу: связка даёт ровно +1, запись без ranges работает
	# на любой дистанции, и разбор называет «лёд (дальний)» один раз.
	if d23_hit.type_multiplier == 1 and d23_reasons.count("лёд") == 1:
		out.append("ок D23 связки: «тип И дистанция» даёт +1, а не +2")
	else:
		out.append("ПРОВАЛ D23 связки: множитель %d (ждали +1), разбор «%s»" % [
			d23_hit.type_multiplier, d23_reasons])
```

- [ ] **Step 2: Прогнать и убедиться, что КРАСНЕЕТ**

```
cmd /c "F:\WORK\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe --headless --path F:\WORK\hunter --quit-after 900 -- --probe --log-file F:\WORK\hunter\_glog.txt"
```

Отчёт — `F:\WORK\hunter\_probe_out.txt`. Ожидается `ПРОВАЛ D23 связки: множитель 2 …` (или ошибка скрипта: у `MonsterData` ещё нет `weakness_rules` — это тоже красное, годится, но тогда переходи к шагу 3 и получи настоящий красный после появления поля).

**Если проверка зелёная — остановиться: она ничего не сторожит.**

- [ ] **Step 3: Добавить модель в `MonsterData`**

Заменить блок полей уязвимостей (`@export var weakness_types` … `@export var type_resist`) на:

```gdscript
@export_group("Уязвимости")
## Записи уязвимостей: [{"types": ["ice"], "ranges": ["ranged"]}].
## Пустое множество = «любой». Запись срабатывает, когда ТИП удара входит
## в types И дистанция входит в ranges (D23, GDD 12.3.1).
## Каждая запись даёт ровно +1.
@export var weakness_rules: Array = []
## Записи резистов — та же форма; каждая даёт −1.
@export var resist_rules: Array = []
```

Ниже добавить API:

```gdscript
## --- Записи уязвимостей и резистов (D23, GDD 12.3.1) -----------------------

## Срабатывает ли запись по этой координате удара. Пустое множество = «любой».
static func rule_applies(rule: Dictionary, type_id: StringName, range_id: StringName) -> bool:
	var types := PackedStringArray(rule.get("types", []))
	if types.size() > 0:
		var hit := false
		for t in types:
			if _type_matches(StringName(t), type_id):
				hit = true
				break
		if not hit:
			return false
	var ranges := PackedStringArray(rule.get("ranges", []))
	if ranges.size() > 0:
		if not ranges.has(String(range_id)):
			return false
	return true


## Совпадает ли записанный тип с типом удара. Легаси-ключ "physical"
## покрывает все три физических подтипа — на нём держатся старые таблицы.
static func _type_matches(recorded: StringName, hit: StringName) -> bool:
	if recorded == hit:
		return true
	return recorded == TYPE_PHYSICAL and is_physical_subtype(hit)


## Типы записи, переведённые в читаемые названия («лёд»), для текстов.
static func rule_types_ru(rule: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	for t in PackedStringArray(rule.get("types", [])):
		out.append(CityData.type_ru(StringName(t)))
	return out


## Сумма уязвимостей по координате удара. Фаза ЗАМЕНЯЕТ базовые уязвимости,
## если у неё задан weak_rules (GDD 4.8: «в истощении он открыт»).
func weakness_modifier(type_id: StringName, range_id: StringName, phase: Dictionary = {}) -> int:
	var rules: Array = weakness_rules
	if phase.has("weak_rules"):
		rules = phase["weak_rules"]
	var sum := 0
	for r in rules:
		if rule_applies(r as Dictionary, type_id, range_id):
			sum += 1
	return sum


## Сумма резистов по координате удара. Резисты фаза НЕ меняет: D21.E говорит,
## что резист действует все три фазы одинаково, а таблица фаз §4.8 колонки
## резистов не имеет вовсе.
func resist_modifier(type_id: StringName, range_id: StringName) -> int:
	var sum := 0
	for r in resist_rules:
		if rule_applies(r as Dictionary, type_id, range_id):
			sum += 1
	return sum


## Модификатор по всем типам одного удара (базовый тип оружия и элемент руны)
## плюс причины для разбора. Один источник правила: и число, и текст.
##
## КЛЮЧЕВОЕ: каждая запись срабатывает НЕ БОЛЕЕ ОДНАЖДЫ на удар. Если запись
## покрывает и физический тип, и элемент руны (`types:[physical]` плюс удар
## дробящим с руной огня), наивный перебор по типам выдал бы две строки и +2 —
## ровно тот дефект, ради которого вводится модель. Поэтому по типам ищем
## совпадение, а причину добавляем одну.
func modifier_reasons(types_hit: Array, range_id: StringName, phase: Dictionary = {}) -> Array[String]:
	var out: Array[String] = []
	var weak_rules_used: Array = weakness_rules
	if phase.has("weak_rules"):
		weak_rules_used = phase["weak_rules"]
	for rule_v in weak_rules_used:
		var rule := rule_v as Dictionary
		var rtype := _matching_type(rule, types_hit, range_id)
		if rtype != &"":
			out.append("слабость: %s +1" % _hit_label(rtype, types_hit))
	for rule_v in resist_rules:
		var rule := rule_v as Dictionary
		var rtype := _matching_type(rule, types_hit, range_id)
		if rtype != &"":
			out.append("резист: %s −1" % _hit_label(rtype, types_hit))
	return out


## Первый тип удара (в порядке перебора), на котором запись срабатывает.
## Пустая строка, если запись не срабатывает вовсе. Нужна, чтобы запись
## срабатывала один раз, а не по разу на каждый совпавший тип.
func _matching_type(rule: Dictionary, types_hit: Array, range_id: StringName) -> StringName:
	for type_v in types_hit:
		var type_id := StringName(type_v)
		if rule_applies(rule, type_id, range_id):
			return type_id
	return &""


## Короткая подпись координаты для разбора: у руны помечаем «(руна)».
## Руна — всё, что не первый тип удара: первый всегда базовый тип оружия.
func _hit_label(type_id: StringName, types_hit: Array) -> String:
	var is_base := types_hit.size() > 0 and StringName(types_hit[0]) == type_id
	var ru := CityData.type_ru(type_id)
	return ru if is_base else "%s (руна)" % ru


## Уязвим ли вид к этому типу на этой дистанции. Нужно валидатору.
func is_weak_to_type(type_id: StringName, range_id: StringName) -> bool:
	return weakness_modifier(type_id, range_id) > 0


## Уязвимости строками для досье и совета: одна строка на запись.
func weakness_lines() -> PackedStringArray:
	return _rule_lines(weakness_rules)


## Резисты строками для досье и совета: одна строка на запись.
func resist_lines() -> PackedStringArray:
	return _rule_lines(resist_rules)


func _rule_lines(rules: Array) -> PackedStringArray:
	var out := PackedStringArray()
	for rule_v in rules:
		var parts := rule_types_ru(rule_v as Dictionary)
		for r in PackedStringArray((rule_v as Dictionary).get("ranges", [])):
			parts.append(CityData.range_ru(StringName(r)))
		out.append(", ".join(parts))
	return out
```

- [ ] **Step 4: Перевести фазы Ламента на `weak_rules`**

В `content/monsters/lament_monster.tres` в трёх записях массива `phases` заменить
`"weak_types"`/`"weak_ranges"` на `"weak_rules"`, а `"resist_types"`/`"resist_ranges"`
удалить (пустые словари больше не читаются и вводят в заблуждение). Для фазы `worn`:

```
"weak_rules": [{"types": [], "ranges": ["melee"]}, {"types": ["poison"], "ranges": []}],
```

Для фаз `rage` и `calm` — `"weak_rules": [],`.

- [ ] **Step 5: Прогнать и убедиться, что ЗЕЛЕНО**

Та же команда. Ожидается `ок D23 связки: «тип И дистанция» даёт +1, а не +2`, и ни одного `ПРОВАЛ` во всём отчёте.

- [ ] **Step 6: Временно оставить переходник и проверить, что игра не сломалась**

Старые поля (`weakness_types` и прочие) **пока оставить** — их читают места из Task 2–3. Добавить над ними пометку:

```gdscript
## ВРЕМЕННО до Task 2: старые независимые списки. Удаляются, когда все
## читатели перейдут на записи. Новый контент писать только в *_rules.
```

Прогнать `--validate`, `--outcomes`, `--loop 10` и убедиться, что числа совпадают с прежними (переходник держит поведение).

- [ ] **Step 7: Коммит**

```
cd F:\WORK\hunter
git add core/model/monster_data.gd content/monsters/lament_monster.tres core/sim/checks/logic_checks.gd
git commit -m "Модель записей уязвимостей и резистов: связка «тип И дистанция» (D23)"
```

---

## Task 2: Боевое ядро и сторож по семи видам (этап 2а, часть 2)

**Files:**
- Modify: `core/battle/damage_calc.gd`
- Modify: `core/model/monster_data.gd` (снять переходник)
- Modify: `core/sim/checks/logic_checks.gd` (два места, где проба задаёт старые поля)
- Test: `core/sim/checks/logic_checks.gd`

**Interfaces:**
- Consumes: API Task 1 (`modifier_reasons`, `weakness_modifier`, `resist_modifier`).
- Produces: `DamageCalc.player_damage` считает модификаторы только через модель; старых полей в `MonsterData` больше нет.

- [ ] **Step 1: Написать проверку связки по каждому из семи видов**

Добавить в `_status_mechanics()` перед `return out`:

```gdscript
	# D23, добор: связка проверяется на КАЖДОМ виде, а не на синтетической пробе.
	# Проверяем два свойства, которые старый код ломал:
	#   (а) запись с двумя ограничениями даёт ровно +1/−1, не удваивается;
	#   (б) запись без types срабатывает на любой тип в этой дистанции.
	var d23_fail: Array[String] = []
	for mon_id in Database.monsters.keys():
		var m: MonsterData = Database.monsters[mon_id]
		# (а) остаток от деления на 3 обязан быть в пределах одного модификатора:
		# ни одна координата не должна давать больше |1| за одну запись.
		for t in MonsterData.PHYSICAL_TYPES:
			var melee_w := m.weakness_modifier(t, MonsterData.RANGE_MELEE)
			var ranged_w := m.weakness_modifier(t, MonsterData.RANGE_RANGED)
			if melee_w > 1 or ranged_w > 1:
				d23_fail.append("%s: уязвимость %s даёт +%d" % [
					m.id, CityData.type_ru(t), maxi(melee_w, ranged_w)])
		# (б) запись «ближний бой» обязана закрывать физику в упор, если она есть.
		for rule_v in m.resist_rules:
			var rule := rule_v as Dictionary
			if PackedStringArray(rule.get("types", [])).size() > 0:
				continue
			var ranges := PackedStringArray(rule.get("ranges", []))
			if not ranges.has(String(MonsterData.RANGE_MELEE)):
				continue
			for t in MonsterData.PHYSICAL_TYPES:
				if m.resist_modifier(t, MonsterData.RANGE_MELEE) < 1:
					d23_fail.append("%s: запись «ближний бой» не сработала на %s" % [
						m.id, CityData.type_ru(t)])
					break
	if d23_fail.is_empty():
		out.append("ок D23 видов: связка «тип И дистанция» работает на всех видах")
	else:
		out.append("ПРОВАЛ D23 видов: %s" % "; ".join(d23_fail))
```

- [ ] **Step 2: Прогнать**

Проба покажет либо `ок D23 видов`, либо `ПРОВАЛ D23 видов: …`. **На этом шаге красное ещё ожидаемо** — данные в `.tres` ещё старые, а записи из них никто не собрал. Если красное есть, зафиксировать его текст в отчёт: он показывает, какие виды пострадали.

- [ ] **Step 3: Переписать блок уязвимостей в `damage_calc.gd`**

Заменить блок от `# --- типовой множитель` до конца цикла по `hit_types` включительно на:

```gdscript
	# --- типовой множитель: уязвимости и резисты вида по ОБЕИМ координатам удара
	# (базовый тип оружия и элемент руны) и с учётом дистанции. Вся арифметика и
	# тексты причин — в MonsterData.modifier_reasons: один источник на правило
	# (D23, GDD 12.3.1).
	r.type_multiplier = 0

	var hit_types: Array = [weapon.damage_type]
	if weapon.rune_type != &"" and weapon.rune_type != weapon.damage_type:
		hit_types.append(weapon.rune_type)

	if phase.has("weak_rules"):
		r.type_reasons.append("фаза: %s" % str(phase.get("title", "")))

	var phase_reason_count := r.type_reasons.size()
	r.type_reasons.append_array(
		monster.modifier_reasons(hit_types, weapon.range_id, phase))

	# Число обязано сходиться с суммой причин: если разбор называет слагаемые,
	# их сумма и есть множитель. Это защита от расхождения текста и числа.
	var summed := 0
	for i in range(phase_reason_count, r.type_reasons.size()):
		if "+1" in r.type_reasons[i]:
			summed += 1
		else:
			summed -= 1
	r.type_multiplier = summed
```

**Важно:** `weak_types`, `weak_ranges`, `phase_has_resist` и `type_resist_for` из этой функции уходят полностью. Проверить, что в файле не осталось чтения старых полей:

```
cd F:\WORK\hunter
Select-String -Path core\battle\damage_calc.gd -Pattern "weakness_types|weakness_ranges|type_resist_for|range_resist_for|resist_types|resist_ranges"
```

Ожидается: пусто.

- [ ] **Step 4: Снять переходник в `MonsterData`**

Удалить старые поля (`weakness_types`, `weakness_ranges`, `type_resist`, `range_resist`) и функции `type_resist_for()`, `range_resist_for()` вместе с пометкой «ВРЕМЕННО».

- [ ] **Step 5: Перевести пробу на записи**

В `core/sim/checks/logic_checks.gd` заменить два места, задающих старые поля:
- в блоке D04: `fire_eater.type_resist = {"fire": 2}` → `fire_eater.resist_rules = [{"types": ["fire"], "ranges": []}]`, а `fire_eater.weakness_types = PackedStringArray(["slash"])` → `fire_eater.weakness_rules = [{"types": ["slash"], "ranges": []}]`; ожидание в тексте проверки поменять с «ожог −2» на «резист −1» (запись даёт −1, не −2);
- в блоке тумана: `mon.type_resist = {"fire": 1, "physical": 1}` → `mon.resist_rules = [{"types": ["fire"], "ranges": []}, {"types": ["physical"], "ranges": []}]`.

- [ ] **Step 6: Прогнать и убедиться, что ЗЕЛЕНО**

```
cmd /c "F:\WORK\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe --headless --path F:\WORK\hunter --quit-after 900 -- --probe --log-file F:\WORK\hunter\_glog.txt"
```

Ожидается `ок D23 связки`, `ок D23 видов` и ни одного `ПРОВАЛ`.

- [ ] **Step 7: Доказать, что сторож связки краснеет**

Временно сломать связку в `monster_data.gd` — в `rule_applies()` заменить проверку диапазона
на безусловное `return true` (то есть вернуть старое «координаты порознь»). Прогнать `--probe`,
убедиться, что вышло `ПРОВАЛ D23 связки: множитель 2`. Вернуть как было, прогнать снова,
убедиться в зелёном и в том, что `git diff core/model/monster_data.gd` пуст.

- [ ] **Step 8: Прогнать остальные режимы**

```
cmd /c "F:\WORK\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe --headless --path F:\WORK\hunter --quit-after 900 -- --validate --log-file F:\WORK\hunter\_glog.txt"
cmd /c "F:\WORK\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe --headless --path F:\WORK\hunter --quit-after 900 -- --outcomes --log-file F:\WORK\hunter\_glog.txt"
cmd /c "F:\WORK\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe --headless --path F:\WORK\hunter --quit-after 900 -- --swap --log-file F:\WORK\hunter\_glog.txt"
```

Ожидается `VALIDATION OK`, `ПРОВАЛОВ: 0 из 6`, `ПРОВАЛОВ: 0 из 7`. **Если валидатор падает** — он ещё читает старые поля; это ожидаемо, и его правка в Task 3. В этом случае зафиксировать текст падения в отчёт и не «чинить» валидатор здесь.

- [ ] **Step 9: Коммит**

```
git add core/battle/damage_calc.gd core/model/monster_data.gd core/sim/checks/logic_checks.gd
git commit -m "Боевое ядро считает модификаторы через записи; связка под сторожем (D23)"
```

---

## Task 3: Валидатор и тексты (этап 2а, часть 3)

**Files:**
- Modify: `core/sim/content_validator.gd`
- Modify: `core/ui_data/dossier_text.gd`
- Modify: `ui/screens/city/city_screen.gd`
- Modify: `core/battle/dossier_recorder.gd`

**Interfaces:**
- Consumes: `MonsterData.weakness_modifier`, `resist_modifier`, `rule_applies`, `weakness_lines`, `resist_lines`, `rule_types_ru`.
- Produces: ни одно место в проекте не читает структуру записи напрямую, кроме `MonsterData`.

- [ ] **Step 1: Запрет пустой записи в валидаторе**

В `content_validator.gd` в функции проверки вида (там, где инвариант «уязвимость и резист не противоречат друг другу») заменить блок на:

```gdscript
	# Инвариант 4 (D23): запись обязана ограничивать хотя бы одну координату.
	# Пустая запись сработала бы на ЛЮБОЙ удар — это скрытый «резист ко всему»,
	# и увидеть его в таблице было бы нечем.
	for rules in [mon.weakness_rules, mon.resist_rules]:
		for rule_v in rules:
			var rule := rule_v as Dictionary
			if PackedStringArray(rule.get("types", [])).size() == 0 \
					and PackedStringArray(rule.get("ranges", [])).size() == 0:
				out.append("%s: запись без types и ranges сработала бы на любой удар" % label)
```

- [ ] **Step 2: Проверка полезности оружия вместо проверки типов**

Заменить в `content_validator.gd` блок, который перебирает `PHYSICAL_TYPES` и `type_resist_for`/`is_weak_to_type`, на проверку по координатам:

```gdscript
		# Полезность уязвимости (D23): уязвимость — это пара «тип И дистанция»,
		# поэтому проверять её по одному типу нельзя: у Громуна дробящее работает
		# только в упор, и «уязвим к дробящему» без дистанции — половина правды.
		# Ошибка контента — когда уязвимость недостижима НИ ОДНОЙ парой
		# (тип, дистанция) из существующего оружия.
		for rule_v in mon.weakness_rules:
			var reachable_by := ""
			for w_id in Database.weapons.keys():
				var w: WeaponData = Database.weapons[w_id]
				if MonsterData.rule_applies(rule_v as Dictionary, w.damage_type, w.range_id):
					reachable_by = w.title
					break
			if reachable_by.is_empty():
				out.append("уязвимость: %s — запись «%s» недостижима ни одним оружием" % [
					label, ", ".join(MonsterData.rule_types_ru(rule_v as Dictionary))])
```

Проверку «закрыты ВСЕ физические подтипы» заменить на проверку по координате — теперь она видит и ограничение по дистанции:

```gdscript
		for range_id in [MonsterData.RANGE_MELEE, MonsterData.RANGE_RANGED]:
			var shut := true
			for t in MonsterData.PHYSICAL_TYPES:
				if mon.resist_modifier(t, StringName(range_id)) < 1:
					shut = false
					break
			if shut:
				out.append("подтипы: %s — закрыта вся физика на дистанции «%s»: выбор оружия тупиковый" % [
					label, CityData.range_ru(StringName(range_id))])
```

- [ ] **Step 3: Обратная сторона — каждое оружие кому-то нужно**

Заменить блок с `m.is_weak_to_type(w.damage_type)` и перебором фаз на:

```gdscript
			if m.weakness_modifier(w.damage_type, w.range_id) > 0:
				useful = true
				break
```

Цикл по `ph` с `weak_types` удалить целиком: фазы читаются тем же `weakness_modifier` (он принимает фазу), а для проверки «оружие кому-то нужно» достаточно базовых уязвимостей.

- [ ] **Step 4: Три места показа — на `weakness_lines`/`resist_lines`**

В `dossier_text.gd` (блок `view["weaknesses"]` и `view["resists"]`), `city_screen.gd`
(`_advice_text`) и `dossier_recorder.gd` (`_weakness_text`) заменить построение строк на:

```gdscript
	view["weaknesses"] = mon.weakness_lines()
	view["resists"] = mon.resist_lines()
```

```gdscript
	weak_parts = mon.weakness_lines()
```

```gdscript
	return ", ".join(_monster.weakness_lines())
```

- [ ] **Step 5: Проверить, что структуру записи читает только модель**

```
cd F:\WORK\hunter
Select-String -Path core\*.gd,core\*\*.gd,core\*\*\*.gd,ui\*\*.gd,ui\*\*\*.gd -Pattern "weakness_types|weakness_ranges|type_resist|range_resist|weak_types|weak_ranges|resist_types|resist_ranges"
```

Ожидается: **пусто**. Если что-то нашлось — это непереведённый читатель: его надо
перевести на записи, а не оставить.

Отдельно проверить, что структуру записи читает **только** `monster_data.gd`:

```
Select-String -Path core\*.gd,core\*\*.gd,core\*\*\*.gd,ui\*\*.gd,ui\*\*\*.gd -Pattern "\.get\(""types""|\.get\(""ranges""|rule_applies"
```

Допустимые попадания — только `core/model/monster_data.gd` (сама модель), `core/sim/content_validator.gd`
(проверка структуры записи — это его работа) и `core/sim/checks/logic_checks.gd` (сторож связки).
Любое другое место означает, что правило снова живёт в двух местах.

- [ ] **Step 6: Прогнать все режимы**

```
cmd /c "tools\run_checks.cmd"
```

Ожидается `ALL MODES OK`. Отдельно проверить `_validate_out.txt` — `VALIDATION OK`, и `_probe_out.txt` — ни одного `ПРОВАЛ`.

- [ ] **Step 7: Коммит**

```
git add core/sim/content_validator.gd core/ui_data/dossier_text.gd ui/screens/city/city_screen.gd core/battle/dossier_recorder.gd
git commit -m "Валидатор и тексты досье читают записи, а не два списка (D23)"
```

---

## Task 4: Данные семи видов и бот (этап 2а, часть 4)

**Files:**
- Modify: `content/monsters/hruz_monster.tres`, `shipun.tres`, `gromun.tres`, `tleun.tres`, `skorb_monster.tres`, `ashmother_monster.tres`, `lament_monster.tres`
- Modify: `core/sim/loop_sim.gd`

**Interfaces:**
- Consumes: форму записей и API Task 1.
- Produces: контент описывает уязвимости и резисты записями; поведение совпадает с прежним (кроме случаев, которые старый код считал неверно).

- [ ] **Step 1: Переписать записи один к одному**

Правило перевода: старая пара «список типов × список дистанций» становится
**декартовым произведением** записей — это ровно то, что делал старый код, и
единственный способ сохранить поведение на этапе 2а.

| Вид | Было | Стало |
|---|---|---|
| Хруз | `weakness_types=[ice,poison]`, `weakness_ranges=[ranged]`, `type_resist={fire:1,slash:1,pierce:1}` | `weakness_rules=[{types:[ice],ranges:[ranged]},{types:[poison],ranges:[ranged]}]`, `resist_rules=[{types:[fire],ranges:[]},{types:[slash],ranges:[]},{types:[pierce],ranges:[]}]` |
| Шипун | `weakness_types=[poison]`, `weakness_ranges=[ranged]`, `type_resist={ice:1,slash:1,pierce:1}` | `weakness_rules=[{types:[poison],ranges:[ranged]}]`, `resist_rules=[{types:[ice],ranges:[]},{types:[slash],ranges:[]},{types:[pierce],ranges:[]}]` |
| Громун | `weakness_types=[crush]`, `weakness_ranges=[melee]`, `type_resist={ice:1}`, `range_resist={ranged:2}` | `weakness_rules=[{types:[crush],ranges:[melee]}]`, `resist_rules=[{types:[ice],ranges:[]},{types:[],ranges:[ranged]}]` |
| Тлеун | `weakness_types=[poison,ice]`, `type_resist={fire:1,crush:1,slash:1}` | `weakness_rules=[{types:[poison],ranges:[]},{types:[ice],ranges:[]}]`, `resist_rules=[{types:[fire],ranges:[]},{types:[crush],ranges:[]},{types:[slash],ranges:[]}]` |
| Скорб | `weakness_types=[fire]`, `weakness_ranges=[ranged]`, `type_resist={slash:1,pierce:1,ice:1,poison:1}` | `weakness_rules=[{types:[fire],ranges:[ranged]}]`, `resist_rules=[{types:[slash],ranges:[]},{types:[pierce],ranges:[]},{types:[ice],ranges:[]},{types:[poison],ranges:[]}]` |
| Пепел-Мать | `weakness_types=[fire,poison,slash]`, `type_resist={crush:1,ice:1}` | `weakness_rules=[{types:[fire],ranges:[]},{types:[poison],ranges:[]},{types:[slash],ranges:[]}]`, `resist_rules=[{types:[crush],ranges:[]},{types:[ice],ranges:[]}]` |
| Ламент | `weakness_types=[]`, `weakness_ranges=[]`, `type_resist={}`, `range_resist={}` | `weakness_rules=[]`, `resist_rules=[]` |

**Внимание про Громуна.** Старый `range_resist = {ranged: 2}` давал **−2** на любой
дальний удар. Запись даёт **−1**. Это осознанное расхождение: значение −2 относилось
к снятой механике «парного резиста» (D21.F), и сохранять его нечем — в модели
модификатор записи всегда −1. Поведение Громуна дальним боем изменится, и это надо
назвать в отчёте, а не спрятать.

**Приёмка шага:** после правки `--probe` остаётся зелёным, а `--outcomes`/`--swap` — без провалов.

- [ ] **Step 2: Починить выбор инструмента ботом**

В `loop_sim.gd` заменить `_equip_best_tool` целиком:

```gdscript
## Бот берёт инструмент, к которому зверь уязвим НА ЭТОЙ ДИСТАНЦИИ (D23): запись
## уязвимости — пара «тип И дистанция», поэтому брать первый тип и первую
## дистанцию из двух списков нельзя: так бот собирал пару, которой в записях нет,
## и получал +1 там, где игрок не получит ничего.
##
## Проверка владения обязательна, и раньше её здесь не было: перебор шёл по всей
## базе (Database.weapons), то есть бот вооружался Клинком или Копьём, не потратив
## на них ни монеты.
func _equip_best_tool(mon: MonsterData) -> void:
	var exact: WeaponData = null
	var by_type: WeaponData = null
	for id in GameState.owned_weapons:
		var w: WeaponData = Database.weapon(id)
		if w == null:
			continue
		if mon.weakness_modifier(w.damage_type, w.range_id) > 0:
			exact = w
			break
		if by_type == null and w.damage_type == mon.weakness_type_hint():
			by_type = w
	var chosen := exact if exact != null else by_type
	if chosen != null:
		GameState.equipped_weapon = chosen.id
```

В `MonsterData` добавить вспомогательную функцию, которая отдаёт «первый тип из
записей уязвимости» — она нужна боту как запасной вариант, когда точной пары нет:

```gdscript
## Первый тип уязвимости — подсказка для бота, когда точной пары нет.
## Пустая строка, если уязвимостей нет.
func weakness_type_hint() -> StringName:
	for rule_v in weakness_rules:
		var types := PackedStringArray((rule_v as Dictionary).get("types", []))
		if types.size() > 0:
			return StringName(types[0])
	return &""
```

- [ ] **Step 3: Прогнать полный набор**

```
cd F:\WORK\hunter
tools\run_checks.cmd
```

Ожидается `ALL MODES OK`.

- [ ] **Step 4: Зафиксировать замер 2а**

```
cmd /c "F:\WORK\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe --headless --path F:\WORK\hunter --quit-after 1800 -- --sim --battles 200 --log-file F:\WORK\hunter\_glog.txt"
```

Сохранить `sim_report.json` как `_sim_2a.json` (файл игнорируется `.gitignore`).
Сравнить с замером до этапа (`--sim --battles 200` на `2b6e3e5`), объяснить каждое
расхождение. **Ожидаемое расхождение одно:** Громун дальним боем слабее на 1
(было −2 за дальний удар, стало −1). Всё остальное обязано совпасть — если не
совпало, остановиться и разобраться, а не списывать.

- [ ] **Step 5: Коммит**

```
git add content/monsters core/sim/loop_sim.gd core/model/monster_data.gd
git commit -m "Семь видов переведены на записи; бот выбирает инструмент по паре (D23)"
```

---

## Task 5: Числа семи видов и знак штрафа брони (этап 2б)

**Files:**
- Modify: `content/monsters/*.tres` (7)
- Modify: `content/armor/heavy.tres`, `core/model/armor_data.gd`

**Interfaces:**
- Consumes: модель записей (Task 1–4).
- Produces: данные совпадают со сводной таблицей D21; штраф брони работает в объявленную сторону.

- [ ] **Step 1: Поставить целевые записи по §2.3 спеки**

Заменить записи каждого вида на целевые (таблица §2.3 спеки переноса):

| Вид | `weakness_rules` | `resist_rules` |
|---|---|---|
| Хруз | `[{types:[ice],ranges:[ranged]}, {types:[poison],ranges:[]}]` | `[{types:[fire],ranges:[]}]` |
| Шипун | `[{types:[poison],ranges:[]}, {types:[fire],ranges:[ranged]}]` | `[{types:[],ranges:[melee]}]` |
| Громун | `[{types:[],ranges:[melee]}, {types:[fire],ranges:[]}]` | `[{types:[],ranges:[ranged]}, {types:[ice],ranges:[]}]` |
| Тлеун | `[{types:[poison],ranges:[]}, {types:[ice],ranges:[]}]` | `[{types:[fire],ranges:[]}, {types:[],ranges:[melee]}]` |
| Скорб | `[{types:[fire],ranges:[]}]` | `[{types:[],ranges:[melee]}, {types:[ice],ranges:[]}, {types:[poison],ranges:[]}]` |
| Пепел-Мать | `[{types:[fire],ranges:[]}]` | `[{types:[pierce],ranges:[]}, {types:[slash],ranges:[]}, {types:[crush],ranges:[]}, {types:[ice],ranges:[]}]` |
| Ламент | `[]` (уязвимость только в фазе «Истощение») | `[{types:[],ranges:[melee]}, {types:[],ranges:[ranged]}, {types:[ice],ranges:[]}, {types:[poison],ranges:[]}]` |

**Фаза Ламента уже переведена в Task 1** — править её здесь не надо, кроме случая,
если проверка покажет расхождение.

- [ ] **Step 2: Починить знак штрафа инициативы (спека §7.8, Д1)**

В `content/armor/heavy.tres` заменить `initiative_penalty = -1` на `initiative_penalty = 1`.
В `core/model/armor_data.gd` расширить диапазон: `@export_range(-3, 0, 1)` → `@export_range(-3, 3, 1)`.

Обоснование в комментарии к полю: формула `hunter_state.gd` **вычитает** штраф,
поэтому положительное значение уменьшает инициативу; `ui_checks.gd` уже пишет
`initiative_penalty = 2` и работает.

- [ ] **Step 3: Прогнать пробу и проверить, что зелено**

```
cmd /c "F:\WORK\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe --headless --path F:\WORK\hunter --quit-after 900 -- --probe --log-file F:\WORK\hunter\_glog.txt"
```

Ожидается `ок D23 видов` и `ок D23 связки`. **Особое внимание — проверке `--prep`:**
в ней инициатива брони задаётся явно, но `Д20`-проверка берёт `Database.armor(&"light")`
(штраф 0), поэтому знак тяжёлой брони её не задевает.

- [ ] **Step 4: Сверить матрицу модификаторов с ожидаемой**

Прогнать `--sim --battles 200` и сверить с `_sim_2a.json`. Расхождения обязаны
объясняться только этими двумя причинами: (а) новые записи по D21, (б) штраф брони
тяжёлой брони 6 → 4. Любое третье — остановиться и разобраться.

- [ ] **Step 5: Прогнать все режимы**

```
cd F:\WORK\hunter
tools\run_checks.cmd
```

Ожидается `ALL MODES OK`. `--validate` обязан быть OK: новые записи Ламента
(четыре резиста) не должны конфликтовать с его фазовой уязвимостью — фаза
переопределяет только уязвимости, резисты остаются.

- [ ] **Step 6: Коммит**

```
git add content/monsters content/armor/heavy.tres core/model/armor_data.gd
git commit -m "Числа семи видов по D21 и починка знака штрафа брони (D23, 2б)"
```

---

## Task 6: Замер этапа 2 и запись в спеку

**Files:**
- Modify: `docs/2026-09-24-migration-to-v1.10-design.md` (раздел 8)

- [ ] **Step 1: Снять замер**

```
cmd /c "F:\WORK\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe --headless --path F:\WORK\hunter --quit-after 1200 -- --loop 10 --log-file F:\WORK\hunter\_glog.txt"
cmd /c "F:\WORK\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe --headless --path F:\WORK\hunter --quit-after 1800 -- --sim --battles 200 --log-file F:\WORK\hunter\_glog.txt"
```

- [ ] **Step 2: Записать раздел 8 в спеку**

Дописать в конец спеки раздел «8. Результаты этапа 2» по образцу раздела 7: две
таблицы (2а — только модель, 2б — модель и числа), причины каждого расхождения,
и **отдельная строка про Ламента**: сколько боёв изменилось, стало ли прохождение
до Легенды хуже и на сколько. Если Ламент стал непроходим — сказать это прямо,
а не сглаживать.

- [ ] **Step 3: Коммит**

```
git add docs/2026-09-24-migration-to-v1.10-design.md
git commit -m "Этап 2 закрыт: модель записей и числа семи видов сверены замером"
```

---

## Что НЕ входит в этот план

- **Каталог оружия, ранги заказов, экономика** — этап 3. Ламент остаётся доступным
  на прежнем ранге до этапа 3.
- **Д2 и Д3 из §7.8 спеки** (недостижимый минимум на непробиваемом пути, мёртвая
  ветка `softened`) — отдельное решение, не этап 2.
- **Терминологическая чистка «физика/огонь/лёд/яд»** — зарезервирована под имя D22
  и не сделана.

## Риски

1. **Ламент может стать непроходимым.** У него в игре сегодня резистов нет вовсе,
   а D21 даёт четыре постоянных поверх панциря 3: модификатор уходит в минус на всех
   двадцати четырёх вариантах «оружие × руна». HP и панцирь не меняются. Если замер
   покажет непроходимость — это **результат этапа**, а не повод править числа
   по вкусу: решение принимается отдельно, с числами на руках.
2. **Декартово произведение в Task 4 раздувает записи.** Это намеренно: так
   поведение сохраняется ровно, и этап 2а можно сравнить с прежним замером.
   Целевые данные (Task 5) записей не раздувают.
3. **Валидатор может упасть в Task 2** — он ещё читает старые поля. Это ожидаемо и
   чинится в Task 3; падение не повод править его раньше.
4. **`--loop` слеп к урону** (измерено на этапе 1). Приёмка этапа 2 опирается на
   `--sim`, а `--loop` используется только для экономики.
