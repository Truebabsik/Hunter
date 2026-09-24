# Этап 1: формулы и механики — план реализации

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development (recommended) or executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Привести четыре правила боя к дизайну v1.10, не меняя структуру данных: минимум 1 урона у зверя, фазы Ламента, симметрия рун вместо привилегии огня, снятие бонуса оружия к инициативе.

**Architecture:** Правки только в формулах и данных, без смены модели. Каждая задача меняет одно правило и проверяется пробой, которая **сначала краснеет** на старом поведении — это единственный способ убедиться, что проверка что-то сторожит.

**Tech Stack:** Godot 4.7.2, GDScript. Проверки — headless-режимы движка, отчёты читаются файлами.

**Spec:** `docs/2026-09-24-migration-to-v1.10-design.md` (§3, этап 1)

## Global Constraints

- Движок: `F:\WORK\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe`, проект `F:\WORK\hunter`.
- Разделитель `--` перед режимом **обязателен**, иначе `main.gd` не найдёт режим.
- Результат читать из файла отчёта, а не из вывода консоли.
- `core/` — чистый GDScript: ни `Node`, ни `SceneTree`, ни сцен.
- Перед правкой кода загрузить скилл `godot-4-development` (правило проекта).
- Проверка, которая не показала красного на сломанном поведении, не считается проверкой.
- Коммит после каждой задачи. Сообщение — по-русски, с объяснением «почему», а не «что».

---

### Task 1: Минимум 1 урона у зверя (D01, D12, D13)

**Files:**
- Modify: `core/battle/damage_calc.gd:151-153`
- Test: `core/sim/checks/logic_checks.gd` (функция `_status_mechanics` — добавить блок)

**Interfaces:**
- Consumes: ничего из предыдущих задач.
- Produces: `DamageCalc.monster_damage()` возвращает `>= 1` вместо `>= 0`. Никаких новых имён; сигнатура не меняется.

- [ ] **Step 1: Написать падающую проверку**

В `core/sim/checks/logic_checks.gd`, в конец функции `_status_mechanics()` перед `return out`, добавить:

```gdscript
	# Минимум 1 урона у ЗВЕРЯ (D01/D12/D13). Инвариант распространяется на обоих:
	# удар всегда наносит хотя бы 1. Проверяем два пути — обычный и непробиваемый,
	# потому что они возвращают разное и правятся оба.
	var thick := MonsterData.new()
	thick.id = &"min_probe"
	thick.title = "Проба минимума"
	thick.max_hp = 20
	thick.base_damage = 3
	var armored := HunterState.new()
	armored.max_hp = 20
	armored.hp = 20
	armored.absorption = 10        # заведомо больше урона зверя
	var normal := DamageCalc.monster_damage(thick, null, armored, false)
	var unblockable_scn := ScenarioData.new()
	unblockable_scn.id = &"probe_unblockable"
	unblockable_scn.card_label = "Непробиваемый"
	unblockable_scn.unblockable = true
	var unblockable := DamageCalc.monster_damage(thick, unblockable_scn, armored, false)
	out.append("минимум урона зверя: обычный путь %d, непробиваемый %d при броне 10" % [
		normal, unblockable])
	if normal >= 1 and unblockable >= 1:
		out.append("ок минимума урона: зверь наносит хотя бы 1 на обоих путях")
	else:
		out.append("ПРОВАЛ минимума урона: обычный %d, непробиваемый %d (ждали ≥1)" % [
			normal, unblockable])
```

- [ ] **Step 2: Прогнать и убедиться, что краснеет**

```
cmd /c "F:\WORK\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe --headless --path F:\WORK\hunter --quit-after 900 -- --probe --log-file F:\WORK\hunter\_glog.txt"
```

Затем прочитать `F:\WORK\hunter\_probe_out.txt`.

Ожидается: `ПРОВАЛ минимума урона: обычный 0, непробиваемый 0 (ждали ≥1)`.
Если проверка зелёная — она ничего не сторожит, и правку делать не над чем.

- [ ] **Step 3: Починить правило**

В `core/battle/damage_calc.gd` заменить строки 151–153:

```gdscript
	if scenario != null and scenario.unblockable:
		return maxi(1, base)
	return maxi(1, base - hunter.total_absorption())
```

И заменить комментарий над функцией (строка 133 и далее), добавив правило:

```gdscript
## Урон зверя (GDD 12.6): базовый урон или урон сценария − броня игрока.
## Панцирь зверя на его собственный урон не влияет.
##
## Минимум — 1, и он НЕ зависит от того, пробивается ли сценарий блоком (D01, D12,
## D13). Раньше здесь стоял maxi(0, …), то есть зверь мог нанести ноль: тяжёлая
## броня (поглощение 3) полностью гасила базовый урон Хруза (3). Это ломало
## воронку сложности — на старте зверь становился безобидным.
##
## Особый случай: сценарий может быть непробиваемым (GDD 4.4, «Вой-паралич не
## пробивается блоком»). Тогда броня не помогает вообще — но минимум 1 остаётся:
## правило одно на оба пути.
```

- [ ] **Step 4: Прогнать и убедиться, что зелено**

Повторить команду из шага 2.

Ожидается: `ок минимума урона: зверь наносит хотя бы 1 на обоих путях`.

- [ ] **Step 5: Проверить, что ничего не сломалось**

```
cmd /c "F:\WORK\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe --headless --path F:\WORK\hunter --quit-after 900 -- --validate --log-file F:\WORK\hunter\_glog.txt"
cmd /c "F:\WORK\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe --headless --path F:\WORK\hunter --quit-after 900 -- --outcomes --log-file F:\WORK\hunter\_glog.txt"
```

Ожидается: `VALIDATION OK` и `ПРОВАЛОВ: 0 из 6`.

- [ ] **Step 6: Коммит**

```
cd F:\WORK\hunter
git add core/battle/damage_calc.gd core/sim/checks/logic_checks.gd
git commit -m "Минимум 1 урона у зверя: правило одно на оба пути (D01/D12/D13)"
```

---

### Task 2: Симметрия рун — у огня нет привилегии (D04)

**Files:**
- Modify: `core/battle/damage_calc.gd:77-80`
- Test: `core/sim/checks/logic_checks.gd` (в тот же блок `_status_mechanics`)

**Interfaces:**
- Consumes: Task 1 не влияет.
- Produces: `DamageCalc.player_damage()` учитывает тип руны как базовый +1, проверяемый на уязвимость и резист; отдельного сообщения `"огонь +1"` в разборе больше нет.

**Контекст.** D04: «+1 от стихии» — это **базовый урон руны**, он симметричен огню, льду и яду и так же подвержен резисту. Сейчас `damage_calc.gd` начисляет `+1` за огонь отдельно и безусловно, а `type_reasons` пишет «огонь +1». Пример §12.5 даёт `4+1(огонь)−2 = 3` — при безусловном +1 и резисте −2 выходит та же тройка, поэтому итог ничего не различает и нужна проверка **структуры** разбора.

- [ ] **Step 1: Написать падающую проверку**

Добавить в `_status_mechanics()`:

```gdscript
	# D04: у огня нет привилегии. «+1» даёт руна любого элемента, и он
	# ПРОВЕРЯЕТСЯ на уязвимость и резист так же, как базовый тип.
	#
	# Проверка смотрит не итог, а структуру разбора: при безусловном +1 и резисте
	# −2 итог совпадает (4+1−2 и 4+1−2), и по числу отличить правила невозможно.
	var sword := WeaponData.new()
	sword.id = &"d04_sword"
	sword.range_id = MonsterData.RANGE_MELEE
	sword.damage_type = MonsterData.TYPE_SLASH
	sword.base_damage = 4
	sword.rune_type = MonsterData.TYPE_FIRE
	var fire_eater := MonsterData.new()
	fire_eater.id = &"d04_mon"
	fire_eater.title = "Проба огня"
	fire_eater.max_hp = 20
	fire_eater.armor = 0
	fire_eater.type_resist = {"fire": 2}
	fire_eater.weakness_types = PackedStringArray(["slash"])
	var d04 := DamageCalc.player_damage(
		sword, fire_eater, DamageCalc.Reading.COUNTER, false, 0, 0, {}, 0.0, null)
	var reasons := ", ".join(d04.type_reasons)
	out.append("D04 руна огня: урон %d, разбор [%s]" % [d04.total, reasons])
	if not ("огонь +1" in reasons) and "слабость: режущий +1" in reasons:
		out.append("ок D04: руна даёт базовый +1 без привилегии огня")
	else:
		out.append("ПРОВАЛ D04: разбор «%s» (ждали слабость режущего и никакого «огонь +1»)" % reasons)
```

- [ ] **Step 2: Прогнать и убедиться, что краснеет**

```
cmd /c "F:\WORK\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe --headless --path F:\WORK\hunter --quit-after 900 -- --probe --log-file F:\WORK\hunter\_glog.txt"
```

Ожидается: `ПРОВАЛ D04: разбор «…огонь +1 (руна)…»`.

- [ ] **Step 3: Починить формулу**

В `core/battle/damage_calc.gd` заменить строки 77–80:

```gdscript
		# Руна даёт базовый +1 и тип элемента (§12.3, D04). Никакой привилегии у
		# огня нет: стихии симметричны. +1 входит в слагаемое «элемент_руны» и
		# потому сам подвержен уязвимости и резисту — как в примере §12.5.
		if is_rune:
			r.type_multiplier += 1
```

- [ ] **Step 4: Прогнать и убедиться, что зелено**

Ожидается: `ок D04: руна даёт базовый +1 без привилегии огня`.

- [ ] **Step 5: Проверить боевые примеры §12.5**

```
cmd /c "F:\WORK\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe --headless --path F:\WORK\hunter --quit-after 900 -- --outcomes --log-file F:\WORK\hunter\_glog.txt"
cmd /c "F:\WORK\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe --headless --path F:\WORK\hunter --quit-after 900 -- --swap --log-file F:\WORK\hunter\_glog.txt"
```

Ожидается: `ПРОВАЛОВ: 0 из 6` и `ПРОВАЛОВ: 0 из 7`.

- [ ] **Step 6: Коммит**

```
git add core/battle/damage_calc.gd core/sim/checks/logic_checks.gd
git commit -m "Руны симметричны: «+1» даёт любой элемент, привилегии огня нет (D04)"
```

---

### Task 3: Фазы Ламента 12/16/12 (D02)

**Files:**
- Verify only: `content/monsters/lament_monster.tres:344-373`
- Test: `core/sim/checks/logic_checks.gd` (новый блок)

**Interfaces:**
- Consumes: ничего.
- Produces: проверка, фиксирующая разбиение фаз 12/16/12 при `max_hp = 40`.

**Контекст.** Фазы заданы порогами `hp_below`: 0.3 и 0.7. При `max_hp = 40` это даёт **12 / 28 / 40**, то есть длины фаз **12 / 16 / 12** — ровно как требует D02. Правка данных, скорее всего, **не нужна**, но это надо доказать проверкой, а не глазами: `phase_for_hp` может считать границы иначе.

- [ ] **Step 1: Написать проверку**

Добавить в `_status_mechanics()`:

```gdscript
	# D02: фазы Ламента — 12/16/12 при 40 HP. Заданы порогами 0.3 и 0.7, значит
	# проверяем ГРАНИЦЫ, а не промежуточные значения: ошибка в них сдвигает фазу
	# на ход-два, и заметить это по одному замеру нельзя.
	var lam: MonsterData = Database.monster(&"lament")
	if lam != null:
		var at40 := StringName(lam.phase_for_hp(40).get("id", ""))
		var at29 := StringName(lam.phase_for_hp(29).get("id", ""))
		var at28 := StringName(lam.phase_for_hp(28).get("id", ""))
		var at13 := StringName(lam.phase_for_hp(13).get("id", ""))
		var at12 := StringName(lam.phase_for_hp(12).get("id", ""))
		var at1 := StringName(lam.phase_for_hp(1).get("id", ""))
		out.append("фазы Ламента: 40→%s, 29→%s, 28→%s, 13→%s, 12→%s, 1→%s" % [
			at40, at29, at28, at13, at12, at1])
		if at40 == &"calm" and at28 == &"rage" and at12 == &"worn" and at1 == &"worn":
			out.append("ок фаз Ламента: 12 / 16 / 12 при 40 HP")
		else:
			out.append("ПРОВАЛ фаз Ламента: границы сдвинуты (28→%s, 12→%s)" % [at28, at12])
	else:
		out.append("ПРОВАЛ фаз Ламента: вид не загружен")
```

- [ ] **Step 2: Прогнать**

```
cmd /c "F:\WORK\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe --headless --path F:\WORK\hunter --quit-after 900 -- --probe --log-file F:\WORK\hunter\_glog.txt"
```

**Если зелено** — данные уже верны. Перейти к шагу 4.
**Если красно** — перейти к шагу 3.

- [ ] **Step 3: Починить пороги (выполнять ТОЛЬКО если шаг 2 красный)**

Если проверка красная, значит `phase_for_hp` в `core/model/monster_data.gd` считает границы неверно. Смотреть её цикл:

```gdscript
	for p in phases:
		var threshold := float(p.get("hp_below", 1.0))
```

Фаза выбирается по условию `hp <= max_hp * hp_below`. При `max_hp = 40` и порогах 0.3 / 0.7 это даёт `hp <= 12` → истощение, `hp <= 28` → бешенство, иначе спокойствие. Именно это и требуется: 12 / 16 / 12.

Если проверка красная при таких данных — правка идёт **в функцию**, а не в `.tres`: скорее всего, сравнение идёт строгим `<` вместо `<=`, и тогда `hp = 12` попадает в бешенство, а не в истощение. Исправляется замена `<` на `<=`.

Если проверка зелёная (ожидаемый исход) — в данные и в функцию не лезть: они уже верны.

- [ ] **Step 4: Коммит**

```
git add core/sim/checks/logic_checks.gd
git commit -m "Проверка фаз Ламента: 12/16/12 при 40 HP (D02)"
```

---

### Task 4: Снять бонус оружия к инициативе (D20)

**Files:**
- Modify: `core/model/weapon_data.gd:29` (удалить поле)
- Modify: `core/model/skill_effects.gd:150`
- Modify: `content/weapons/blade.tres`, `bow.tres`, `crossbow.tres`, `mace.tres`, `spear.tres`
- Modify: `ui/checks/ui_checks.gd:207`
- Test: `core/sim/checks/logic_checks.gd`

**Interfaces:**
- Consumes: ничего.
- Produces: `WeaponData` больше не имеет поля `initiative_bonus`; `HunterState.initiative_bonus_total` заполняется только знаками ранга (в бою не заполняется вовсе, остаётся `0`). Инициатива охотника = `5 − штраф брони`.

- [ ] **Step 1: Написать проверку**

```gdscript
	# D20: концепт скорости оружия снят. Инициативу дают только знаки ранга,
	# а оружие на неё не влияет вовсе.
	var fast := WeaponData.new()
	fast.id = &"d20_probe"
	fast.range_id = MonsterData.RANGE_MELEE
	fast.damage_type = MonsterData.TYPE_CRUSH
	fast.base_damage = 5
	var d20_hunter := SkillEffects.build_hunter(fast, Database.armor(&"light"))
	var has_field := "initiative_bonus" in fast
	out.append("D20 инициатива: поле у оружия %s, инициатива охотника %d (ждали 5)" % [
		str(has_field), d20_hunter.initiative()])
	if not has_field and d20_hunter.initiative() == 5:
		out.append("ок D20: оружие на инициативу не влияет")
	else:
		out.append("ПРОВАЛ D20: поле %s, инициатива %d" % [str(has_field), d20_hunter.initiative()])
```

- [ ] **Step 2: Прогнать и убедиться, что краснеет**

Ожидается `ПРОВАЛ D20: поле true, инициатива 6` или подобное — то есть проверка видит живое поле.

- [ ] **Step 3: Удалить поле из модели**

В `core/model/weapon_data.gd` удалить строки 28–29:

```gdscript
## Бонус инициативы (GDD 12.9).
@export_range(-2, 3, 1) var initiative_bonus: int = 0
```

- [ ] **Step 4: Убрать присваивание**

В `core/model/skill_effects.gd` удалить строку 150:

```gdscript
		hunter.initiative_bonus_total = weapon.initiative_bonus
```

Параметр `weapon` у `build_hunter` остаётся: он нужен для `weapon_id`, и его сигнатуру менять нельзя — её читают `battle_screen` и `loop_sim`.

- [ ] **Step 5: Убрать поле из пяти файлов оружия**

В каждом из `content/weapons/*.tres` удалить строку с `initiative_bonus = N`.

- [ ] **Step 6: Убрать присваивание в проверке**

В `ui/checks/ui_checks.gd:207` удалить строку `phoenix_weapon.initiative_bonus = 0`.

- [ ] **Step 7: Прогнать и убедиться, что зелено**

```
cmd /c "F:\WORK\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe --headless --path F:\WORK\hunter --quit-after 900 -- --probe --log-file F:\WORK\hunter\_glog.txt"
```

Ожидается `ок D20: оружие на инициативу не влияет`.

- [ ] **Step 8: Проверить, что поле нигде не осталось**

```
cd F:\WORK\hunter
Select-String -Path core\*.gd,core\*\*.gd,core\*\*\*.gd,ui\*\*.gd,ui\*\*\*.gd,content\weapons\*.tres -Pattern "initiative_bonus"
```

Ожидается: только упоминание `initiative_bonus_total` (это другое поле) и комментарий в `hunter_state.gd`. Ссылок на `weapon.initiative_bonus` быть не должно.

- [ ] **Step 9: Проверить остальные режимы**

```
cmd /c "F:\WORK\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe --headless --path F:\WORK\hunter --quit-after 900 -- --validate --log-file F:\WORK\hunter\_glog.txt"
cmd /c "F:\WORK\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe --headless --path F:\WORK\hunter --quit-after 900 -- --prep --log-file F:\WORK\hunter\_glog.txt"
cmd /c "F:\WORK\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe --headless --path F:\WORK\hunter --quit-after 900 -- --smoke --log-file F:\WORK\hunter\_glog.txt"
```

Ожидается: `VALIDATION OK`, `ПРОВАЛОВ: 0 из 14`, и экран боя проходит бой.

- [ ] **Step 10: Коммит**

```
git add core/model/weapon_data.gd core/model/skill_effects.gd content/weapons ui/checks/ui_checks.gd core/sim/checks/logic_checks.gd
git commit -m "Снят бонус оружия к инициативе: её дают только знаки ранга (D20)"
```

---

### Task 5: Контрольный замер этапа

**Files:**
- Verify only, ничего не меняется.

**Interfaces:**
- Consumes: результаты задач 1–4.
- Produces: числа боя до и после этапа, с объяснением каждого расхождения.

- [ ] **Step 1: Снять замер прогоном**

```
cmd /c "F:\WORK\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe --headless --path F:\WORK\hunter --quit-after 1200 -- --loop 10 --log-file F:\WORK\hunter\_glog.txt"
```

- [ ] **Step 2: Сверить с эталоном**

В `F:\WORK\hunter\_baseline_loop.txt` лежит замер **до** переноса. Прочитать оба файла и объяснить каждое расхождение.

Ожидаемые расхождения и их причины:

| Величина | Почему изменится |
|---|---|
| Превентивные удары | бонус оружия к инициативе снят → инициатива охотника с 6 до 5 → больше зверей бьют первыми |
| Полученный урон | минимум 1 урона → там, где раньше было 0, теперь 1 |
| Урон игрока по видам с резистом к огню | руна огня теперь проверяется на резист вместо безусловного +1 |
| Доход, слава, достижения | могут сдвинуться как следствие боёв |

Любое расхождение, которое **не** объясняется этими четырьмя причинами, — повод остановиться и разобраться.

- [ ] **Step 3: Прогнать все режимы**

```
cd F:\WORK\hunter
tools\run_checks.cmd
```

Ожидается: `ALL MODES OK`.

- [ ] **Step 4: Закоммитить отчёт о замере**

```
git add docs/2026-09-24-migration-to-v1.10-design.md
git commit -m "Этап 1 переноса закрыт: замеры сверены с эталоном"
```

---

## Что НЕ входит в этот план

- **Модель записей «тип И дистанция»** — этап 2. Здесь она не нужна: четыре правки этапа 1 её не касаются. Но помнить: уязвимости читают **шесть** мест (`damage_calc`, `city_screen`, `loop_sim`, `dossier_recorder`, `content_validator`, `dossier_text`), и смена модели затронет каждое.
- **Каталог оружия, ранги заказов, экономика** — этап 3.
- **Накопительное досье, альтернативная цель, хроника, реакция на удар** — этап 4.
- **Пул 378 фраз** — отдельная работа.

## Риски

1. **Task 3 может оказаться пустой** — данные, возможно, уже верны. Это нормально: проверка остаётся как сторож.
2. **Task 4 меняет инициативу всех боёв.** До этапа 2 любые выводы о балансе недействительны, поэтому контрольный замер Task 5 — это фиксация, а не приёмка баланса.
3. **Проверки в `_status_mechanics` растут.** Если функция станет слишком длинной, её стоит разбить по задачам — но это отдельная правка, не в этом плане.
