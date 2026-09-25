# Этап 3: каталог, ранги заказов, экономика — план реализации

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development (recommended) or executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Привести к дизайну v1.10 три слоя, оставшиеся от старой игры: каталог оружия (шесть стволов, матрица 3×2), доступ к заказам по шести рангам, и экономику, сходящуюся по замеру.

**Architecture:** Данные оружия — по одному ресурсу на ствол, магазин строится из `Database.weapons`, поэтому новые стволы появляются без правок экрана. Доступ к заказам переезжает из правила «ранг = тир» в **порог ранга у тира** — одна таблица остаётся источником. Замер (`--loop`) получает учёт must-buy и снимается на 25 охотах, потому что при трёх днях за поход 45 дней дают ровно 15 охот.

**Tech Stack:** Godot 4.7.2, GDScript. Проверки — headless-режимы, отчёты читаются файлами.

**Spec:** `docs/2026-09-24-stage3-catalog-economy-design.md`
**Дизайн:** `docs/dizain_hunter.md` §12.2 (каталог), §8.1 (шкала рангов), §12.10 (трофеи)

## Global Constraints

- Движок: `F:\WORK\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe`, проект `F:\WORK\hunter`.
- Разделитель `--` перед режимом **обязателен**; отчёты читать **файлами** (`Get-Content <файл> -Encoding UTF8`), **удалять перед прогоном**.
- `core/` — чистый GDScript: ни `Node`, ни `SceneTree`, ни сцен. Отступы — табы.
- Правки `.gd`/`.tres` — **только инструментом `edit`** (иначе BOM пачкает дифф).
- **Идентификаторы ресурсов оружия НЕ меняются** (`blade`, `bow`, `mace`, `spear`): на них держатся `GameState.owned_weapons`, `Database.weapon(&"bow")` в проверках и `weapon_id` в забеге. Меняется только `title` (то, что видит игрок).
- **Цены берутся из таблицы §12.2 дизайна**, а не из гипотез β.1/β.2: снижение ранних цен и подъём трофеев в игре **не применялись** (`PRICE_MULTIPLIER = 1.0`), и подгонять под них нельзя.
- **Ожидаемый красный `--validate` — три ламантовы строки** (тупик + две записи фазы «Истощение» перекрыты резистами). Это открытый вопрос дизайна (§14.1), **не глушить**.
- Обёртка проверок читает вердикт **внутри** отчётов: строка с «ПРОВАЛ» в начале и маркеры `VALIDATION FAILED` / `SMOKE FAILED` / `LOAD FAILED` ломают вердикт.
- **В дереве есть чужие незакоммиченные правки** (`art/monsters/hruz.png`, `docs/ART_*.md`, переименование `.bat`). Не трогать, не коммитить, не откатывать. Перед коммитом проверять `git show --stat HEAD`.

## Файловая структура

| Файл | Ответственность | Что с ним |
|---|---|---|
| `content/weapons/*.tres` | По одному стволу на ресурс | Переименовать `blade`, поправить `spear`, завести `sling` и `chakram`, снять `crossbow` |
| `core/ui_data/city_data.gd` | Тиры заказов и доступ по рангу | Порог ранга у тира вместо «ранг = тир» |
| `core/sim/loop_sim.gd` | Замер цикла, бот, экономика | Учёт must-buy; замер на 25 охотах |
| `core/sim/balance_sim.gd` | Замер боёв по сборкам | Подписи сборок после переименования |
| `core/sim/checks/logic_checks.gd` | Сторожа | Сторож доступа по рангам |
| `core/sim/content_validator.gd` | Инварианты контента | Проверка, что арбалета нет, а матрица полна |

---

## Task 1: Каталог оружия — матрица 3×2

**Files:**
- Modify: `content/weapons/blade.tres` (title), `spear.tres` (урон и цена)
- Create: `content/weapons/sling.tres`, `content/weapons/chakram.tres`
- Delete: `content/weapons/crossbow.tres`
- Modify: `core/sim/balance_sim.gd` (подписи сборок)
- Modify: `core/sim/content_validator.gd` (инвариант полноты матрицы)

**Interfaces:**
- Consumes: `WeaponData` (`id`, `title`, `range_id`, `damage_type`, `base_damage`, `price`), `MonsterData.PHYSICAL_TYPES`, `RANGE_MELEE`, `RANGE_RANGED`.
- Produces: шесть стволов, покрывающих все шесть ячеек «дальность × тип»; `Database.weapons` отдаёт ровно их.

- [ ] **Step 1: Написать падающую проверку полноты матрицы**

В `core/sim/content_validator.gd` рядом с проверкой «каждое оружие кому-то нужно» добавить проверку, что матрица «дальность × физический тип» **закрыта полностью и без дублей**:

```gdscript
	# Матрица (дальность × физический тип) обязана быть закрыта ровно один раз
	# каждой ячейкой: шесть оружий D20 — это все шесть сочетаний. Дубль означает
	# два ствола с одной ролью (так в игре жили Лук и Арбалет), пробел — роль,
	# которую нечем занять (так не было дальнего дробящего и дальнего режущего).
	var cells := {}
	for id in Database.weapons.keys():
		var w: WeaponData = Database.weapons[id]
		if not MonsterData.is_physical_subtype(w.damage_type):
			continue
		var cell := "%s|%s" % [w.range_id, w.damage_type]
		if cells.has(cell):
			out.append("каталог: ячейка «%s» занята дважды — «%s» и «%s»" % [
				cell, cells[cell], w.title])
		cells[cell] = w.title
	for rng in [MonsterData.RANGE_MELEE, MonsterData.RANGE_RANGED]:
		for t in MonsterData.PHYSICAL_TYPES:
			var cell := "%s|%s" % [rng, t]
			if not cells.has(cell):
				out.append("каталог: ячейка «%s» пуста — этой роли нет ни у одного оружия" % cell)
```

- [ ] **Step 2: Прогнать — ожидается КРАСНОЕ с двумя пробелами**

```
cmd /c "F:\WORK\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe --headless --path F:\WORK\hunter --quit-after 900 -- --validate --log-file F:\WORK\hunter\_glog.txt"
```

Ожидается в `_validate_out.txt`: `каталог: ячейка «ranged|crush» пуста` и `каталог: ячейка «ranged|slash» пуста` (это праща и чакрам). Дубль `ranged|pierce` при этом **не назван только потому, что правило ловит его по ключу** — проверь в выводе, что он есть: если его нет, значит `cells` затирает значение и проверка дублей не работает.

- [ ] **Step 3: Поправить существующие стволы**

`content/weapons/blade.tres`: `title = "Клинок"` → `title = "Меч"`.
`content/weapons/spear.tres`: `base_damage = 3` → `4`, `price = 15` → `25`.

- [ ] **Step 4: Завести Пращу и Чакрам**

Создать `content/weapons/sling.tres` по образцу `bow.tres`:

```
[gd_resource type="Resource" script_class="WeaponData" load_steps=2 format=3]

[ext_resource type="Script" path="res://core/model/weapon_data.gd" id="1_wpn"]

[resource]
script = ExtResource("1_wpn")
id = &"sling"
title = "Праща"
range_id = &"ranged"
damage_type = &"crush"
base_damage = 3
price = 15
```

Создать `content/weapons/chakram.tres` так же, с `id = &"chakram"`, `title = "Чакрам"`,
`range_id = &"ranged"`, `damage_type = &"slash"`, `base_damage = 3`, `price = 40`.

**Не копируй арт-поля** из чужих стволов, если их нет в образце: пустое поле означает
текстовый плейсхолдер, и это допустимо.

- [ ] **Step 5: Снять Арбалет**

Удалить файл `content/weapons/crossbow.tres`. Затем проверить, что на него нигде нет ссылок:

```
cd F:\WORK\hunter
Select-String -Path core\*.gd,core\*\*.gd,core\*\*\*.gd,ui\*\*.gd,ui\*\*\*.gd,content\*\*.tres,content\*.tres,autoload\*.gd -Pattern "crossbow|Арбалет"
```

Ожидается: пусто (упоминания в `docs/` допустимы — это история решений).

- [ ] **Step 6: Поправить подписи сборок в `balance_sim.gd`**

Три сборки называют оружие «Клинок» (`клинок_физ`, `клинок_яд`, `клинок_огонь_мастер`).
Ключи словаря **не менять** (на них ссылаются артефакты замеров и отчёты), меняются только
`title`: «Клинок» → «Меч». Это подписи отчёта, а не игровой текст.

- [ ] **Step 7: Прогнать — ожидается ЗЕЛЁНО**

```
cmd /c "tools\run_checks.cmd"
```

Ожидается: красный **ровно один** режим (`--validate`, три ламантовы строки), пробелов
каталога в выводе нет. Если появилась строка про дубль или пустую ячейку — матрица
собрана неверно, разбираться, а не глушить.

- [ ] **Step 8: Коммит**

```
git add content/weapons core/sim/balance_sim.gd core/sim/content_validator.gd
git commit -m "Каталог D20: матрица 3×2 из шести стволов; Арбалет снят, Праща и Чакрам заведены"
```

---

## Task 2: Доступ к заказам по шести рангам

**Files:**
- Modify: `core/ui_data/city_data.gd` (`ORDER_RANKS`, `available_monsters`)
- Modify: `core/sim/checks/logic_checks.gd` (сторож доступа)
- Test: `core/sim/checks/logic_checks.gd`

**Interfaces:**
- Consumes: `Database.monster()`, `GameState.RANKS`.
- Produces: `ORDER_RANKS[tier]["min_rank"]`; `available_monsters(rank)` отбирает тиры по порогу.

- [ ] **Step 1: Написать падающую проверку доступа по рангам**

Добавить в `_status_mechanics()` перед `return out`:

```gdscript
	# Ранги заказов (D21 + §8.1): доступ к тиру открывается ПОРОГОМ ранга, а не
	# правилом «ранг = тир». Старое правило делало Ламанта достижимым на ранге 3
	# («Ветеран»), а ранг 4 («Мастер») не открывал ничего нового.
	var d21_orders := {
		0: [], 1: [], 2: ["skorb"], 3: ["ashmother"], 4: ["lament"], 5: [],
	}
	var d21_orders_fail: Array[String] = []
	for r in range(0, 6):
		var ids: Array = []
		for o in CityData.available_monsters(r):
			ids.append(String(o["monster_id"]))
		var must_gain: Array = d21_orders[r]
		for m in must_gain:
			if not ids.has(m):
				d21_orders_fail.append("ранг %d: «%s» недоступен, а обязан быть" % [r, m])
		# Ламант обязан появляться ТОЛЬКО на ранге 4 и выше.
		if r < 4 and ids.has("lament"):
			d21_orders_fail.append("ранг %d: Ламант доступен раньше срока" % r)
		# Ранг 5 новых заказов не открывает: доступ совпадает с рангом 4.
		if r == 5:
			var prev: Array = []
			for o in CityData.available_monsters(4):
				prev.append(String(o["monster_id"]))
			if ids.size() != prev.size():
				d21_orders_fail.append("ранг 5 открывает новые заказы (%d против %d)" % [
					ids.size(), prev.size()])
	out.append("заказы по рангам: 0:%d 1:%d 2:%d 3:%d 4:%d 5:%d видов" % [
		CityData.available_monsters(0).size(), CityData.available_monsters(1).size(),
		CityData.available_monsters(2).size(), CityData.available_monsters(3).size(),
		CityData.available_monsters(4).size(), CityData.available_monsters(5).size()])
	if d21_orders_fail.is_empty():
		out.append("ок заказов: доступ открывается по шести рангам (§8.1)")
	else:
		out.append("ПРОВАЛ заказов: %s" % "; ".join(d21_orders_fail))
```

- [ ] **Step 2: Прогнать и убедиться, что КРАСНЕЕТ**

```
cmd /c "F:\WORK\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe --headless --path F:\WORK\hunter --quit-after 900 -- --probe --log-file F:\WORK\hunter\_glog.txt"
```

Ожидается `ПРОВАЛ заказов: ранг 3: Ламант доступен раньше срока` (сейчас `max_tier = rank`
делает его достижимым на 3). Если проверка зелёная — она ничего не сторожит.

- [ ] **Step 3: Ввести порог ранга у тира**

**Отступление от спеки, которое надо принять осознанно.** Спека этапа говорит
«физических тиров остаётся **четыре**», но её же таблица доступа требует, чтобы ранг 3
давал Пепел-Мать, а ранг 2 — Скорба. Одним элитным тиром это невыразимо: у тира один
порог. Поэтому элитный тир **разделяется на два** — «элитный» (Скорб, ранг 2) и
«элитный II» (Пепел-Мать, ранг 3), и тиров становится **пять**. Дизайн §4.6–4.7 даёт
этим видам разные тиры T3 и разные образы, так что разделение не выдумано кодом.
**Цена:** `GLORY_BY_TIER` и `death_penalty` читают тир, поэтому оба элитных тира обязаны
давать **4** славы (§8.2), а «легендарный» — 10. Сверка — в шаге 4.

В `core/ui_data/city_data.gd` заменить `ORDER_RANKS` и `available_monsters`:

```gdscript
## Тиры заказов и ранг, с которого тир открывается (GDD 4.x + §8.1).
##
## Раньше здесь стояло правило «ранг = тир» (`max_tier = clampi(rank, 0, 3)`), и оно
## делало Ламанта достижимым на ранге 3 («Ветеран»), а ранг 4 («Мастер») не открывал
## ничего. Дизайн разводит элитных по двум рангам: ранг 2 — первый, ранг 3 — второй,
## ранг 4 — Ламант. Порог живёт в таблице, потому что это свойство тира, а не ранга.
##
## Элитных ДВА тира, а не один: одному тиру не выразить два разных порога.
const ORDER_RANKS := {
	0: {"title": "стартовый", "min_rank": 0, "monsters": ["hruz", "shipun"]},
	1: {"title": "продвинутый", "min_rank": 2, "monsters": ["gromun", "tleun"]},
	2: {"title": "элитный", "min_rank": 2, "monsters": ["skorb"]},
	3: {"title": "элитный II", "min_rank": 3, "monsters": ["ashmother"]},
	4: {"title": "легендарный", "min_rank": 4, "monsters": ["lament"]},
}
```

`available_monsters` отбирает по порогу:

```gdscript
static func available_monsters(rank: int) -> Array:
	var out: Array = []
	for tier in ORDER_RANKS.keys():
		if rank < int(ORDER_RANKS[tier]["min_rank"]):
			continue
		for m in ORDER_RANKS[tier]["monsters"]:
			if Database.monster(StringName(m)) == null:
				continue
			out.append({"monster_id": m, "tier": int(tier), "tier_title": ORDER_RANKS[tier]["title"]})
	return out
```

- [ ] **Step 4: Проверить, что слава за тир и порядок в списке не сломались**

`GLORY_BY_TIER` и `death_penalty` читают **тир заказа**; после расширения таблицы до пяти
тиров ключ 4 обязан давать 10 (Ламант), а 2 и 3 — 4. Прогнать `--probe` и убедиться, что
проверки славы (если есть) не покраснели, затем `--outcomes`, `--prep`, `--swap`.

- [ ] **Step 5: Прогнать и убедиться, что ЗЕЛЕНО**

```
cmd /c "F:\WORK\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe --headless --path F:\WORK\hunter --quit-after 900 -- --probe --log-file F:\WORK\hunter\_glog.txt"
```

Ожидается `ок заказов` и строка `заказы по рангам: 0:N 1:N 2:N 3:N 4:N 5:N видов`,
где 0 и 1 совпадают, 2 больше 1 (Скорб, Громун, Тлеун), 3 больше 2 (Пепел-Мать),
4 больше 3 (Ламант), 5 совпадает с 4.

- [ ] **Step 6: Доказать, что сторож краснеет**

Временно вернуть в `available_monsters` правило `max_tier = clampi(rank, 0, 3)` →
прогнать → ожидается `ПРОВАЛ заказов: ранг 3: Ламант доступен раньше срока`. Вернуть
как было, убедиться в зелёном и в пустом `git diff core/ui_data/city_data.gd`.

- [ ] **Step 7: Коммит**

```
git add core/ui_data/city_data.gd core/sim/checks/logic_checks.gd
git commit -m "Доступ к заказам по шести рангам: порог у тира вместо «ранг = тир»"
```

---

## Task 3: Замер экономики — учёт must-buy и 25 охот

**Files:**
- Modify: `core/sim/loop_sim.gd`
- Modify: `tools/run_headless.ps1` (только если `--loop` требует аргумент)

**Interfaces:**
- Consumes: `GameState.coins`, `GameState.owned_weapons`, `GameState.rank`, `SkillsData.SKILLS`.
- Produces: отчёт `--loop` печатает, какие предметы узкого набора куплены, на каком ранге и за сколько.

- [ ] **Step 1: Ввести список узкого набора (must-buy) как данные**

Рядом с `LOADOUTS` в `core/sim/loop_sim.gd` (или в начале файла) добавить:

```gdscript
## Узкий набор (A-narrowed): минимум, которым берётся Ламант. Список — ДАННЫЕ,
## а не условие в коде: цена набора меняется от правок баланса, и замер обязан
## показывать, что именно куплено и когда, иначе «must-buy сходится» непроверяемо.
##
## Оружие в списке есть (молот и лук), хотя на старте оно бесплатно (F3): так
## отчёт видит, что набор закрыт, не считая его покупкой.
const MUST_BUY := {
	"skills": [&"read_signal", &"read_double", &"read_triple",
		&"wpn_dmg1", &"wpn_dmg2", &"wpn_dmg3",
		&"surv_armor1", &"surv_armor2", &"surv_armor3"],
	"weapons": [&"mace", &"bow"],
	"runes": [&"wpn_mod", &"wpn_crit2"],
	"armor": [&"light", &"heavy"],
	"advice": ["shipun", "gromun", "tleun", "skorb", "ashmother", "lament"],
}
```

**Проверь по факту:** идентификаторы навыков и брони сверить с `SkillsData.SKILLS` и
`content/armor/*.tres`; если что-то названо иначе — поправить список, а не подгонять код.

- [ ] **Step 2: Считать закрытие набора по ходу прогона**

В `_run_player` завести счётчики и записывать момент закрытия:

```gdscript
	## Что из узкого набора куплено и на каком ранге: главное число приёмки этапа 3.
	var must_buy_got: Dictionary = {}      # id -> ранг, на котором куплено
	var must_buy_done_at := -1             # ранг, на котором набор закрыт целиком
```

После каждой охоты (там, где уже считается `coins_spent`) добавить вызов помощника:

```gdscript
## Отмечает купленное из узкого набора. Оружие, броня и навыки читаются из GameState:
## у него есть ВСЁ нужное — `has_skill`, `owned_weapons`, `owned_armors` (проверено
## разведкой, выдумывать поля не надо).
func _note_must_buy(got: Dictionary) -> void:
	for id in MUST_BUY["skills"]:
		if GameState.has_skill(id) and not got.has("skill:" + String(id)):
			got["skill:" + String(id)] = GameState.rank
	for id in MUST_BUY["weapons"]:
		if id in GameState.owned_weapons and not got.has("weapon:" + String(id)):
			got["weapon:" + String(id)] = GameState.rank
	for id in MUST_BUY["armor"]:
		if id in GameState.owned_armors and not got.has("armor:" + String(id)):
			got["armor:" + String(id)] = GameState.rank
```

**Молот, лук и лёгкая броня закрываются на старте** (`owned_weapons = [&"bow", &"mace"]`,
`owned_armors = [&"light"]`), поэтому в отчёте они получат ранг 0 — это и есть проверка
F3: набор закрыт сразу, а не куплен.

- [ ] **Step 3: Печатать набор в отчёте**

В сводку прогона добавить строку, из которой видно и полноту, и цену:

```gdscript
	out.append("узкий набор: куплено %d из %d, закрыт на ранге %d, потрачено %d" % [
		must_buy_got.size(), _must_buy_total(), must_buy_done_at, coins_spent])
```

где `_must_buy_total()` считает общее число отслеживаемых позиций.

- [ ] **Step 4: Прогнать замер на 25 охотах**

```
cmd /c "F:\WORK\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe --headless --path F:\WORK\hunter --quit-after 2400 -- --loop 25 --log-file F:\WORK\hunter\_glog.txt"
```

Перед прогоном удалить `_loop_out.txt`. Ожидается строка `узкий набор: …` и, впервые,
строка `ЛЕГЕНДА: охота N, дней D, слава S` — при трёх днях за поход 45 дней дают
**ровно 15 охот**, поэтому 25 — достаточный запас.

- [ ] **Step 5: Учесть must-buy в отчёте как отдельный блок**

Добавить в отчёт таблицу: позиция → ранг покупки → цена. Из неё должно быть видно,
**что докупается после Легенды** (если докупается) — это и есть «набор не закрывается».

- [ ] **Step 6: Прогнать все режимы и закоммитить**

```
cmd /c "tools\run_checks.cmd"
git add core/sim/loop_sim.gd
git commit -m "Замер считает узкий набор: что куплено, на каком ранге и за сколько"
```

Ожидается: красный ровно один режим (`--validate`, три ламантовы строки).

---

## Task 4: Подгонка экономики по замеру

**Files:**
- Modify: `core/ui_data/market_data.gd` (`PRICE_MULTIPLIER`) и/или `content/monsters/*.tres` (цены трофеев)
- Modify: `docs/2026-09-24-stage3-catalog-economy-design.md` (числа замеров)

**Interfaces:**
- Consumes: отчёт `--loop 25` из Task 3.
- Produces: экономика, у которой набор закрывается, буфер положителен, Легенда за 10–15 охот.

- [ ] **Step 1: Снять базовый замер и записать числа**

Прогнать `--loop 25` (и повторить на трёх сидах, если у прогона есть параметр сида) и
записать: доход, траты, кошелёк в конце, ранг закрытия набора, охоту Легенды.

- [ ] **Step 2: Решить одним из двух рычагов — и обосновать выбор замером**

- **Если доход выше нужного** (сейчас `PRICE_MULTIPLIER = 1.0`, доход цикла был ~1020):
  поднимать **цены покупок** (F1), а не резать трофеи.
- **Если набор не закрывается** (докупается после Легенды или кошелёк в минусе):
  поднимать **цены трофеев** умеренно.

Правка — **одно число за раз**, с прогоном после каждого. Записывать в спеку этапа
таблицу «правка → что стало с тремя свойствами приёмки».

- [ ] **Step 3: Проверить, что минимум из трёх свойств приёмки достигнут**

Приёмка (согласована с пользователем): **набор закрывается** · **буфер положителен**
· **Легенда за 10–15 охот**. Точные числа дохода/трат фиксируются замером.

- [ ] **Step 4: Коммит**

```
git add core/ui_data/market_data.gd content/monsters docs/2026-09-24-stage3-catalog-economy-design.md
git commit -m "Экономика этапа 3: цены подогнаны замером до закрытия узкого набора"
```

---

## Task 5: Прогон всего и запись результатов

**Files:**
- Modify: `docs/2026-09-24-migration-to-v1.10-design.md` (раздел 9)

- [ ] **Step 1: Полный прогон всех режимов**

```
cmd /c "tools\run_checks.cmd"
```

Ожидается: `PROBLEMS: 1`, код 1, красный ровно `--validate` с **тремя** ламантовыми
строками; остальные десять режимов зелёные.

- [ ] **Step 2: Замер боёв после смены каталога**

```
cmd /c "F:\WORK\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe --headless --path F:\WORK\hunter --quit-after 1800 -- --sim --battles 200 --log-file F:\WORK\hunter\_glog.txt"
```

Сверить с `_sim_after_2b.json` и объяснить расхождения **поимённо**. Ожидаемые причины:
у копья урон 3 → 4; у Тлеуна слабость яд → колющее (дальний); лук и копьё стали «нужны».

- [ ] **Step 3: Записать раздел 9 в спеку переноса**

Дописать в `docs/2026-09-24-migration-to-v1.10-design.md` раздел «## 9. Результаты этапа 3»:
что изменилось в каталоге, рангах и экономике; таблица «правка → замер»; охота Легенды
и день; что осталось необъяснённым (если осталось — назвать прямо).

- [ ] **Step 4: Коммит**

```
git add docs/2026-09-24-migration-to-v1.10-design.md
git commit -m "Этап 3 закрыт: каталог, ранги и экономика сверены замером"
```

---

## Что НЕ входит

- **Подсистемы этапа 4:** накопительное досье (D06 v2), шкала знаний (D10 v3),
  альтернативная цель (D15), хроника гильдии (D17), нарративная реакция на удар (D19).
- **Вопрос про Ламанта** (40 раундов вместо 18) — открыт, решается отдельно.
- **β.1/β.2/β.3** как самостоятельные правки: это гипотезы для другой кривой, цены
  берутся фактические из §12.2 и подгоняются замером.

## Риски

1. **Приёмка «10–15 охот» может не сойтись.** Наш бот за 10 охот доходит только до
   «Мастера» (слава 93 при пороге Легенды 100). Нужен `--loop 25`; если путь длиннее,
   это результат — решать ценами и славой, а не подгонкой лимита замера.
2. **Пять тиров вместо четырёх меняют славу и штрафы.** `GLORY_BY_TIER` и `death_penalty`
   читают тир: после расширения оба элитных тира обязаны давать 4 славы (§8.2), а Ламант — 10.
   Ошибка здесь тихо сместит всю прогрессию, поэтому шаг 4 Task 2 требует сверки.
3. **Переименование «Клинок» → «Меч» обесценивает старые артефакты замеров.** Сравнивать
   `_sim_*` по подписям сборок после правки нельзя — только по ключам.
4. **Экономика сойдётся на неверном основании.** Доход 1020 — это доход на стартовом
   наборе и при малых покупках. Все правки цен проверяются замером **с учётом must-buy**.
