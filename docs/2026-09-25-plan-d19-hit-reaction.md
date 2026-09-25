# D19 — реакция на удар: план реализации

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development (recommended) or executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Боевая проза честно называет исход удара игрока — тип наткнулся на защиту, нашёл щель или прошёл нейтрально — не добавляя подсказок, UI и не меняя ни одного числа боя.

**Architecture:** Вердикт считается в ядре из знака **суммы причин** вида (поле `DamageResult.type_reasons_sum`, добавляется этой задачей: `type_multiplier` для вердикта не годится — в нём сидит безусловный «+1» руны и в резист гасит штраф) и уезжает в исход действия идентификатором. Слова собираются из **деталей** — новый CSV в `content/phrases/` по существующей схеме, поэтому загрузчик не меняется, — а сборка живёт рядом с генератором прозы и зовёт его же взвешенный выбор. Показ — строкой под прозой раунда, вне тумана: реакция это факт о твоём ударе, а не наблюдение за зверем.

**Tech Stack:** Godot 4.7.2, GDScript. Проверки — headless-режимы, отчёты читаются файлами.

**Spec:** `docs/2026-09-25-d19-hit-reaction-design.md` — план аргументирует от неё, спека едет вместе с планом; исполнителю читать обе.

> **Правка области после выполнения, задача 8 (решение пользователя, 2026-09-25).** Подсистема
> D19 **сужена до СТАРТОВОГО вида**: реакция считается и показывается **только для Хруза**, у
> остальных шести видов вердикт, серия и строка не считаются вовсе — поля исхода остаются
> пустыми, как при промахе. Область включения — **один список** `HitReaction.ENABLED_SPECIES`
> в `core/battle/hit_reaction.gd`, движок спрашивает `HitReaction.enabled_for(monster)`, второй
> копии условия в `submit_read` нет. Задачи 1–7 этим **не отменяются**: правило вердикта, пул и
> сборка принимаются как есть, и данные остальных видов остаются в CSV задел ом (проверка
> покрытия не ослаблена — включать виды по одной строке в списке).
> **Что это повлекло по факту:**
> - боевые пробы (`_reaction_in_battle`) **перебазированы с Громунa на Хруза** с сохранением всех
>   правил (охват, примерка-`swap`, промах, серия `[1, 2, 3]`, смена вердикта, промах серию не
>   сбрасывает, новая битва с первой ступени, вводная каждой ступени из своего пула); добавлен
>   **сторож границы области** `_reaction_scopes` — удар по не-стартовому виду не даёт ни
>   вердикта, ни серии, ни строки;
> - проба «читать нечего» в дыме (`ui_checks.smoke`) **перебазирована с тумана Тлеуна на
>   СЛЕПОТУ Хруза** (`BattleEngine.STATUS_BLIND`): на Тлеуне подсистема выключена, и проба
>   проверяла бы выключенность, а не ветвь `lines.is_empty()`;
> - **бриф задачи 8 ошибался в одном ожидании, и это измерено:** «лук → уязвимость» неверно.
>   У Хруза слабость — `{"ranges": ["ranged"], "types": ["ice"]}`, и `MonsterData.rule_applies`
>   требует И дальности, И стихии; лук бьёт `pierce` без стихии и даёт **нейтраль** (сумма `+0`).
>   Измерено: молот — `neutral` (`+0`), молот + руна огня — `resist` (`−1`), лук + руна льда —
>   `weak` (`+1`); бриф верен в части молота и резиста и неверен в части лука.
> **Цена ошибки, если бы оставили по первой редакции:** проба на Громунe осталась бы зелёной
> при снятом условии включения (она сторожит данные вида, а не список), а проба дыма на Тлеуне
> краснела бы на корректном коде; ожидание «лук → уязвимость» краснило бы верный код.

## Global Constraints

- Движок: `F:\WORK\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe`, проект `F:\WORK\hunter`.
- Разделитель `--` перед режимом **обязателен**; отчёты читать **файлами** (`Get-Content <файл> -Encoding UTF8`), **удалять перед прогоном**.
- `core/` — чистый GDScript: ни `Node`, ни `SceneTree`, ни сцен. Отступы — **табы**.
- Правки `.gd`/`.tres`/`.csv` — **только инструментами `edit`/`write`**. `Set-Content` по `.gd` в этом проекте уже склеивал файл в одну строку.
- **Ни одно число боя не меняется.** Замер `--loop 25` остаётся побайтово прежним (эталон SHA256 `AD17FB96B388B35D2C79779B630866E6F548E57FC5EEBB880FD89A7A21DB5F58`); `--sim --battles 200` сверяется с зафиксированной базой `_sim_before_d19.json` (SHA256 `877F760679DDE2D8508B8A2A0D5112A2AAFF6A084EB741108D8CA0110FA65CC1`, снята до первой правки D19; на коде задач 1–2 повторный прогон совпал побайтово).
- Ожидаемый красный `--validate` — **ровно три ламантовы строки** (§14.1). Не глушить и не «чинить».
- Обёртка проверок читает вердикт внутри отчётов: строка, начинающаяся с «ПРОВАЛ», маркеры `VALIDATION FAILED`/`SMOKE FAILED`/`LOAD FAILED` и `SCRIPT ERROR` на stderr ломают вердикт.
- **Чужие незакоммиченные файлы не трогать**: `art/monsters/hruz.png`, `docs/ART_*.md`, `docs/dizain_hunter_old.md`, `*.bat`.
- **Новый `class_name` не виден headless-прогону, пока не пересобран кеш глобальных классов.** Признак — `Parse Error: Identifier "<Имя>" not declared`. Лечение: один раз `--headless --import`, затем обычный прогон. Относится ко всякой задаче, создающей файл с `class_name`.
- **Общая база оружия остаётся зачарованной после пробы `_weapon_after_death`** (`logic_checks.gd`): она чарует ОБЩИЙ `Database.weapon(&"mace")` огнём и не снимает чары. Пробы задач 4–5 идут позже в том же процессе, поэтому **перед своим замером оружия обязаны снять чары** (`disenchant()`) и утверждать то состояние, которое сами подготовили. `duplicate()` не спасает — чары копируются.
- **Каждая новая проверка показывается КРАСНОЙ мутацией** с сохранённым отчётом. Зелёная проверка без показанной красноты не принимается.

## Файловая структура

| Файл | Ответственность | Что с ним |
|---|---|---|
| `core/battle/hit_reaction.gd` | Вердикт и сборка строки реакции из деталей пула | **создать** |
| `content/phrases/reactions.csv` | Детали фразы: носители, глаголы, отпечатки, стихии, вводные | **создать** |
| `core/battle/text_generator.gd` | Взвешенный выбор фразы (единственная реализация) | открыть `_pick_phrase` наружу |
| `core/battle/battle_engine.gd` | Вердикт удара, счётчик серий, сборка в исходе | правка |
| `core/sim/content_validator.gd` | Покрытие пула реакции | правка |
| `core/sim/checks/logic_checks.gd` | Проверки правила, сборки, серий, охвата | правка |
| `ui/screens/battle/battle_screen.gd` | Строка реакции под прозой раунда | правка |
| `ui/checks/ui_checks.gd` | Дым боя: строка реакции видна | правка |
| `docs/dizain_hunter.md` | §11.10: пороги заменены знаком; отметка о посеве | правка |

---

## Task 1: Правило вердикта

**Files:**
- Create: `core/battle/hit_reaction.gd`
- Modify: `core/battle/damage_result.gd` (новое поле `type_reasons_sum`)
- Modify: `core/battle/damage_calc.gd` (заполнение поля в том же цикле, что считает множитель)
- Modify: `core/sim/checks/logic_checks.gd` (новая функция `_hit_reaction()`, вызов из `probe()` рядом с `_rune_rule()`)
- Modify: `docs/dizain_hunter.md` (§11.10 — таблица порогов; история изменений)

**Files — отступление от первой редакции брифа, решение координатора:** `damage_result.gd` и `damage_calc.gd` в списке не стояли, потому что первая редакция спеки называла источником вердикта `type_multiplier` — **это была ошибка**: он начинается с `element_bonus` и суммирует причины поверх элемента (`damage_calc.gd:110-116`), поэтому знак множителя не означает «тип сработал / не сработал». Голой суммы причин в результате нет, её надо завести.

**Interfaces:**
- Produces: `HitReaction.VERDICT_RESIST` / `VERDICT_WEAK` / `VERDICT_NEUTRAL` (`StringName`), `HitReaction.verdict_of(reasons_sum: int) -> StringName`, поле `DamageResult.type_reasons_sum: int`.

- [ ] **Step 1: Заглушка класса — чтобы краснота была НАЗВАННОЙ, а не падением**

Создать `core/battle/hit_reaction.gd`:

```gdscript
extends RefCounted
class_name HitReaction
## Вердикт удара игрока (D19): тип удара наткнулся на защиту зверя, нашёл щель
## или прошёл нейтрально.
##
## Вердикт — про ТИП, а не про силу удара. Источник — сумма причин «слабость +1 /
## резист −1» (поле `DamageResult.type_reasons_sum`), БЕЗ безусловного «+1» элемента
## руны (D04): в `type_multiplier` элемент уже прибавлен и в резист гасит штраф,
## поэтому удар руной в стену даёт там ноль — и по множителю проза сказала бы
## «нейтрально» там, где разбор называет резист (измерено на Ламанте).

const VERDICT_RESIST := &"resist"
const VERDICT_WEAK := &"weak"
const VERDICT_NEUTRAL := &"neutral"


## ЗАГЛУШКА: возвращает «нейтрально» всегда. Настоящее правило — шаг 4.
static func verdict_of(_reasons_sum: int) -> StringName:
	return VERDICT_NEUTRAL
```

Шаг 1 не заканчивается на заглушке: **поле обязано существовать до красного прогона**, иначе проба не скомпилируется и краснота будет падением разбора. В `core/battle/damage_result.gd` рядом с `type_multiplier`:

```gdscript
## Сумма причин вида («слабость +1 / резист −1») БЕЗ безусловного «+1» элемента
## руны (D04). Отдельно от `type_multiplier`, потому что там элемент уже прибавлен
## и в резист гасит его: удар руной в стену поднимает итог, ничего не пробивая.
## Вердикт удара (D19) обязан смотреть на реакцию ТИПА, а не на итог с элементом.
var type_reasons_sum: int = 0
```

Поле пока остаётся нулевым — заполнение на шаге 4. Поэтому ветвь пробы про руну в резист на красном прогоне покраснеет **по имени** («получили neutral»), а не упадёт.

- [ ] **Step 2: Написать проверку правила**

В `core/sim/checks/logic_checks.gd` рядом с `_rune_rule()`:

```gdscript
## Правило реакции на удар (D19): вердикт — знак СУММЫ ПРИЧИН вида, а не итог
## удара и не типовой множитель. Отдельная ветвь про руну в резист: итог растёт
## (элемент безусловен, D04), множитель при этом обнуляется, а вердикт обязан
## остаться «резист» — иначе проза называет стену нейтралью.
static func _hit_reaction() -> Array[String]:
	var out: Array[String] = []
	var failures: Array[String] = []

	var cases := [
		{"sum": -2, "want": HitReaction.VERDICT_RESIST},
		{"sum": -1, "want": HitReaction.VERDICT_RESIST},
		{"sum": 0, "want": HitReaction.VERDICT_NEUTRAL},
		{"sum": 1, "want": HitReaction.VERDICT_WEAK},
		{"sum": 3, "want": HitReaction.VERDICT_WEAK},
	]
	for c in cases:
		var got := HitReaction.verdict_of(int(c["sum"]))
		out.append("реакция: сумма причин %+d → %s" % [int(c["sum"]), got])
		if got != StringName(c["want"]):
			failures.append("сумма причин %+d дала «%s», а ждали «%s»" % [
				int(c["sum"]), got, c["want"]])

	# РАСХОЖДЕНИЕ, ради которого проба и написана: удар руной в стену. Стена
	# резистит БАЗОВЫЙ тип, руна нейтральна — значит итог растёт на «+1» элемента,
	# разбор называет резист, а множитель обнуляется (элемент гасит штраф).
	# Вердикт обязан остаться «резист»: если считать по множителю, проза скажет
	# «нейтрально» там, где разбор называет стену.
	var wall := MonsterData.new()
	wall.id = &"reaction_wall"
	wall.title = "Проба стены"
	wall.max_hp = 20
	wall.armor = 0
	wall.resist_rules = [{"types": [String(MonsterData.TYPE_CRUSH)], "ranges": []}]
	var plain := WeaponData.new()
	plain.id = &"reaction_plain"
	plain.range_id = MonsterData.RANGE_MELEE
	plain.damage_type = MonsterData.TYPE_CRUSH
	plain.base_damage = 4
	var bare := DamageCalc.player_damage(
		plain, wall, DamageCalc.Reading.COUNTER, false, 0, 0, {}, 0.0, null)
	plain.enchant(MonsterData.TYPE_ICE)
	var runed := DamageCalc.player_damage(
		plain, wall, DamageCalc.Reading.COUNTER, false, 0, 0, {}, 0.0, null)
	var verdict := HitReaction.verdict_of(runed.type_reasons_sum)
	out.append("реакция: руна в резист — урон %d (без чар %d), множитель %+d, сумма причин %+d, разбор [%s] → %s" % [
		runed.total, bare.total, runed.type_multiplier, runed.type_reasons_sum,
		", ".join(runed.type_reasons), verdict])
	if verdict != HitReaction.VERDICT_RESIST:
		failures.append("руна в резист дала вердикт «%s», а ждали «резист»" % verdict)
	if runed.total <= bare.total:
		failures.append("проба не воспроизводит случай: руна не подняла урон (%d против %d)" % [
			runed.total, bare.total])
	if runed.type_multiplier != 0:
		failures.append("проба не воспроизводит расхождение: множитель %+d не обнулился, значит элемент не погасил штраф" % runed.type_multiplier)
	plain.disenchant()

	# ЖИВОЙ СЛУЧАЙ — свидетельством, без утверждения: Ламант с руной. Тупик
	# Ламанта открыт вопросом §14.1, и утверждение покраснело бы, когда дизайн
	# его решит. Строку печатаем: она показывает, что расхождение не выдумано.
	var lament := Database.monster(&"lament")
	var mace: WeaponData = Database.weapon(&"mace")
	if lament != null and mace != null:
		mace.disenchant()
		var l_bare := DamageCalc.player_damage(
			mace, lament, DamageCalc.Reading.COUNTER, false, 0, 0, {}, 0.0, null)
		mace.enchant(MonsterData.TYPE_FIRE)
		var l_runed := DamageCalc.player_damage(
			mace, lament, DamageCalc.Reading.COUNTER, false, 0, 0, {}, 0.0, null)
		out.append("реакция: Ламант молотом — без чар %d (множитель %+d, сумма %+d), с огнём %d (множитель %+d, сумма %+d) → %s / %s" % [
			l_bare.total, l_bare.type_multiplier, l_bare.type_reasons_sum,
			l_runed.total, l_runed.type_multiplier, l_runed.type_reasons_sum,
			HitReaction.verdict_of(l_bare.type_reasons_sum),
			HitReaction.verdict_of(l_runed.type_reasons_sum)])
		mace.disenchant()

	if failures.is_empty():
		out.append("ок реакции: вердикт следует знаку суммы причин, элемент его не подменяет")
	else:
		out.append("ПРОВАЛ реакции: %s" % "; ".join(failures))
	Report.write(HIT_REACTION_REPORT, out)
	return out
```

Рядом с остальными константами отчётов добавить `const HIT_REACTION_REPORT := "_probe_reaction.txt"`, а в `probe()` — строку `out.append_array(_hit_reaction())` рядом с `out.append_array(_rune_rule())`.

- [ ] **Step 3: Прогнать — ожидается КРАСНОЕ с названными причинами**

```
cmd /c "F:\WORK\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe --headless --path F:\WORK\hunter --quit-after 900 -- --probe --log-file F:\WORK\hunter\_glog.txt"
```

Ожидается в `_probe_out.txt` строка `ПРОВАЛ реакции:` с причинами вида «сумма причин −1 дала „нейтрально“» (поле ещё нулевое) и, **обязательно**, строка `реакция: руна в резист — урон N (без чар M), множитель +0, сумма причин −1` с `N > M`. Если роста числа нет или множитель не обнулился, проба не воспроизводит расхождение, ради которого написана, — разбирайся с пробой, а не подгоняй ожидание.

- [ ] **Step 4: Реализовать правило**

Сначала заполнить поле в `core/battle/damage_calc.gd` — **тем же циклом**, что считает множитель: правило подписи причины («`+1` — плюс, иначе минус») обязано остаться в одном месте, вторая его копия запрещена.

```gdscript
	var summed := element_bonus
	var reasons_sum := 0
	for i in range(phase_reason_count, r.type_reasons.size()):
		if "+1" in r.type_reasons[i]:
			summed += 1
			reasons_sum += 1
		else:
			summed -= 1
			reasons_sum -= 1
	r.type_reasons_sum = reasons_sum
	r.type_multiplier = summed
```

`type_multiplier` сохраняет прежний смысл — меняется только то, что рядом появляется вторая сумма. Затем в `core/battle/hit_reaction.gd` заменить заглушку:

```gdscript
## Вердикт по знаку СУММЫ ПРИЧИН вида («слабость +1 / резист −1») без «+1» элемента
## руны (D04). Ноль — взаимодействия нет.
static func verdict_of(reasons_sum: int) -> StringName:
	if reasons_sum < 0:
		return VERDICT_RESIST
	if reasons_sum > 0:
		return VERDICT_WEAK
	return VERDICT_NEUTRAL
```

- [ ] **Step 5: Прогнать — ожидается ЗЕЛЁНОЕ**

Та же команда. Ожидается `ок реакции: вердикт следует знаку суммы причин, элемент его не подменяет` и отсутствие `ПРОВАЛ` в отчёте. В отчёте обязана быть строка про Ламант: у неё **сумма причин одинаковая (−1) при разном множителе** — это и есть свидетельство, что расхождение не выдумано.

- [ ] **Step 6: Показать красноту мутацией**

Поменять в `verdict_of` знаки местами (`> 0` → резист, `< 0` → щель) → прогнать → ожидается `ПРОВАЛ реакции` с именами случаев. Вернуть как было, сохранить отчёт мутации как `_probe_mutation_reaction_signs.txt`, убедиться, что `git diff core/battle/hit_reaction.gd` показывает только рабочий код.

- [ ] **Step 7: Правка дизайна — пороги заменены знаком**

В `docs/dizain_hunter.md` §11.10 таблицу порогов (`≤ 30 %` / `≥ 150 %`) заменить на правило знака с объяснением из двух частей: (1) при целых `±1` слабость к базе около пяти — это `+20 %`, а не `+150 %`, поэтому прежние пороги не сработали бы ни разу; (2) источник вердикта — **сумма причин без «+1» элемента руны**, потому что в `type_multiplier` элемент уже прибавлен и в резист гасит штраф (иначе удар руной в стену читался бы как нейтральный). В историю изменений добавить запись **v1.10.11**.

- [ ] **Step 8: Проверить, что числа не поехали**

```
cmd /c "F:\WORK\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe --headless --path F:\WORK\hunter --quit-after 2400 -- --loop 25 --log-file F:\WORK\hunter\_glog.txt"
```

Ожидается SHA256 `_loop_out.txt` **равный** `AD17FB96B388B35D2C79779B630866E6F548E57FC5EEBB880FD89A7A21DB5F58`: поле новое, числа не меняются. Другое значение — стоп.

**Если прогон падает `Parse Error: Identifier "HitReaction" not declared`** — это кеш глобальных классов, а не ошибка кода: новый `class_name` не виден прогону, пока кеш не пересобран. Выполнить один раз `--headless --import` и повторить прогон. Это относится ко всем задачам D19, создающим новые файлы с `class_name`.

- [ ] **Step 9: Коммит**

```bash
git add core/battle/hit_reaction.gd core/battle/damage_result.gd core/battle/damage_calc.gd core/sim/checks/logic_checks.gd docs/dizain_hunter.md
git commit -m "D19: вердикт удара — знак суммы причин вида (без «+1» элемента); пороги §11.10 заменены"
```

---

## Task 2: Пул деталей и покрытие

**Files:**
- Create: `content/phrases/reactions.csv`
- Modify: `core/sim/content_validator.gd` (проверка покрытия)

**Interfaces:**
- Produces: значения `slot` — `reaction_carrier`, `reaction_verb`, `reaction_weapon`, `reaction_element`, `reaction_intro`; значения `role` — вердикты, id оружия, типы рун, группы вводных (см. таблицу).

- [ ] **Step 1: Создать CSV с шапкой и вводными**

Файл `content/phrases/reactions.csv`, шапка та же, что у видовых пулов:

```csv
id,monster,scenario,slot,role,text,weight,tags
```

Вводные (единственная часть пула, которой нет в дизайне — она авторская; 4 на группу):

```csv
rx.intro.resist.01,,,reaction_intro,resist,Едва,10,reaction
rx.intro.resist.02,,,reaction_intro,resist,Мимо,10,reaction
rx.intro.resist.03,,,reaction_intro,resist,Впустую,10,reaction
rx.intro.resist.04,,,reaction_intro,resist,Напрасно,10,reaction
rx.intro.resist_again.01,,,reaction_intro,resist_again,Опять,10,reaction
rx.intro.resist_again.02,,,reaction_intro,resist_again,Снова,10,reaction
rx.intro.resist_again.03,,,reaction_intro,resist_again,И снова,10,reaction
rx.intro.resist_again.04,,,reaction_intro,resist_again,Всё так же,10,reaction
rx.intro.resist_hard.01,,,reaction_intro,resist_hard,Опять в стену,10,reaction
rx.intro.resist_hard.02,,,reaction_intro,resist_hard,Снова впустую,10,reaction
rx.intro.resist_hard.03,,,reaction_intro,resist_hard,Так и не пробил,10,reaction
rx.intro.resist_hard.04,,,reaction_intro,resist_hard,Снова мимо,10,reaction
rx.intro.weak.01,,,reaction_intro,weak,Точно,10,reaction
rx.intro.weak.02,,,reaction_intro,weak,Наконец-то,10,reaction
rx.intro.weak.03,,,reaction_intro,weak,Есть,10,reaction
rx.intro.weak.04,,,reaction_intro,weak,Вот так,10,reaction
rx.intro.weak_again.01,,,reaction_intro,weak_again,Опять туда же,10,reaction
rx.intro.weak_again.02,,,reaction_intro,weak_again,Снова в щель,10,reaction
rx.intro.weak_again.03,,,reaction_intro,weak_again,И снова точно,10,reaction
rx.intro.weak_again.04,,,reaction_intro,weak_again,Ещё раз в шов,10,reaction
rx.intro.weak_hard.01,,,reaction_intro,weak_hard,Снова в то же место,10,reaction
rx.intro.weak_hard.02,,,reaction_intro,weak_hard,Опять нашёл,10,reaction
rx.intro.weak_hard.03,,,reaction_intro,weak_hard,И опять туда,10,reaction
rx.intro.weak_hard.04,,,reaction_intro,weak_hard,Всё туда же,10,reaction
rx.intro.neutral.01,,,reaction_intro,neutral,Так,10,reaction
rx.intro.neutral.02,,,reaction_intro,neutral,Ровно,10,reaction
rx.intro.neutral.03,,,reaction_intro,neutral,Без разницы,10,reaction
rx.intro.neutral.04,,,reaction_intro,neutral,Как обычно,10,reaction
rx.intro.neutral_again.01,,,reaction_intro,neutral_again,Опять так же,10,reaction
rx.intro.neutral_again.02,,,reaction_intro,neutral_again,Снова ровно,10,reaction
rx.intro.neutral_again.03,,,reaction_intro,neutral_again,И снова так,10,reaction
rx.intro.neutral_again.04,,,reaction_intro,neutral_again,Так же,10,reaction
rx.intro.neutral_hard.01,,,reaction_intro,neutral_hard,Снова без отклика,10,reaction
rx.intro.neutral_hard.02,,,reaction_intro,neutral_hard,Опять ни то ни это,10,reaction
rx.intro.neutral_hard.03,,,reaction_intro,neutral_hard,"Ровно, снова",10,reaction
rx.intro.neutral_hard.04,,,reaction_intro,neutral_hard,Ни туда ни сюда,10,reaction
rx.intro.swap.01,,,reaction_intro,swap,Примеряешься,10,reaction
rx.intro.swap.02,,,reaction_intro,swap,Заносишь,10,reaction
rx.intro.swap.03,,,reaction_intro,swap,Берёшь на изготовку,10,reaction
rx.intro.swap.04,,,reaction_intro,swap,Пробуешь хват,10,reaction
```

- [ ] **Step 2: Дописать носители, глаголы, отпечатки и стихии**

Словарь берётся **дословно из §11.10 дизайна** (таблицы «`{носитель}`», «`{глагол-реакция}`», «Отпечаток удара», «Стихийный слой»). Строки:

- `reaction_carrier`, `monster` = id вида, **по три носителя на каждый из семи видов** (Хруз, Шипун, Громун, Тлеун, Скорб, Пепел-Мать, Ламент);
- `reaction_verb`, `role` = `resist` / `weak` / `neutral`, **по четыре глагола** на категорию;
- `reaction_weapon`, `role` = `mace` / `blade` / `spear` / `bow` / `sling` / `chakram`, **по три отпечатка**;
- `reaction_element`, `role` = `fire` / `ice` / `poison`, **по три окраски**.

Ровно эти идентификаторы — id вида и оружия обязаны совпадать с `content/monsters/*.tres` и `content/weapons/*.tres` **посимвольно**: опечатка здесь означает молча пропавшую деталь, и именно её ловит Step 3.

- [ ] **Step 3: Написать проверку покрытия в валидаторе**

В `core/sim/content_validator.gd` добавить проверку, которая **называет** дыру:

```gdscript
## Покрытие пула реакции на удар (D19). Дыра здесь — не мелочь: сборщик не имеет
## права печатать обрубок, а игрок — не получить обещанную фразу, поэтому
## недостающая деталь называется по имени.
func _check_reactions() -> void:
	var verdicts := ["resist", "weak", "neutral"]
	for v in verdicts:
		if Database.phrases_for(&"", &"", &"reaction_verb", StringName(v)).is_empty():
			out.append("реакция: нет ни одного глагола для вердикта «%s»" % v)
		for step in ["", "_again", "_hard"]:
			var role := StringName("%s%s" % [v, step])
			if Database.phrases_for(&"", &"", &"reaction_intro", role).is_empty():
				out.append("реакция: нет вводных для группы «%s»" % role)
	if Database.phrases_for(&"", &"", &"reaction_intro", &"swap").is_empty():
		out.append("реакция: нет вводных для примерки («swap»)")
	for id in Database.monsters.keys():
		if Database.phrases_for(StringName(id), &"", &"reaction_carrier", &"").is_empty():
			out.append("реакция: у вида «%s» нет носителя" % id)
	for id in Database.weapons.keys():
		if Database.phrases_for(&"", &"", &"reaction_weapon", StringName(id)).is_empty():
			out.append("реакция: у оружия «%s» нет отпечатка удара" % id)
	for rune in SkillsData.RUNE_SKILLS.values():
		if Database.phrases_for(&"", &"", &"reaction_element", StringName(rune)).is_empty():
			out.append("реакция: у руны «%s» нет стихийной окраски" % rune)
```

Вызвать её там, где собираются прочие проверки контента (рядом с проверками слабостей), с префиксом протокола, принятым в файле.

**Внимание к пустому `role`:** `phrases_for` для носителей вызывается с `role = &""`; если загрузчик раскладывает по `role` из колонки, у носителей колонка `role` должна быть **пустой** — проверь это первым прогоном, а не догадкой.

- [ ] **Step 4: Прогнать и убедиться, что покрытие ЗЕЛЁНОЕ**

```
cmd /c "tools\run_checks.cmd --validate"
```

Ожидается: красный ровно `--validate` с тремя ламантовыми строками, и **ни одной** строки «реакция: нет…».

- [ ] **Step 5: Показать красноту покрытия**

Удалить одну строку носителя (любого вида) → `--validate` → ожидается `реакция: у вида «<id>» нет носителя`. Вернуть строку, сохранить отчёт как `_probe_mutation_reaction_coverage.txt`.

- [ ] **Step 6: Отметить в дизайне, что пул — посев**

В §11.10 добавить абзац: пул сейчас **посев** (≈100–120 деталей), расширение вариантов на слот — отдельная работа, замысел §11.10 от этого не меняется.

- [ ] **Step 7: Коммит**

```bash
git add content/phrases/reactions.csv core/sim/content_validator.gd docs/dizain_hunter.md
git commit -m "D19: пул деталей реакции (посев) и проверка покрытия"
```

---

## Task 3: Сборка фразы

**Files:**
- Modify: `core/battle/text_generator.gd` (`_pick_phrase` → публичный `pick_phrase`)
- Modify: `core/battle/hit_reaction.gd` (сборка)
- Modify: `core/sim/checks/logic_checks.gd` (проверки сборки)
- Test: `_probe_out.txt`, `_probe_reaction.txt`

**Interfaces:**
- Consumes: `Database.phrases_for(monster_id, scenario_id, slot, role) -> Array`; `TextGenerator.pick_phrase(...)`.
- Produces: `HitReaction.assemble(monster: MonsterData, weapon: WeaponData, verdict: StringName, run: int, is_swap: bool, rng: RandomNumberGenerator) -> String`; `HitReaction.intro_role(verdict: StringName, run: int, is_swap: bool) -> StringName`.

**Первый аргумент `pick_phrase` — не везде id вида, иначе пул не выберется.** `Database.phrases_for` откатывается **только по сценарию**: `monster_id` остаётся в обоих ключах (`autoload/database.gd:120–124`), поэтому общие детали — они лежат в CSV с пустым `monster` — достижимы **лишь при `monster = &""`**. Значит при сборке `TextGenerator.pick_phrase(monster.id, …)` — **только** для носителя (`HitReaction.SLOT_CARRIER`); для глагола, отпечатка удара, стихийной окраски и вводной первый аргумент обязан быть `&""`. Ошибка здесь молчит: `pick_phrase` вернёт `null`, `assemble` — пустую строку, и проверка сборки покраснеет «пустым пулом» вместо внятной «одной строки». Слоты и вердикты берутся из `HitReaction` (`SLOT_*` / `VERDICT_*` — константы уже объявлены там, второй копии строк быть не должно); ключи и смысл колонок — таблица «Посев» §4 спеки.

- [ ] **Step 1: Открыть взвешенный выбор наружу — без второй реализации**

В `core/battle/text_generator.gd` переименовать `_pick_phrase` в `pick_phrase` (и все внутренние вызовы), оставив тело и docstring прежними, добавив в docstring строку: «Публичная, потому что взвешенный выбор фразы — правило пула, и вторая его копия разошлась бы молча (её зовёт и сборка реакции D19)». Никакого второго взвешивания не писать.

- [ ] **Step 2: Написать проверки сборки**

В `logic_checks.gd` дополнить `_hit_reaction()`:

```gdscript
	# Сборка: три вердикта дают три РАЗНЫЕ строки, каждая со своей лексикой;
	# без руны стихийная часть исчезает вместе с запятой; знаков не удваивается.
	var mon := Database.monster(&"gromun")
	var wpn: WeaponData = Database.weapon(&"mace")
	if mon == null or wpn == null:
		failures.append("нет данных для сборки: вид gromun или оружие mace")
	else:
		var rng := RandomNumberGenerator.new()
		rng.seed = 20260925
		var lines := {}
		for v in [HitReaction.VERDICT_RESIST, HitReaction.VERDICT_WEAK, HitReaction.VERDICT_NEUTRAL]:
			lines[v] = HitReaction.assemble(mon, wpn, StringName(v), 1, false, rng)
			out.append("реакция: «%s» → %s" % [v, lines[v]])
		if lines[HitReaction.VERDICT_RESIST] == lines[HitReaction.VERDICT_WEAK]:
			failures.append("резист и уязвимость дали одну строку — приёмка не выполнена")
		if lines[HitReaction.VERDICT_NEUTRAL] == lines[HitReaction.VERDICT_RESIST] \
				or lines[HitReaction.VERDICT_NEUTRAL] == lines[HitReaction.VERDICT_WEAK]:
			failures.append("нейтральная строка совпала с одной из двух")
		for v in lines.keys():
			var line: String = lines[v]
			if line.contains("  ") or line.contains(",,") or line.contains("—  —") \
					or line.contains("..") or line.ends_with(" ") or line.begins_with(" "):
				failures.append("строка «%s» собрана грязно: %s" % [v, line])
		# Без руны стихийной части нет: строка короче и не содержит запятой перед точкой.
		var no_rune := HitReaction.assemble(mon, wpn, HitReaction.VERDICT_NEUTRAL, 1, false, rng)
		out.append("реакция: без руны → %s" % no_rune)
		if no_rune.contains(", .") or no_rune.contains(",."):
			failures.append("без руны осталась висячая запятая: %s" % no_rune)
		# Детерминизм: та же соль — та же строка.
		var rng_a := RandomNumberGenerator.new()
		rng_a.seed = 7
		var rng_b := RandomNumberGenerator.new()
		rng_b.seed = 7
		var one := HitReaction.assemble(mon, wpn, HitReaction.VERDICT_WEAK, 2, false, rng_a)
		var two := HitReaction.assemble(mon, wpn, HitReaction.VERDICT_WEAK, 2, false, rng_b)
		if one != two:
			failures.append("сборка не детерминирована: «%s» против «%s»" % [one, two])
		# Вводная примерки перебивает ступень серии.
		if HitReaction.intro_role(HitReaction.VERDICT_RESIST, 3, true) != &"swap":
			failures.append("примерка не перебила ступень серии")
		if HitReaction.intro_role(HitReaction.VERDICT_RESIST, 3, false) != &"resist_hard":
			failures.append("третья ступень серии не выбрала «resist_hard»")
		# Лексика своего класса: строка обязана содержать глагол ИМЕННО своего
		# вердикта. Иначе «три разные строки» выполнялись бы разными носителями,
		# а класс исхода остался бы неотличим.
		for v in [HitReaction.VERDICT_RESIST, HitReaction.VERDICT_WEAK, HitReaction.VERDICT_NEUTRAL]:
			var verbs := Database.phrases_for(&"", &"", HitReaction.SLOT_VERB, StringName(v))
			var found := false
			for p in verbs:
				if str(lines[v]).contains(str(p.text)):
					found = true
					break
			if not found:
				failures.append("строка вердикта «%s» не содержит ни одного своего глагола: %s" % [
					v, lines[v]])
```

- [ ] **Step 3: Прогнать — ожидается КРАСНОЕ**

> **Правка порядка после выполнения (найдено исполнителем, подтверждено замером).** В первой
> редакции этого шага было «снять руну с общего молота, затем собрать три вердикта и случай
> без руны». Порядок **неверен**: на чистом оружии стихийной части не бывает вовсе, поэтому
> мутация «убрать добавление стихии» оставалась **зелёной** — ветка стихии оказывалась
> недостижимой для проверки. Сделано иначе: три вердикта собираются на **зачарованном** молоте,
> случай «без руны» — на чистом, и строки сравниваются посимвольно (зачарованная = чистая +
> «, <стихия>.»), со сбросом статической истории фраз и свежим генератором.
> **Цена ошибки, если бы оставили по первой редакции:** проверка была бы зелёной на сломанной
> стихийной части.

```
cmd /c "F:\WORK\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe --headless --path F:\WORK\hunter --quit-after 900 -- --probe --log-file F:\WORK\hunter\_glog.txt"
```

Ожидается падение разбора (`HitReaction.assemble` ещё нет) — это не годная краснота. Поэтому **сначала добавить в `hit_reaction.gd` заглушки**: `assemble(...) -> String` возвращающую `""`, и `intro_role(verdict, _run, _is_swap) -> StringName` возвращающую `verdict`. Слоты `SLOT_CARRIER` / `SLOT_VERB` / `SLOT_WEAPON` / `SLOT_ELEMENT` / `SLOT_INTRO` **уже объявлены там задачей 2** — не объявляй их второй раз и не заводи копию строк. Затем прогнать: ожидается `ПРОВАЛ реакции` с причинами про одинаковые строки, грязную сборку и ненайденный глагол — то есть проверки есть, сборки нет.

- [ ] **Step 4: Реализовать сборку**

В `core/battle/hit_reaction.gd` — **только знаки препинания**: слоты `SLOT_*` здесь уже есть (их завела задача 2, чтобы валидатор не держал вторую копию строк), объявлять их снова нельзя.

```gdscript
## Пунктуация принадлежит СБОРЩИКУ, а не данным: иначе знак пришлось бы дублировать
## в каждой строке CSV, и «двойная запятая» стала бы вопросом данных, а не правила.
const P_AFTER_INTRO := ". "
const P_BEFORE_WEAPON := " — "
const P_BEFORE_ELEMENT := ", "
const P_END := "."


## Группа вводной: ступень серии, но примерка перебивает ступень — смена оружия
## без удара не повтор удара.
static func intro_role(verdict: StringName, run: int, is_swap: bool) -> StringName:
	if is_swap:
		return &"swap"
	if run >= 3:
		return StringName("%s_hard" % verdict)
	if run == 2:
		return StringName("%s_again" % verdict)
	return verdict


static func assemble(
	monster: MonsterData,
	weapon: WeaponData,
	verdict: StringName,
	run: int,
	is_swap: bool,
	rng: RandomNumberGenerator
) -> String:
	if monster == null or weapon == null:
		return ""
	var intro := TextGenerator.pick_phrase(&"", &"", SLOT_INTRO, intro_role(verdict, run, is_swap), rng)
	var carrier := TextGenerator.pick_phrase(monster.id, &"", SLOT_CARRIER, &"", rng)
	var verb := TextGenerator.pick_phrase(&"", &"", SLOT_VERB, verdict, rng)
	var print_weapon := TextGenerator.pick_phrase(&"", &"", SLOT_WEAPON, StringName(weapon.id), rng)
	if intro == null or carrier == null or verb == null or print_weapon == null:
		return ""
	var line: String = str(intro.text) + P_AFTER_INTRO \
		+ str(carrier.text) + " " + str(verb.text) + P_BEFORE_WEAPON + str(print_weapon.text)
	if weapon.rune_type != &"":
		var element := TextGenerator.pick_phrase(
			&"", &"", SLOT_ELEMENT, StringName(weapon.rune_type), rng)
		if element != null:
			line += P_BEFORE_ELEMENT + str(element.text)
	return line + P_END
```

`TextGenerator.pick_phrase` возвращает `Phrase` или `null` — если в существующем коде он возвращает `Phrase` без `null`, привести к этому виду и **не** менять его поведение.

- [ ] **Step 5: Прогнать — ожидается ЗЕЛЁНОЕ**

Та же команда. Ожидается `ок реакции: …`, три разные строки в отчёте и отсутствие `ПРОВАЛ`.

- [ ] **Step 6: Показать красноту мутацией**

Убрать из `assemble` добавление стихийной части (то есть всегда без элемента) → `--probe` → ожидается `ПРОВАЛ реакции` про висячую запятую или совпадение строк. Вернуть, сохранить отчёт `_probe_mutation_reaction_assemble.txt`.

- [ ] **Step 7: Коммит**

```bash
git add core/battle/hit_reaction.gd core/battle/text_generator.gd core/sim/checks/logic_checks.gd
git commit -m "D19: сборка строки реакции из деталей пула, выбор фразы переиспользован"
```

---

## Task 4: Вердикт и серия в бою

**Files:**
- Modify: `core/battle/battle_engine.gd` (состояние серии в `setup()`, вердикт и сборка в `submit_read`)
- Modify: `core/sim/checks/logic_checks.gd` (проверки охвата и серий)

**Interfaces:**
- Consumes: `HitReaction.verdict_of(...)`, `HitReaction.assemble(...)`, `HitReaction.intro_role(...)`.
- Produces: поля исхода `verdict: StringName`, `verdict_run: int`, `reaction: String`; приватное состояние `_verdict_run: int`, `_last_verdict: StringName`.

- [ ] **Step 1: Написать проверки охвата и серий**

В `_hit_reaction()` добавить прогон настоящего боя (образец сборки движка — в `loop_sim._run_player` и в соседних пробах `logic_checks`):

```gdscript
	# Охват: удар, примерка, промах. Серия: тот же вердикт усиливает вводную,
	# смена вердикта возвращает обычную, промах серию НЕ сбрасывает.
	var gromun := Database.monster(&"gromun")
	var bow: WeaponData = Database.weapon(&"bow")
	var spear: WeaponData = Database.weapon(&"spear")
	if gromun == null or bow == null or spear == null:
		failures.append("нет данных для боя: gromun/bow/spear")
	else:
		var hunter := SkillEffects.build_hunter(spear, Database.armor(&"light"))
		var engine := BattleEngine.new()
		engine.seed_source = SeedSource.new(4242, 1)
		engine.setup(gromun, hunter, spear)
		engine.advance_round()
		var correct := engine.current_scenario_id()
		var hit := engine.submit_read(correct, true)
		out.append("реакция: удар — вердикт «%s», серия %d, строка %s" % [
			hit.get("verdict", ""), int(hit.get("verdict_run", 0)), hit.get("reaction", "")])
		if str(hit.get("verdict", "")) == "":
			failures.append("удар не дал вердикта")
		if not str(hit.get("reaction", "")).contains("."):
			failures.append("удар не дал строки реакции")
		# Примерка: верное чтение без удара.
		if not engine.is_over():
			engine.advance_round()
			var swap := engine.submit_read(engine.current_scenario_id(), false)
			out.append("реакция: примерка — вердикт «%s», строка %s" % [
				swap.get("verdict", ""), swap.get("reaction", "")])
			if str(swap.get("verdict", "")) == "":
				failures.append("примерка не дала вердикта")
		# Промах: расчёта нет, значит и реакции нет.
		var engine2 := BattleEngine.new()
		engine2.seed_source = SeedSource.new(4242, 1)
		engine2.setup(gromun, hunter, spear)
		engine2.advance_round()
		var wrong := &""
		for s in gromun.scenarios:
			if s.id != engine2.current_scenario_id():
				wrong = s.id
				break
		var miss := engine2.submit_read(wrong, true)
		out.append("реакция: промах — вердикт «%s», строка «%s»" % [
			miss.get("verdict", ""), miss.get("reaction", "")])
		if str(miss.get("verdict", "")) != "" or str(miss.get("reaction", "")) != "":
			failures.append("промах дал реакцию, а не должен")
```

Серия проверяется отдельно, на одном и том же вердикте. Громун против лука даёт резист — берём его и бьём дважды:

```gdscript
		# Серия: две реакции подряд с ОДНИМ вердиктом обязаны отличаться ступенью.
		# Проверяем ступень (число) и РОЛЬ вводной — обе детерминированы, — а не
		# равенство строк: строки могут совпасть по случайности выбора из четырёх
		# вариантов, и тогда проверка краснела бы на здоровом коде.
		var engine3 := BattleEngine.new()
		engine3.seed_source = SeedSource.new(99, 3)
		engine3.setup(gromun, SkillEffects.build_hunter(bow, Database.armor(&"light")), bow)
		var runs: Array[int] = []
		var texts: Array[String] = []
		for i in 2:
			if engine3.is_over():
				break
			engine3.advance_round()
			var o := engine3.submit_read(engine3.current_scenario_id(), true)
			var v := StringName(o.get("verdict", &""))
			if v != HitReaction.VERDICT_RESIST:
				failures.append("проба серии: ждали вердикт «resist», получили «%s»" % v)
				break
			runs.append(int(o.get("verdict_run", 0)))
			texts.append(str(o.get("reaction", "")))
		out.append("реакция: серия — ступени %s, строки «%s»" % [str(runs), "» / «".join(texts)])
		if runs != [1, 2]:
			failures.append("ступени серии %s, а ждали [1, 2]" % str(runs))
		if HitReaction.intro_role(HitReaction.VERDICT_RESIST, 1, false) \
				== HitReaction.intro_role(HitReaction.VERDICT_RESIST, 2, false):
			failures.append("вторая ступень серии не сменила роль вводной")
```

- [ ] **Step 2: Прогнать — ожидается КРАСНОЕ**

Та же команда `--probe`. Ожидается `ПРОВАЛ реакции` с причинами «удар не дал вердикта», «промах дал реакцию» — то есть проверки есть, поведения нет.

- [ ] **Step 3: Реализовать в движке**

В `core/battle/battle_engine.gd`:

1. Рядом с прочими полями боя — состояние серии, и сброс его в `setup()`:

```gdscript
## Серия одинаковых вердиктов подряд (D19): усиливает вводную. Сбрасывается сменой
## вердикта и НЕ сбрасывается промахом — промах не проверяет оружие, значит стену
## не отменяет.
var _last_verdict: StringName = &""
var _verdict_run: int = 0
```

```gdscript
	_last_verdict = &""
	_verdict_run = 0
```

2. В `submit_read`, **после** того как `dmg` посчитан (внутри `if read_correct:`), добавить в `outcome` три поля. Для удара и для примерки — одинаково, отличается только `is_swap`:

```gdscript
		var verdict := HitReaction.verdict_of(dmg.type_reasons_sum)
		if verdict == _last_verdict:
			_verdict_run += 1
		else:
			_last_verdict = verdict
			_verdict_run = 1
		outcome["verdict"] = verdict
		outcome["verdict_run"] = _verdict_run
		outcome["reaction"] = HitReaction.assemble(
			monster, weapon, verdict, _verdict_run, not attack,
			_round_rng(round_index, &"reaction"))
```

**Отдельная соль обязательна:** `&"reaction"` — не `&"text"`. `SeedSource.round_rng` создаёт **свежий** генератор на каждую пару (раунд, соль), поэтому «расхода потока» не бывает; дело в **независимости**: с общей солью реакция тянула бы те же числа, что проза раунда, и правка в прозе молча сдвигала бы слова реакции (и наоборот).

3. При промахе поля **не заполнять** — в словаре исхода они остаются пустыми по умолчанию, а `verdict`/`reaction` объявлены пустыми там же, где прочие поля исхода (`"damage_to_monster": 0` и соседи): `"verdict": &"", "verdict_run": 0, "reaction": ""`.

- [ ] **Step 4: Прогнать — ожидается ЗЕЛЁНОЕ**

Та же команда. Ожидается `ок реакции: …` и строки охвата: удар дал вердикт и строку, примерка дала вердикт, промах не дал ничего.

- [ ] **Step 5: Показать красноту мутацией**

Заполнить `verdict`/`reaction` и при промахе → `--probe` → ожидается `ПРОВАЛ реакции: промах дал реакцию`. Вернуть, сохранить отчёт `_probe_mutation_reaction_miss.txt`.

- [ ] **Step 6: Проверить, что числа не поехали — сразу здесь, а не в конце**

Именно эта задача впервые могла сдвинуть игру: появилась соль случайности в боевом пути.

```
cmd /c "F:\WORK\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe --headless --path F:\WORK\hunter --quit-after 2400 -- --loop 25 --log-file F:\WORK\hunter\_glog.txt"
```

Ожидается SHA256 `_loop_out.txt` **равный** `AD17FB96B388B35D2C79779B630866E6F548E57FC5EEBB880FD89A7A21DB5F58`. Другое значение — стоп: соль, счётчик серий или вердикт вмешались в правила.

- [ ] **Step 7: Коммит**

```bash
git add core/battle/battle_engine.gd core/sim/checks/logic_checks.gd
git commit -m "D19: вердикт и серия реакций в исходе действия"
```

---

## Task 5: Показ строки

**Files:**
- Modify: `ui/screens/battle/battle_screen.gd`
- Modify: `ui/checks/ui_checks.gd` (дым боя)

**Interfaces:**
- Consumes: `outcome["reaction"]` (строка) — последний исход боя хранится в экране так же, как прочие факты для лога.

- [ ] **Step 1: Дописать проверку в дым боя**

В `ui/checks/ui_checks.gd`, в блоке дыма боя (там, где экран боя уже прогоняется и подаются чтения), добавить проверку: после удара текст панели обязан содержать строку реакции последнего исхода. Проверка обязана **краснеть**:

```gdscript
	# D19: строка реакции обязана доехать до панели прозы. Проверяем через тот же
	# путь, что и остальные проверки экрана, — вызовом его функции.
	checks += 1
	var reaction := str(battle_scr.last_outcome.get("reaction", ""))
	if reaction.is_empty():
		failed += 1
		out.append("ПРОВАЛ: удар не дал строки реакции")
	elif battle_scr._render_prose().contains(reaction):
		out.append("ок: строка реакции показана (%s)" % reaction)
	else:
		failed += 1
		out.append("ПРОВАЛ: строка реакции не показана — «%s» нет в панели" % reaction)
```

Если у экрана боя нет поля `last_outcome`, добавить его там же, где экран берёт исход для лога (экран уже читает `damage_breakdown` из последнего исхода), — это то же состояние, второй копии не заводить.

- [ ] **Step 2: Прогнать — ожидается КРАСНОЕ**

```
cmd /c "tools\run_checks.cmd --smoke"
```

Ожидается `ПРОВАЛ` про не показанную строку реакции.

- [ ] **Step 3: Показать строку под прозой**

В `battle_screen.gd` завести поле и заполнять его там, где экран читает последний исход:

```gdscript
## Строка реакции на последний удар (D19). Живёт до начала следующего раунда:
## иначе она осталась бы на экране, когда раунд уже сменился.
var last_outcome: Dictionary = {}
```

В `_render_prose()` строка добавляется **в обеих ветвях**, и это не мелочь: при тумане и слепоте функция возвращает готовый текст, а реакция обязана показываться и там — она факт о твоём ударе, а не наблюдение за зверем.

```gdscript
func _render_prose() -> String:
	var prose: Dictionary = engine.current_prose()
	if prose.is_empty():
		return ""
	var lines: Array = prose.get("lines", [])
	if lines.is_empty():
		return _with_reaction(str(prose.get("prose", "")))
	# … существующий цикл сборки `out` без изменений …
	return _with_reaction("\n".join(out))


## Реакция дописывается последней строкой — и в тумане тоже (см. `_render_prose`).
func _with_reaction(text: String) -> String:
	var reaction := str(last_outcome.get("reaction", ""))
	if reaction.is_empty():
		return text
	if text.is_empty():
		return "[i]%s[/i]" % reaction
	return "%s\n[i]%s[/i]" % [text, reaction]
```

При начале нового раунда (там, где экран зовёт `engine.advance_round()`) очищать `last_outcome = {}`.

- [ ] **Step 4: Прогнать — ожидается ЗЕЛЁНОЕ**

```
cmd /c "tools\run_checks.cmd"
```

Ожидается `PROBLEMS: 1`, красный ровно `--validate` (три ламантовы строки), дым без провалов.

- [ ] **Step 5: Показать красноту мутацией**

Вернуть `_render_prose()` к виду без `_with_reaction` → `--smoke` → ожидается `ПРОВАЛ` про строку реакции. Вернуть, сохранить отчёт `_smoke_mutation_reaction_hidden.txt`.

- [ ] **Step 6: Коммит**

```bash
git add ui/screens/battle/battle_screen.gd ui/checks/ui_checks.gd
git commit -m "D19: строка реакции показывается под прозой раунда"
```

---

## Task 6: Приёмка и инварианты

**Files:**
- Modify: `docs/2026-09-25-d19-hit-reaction-design.md` (раздел результатов)

- [ ] **Step 1: Полный прогон**

```
cmd /c "tools\run_checks.cmd"
```

Ожидается `PROBLEMS: 1`, красный ровно `--validate` с тремя ламантовыми строками; `SCRIPT ERRORS`/`NO REPORT`/`EXIT CODE` нет.

- [ ] **Step 2: Проверить, что ни одно число не поехало**

```
cmd /c "F:\WORK\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe --headless --path F:\WORK\hunter --quit-after 2400 -- --loop 25 --log-file F:\WORK\hunter\_glog.txt"
```

Ожидается SHA256 `_loop_out.txt` **равный эталону** `AD17FB96B388B35D2C79779B630866E6F548E57FC5EEBB880FD89A7A21DB5F58`. Это проверка **чисел**, а не прозы: в отчёте замера текстов нет. Если хеш другой — стоп и разбор: реакция вмешалась в правила или в урон.

Ту же сверку сделать **сразу после Task 4** — там появляется соль случайности, то есть первое место, где числа вообще могли поехать; искать это только в конце дороже.

```
cmd /c "F:\WORK\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe --headless --path F:\WORK\hunter --quit-after 1800 -- --sim --battles 200 --log-file F:\WORK\hunter\_glog.txt"
```

**База сравнения зафиксирована заранее:** `_sim_before_d19.json` — копия `sim_report.json`, снятая до первой правки D19, SHA256 `877F760679DDE2D8508B8A2A0D5112A2AAFF6A084EB741108D8CA0110FA65CC1`. На коде задач 1–2 повторный прогон дал **побайтово тот же** отчёт, то есть числа боя не двигались. Ожидание: и сейчас `sim_report.json` совпадает с этой базой побайтово. Если не совпадёт — сравнивать **по ключам** `monster|loadout_id|read_level` (подписи сборок сравнивать нельзя: их ломает переименование) и назвать изменившиеся случаи поимённо.

- [ ] **Step 3: Записать результат приёмки в спеку**

В `docs/2026-09-25-d19-hit-reaction-design.md` дописать раздел «Результат приёмки»: три вердикта дают разные строки (с цитатами из отчёта), серии работают, примерка и промах ведут себя как решено, инвариант чисел удержан (хеш замера, сверка `--sim`), пул — посев и что отложено.

- [ ] **Step 4: Коммит**

```bash
git add docs/2026-09-25-d19-hit-reaction-design.md
git commit -m "D19 закрыт: приёмка подсистемы записана, инвариант чисел удержан"
```

---

## Что НЕ входит

- **Остальные шесть видов** — вне области включения (правка задачи 8): реакция включена только для стартового вида. **Включение — одна строка** в `HitReaction.ENABLED_SPECIES`; данные и проверки покрытия для них уже лежат.
- **Расширение пула** (больше вариантов на слот) — отдельный заход; сейчас посев.
- **~378 фраз D19/D20 целиком** — объём не входит.
- **Метрика «удар слаб относительно достижимого»** — отклонена в пользу знака типа; возврат = новая спека.
- **Реакция на действие зверя** — D19 только про удар игрока.
- **Новый UI** — ни панелей, ни иконок, ни счётчиков.
- **Остальные подсистемы этапа 4** (D06 v2 + D10 v3, D17, D15) — каждый своим циклом спека → план → задачи.

## Риски

1. **Проза начнёт повторяться** — посев мал. Принято сознательно, расширение запланировано.
2. **Вердикт и число читаются как противоречие** — руна в резист поднимает урон, а проза говорит «резист». Это не противоречие (элемент безусловен, D04), но глаголы обязаны говорить о **типе**, а не о силе. Проверка Task 1 держит это явно.
3. **Серия по вердикту — прокси замысла §11.10** («тупиковое оружие 2–3 раунда»). На смешанных наборах может усилить вводную там, где игрок перебирает. Уточнение — вместе с расширением пула.
4. **Открытие `pick_phrase` наружу** — единственная правка интерфейса в подсистеме. Альтернатива (вторая реализация взвешивания) запрещена правилом «один источник на правило», поэтому выбрана правка.
