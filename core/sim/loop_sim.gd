extends RefCounted
class_name LoopSim
## Прогон полного игрового цикла без графики: город → заказ → след → бой → итог.
##
## Зачем: это проверка не баланса одного боя, а экономики и прогрессии. Именно
## здесь вылезает то, что в GDD 12.12 было посчитано на глаз: сколько охот нужно
## до Легенды и хватает ли дохода на прокачку.

## --- Узкий набор (must-buy) ---------------------------------------------------
##
## Минимум, которым берётся Ламант. Список — ДАННЫЕ, а не условие в коде: цена
## набора меняется от правок баланса, и замер обязан показывать, что именно
## куплено и когда, иначе «must-buy сходится» непроверяемо.
##
## Оружие в списке есть (молот и лук), хотя на старте оно бесплатно (F3): так
## отчёт видит, что набор закрыт, не считая его покупкой.
##
## Руны читаются через навыки: руна в игре — это навык (`SkillsData.RUNE_SKILLS`),
## отдельного поля «куплена руна» нет, и выдумывать его замеру незачем.
##
## Советы Старика входят в набор наравне с остальным. Раньше они стояли с источником
## «none»: состояние покупки совета жило в экране города (`city_screen.advice_bought`),
## экран уничтожается при каждом возвращении в город, и прогон без сцен его не видел.
## Теперь состояние — в `GameState.advice_bought` (Task 3б), поэтому замер обязан его
## читать. Цифры — те, что печатает отчёт: шесть советов стоят 80 монет, а весь набор
## по прайсу — 675, из которых бот платит 605 (молот, лук и лёгкая броня бесплатны по
## F3). В первой редакции здесь стояло «80 из 620» — цена набора без бесплатных
## позиций; числа разъехались потому, что комментарий считали по спеке, а не по прайсу
## игры. Сторож прайса — сам отчёт: строка «цена по прайсу» печатает факт.
const MUST_BUY := {
	"skills": [&"read_signal", &"read_double", &"read_triple",
		&"wpn_dmg1", &"wpn_dmg2", &"wpn_dmg3",
		&"surv_armor1", &"surv_armor2", &"surv_armor3"],
	"weapons": [&"mace", &"bow"],
	"runes": [&"wpn_mod", &"wpn_crit2"],
	"armor": [&"light", &"heavy"],
	"advice": ["shipun", "gromun", "tleun", "skorb", "ashmother", "lament"],
}

## Как называется и откуда читается каждая категория набора. Одна таблица на всё:
## `source` — откуда брать «куплено ли» (none = замер этого не видит),
## `price_from` — откуда брать цену. Категория, добавленная в MUST_BUY без строки
## здесь, сломает прогон громко, а не посчитает набор молча неполным.
const MUST_BUY_KINDS := {
	"skills": {"title": "навык", "prefix": "skill", "source": "skill", "price_from": "skill"},
	"weapons": {"title": "оружие", "prefix": "weapon", "source": "weapon", "price_from": "weapon"},
	"runes": {"title": "руна", "prefix": "rune", "source": "skill", "price_from": "skill"},
	"armor": {"title": "броня", "prefix": "armor", "source": "armor", "price_from": "armor"},
	"advice": {"title": "совет", "prefix": "advice", "source": "advice", "price_from": "advice"},
}


## Порядок покупок бота: ЧТО покупать и в каком порядке. Это тоже ДАННЫЕ, а не условие
## в коде, и по той же причине, что MUST_BUY: приёмка этапа 3 спрашивает «закрывается
## ли узкий набор по ходу пути», и ответ обязан быть следствием экономики, а не вкуса
## бота. Раньше бот брал четыре фиксированных навыка, все стволы и `surv_armor2` —
## восемь отслеживаемых позиций набора он не покупал даже при 225 монетах в кошельке,
## и «набор закрывается» измеряло его политику.
##
## Правило порядка: по возрастанию ТРЕБУЕМОГО РАНГА (у навыка это поле `rank`;
## у оружия, брони и совета требования ранга в игре нет, поэтому они идут первыми),
## внутри ранга — по цене от дешёвой. Так в отчёте видны три разных ответа приёмки:
## «закрыт по пути» (все позиции закрыты до ранга 5), «закрыт после Легенды» и
## «не закрыт вовсе» — по одному счётчику их не различить.
##
## Таблица ОБЯЗАНА покрывать MUST_BUY целиком, и это проверяется, а не подразумевается
## (_must_buy_data_problems): забытая здесь позиция не покупалась бы никогда и молча
## висела бы в знаменателе набора.
const BUY_ORDER := [
	# Ранг 0 и всё, у чего требования ранга нет, — по цене.
	{"kind": "advice", "id": "shipun"},       # 5
	{"kind": "advice", "id": "gromun"},       # 10
	{"kind": "advice", "id": "tleun"},        # 10
	{"kind": "armor", "id": "light"},         # 15, был с начала (F3)
	{"kind": "advice", "id": "skorb"},        # 15
	{"kind": "advice", "id": "ashmother"},    # 15
	{"kind": "skills", "id": "read_signal"},  # 20
	{"kind": "runes", "id": "wpn_mod"},       # 20
	{"kind": "weapons", "id": "bow"},         # 25, был с начала (F3)
	{"kind": "skills", "id": "wpn_dmg1"},     # 25
	{"kind": "skills", "id": "surv_armor1"},  # 25
	{"kind": "advice", "id": "lament"},       # 25
	{"kind": "weapons", "id": "mace"},        # 30, был с начала (F3)
	{"kind": "armor", "id": "heavy"},         # 40
	# Ранг 1.
	{"kind": "skills", "id": "read_double"},  # 40
	{"kind": "skills", "id": "wpn_dmg2"},     # 45
	{"kind": "skills", "id": "surv_armor2"},  # 45
	# Ранг 2.
	{"kind": "skills", "id": "read_triple"},  # 60
	# Ранг 3.
	{"kind": "runes", "id": "wpn_crit2"},     # 65
	{"kind": "skills", "id": "wpn_dmg3"},     # 70
	{"kind": "skills", "id": "surv_armor3"},  # 70
]


## Политики выбора заказа — ДАННЫЕ, как MUST_BUY и BUY_ORDER. Политика это ВОПРОС,
## который замер задаёт игре, поэтому она живёт в профиле бота и называется в отчёте,
## а не спрятана в условии:
##
##  * «без тупиков» — высший доступный тир, по которому бот пробьёт слабость своим
##    стволом (с учётом известных ему рун). Заказ, где выбор оружия ничего не решает,
##    бот не берёт: штраф за смерть на легендарном тире — 12;
##  * «всегда высший тир» — высший доступный без оглядки на слабость, включая
##    легендарный. §14.1 считает Ламанта ПРОХОДИМЫМ («на идеальном чтении все пять
##    сборок дают 100 % побед»), а тупик у него — по отсутствию ВЫГОДНОЙ пары, не по
##    проходимости. Значит «не ходить в тупик» может быть слишком строгим, и это
##    обязано решить измерение, а не рассуждение.
const ORDER_POLICIES := {
	"open_weakness": {"title": "заказ без тупиков"},
	"highest_tier": {"title": "заказ — всегда высший тир"},
}


## Ключи сида бота. Это НЕ подписи, а идентификаторы игры профиля: два профиля с одной
## игрой (то же чтение, тот же выбор инструмента) обязаны получить ОДНИ броски, иначе
## разница между политиками смешалась бы с разницей в костях.
const SEED_NOVICE := "новичок (лук, чтение 45%)"
const SEED_EXPERT := "опытный (лучший инструмент, чтение 75%)"


## Как играет бот. Профиль — это ДАННЫЕ: чтение, выбор инструмента, политика заказа
## и ключ сида. Политика вынесена в профиль потому, что «не ходить в тупик» — решение
## ПРОФИЛЯ, а вопрос приёмки звучит иначе: доходит ли до Легенды бот, который берёт
## высший доступный тир, включая легендарный.
class Player:
	var read_accuracy: float
	var title: String
	var smart_tools: bool
	## Имя политики выбора заказа из ORDER_POLICIES.
	var order_policy: String
	## Ключ сида: см. SEED_NOVICE / SEED_EXPERT.
	var seed_key: String

	func _init(
		p_title: String, p_read: float, p_smart: bool, p_policy: String, p_seed_key: String
	) -> void:
		title = p_title
		read_accuracy = p_read
		smart_tools = p_smart
		order_policy = p_policy
		seed_key = p_seed_key


func run(hunts: int, out: Array[String], run_seed: int = 20260922) -> Array[Dictionary]:
	# Параметры прогона — ПЕРВЫМИ строками отчёта, а не только в трассе. Без них
	# артефакт не отвечает на вопрос «чем это снято», а приёмочные числа этапа 3
	# обязаны воспроизводиться командой: сид жил в `_loop_trace.txt`, и повторить
	# отчёт можно было, только заглянув в трассу.
	out.append("--- прогон ---")
	out.append("прогон: --loop %d, сид %d (три профиля)" % [hunts, run_seed])

	# Проверка ДАННЫХ набора — один раз на прогон, а не на каждого бота: опечатка в
	# MUST_BUY, в MUST_BUY_KINDS или в BUY_ORDER от игрока не зависит, и печатать её
	# дважды значило бы прятать её в повторе.
	out.append("--- узкий набор: проверка данных ---")
	var data_problems := _must_buy_data_problems()
	if data_problems.is_empty():
		out.append("набор: позиций %d, все категории описаны, все id есть в данных, BUY_ORDER покрывает набор" % _must_buy_total())
	else:
		for problem in data_problems:
			out.append("ПРОВАЛ набора: %s" % problem)
		# Категория без строки в MUST_BUY_KINDS — единственная поломка, после которой
		# отчёт построить НЕЛЬЗЯ: имени и источника у неё нет, и `_must_buy_source`
		# падает на первом же обращении. Измерено: прогон обрывался SCRIPT ERROR, а на
		# диске оставался ОБРЕЗАННЫЙ отчёт — начало бота без итогов, то есть числа,
		# которые читаются как измерение. Поэтому прогон останавливается сам, и в
		# отчёте остаётся причина, а не половина результата.
		#
		# Опечатка в id или расхождение с BUY_ORDER прогон НЕ останавливают: там
		# измерение остаётся осмысленным, а строка «ПРОВАЛ набора» называет, какая
		# именно позиция выпала.
		if not _must_buy_kinds_complete():
			return []

	# Три профиля: неопытный бот и ДВА опытных — с разными политиками заказа и одним
	# ключом сида. Опытные обязаны играть на одних бросках: иначе замер ответит на
	# вопрос «повезло ли политике», а не «работает ли политика».
	var players := [
		Player.new("новичок (лук, чтение 45%)", 0.45, false, "open_weakness", SEED_NOVICE),
		Player.new("опытный (лучший инструмент, чтение 75%) — заказ без тупиков",
			0.75, true, "open_weakness", SEED_EXPERT),
		Player.new("опытный (лучший инструмент, чтение 75%) — всегда высший тир",
			0.75, true, "highest_tier", SEED_EXPERT),
	]
	## Числа каждого профиля в машинном виде — их читает скан по сидам (`run_scan`).
	## Возвращаются наружу, а не пересчитываются: см. `_run_player`.
	var facts: Array[Dictionary] = []
	for p in players:
		out.append("")
		out.append("========== %s ==========" % p.title)
		facts.append(_run_player(p, hunts, out, run_seed))
	return facts


## Разброс по сидам: `seeds` прогонов подряд (сиды `base_seed … base_seed + seeds - 1`),
## в каждом — те же три профиля, что и у одного `run`.
##
## Зачем отдельный режим. «30 сидов» в спеке этапа 3 существовали артефактом РУЧНЫХ
## прогонов: замер умел один сид, и разброс нельзя было повторить командой — то есть
## доказательство нельзя было проверить. Здесь сиды перебирает тот же замер, поэтому
## разброс снимается одной командой:
##
##     godot --headless --path <проект> -- --loop 25 --seeds 30
##
## Скан ВТОРИЧЕН и приёмку не заменяет: приёмочные числа сняты одним прогоном на сиде
## по умолчанию, а скан говорит, насколько они устойчивы. Это сказано и в сводке —
## иначе «25 из 30 забегов дошли до Легенды» прочиталось бы как приёмка.
##
## Полные отчёты каждого прогона пишутся в `full_out`, сводка возвращается. Сводка без
## первичных отчётов не проверяема (число не с чем сверить), а первичные без сводки не
## читаются. Файлы раскладывает вызывающий: куда писать — дело проверки, а не замера.
func run_scan(
	hunts: int, full_out: Array[String], base_seed: int, seeds: int
) -> Array[String]:
	var out: Array[String] = []
	out.append("=== разброс по сидам ===")
	out.append("скан: --loop %d --seeds %d, сиды %d..%d, три профиля в каждом" % [
		hunts, seeds, base_seed, base_seed + seeds - 1])
	out.append("скан — ВТОРИЧНЫЙ замер вокруг приёмочного прогона: приёмка снята ОДНИМ сидом (--loop N --seed S), и разброс её не заменяет, а показывает, насколько она устойчива.")

	var facts: Array[Dictionary] = []
	for i in range(seeds):
		var seed_value := base_seed + i
		full_out.append("")
		full_out.append("########## сид %d ##########" % seed_value)
		facts.append_array(run(hunts, full_out, seed_value))

	# Раскладываем факты по подписям профилей, а не по числу «три»: второй копии
	# этого числа здесь быть не должно, а порядок берём из первого встреченного —
	# так сводка называет профили теми же словами, что отчёт.
	var order: Array[String] = []
	var by_profile: Dictionary = {}
	for f in facts:
		var title := String(f["title"])
		if not by_profile.has(title):
			by_profile[title] = []
			order.append(title)
		(by_profile[title] as Array).append(f)

	# Число фактов обязано быть ровно `seeds × профилей`. Расхождение означает, что
	# прогон оборвался (например, данные набора перестали сходиться и `run` вышел
	# раньше) — тогда сводка была бы посчитана по ЧАСТИ сидов и выглядела бы
	# измерением. Молчаливый неполный скан — тот же класс, что стухший отчёт.
	if order.is_empty() or facts.size() != seeds * order.size():
		out.append("ПРОВАЛ СКАНА: фактов %d на %d сидов и %d профилей — прогон оборвался, полные отчёты в _loop_scan_full.txt" % [
			facts.size(), seeds, order.size()])
		return out

	for title in order:
		var rows: Array = by_profile[title]
		var legend: Array[int] = []
		var legend_days: Array[int] = []
		var over: Array[int] = []
		var closed_ranks: Array[int] = []
		var mins: Array[int] = []
		var ends: Array[int] = []
		var incomes: Array[int] = []
		var spent: Array[int] = []
		var closed := 0
		var marks: PackedStringArray = PackedStringArray()
		for row in rows:
			var f: Dictionary = row
			if int(f["legend_hunt"]) > 0:
				legend.append(int(f["legend_hunt"]))
				legend_days.append(int(f["legend_day"]))
			if int(f["run_over_hunt"]) > 0:
				over.append(int(f["run_over_hunt"]))
			if int(f["closed_rank"]) >= 0 and int(f["must_buy_got"]) >= int(f["must_buy_total"]):
				closed += 1
				closed_ranks.append(int(f["closed_rank"]))
			mins.append(int(f["min_coins"]))
			ends.append(int(f["coins_end"]))
			incomes.append(int(f["income"]))
			spent.append(int(f["spent"]))
			marks.append(_scan_mark(f))
		out.append("")
		out.append("профиль: %s" % title)
		out.append("  Легенда: %d из %d забегов%s%s" % [
			legend.size(), rows.size(),
			_scan_range("охота", legend), _scan_range("дней", legend_days)])
		out.append("  окончательная смерть: %d из %d%s" % [
			over.size(), rows.size(), _scan_range("охота", over)])
		out.append("  узкий набор: закрыт в %d из %d%s" % [
			closed, rows.size(), _scan_range("ранг закрытия", closed_ranks)])
		out.append("  минимум на счету %s; остаток в кошельке %s" % [
			_scan_range("", mins), _scan_range("", ends)])
		out.append("  доход %s; траты %s" % [_scan_range("", incomes), _scan_range("", spent)])
		out.append("  по сидам (охота до Легенды; «—» не дошёл, «†N» забег кончился на охоте N, «*» набор не закрыт):")
		out.append("    " + ", ".join(marks))

	# ПРОВАЛы, которые поймали сами прогоны сидов, обязаны быть видны и в сводке:
	# иначе «30 из 30 дошли» рядом с красным отчётом одного сида читается как успех.
	var fails := 0
	for line in full_out:
		if String(line).begins_with("ПРОВАЛ"):
			fails += 1
	if fails > 0:
		out.append("ПРОВАЛ СКАНА: в отчётах сидов %d строк «ПРОВАЛ» — скан зелёным не считается" % fails)
	else:
		out.append("отчёты сидов: строк «ПРОВАЛ» нет")
	return out


## Отметка одного забега для строки «по сидам»: номер охоты, на которой взята Легенда,
## «—» если не взята, «†N» — забег кончился окончательной смертью на охоте N, «*» —
## узкий набор не закрыт. Компактная строка показывает, ЧЕМ сделан разброс, а не
## только его крайние числа: «25, 21, 23…» и «—, —, 23…» читаются по-разному.
func _scan_mark(f: Dictionary) -> String:
	var mark := "—"
	if int(f["legend_hunt"]) > 0:
		mark = str(int(f["legend_hunt"]))
	if int(f["run_over_hunt"]) > 0:
		mark += "†%d" % int(f["run_over_hunt"])
	if int(f["closed_rank"]) < 0:
		mark += "*"
	return mark


## Хвост сводки по списку чисел: «, охота 17..25, медиана 20». Пустой список не даёт
## ничего: строка «охота .. » на пустоте читалась бы как измерение нуля, которого не
## было, а «нет ни в одном забеге» дублировало бы счётчик рядом. Медиана — ВЕРХНЯЯ из
## двух средних при чётном числе забегов: половинка охоты выглядела бы точностью,
## которой у целых охот нет.
##
## Форма зависит от метки: с меткой строка — ХВОСТ фразы (ведущая запятая, «Легенда:
## 22 из 30 забегов, охота 17..25»), без метки — подстановка в готовую фразу
## («минимум на счету 0..5, медиана 0»).
func _scan_range(label: String, values: Array[int]) -> String:
	if values.is_empty():
		return ""
	var sorted := values.duplicate()
	sorted.sort()
	var tail := "%d..%d, медиана %d" % [
		sorted[0], sorted[sorted.size() - 1], sorted[sorted.size() / 2]]
	return tail if label.is_empty() else ", %s %s" % [label, tail]


## Веха: пишется в отчёт и в отдельный файл, чтобы при зависании было видно шаг.
func _milestone(out: Array[String], text: String) -> void:
	out.append("   · " + text)
	var f := FileAccess.open("res://_loop_progress.txt", FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(out))
		f.close()


## Диагностическая трасса: пишется в отдельный файл, чтобы обрыв прогона был виден
## как последняя дошедшая строка, а не как «отчёт просто короткий».
func _trace(text: String) -> void:
	var f := FileAccess.open("res://_loop_trace2.txt", FileAccess.READ_WRITE)
	if f == null:
		f = FileAccess.open("res://_loop_trace2.txt", FileAccess.WRITE)
	if f == null:
		return
	f.seek_end()
	f.store_string(text + "\n")
	f.close()


func _run_player(player: Player, max_hunts: int, out: Array[String], run_seed: int = 20260922) -> Dictionary:
	GameState.reset()
	GameState.coins = 30  # стартовые деньги из GDD 12.12 (первый этап: доход 30)
	RNGService.start_run(run_seed)
	TextGenerator.reset_history()

	## Что из узкого набора куплено и на каком ранге: главное число приёмки этапа 3.
	## Ключ — «категория:id», значение — ранг, на котором позиция впервые появилась.
	var must_buy_got: Dictionary = {}
	## Ранг, на котором набор закрыт целиком. -1 — не закрыт.
	var must_buy_done_at := -1
	## Что у бота было ДО первой охоты (F3: молот, лук и лёгкая броня). Отделено от
	## покупок, чтобы отчёт не выдал стартовый набор за приобретение: отметка идёт
	## на ранге 0, и без этого «куплено на ранге 0» читалось бы как «куплено сразу».
	var must_buy_start: Dictionary = {}
	_note_must_buy(must_buy_got)
	must_buy_start = must_buy_got.duplicate()

	var rng := RandomNumberGenerator.new()
	# Сид бота зависит и от забега: иначе один и тот же бот читает одинаково
	# при любом сиде забега, и разброс между сидами получился бы ненастоящим.
	# Берётся `seed_key`, а не подпись: у двух опытных профилей игра одна, значит
	# и броски обязаны быть одни.
	rng.seed = hash("%s:%d" % [player.seed_key, run_seed])

	var hunt_no := 0
	var victories := 0
	## Победы, в которых бот менял инструмент В БОЮ. Нужны, чтобы гейт достижения
	## «Победа одним оружием» был проверяем, а не просто присутствовал в отчёте.
	var victories_with_switch := 0
	var defeats := 0
	var escapes_attempted := 0
	var escapes_succeeded := 0
	var escapes := 0
	var total_income := 0
	var coins_spent := 0
	## Минимум, до которого опускался кошелёк. Нужен как инвариант: монеты —
	## единственный ресурс, который нельзя получить назад без продажи, и уход в
	## минус означает, что где-то цена проверялась отдельно от списания
	## (четыре такие копии убраны в GameState.spend_coins).
	var min_coins := 30  # стартовые деньги: ниже них кошелёк опускаться не должен
	## Рынок: сколько добычи продано, сколько потеряно и сколько осталось в ноше.
	## Три величины обязаны сходиться с добычей за победы — это контроль учёта.
	var bag_sold := 0
	var bag_lost_value := 0
	## Сколько боёв кончилось окончательной смертью (срок богини вышел). Нужен для
	## контроля суммы: каждый бой обязан дать ровно один исход.
	var run_overs := 0
	## Охота, на которой забег кончился окончательной смертью. 0 — не кончился.
	## Считается, а не только печатается: цикл обязан на ней ОСТАНОВИТЬСЯ, иначе
	## отчёт складывает охоты двух забегов в одно состояние, которого игра не создаёт.
	var run_over_hunt := 0
	var rank_history: Array[String] = []
	var reached_legend_at := -1
	## Сколько раз бот ходил на каждый вид. Нужен для ротации заказов: без неё
	## прогон всегда бьёт одного и того же зверя и не меряет игру (см. _pick_order).
	var order_seen: Dictionary = {}
	## День, в который достигнута Легенда: главное число для срока богини.
	var legend_day := 0
	## Урон за прогон и победы без урона. Нужны, чтобы влияние снаряжения (руна, броня)
	## было ИЗМЕРЕНО, а не заявлено строкой «руна наложена»: слава за победу включает
	## бонус «не получил урона» (HuntResult._apply_victory), поэтому броня и руна
	## двигают не только урон, но и путь до Легенды.
	var damage_taken_total := 0
	var damage_dealt_total := 0
	var flawless_victories := 0

	while hunt_no < max_hunts and GameState.rank < 5:
		hunt_no += 1
		_milestone(out, "охота %d: выбор заказа" % hunt_no)
		var order := _pick_order(order_seen, player.order_policy, player.smart_tools)
		if order.is_empty():
			out.append("нет доступных заказов — тупик прогрессии")
			break
		var mon: MonsterData = Database.monster(StringName(order["monster_id"]))
		if mon == null:
			break
		var mon_key := String(mon.id)
		order_seen[mon_key] = int(order_seen.get(mon_key, 0)) + 1
		# Выбор заказа — строкой в ОТЧЁТ, а не только в трассу: правило выбора обязано
		# быть проверяемым, а не заявленным. Здесь видно и тир, и на чём он выбран.
		out.append("выбор заказа: охота %d — %s, тир %d «%s», %s" % [
			hunt_no, mon.title, int(order["tier"]),
			CityData.order_tier_title(int(order["tier"])), String(order.get("pick_note", ""))])

		# --- След (нарратив; проверяем, что он вообще собирается)
		var is_repeat := GameState.kill_counts(mon.id) > 0
		var stages := HuntTrail.build(mon, is_repeat, false, RNGService.mechanics(0))
		if stages.is_empty():
			out.append("ПРЕДУПРЕЖДЕНИЕ: пустой след для %s" % mon.id)

		# --- Снаряжение: ствол под зверя, руна на нём и броня забега
		#
		# Одна операция, а не три: руна бессмысленна без ствола, а ствол без руны не
		# пробьёт то, что бот увидел при выборе заказа. Заодно она выставляет руну
		# ЯВНО перед каждой охотой — см. `_prepare_weapon` про общий ресурс базы.
		_prepare_weapon(mon, player.smart_tools)
		var weapon: WeaponData = Database.weapon(GameState.equipped_weapon)
		if weapon == null:
			break
		var armor: ArmorData = Database.armor(GameState.equipped_armor)
		# Снаряжение — строкой в отчёт: без неё проверка «бот дерётся тем, что купил»
		# держалась бы на вере. Здесь видно и руну (типы удара через запятую считает
		# `CityData.damage_type_names`, а не замер), и броню, которую бот НАДЕЛ.
		out.append("снаряжение: охота %d — %s (%s, %s, урон %d), броня: %s (поглощение %d)" % [
			hunt_no, weapon.title, CityData.damage_type_names(weapon),
			CityData.range_ru(weapon.range_id), weapon.base_damage,
			armor.title if armor != null else "—", armor.absorption if armor != null else 0])

		_milestone(out, "охота %d: бой" % hunt_no)
		# Каким оружием бот идёт на зверя и было ли оно у него. Строка нужна как
		# постоянная проверка: прогон обязан играть тем, что игрок КУПИЛ, иначе он
		# измеряет не ту игру. Перебор идёт по `GameState.owned_weapons` — так было и
		# до Task 4: цикл по своей базе стоит с начального коммита (проверено
		# историей — 038dcab, 1d06879, f6ccc31, 2b6e3e5, d44c312). Изменился только
		# способ выбора пары; прежнее «раньше перебор шёл по всей базе» было ложным.
		_trace("охота %d: %s, инструмент %s (в наличии %s, всего у игрока %d)" % [
			hunt_no, mon.title, weapon.title,
			str(weapon.id in GameState.owned_weapons), GameState.owned_weapons.size()])
		# --- Бой
		# Сборка охотника — общая с экраном боя (SkillEffects.build_hunter). Раньше
		# здесь стояли свои копии _hp_bonus/_armor_bonus/_damage_bonus, и одна
		# копия уже разошлась: прогон не считал бонус к побегу от навыка и плаща.
		var hunter := SkillEffects.build_hunter(weapon, armor)

		RNGService.next_battle()
		var engine := BattleEngine.new()
		engine.seed_source = SeedSource.new(GameState.glory * 1000 + hunt_no, hunt_no)
		engine.setup(mon, hunter, weapon)

		var result := HuntResult.new()
		result.monster_id = mon.id
		var guard := 0
		# Живой игрок уходит, когда бой идёт плохо: иначе отступление — механика
		# в вакууме, а в прогоне цикла видно, спасает ли оно от смерти.
		var escape_threshold := int(hunter.max_hp * 0.30)
		# Тот же сборщик досье, что и в экране боя: расхождение между игрой
		# и прогоном сделало бы результаты прогона недостоверными.
		var dossier := DossierRecorder.new()
		dossier.begin(mon, GameState.dossier_entry(mon.id))
		# Учёт боя — общий с экраном (BattleTally). Раньше здесь стоял свой разбор
		# исхода, и он УДВАИВАЛ урон: число бралось и из outcome.damage_to_monster,
		# и повторно из события monster_damaged, то есть отчёт баланса показывал
		# двойной урон игрока. Правило «что считать промахом» тоже было своё.
		var tally := BattleTally.new()
		# Оружие, с которым бот начал охоту. Нужно, чтобы выставить «сменил за бой»
		# честно: сравниваем на выходе из боя, а не гадаем внутри цикла.
		var weapon_at_start: StringName = weapon.id
		while not engine.is_over() and guard < 300:
			guard += 1
			if hunter.hp <= escape_threshold:
				var esc := engine.attempt_escape()
				escapes_attempted += 1
				if bool(esc.get("success", false)):
					escapes_succeeded += 1
				if engine.is_over():
					break
			var outcome := engine.submit_read(
				_simulate_read(mon, engine.current_scenario_id(), player.read_accuracy, rng))
			tally.add(outcome)
			dossier.record(outcome)
			engine.take_events()
			if not engine.is_over():
				engine.advance_round()

		_trace("охота %d: страж %d, фаза %s" % [hunt_no, guard, engine.phase])
		dossier.commit()
		result.new_signals = dossier.new_signals.duplicate()
		result.new_decoys = dossier.new_decoys.duplicate()
		result.new_scenarios = dossier.new_scenarios.duplicate()
		result.new_weaknesses = dossier.new_weaknesses.duplicate()

		result.victory = engine.phase == BattleEngine.PHASE_VICTORY
		result.fled = engine.phase == BattleEngine.PHASE_FLED
		result.rounds = engine.round_index
		result.hp_left = hunter.hp
		result.last_scenario_label = engine.scenario_label_for(engine.current_scenario_id())
		result.order_rank = int(order["tier"])
		# «Сменил ли инструмент за бой» — из сравнения с оружием на входе. Экран боя
		# ведёт для этого отдельный флаг, потому что там смену делает игрок; в прогоне
		# смены в бою нет вовсе — ствол выбран ДО охоты (`_prepare_weapon`), поэтому
		# ожидаемое значение здесь ноль. Сравнение оставлено контролем: если флаг
		# когда-нибудь станет единицей, это будет смена, которой экран не видел.
		tally.apply_to(result, engine.weapon != null and engine.weapon.id != weapon_at_start, false)
		result.apply(false)
		# Диагностика исхода: при побеге и смерти видно, сколько добычи потеряно,
		# а не только что «охота прошла». Без этого механика ноши невидима в логе.
		_trace("охота %d: фаза %s, раундов %d, ноша %d, потеряно %d, монет %d" % [
			hunt_no, engine.phase, result.rounds, GameState.bag_value(),
			result.bag_lost, GameState.coins])

		if result.run_over:
			run_overs += 1
		damage_taken_total += result.damage_taken
		damage_dealt_total += result.damage_dealt
		if result.victory and result.damage_taken == 0:
			flawless_victories += 1
		if result.victory:
			victories += 1
			if result.switched_weapon:
				victories_with_switch += 1
		elif result.fled:
			escapes += 1
		else:
			defeats += 1
		rank_history.append("охота %d: %s %s — ранг %s, слава %d, монет %d" % [
			hunt_no, mon.title,
			"побеждён" if result.victory else ("ты ушёл" if result.fled else "победил тебя"),
			GameState.rank_title(), GameState.glory, GameState.coins])

		_milestone(out, "охота %d: трофеи и траты" % hunt_no)
		# --- Рынок: бот продаёт всё, что донёс
		#
		# С появлением ноши монеты сами не приходят, и без этого шага бот остался бы
		# без денег: отчёт показывал бы прокачку, которой нет. Добыча приходит только
		# от Лиса, поэтому бот обязан сдавать её — как это делает игрок в городе.
		#
		# Продаём РАЗ В ОХОТУ, а не когда накопится: расчётливый бот не понесёт лишний
		# риск. Смерть и так стирает всю ношу, и в отчёте это видно как потерянное.
		var sold := GameState.sell_all_trophies()
		total_income += sold
		bag_sold += sold
		bag_lost_value += result.bag_lost
		coins_spent += _spend_coins()
		# Учёт узкого набора — ПОСЛЕ трат, а не до: иначе позиция, купленная на
		# этой охоте, была бы записана рангом предыдущей.
		_note_must_buy(must_buy_got)
		if must_buy_done_at < 0 and must_buy_got.size() >= _must_buy_total():
			must_buy_done_at = GameState.rank
		min_coins = mini(min_coins, GameState.coins)
		if GameState.rank >= 5 and reached_legend_at < 0:
			reached_legend_at = hunt_no
			legend_day = GameState.day
		# --- Граница забега ---
		#
		# В игре окончательная смерть ЗАКАНЧИВАЕТ забег: `Outcome.RUN_OVER` →
		# `game_root._on_new_run` → `GameState.reset()` (слава 0, ранг 0). Продолжать
		# после неё — считать славу, которую игра обнулила, то есть описывать
		# слияние двух забегов. Так отчётные «25 охот, слава 62» оказывались числом,
		# которого игра не создаёт.
		#
		# Место проверки — ПОСЛЕ `result.apply()` и трат: apply начисляет славу и
		# пересчитывает ранг, смерть обнуляет кошелёк и ношу, а бот после боя
		# докупает набор. Остановка раньше показала бы состояние, которого после
		# охоты уже нет.
		#
		# Дни после срока сами по себе не запрещены: N — бюджет, а не таймер
		# (GDD 1.3.1, «срок вышел — возвращать некому»). Поэтому выход ровно по
		# `run_over` и ни по чему другому.
		if result.run_over:
			run_over_hunt = hunt_no
			break

	# Граница забега — ПЕРВОЙ строкой итогов: она объясняет, что означают все числа
	# ниже. Два случая различаются словами, а не оттенком: «забег кончился» — это
	# окончательная смерть, после которой чисел больше нет; «забег не кончился за N
	# охот» — отведённые охоты кончились, а забег жив. Без этого различия
	# «ЛЕГЕНДА НЕ ДОСТИГНУТА» читается как «дошёл и не хватило», хотя в первом
	# случае забега, в котором можно было дойти, уже нет.
	if run_over_hunt > 0:
		out.append("забег кончился: охота %d, день %d, слава %d, ранг %s (срок богини вышел, смерть окончательна)" % [
			run_over_hunt, GameState.day, GameState.glory, GameState.rank_title()])
	else:
		out.append("забег не кончился за %d охот (день %d, слава %d)" % [
			hunt_no, GameState.day, GameState.glory])
	out.append("охот проведено: %d (побед %d, побегов %d, поражений %d)" % [
		hunt_no, victories, escapes, defeats])
	out.append("попыток побега: %d, удачных: %d" % [escapes_attempted, escapes_succeeded])
	out.append("ранг: %s, слава %d" % [GameState.rank_title(), GameState.glory])
	out.append("доход всего: %d, потрачено: %d, в кошельке: %d" % [
		total_income, coins_spent, GameState.coins])
	# Рынок отдельным блоком: видно, сколько добычи бот донёс до Лиса, а сколько
	# бросил в побеге или потерял со смертью. Это и есть новая механика в числах.
	out.append("рынок: продано на %d, потеряно добычи на %d, осталось в ноше на %d" % [
		bag_sold, bag_lost_value, GameState.bag_value()])
	var dropped := bag_sold + bag_lost_value + GameState.bag_value()
	# Контроль суммы: вся добыча, что попала в руки, должна быть либо продана,
	# либо потеряна, либо ещё лежать в ноше. Расхождение = баг учёта.
	out.append("контроль добычи: продано + потеряно + в ноше = %d (должно сойтись с добычей за победы)" % dropped)
	var outcomes_total := victories + escapes + defeats
	out.append("исходы: побед %d, побегов %d, поражений %d (из них окончательных %d)" % [
		victories, escapes, defeats, run_overs])
	# Контроль суммы: каждый бой даёт ровно один исход. Та же защита, что поймала
	# симулятор, считавший побег поражением («100 поражений» при 71 побеге).
	# Боёв ровно столько же, сколько исходов, поэтому сравниваем с hunt_no.
	out.append("контроль исходов: сумма исходов %d, боёв %d — %s" % [
		outcomes_total, hunt_no, "сходится" if outcomes_total == hunt_no else "РАСХОЖДЕНИЕ"])
	# Бой в числах: урон и победы без урона. Нужны как ИЗМЕРЕНИЕ влияния снаряжения:
	# «руна наложена» и «броня надета» видны строкой `снаряжение`, а стоит ли это
	# чего-нибудь — видно здесь, потому что слава за победу включает бонус «не получил
	# урона» (HuntResult._apply_victory). Проба без рун и без брони сравнивается по
	# этим числам, а не по наличию строки.
	out.append("бой: побед без урона %d, урона получено %d, нанесено %d" % [
		flawless_victories, damage_taken_total, damage_dealt_total])
	out.append("навыков куплено: %d из %d" % [GameState.skills.size(), SkillsData.SKILLS.size()])
	# Проверка гейта «Победа одним оружием». Достижение награждает, только если бой
	# прошёл БЕЗ смены инструмента, поэтому недостаточно увидеть его в списке: на
	# прогоне, где бот оружие в бою не меняет, оно выдаётся всегда и разницы между
	# верным и неверным гейтом не видно. Числа ниже делают гейт проверяемым: если
	# побед со сменой больше нуля, а достижение всё равно выдано — гейт врёт.
	out.append("бой со сменой инструмента: побед %d, всего боёв %d" % [
		victories_with_switch, victories])
	if victories_with_switch > 0 and victories_with_switch == victories \
			and GameState.achievements.has("one_weapon"):
		out.append("ПРОВАЛ ДОСТИЖЕНИЙ: «Победа одним оружием» выдана, хотя ВСЕ победы со сменой инструмента")
	# Контроль экономики. Три условия, и все обязательны:
	#  1) кошелёк не уходил в минус — значит цену проверяли ДО списания;
	#  2) траты вообще были — иначе первое условие зелено на прогоне, где бот
	#     ничего не купил, то есть не проверилось ничего. Ровно так «проверка»
	#     строкового рендера досье сторожила функцию, которой никто не пользовался;
	#  3) у УМЕЛОГО профиля кошелёк нигде не упирался в ноль — вторая половина
	#     свойства приёмки «буфер положителен» («не висит в нуле»).
	#
	# Про (3). До этого шага красным считался только минус, а «минимум на счету»
	# печатался: свойство жило СЛОВОМ, и его вторая половина не проверялась вовсе —
	# отчёт с нулём в минимуме выглядел здоровым. Теперь ноль у умелого профиля
	# краснеет: он означает, что бот потратил последнюю монету, то есть доход шёл
	# впритык к узкому набору.
	#
	# Почему только у умелого. «Набор закрывается» и «буфер» — свойства пути, которым
	# игра проходится (§1.3.1: срок для неумелого не «сложен», а недостижим), и замер
	# это подтверждает: у новичка минимум 0 при закрытом наборе. Сторожить ноль у
	# новичка значило бы краснеть на состоянии, которое замер и должен показать.
	# Числа обоих профилей всё равно в отчёте — рядом со строкой контроля.
	var spends := int(GameState.counters.get("coins_spent", 0))
	if min_coins < 0:
		out.append("ПРОВАЛ ЭКОНОМИКИ: кошелёк уходил в минус (минимум %d) — где-то цена проверялась отдельно от списания" % min_coins)
	elif spends == 0:
		out.append("ПРОВАЛ ЭКОНОМИКИ: ни одной траты за прогон — инвариант кошелька не проверился")
	elif player.smart_tools and min_coins <= 0:
		out.append("ПРОВАЛ ЭКОНОМИКИ: умелый профиль упирался в ноль (минимум на счету %d, остаток %d) — буфер не положителен: доход идёт впритык к узкому набору" % [
			min_coins, GameState.coins])
	else:
		out.append("контроль экономики: трат %d, минимум на счету %d, остаток %d — в минус не уходили, %s" % [
			spends, min_coins, GameState.coins,
			"буфер положителен (минимум выше нуля)" if player.smart_tools
			else "ноль в минимуме новичка свойством не считается: свойство сторожится у умелого профиля"])
	# Узкий набор отдельным блоком: счётчик полноты и таблица «позиция → ранг →
	# цена». Счётчик без таблицы приёмку «набор закрывается» не доказывает — см.
	# _must_buy_summary.
	out.append("--- узкий набор (must-buy): что куплено и на каком ранге ---")
	for line in _must_buy_summary(must_buy_got, must_buy_start, must_buy_done_at, coins_spent):
		out.append(line)
	out.append("достижений открыто: %d из %d" % [
		GameState.unlocked_achievements(), Achievements.total()])
	var unlocked: PackedStringArray = PackedStringArray()
	for a in Achievements.LIST:
		if GameState.achievements.has(str(a["id"])):
			unlocked.append(str(a["title"]))
	if not unlocked.is_empty():
		out.append("  " + ", ".join(unlocked))
	out.append("записей в Хронике: %d (дней: %d)" % [GameState.fame_log.size(), GameState.day])
	# Главное число для срока богини (GDD 1.3.1): за сколько ДНЕЙ бот дошёл до
	# Легенды. Именно оно задаёт N — и его же можно сделать ручкой сложности.
	if reached_legend_at > 0:
		out.append("ЛЕГЕНДА: охота %d, дней %d, слава %d" % [
			reached_legend_at, legend_day, GameState.glory])
	else:
		out.append("ЛЕГЕНДА НЕ ДОСТИГНУТА за %d охот (дней %d, ранг %s, слава %d)" % [
			hunt_no, GameState.day, GameState.rank_title(), GameState.glory])
	# Диагностика выхода из цикла: без неё «прогон просто кончился» ни о чём не говорит.
	out.append("диагностика: rank=%d (%s), циклов=%d, доступных заказов=%d, история=%d" % [
		GameState.rank, GameState.rank_title(), hunt_no,
		CityData.available_monsters(GameState.rank).size(), rank_history.size()])
	out.append("--- последние 8 охот ---")
	var start := maxi(0, rank_history.size() - 8)
	for i in range(start, rank_history.size()):
		out.append("  " + rank_history[i])

	# Числа отчёта в МАШИННОМ виде — для скана по сидам (`run_scan`). Собираются из
	# ТЕХ ЖЕ локальных величин, что печатают строки выше, а не пересчитываются: скан
	# не разбирает текст отчёта, поэтому не может «прочитать» число, которого в
	# отчёте нет, и не разойдётся с ним при правке формата. Ранг закрытия набора и
	# минимум на счету уже посчитаны выше для строк отчёта — здесь они только
	# переносятся.
	var facts := {
		"title": player.title,
		"hunts": hunt_no,
		"run_over_hunt": run_over_hunt,
		"legend_hunt": reached_legend_at,
		"legend_day": legend_day,
		"closed_rank": must_buy_done_at,
		"must_buy_got": must_buy_got.size(),
		"must_buy_total": _must_buy_total(),
		"min_coins": min_coins,
		"coins_end": GameState.coins,
		"income": total_income,
		"spent": coins_spent,
		"rank": GameState.rank,
		"glory": GameState.glory,
	}
	return facts


## Какой заказ берём. Политика — параметр профиля (см. ORDER_POLICIES), внутри тира
## вид выбирается по РОТАЦИИ: берём того, на кого ходили РЕЖЕ ВСЕГО.
##
## Политика «без тупиков» берёт ВЫСШИЙ ДОСТУПНЫЙ ТИР, по которому бот может ударить
## слабостью, а если таких нет вовсе — низший доступный (фарм славы). Почему не
## «высший тир» безусловно, как было: на ранге 4 высший тир — легендарный (Ламант),
## у него валидатор находит тупик, а штраф за смерть на нём — 12 (вдвое больше
## элитного). Бот отдавал славу в стену, и она колебалась 48–63 при 225 неистраченных
## монетах в кошельке.
##
## Политика «всегда высший тир» — противоположный ответ на тот же вопрос, и она
## обязана измеряться, а не отвергаться рассуждением: §14.1 считает Ламанта
## ПРОХОДИМЫМ, а тупик у него — по отсутствию выгодной пары, не по проходимости.
## Раньше на Ламанта ходили БЕЗ набора (без брони, навыков и рун) — с полным набором
## ответ может быть другим, и замер обязан его назвать.
##
## Свойство вида берётся ТО ЖЕ, которым игра выбирает инструмент, —
## `MonsterData.weakness_modifier(type, range)` и `WeaponData.damage_types()` (руна
## добавляет тип, GDD 12.3; см. `_weakness_type`). Свой список «тупиковых видов»
## здесь был бы второй копией правила и разошёлся бы с игрой молча.
##
## Ротация нужна по двум причинам. Первая: раньше бот брал `usable[0]` высшего тира,
## то есть вид, идущий в таблице первым, — 4 Скорба подряд и 3 Ламента, а Пепел-Мать
## не встретилась ни разу: 907 монет против 767 в кривой спеки. Вторая: без ротации
## бот НИКОГДА не встречает новый вид, не наполняет досье и не проходит через «первую
## встречу» — проверка, всегда ходящая на одного зверя, меряет одну арену.
##
## Фильтр по данным обязателен: в таблице есть виды без файлов, и выбор «пустого»
## заказа молча обрывал прогон.
func _pick_order(order_seen: Dictionary, policy: String, smart_tools: bool) -> Dictionary:
	var usable: Array = []
	for o in CityData.available_monsters(GameState.rank):
		if Database.monster(StringName(o["monster_id"])) != null:
			usable.append(o)
	if usable.is_empty():
		return {}
	# Заказы, по которым бот может ударить слабостью стволом, который он реально может
	# взять в бой. Пара ствола описывается для отчёта: видно, чем именно открыт тир.
	var candidates: Array = []
	for o in usable:
		var mon: MonsterData = Database.monster(StringName(o["monster_id"]))
		var tool := _weakness_tool(mon, smart_tools)
		if tool != &"":
			candidates.append({"order": o, "pair": _weakness_label(mon, tool)})
	var fallback := false
	if policy == "highest_tier":
		# Высший доступный тир — без оглядки на слабость. Пару всё равно называем:
		# пустая пара и есть ответ «выгодной пары нет».
		candidates.clear()
		for o in usable:
			var mon: MonsterData = Database.monster(StringName(o["monster_id"]))
			var tool := _weakness_tool(mon, smart_tools)
			candidates.append({
				"order": o,
				"pair": "" if tool == &"" else _weakness_label(mon, tool),
			})
	elif candidates.is_empty():
		# Открытых заказов нет вовсе: фармим славу низшим доступным тиром.
		fallback = true
		var low_tier := 1 << 30
		for o in usable:
			low_tier = mini(low_tier, int(o["tier"]))
		for o in usable:
			if int(o["tier"]) == low_tier:
				candidates.append({"order": o, "pair": ""})
	var best_tier := -1
	for c in candidates:
		best_tier = maxi(best_tier, int(c["order"]["tier"]))
	var best: Dictionary = {}
	var best_seen := -1
	var best_pair := ""
	for c in candidates:
		var o: Dictionary = c["order"]
		if int(o["tier"]) != best_tier:
			continue
		var seen := int(order_seen.get(String(o["monster_id"]), 0))
		if best.is_empty() or seen < best_seen:
			best = o.duplicate()
			best_seen = seen
			best_pair = String(c["pair"])
	# Причина выбора едет вместе с заказом в отчёт: «почему этот тир» — часть
	# измерения, и отдельным полем её не подделать.
	if policy == "highest_tier":
		best["pick_note"] = "высший доступный тир по политике профиля: %s" % (
			"слабость открыта — %s" % best_pair if not best_pair.is_empty()
			else "выгодной пары нет (дизайн §14.1 считает такой заказ проходимым)")
	elif fallback:
		best["pick_note"] = "низший доступный тир: слабости не открыты ни одним своим стволом"
	else:
		best["pick_note"] = "слабость открыта: %s" % best_pair
	return best


## Стволы, которыми бот РЕАЛЬНО может ударить в бою. Умелый бот меняет инструмент под
## зверя, поэтому выбирает из всего, что куплено; неопытный держит то, что взял
## (профиль «лук»), и других стволов у него в бою нет.
##
## Без этого различия строка выбора называла бы ствол, которого бот в руки не возьмёт:
## «слабость открыта: Молот» у бота с луком — обещание, которого он не выполнит, и
## замер отвечал бы не на тот вопрос (так и было до правки ревью).
func _tools(smart_tools: bool) -> Array[StringName]:
	if smart_tools:
		return GameState.owned_weapons
	return [GameState.equipped_weapon] as Array[StringName]


## Ствол, которым бот пробьёт слабость вида: первый по списку доступных ему стволов.
## Пустой StringName — пробить нечем.
##
## Перебор здесь ОДИН на двоих: этим же вызовом `_prepare_weapon` решает, какой ствол
## взять и какую руну на него наложить. Две копии перебора разошлись бы молча, и
## «открытый» заказ оказался бы закрыт в бою.
func _weakness_tool(mon: MonsterData, smart_tools: bool) -> StringName:
	if mon == null:
		return &""
	for id in _tools(smart_tools):
		var w: WeaponData = Database.weapon(id)
		if w == null:
			continue
		if _weakness_type(mon, w) != &"":
			return w.id
	return &""


## Тип удара, которым этот ствол пробьёт слабость вида: СВОЙ тип, если он подходит,
## иначе — известная боту руна (руна добавляет второй тип, а не заменяет базовый,
## GDD 12.3.1). Пустой StringName — не пробивает ничем.
##
## Рун берутся именно ЗНАНИЯ бота (`SkillsData.known_runes` — тот же вызов, что
## в экране подготовки), а не таблица рун: чужой руной ударить нельзя. Достижимость
## уязвимости игра считает так же — базовые типы оружия плюс типы рун
## (content_validator._check_physical_subtypes).
func _weakness_type(mon: MonsterData, w: WeaponData) -> StringName:
	if mon == null or w == null:
		return &""
	if mon.weakness_modifier(w.damage_type, w.range_id) > 0:
		return w.damage_type
	for rune in SkillsData.known_runes(GameState.skills):
		if mon.weakness_modifier(rune, w.range_id) > 0:
			return rune
	return &""


## Подпись пары для отчёта: «Молот + руна огня (дробящий, огонь, ближний)» — сначала
## чем бьём и что наложено, потом типы удара и дистанция. Типы считает игра
## (`CityData.damage_type_names`), а не замер: своя подпись разошлась бы с уроном.
##
## Руна в подписи — ВЫБРАННАЯ (`_weakness_type`), а не живая `w.rune_type`. Разница
## не косметическая: `_pick_order` идёт РАНЬШЕ `_prepare_weapon`, поэтому живая руна
## в момент подписи — либо остаток ПРОШЛОЙ охоты, либо (на первой охоте с руной)
## пусто. Измерено: строка выбора говорила «Лук + руна огонь (колющий, дальний)», а
## строка снаряжения той же охоты — «Лук (колющий, огонь, дальний)». Читатель видел
## две разные картины одного выбора, и обе выглядели фактом.
func _weakness_label(mon: MonsterData, weapon_id: StringName) -> String:
	var w: WeaponData = Database.weapon(weapon_id)
	if w == null:
		return ""
	var rune := _weakness_type(mon, w)
	var rune_note := ""
	if rune != &"" and rune != w.damage_type:
		rune_note = " + руна %s" % CityData.rune_title(rune).to_lower()
	return "%s%s (%s, %s)" % [
		w.title, rune_note, CityData.damage_type_names_with_rune(w, rune),
		CityData.range_ru(w.range_id)]


func _simulate_read(
	mon: MonsterData,
	scenario_id: StringName,
	accuracy: float,
	rng: RandomNumberGenerator
) -> StringName:
	if rng.randf() < accuracy:
		return scenario_id
	var others: Array[StringName] = []
	for s in mon.scenarios:
		if s.id != scenario_id:
			others.append(s.id)
	if others.is_empty():
		return scenario_id
	return others[rng.randi_range(0, others.size() - 1)]


## Снаряжение охоты: взять ствол под зверя (умелый бот), наложить на него руну,
## снять руны со всех прочих стволов.
##
## Почему ОДНА функция, а не «выбрать оружие» и «зачаровать» по отдельности: руна
## бессмысленна без ствола (она живёт на оружии, GDD 11.6), а ствол без руны не
## пробьёт то, что бот увидел при выборе заказа. Разнести их — значит допустить
## состояние «ствол выбран, руна ещё нет», в котором `_weakness_type` отвечает не то.
##
## Про ОБЩИЙ РЕСУРС БАЗЫ. `WeaponData.rune_type` — поле ресурса из `Database`, а не
## состояние забега: чары, наложенные одним ботом, остались бы на оружии для
## следующего (смерть их не снимает — руна есть знание, на этом стоит проверка
## `_weapon_after_death`). Поэтому руна выставляется ЯВНО перед каждой охотой и на
## ВСЕХ стволах базы: на подобранном — своя, на остальных — пустая. Иначе замер
## мерил бы остаток чужой охоты, а не своё решение.
##
## Что именно руна делает с ударом, решает не замер, а игра: `WeaponData.damage_types()`
## (руна добавляет второй тип) и `DamageCalc`, который читает `weapon.rune_type`
## напрямую. Замер только выбирает, КАКУЮ из известных рун наложить, — и это политика
## профиля, а не правило игры.
func _prepare_weapon(mon: MonsterData, smart_tools: bool) -> void:
	# Снять чары со всех стволов базы: состояние бота не должно достаться следующему.
	for id in Database.weapons.keys():
		var w: WeaponData = Database.weapon(id)
		if w != null:
			w.rune_type = &""
	var tool := _weakness_tool(mon, smart_tools)
	if tool == &"":
		# Пробить нечем: ствол не меняем (умелый бот остаётся с прежним), руну не
		# накладываем — «руна просто так» в игре не решение, а трата.
		return
	if smart_tools:
		GameState.equipped_weapon = tool
	var w: WeaponData = Database.weapon(tool)
	if w == null:
		return
	var rune := _weakness_type(mon, w)
	if rune != &"" and rune != w.damage_type:
		w.rune_type = rune


## Бот тратит монеты: сначала узкий набор в порядке BUY_ORDER, потом оружие вне набора.
##
## Политика покупок у всех профилей ОДНА: иначе «набор закрывается» снова мерило бы
## вкус конкретного бота, а не экономику. Различаются профили чтением, выбором
## инструмента и политикой заказа.
func _spend_coins() -> int:
	var spent := 0
	for entry in BUY_ORDER:
		spent += _buy_must_buy(String(entry["kind"]), String(entry["id"]))
	# Оружие вне набора — ПОСЛЕ набора. Пока минимум не собран, монеты, ушедшие на
	# пращу или чакрам, отвечают не на вопрос приёмки, а на вопрос «что бот любит»:
	# именно на этом прежний замер терял часть набора при полном кошельке.
	if not _must_buy_complete():
		return spent
	# Сортируем сами оружия, а не их id: так в компараторе нет ни повторного поиска,
	# ни разыменования null, которое было бы возможно, если бы ключ базы разошёлся
	# с содержимым ресурса. По цене от дешёвой — тот же порядок, что у BUY_ORDER.
	var off_set: Array[WeaponData] = []
	for id in Database.weapons.keys():
		var w: WeaponData = Database.weapon(id)
		if w != null:
			off_set.append(w)
	off_set.sort_custom(func(a, b): return a.price < b.price)
	for w in off_set:
		if w.id in GameState.owned_weapons:
			continue
		if w.price > 0 and GameState.spend_coins(w.price):
			GameState.owned_weapons.append(w.id)
			spent += w.price
	return spent


## Купить одну позицию набора, если она ещё не куплена и покупка возможна. Возвращает
## потраченное (0 — покупки не было).
##
## Покупка идёт ЧЕРЕЗ ПРАВИЛА ИГРЫ, а не через их копию: навык — `SkillsData.can_buy`
## и `GameState.buy_skill` (ровно так покупает экран города), совет — `GameState.buy_advice`
## (цена и списание внутри, второй копии цены нет), оружие и броня — `GameState.spend_coins`.
## Своя проверка «хватает ли монет и дорос ли ранг» разошлась бы с игрой молча — как уже
## расходилась цена совета.
##
## Оружие бот НЕ берёт в руки при покупке: у неопытного бота инструмент остаётся тем,
## чем он назван (лук), а опытный выбирает пару под зверя в `_prepare_weapon`.
func _buy_must_buy(kind: String, id: String) -> int:
	var sid := StringName(id)
	match kind:
		"skills", "runes":
			var skill := SkillsData.find_skill(sid)
			if skill.is_empty():
				return 0
			# Тот же вопрос, что задаёт экран города перед покупкой: хватает монет,
			# не куплено, ранг дорос. Своя копия этих трёх условий разошлась бы с
			# игрой молча — как уже расходилась цена совета.
			var check := SkillsData.can_buy(sid, GameState.coins, GameState.rank, GameState.skills)
			if not bool(check["ok"]):
				return 0
			var skill_price := int(skill["price"])
			if not GameState.buy_skill(sid, skill_price):
				return 0
			return skill_price
		"weapons":
			if sid in GameState.owned_weapons:
				return 0
			var w: WeaponData = Database.weapon(sid)
			if w == null or w.price <= 0 or not GameState.spend_coins(w.price):
				return 0
			GameState.owned_weapons.append(w.id)
			# Оружие при покупке в руку НЕ берётся: чем бить, решает `_prepare_weapon`
			# перед каждой охотой — это замерный аналог экрана подготовки («ВЗЯТЬ»),
			# а не экрана города. Экран города при покупке надевает сам
			# (`_buy_or_equip_weapon`), и для неопытного профиля это значило бы, что
			# его инструмент зависит от того, что он купил последним, а профиль
			# называется «лук». Разница названа в отчёте, а не спрятана.
			return w.price
		"armor":
			if sid in GameState.owned_armors:
				return 0
			var a: ArmorData = Database.armor(sid)
			if a == null or a.price <= 0 or not GameState.spend_coins(a.price):
				return 0
			GameState.owned_armors.append(a.id)
			# А броня надевается — ровно как в экране города (`_buy_or_equip_armor`).
			# У брони нет выбора «под зверя», значит покупка и есть решение надеть;
			# без этой строки бот платил 40 монет за тяжёлую и дрался в лёгкой
			# (дефект, найденный ревью Task 3в).
			#
			# ЧТО БОТ ЗА ЭТО ПОЛУЧАЕТ (измерено, `--loop` + данные игры). Тяжёлая
			# броня (40 монет) — это **−1 инициативы без прироста поглощения**:
			# `HunterState.total_absorption` режет по `ABSORPTION_CAP = 3`, а +3 к
			# поглощению даёт навык `surv_armor3` ИЗ ТОГО ЖЕ НАБОРА, поэтому 1+3 и 3+3
			# оба упираются в потолок 3. Остаётся `initiative_penalty = 1`
			# (`content/armor/heavy.tres`), и он доезжает до боя:
			# `skill_effects.gd:build_hunter` → `hunter_state.gd:initiative()` →
			# `battle_engine.gd:apply_preemptive_strike` (зверь с инициативой 5 бьёт
			# первым). Вопрос «оставлять ли предмет в §4.2 спеки» — открытый, с числами
			# записан в §14.1 дизайна; правка здесь была бы правкой баланса, а этап 3
			# про каталог, ранги и экономику.
			#
			# «Купил = носишь до конца забега» — решение ЗАМЕРА, а не правило игры:
			# игрок вправе бесплатно вернуть лёгкую (`city_screen.gd:_buy_or_equip_armor`
			# для уже купленной брони надевает без списания). Профиль бота так не делает,
			# потому что иначе «набор закрыт» мерило бы его политику снятия брони.
			GameState.equipped_armor = a.id
			return a.price
		"advice":
			# Потраченное берём разницей кошелька: цену читает и списывает
			# `buy_advice` в GameState, и вторая копия цены здесь не нужна.
			var before := GameState.coins
			if not GameState.buy_advice(sid):
				return 0
			return before - GameState.coins
	return 0


## Собран ли узкий набор целиком. Спрашивается по MUST_BUY через `_must_buy_owned` —
## тот же источник, что у счётчика отчёта, поэтому «купить оружие вне набора» не может
## начаться раньше, чем набор закрыт по мнению счётчика.
func _must_buy_complete() -> bool:
	for kind in MUST_BUY.keys():
		for id in MUST_BUY[kind]:
			if not _must_buy_owned(kind, id):
				return false
	return true


## Откуда берётся «куплено ли» для категории набора. Источников ровно четыре, и все
## они — состояние забега в GameState: навыки (вместе с рунами), оружие, броня, совет.
## Строка «none» осталась для случая, которого сегодня нет: замер обязан молчать о
## позиции, а не считать её закрытой, если состояния в игре нет вовсе.
func _must_buy_source(kind: String) -> String:
	return String(MUST_BUY_KINDS[kind]["source"])


## Проверка САМИХ данных набора — в отчёт, а не в лог. Раньше обещание «категория без
## строки в MUST_BUY_KINDS сломает прогон громко» жило только комментарием: неизвестный
## ключ давал пустую строку, позиция молча оставалась в знаменателе и никогда не
## отмечалась, а прогон выглядел здоровым. Три случая:
##  1. категория из MUST_BUY не описана в MUST_BUY_KINDS — её позиции никто не читает;
##  2. у id нет данных в игре (SkillsData.find_skill, Database.weapon/armor,
##     CityData.ADVICE_PRICES) — опечатка в id;
##  3. BUY_ORDER и MUST_BUY не совпадают множествами — забытая в порядке покупок
##     позиция не покупалась бы никогда;
##  4. порядок BUY_ORDER разошёлся с объявленным правилом «ранг, затем цена» — см.
##     `_buy_order_problems`.
func _must_buy_data_problems() -> Array[String]:
	var out: Array[String] = []
	for kind in MUST_BUY.keys():
		if not MUST_BUY_KINDS.has(kind):
			out.append("категория «%s» есть в MUST_BUY, но не описана в MUST_BUY_KINDS: её позиции никто не читает" % kind)
			continue
		for id in MUST_BUY[kind]:
			var source := _must_buy_missing_source(kind, String(id))
			if not source.is_empty():
				out.append("id «%s» (категория «%s»): данных нет — %s" % [String(id), kind, source])
	var in_set := {}
	for kind in MUST_BUY.keys():
		for id in MUST_BUY[kind]:
			in_set["%s:%s" % [kind, String(id)]] = true
	var in_order := {}
	for entry in BUY_ORDER:
		in_order["%s:%s" % [String(entry["kind"]), String(entry["id"])]] = true
	for key in in_set.keys():
		if not in_order.has(key):
			out.append("позиция «%s» есть в MUST_BUY, но не в BUY_ORDER: бот её не купит" % key)
	for key in in_order.keys():
		if not in_set.has(key):
			out.append("позиция «%s» есть в BUY_ORDER, но не в MUST_BUY: бот купит лишнее" % key)
	out.append_array(_buy_order_problems())
	return out


## Сторож ПОРЯДКА покупок: позиции BUY_ORDER обязаны идти по неубыванию
## «(требуемый ранг, цена)». Таблица объявляет именно это правило, и без сторожа
## ручная правка ломает его МОЛЧА: набор по-прежнему покрыт, покрытие зелено, а
## политика покупок стала другой — тот же класс, что слепое пятно `.get(_, 0)`
## в стороже штрафа (Task 3б).
##
## Сравниваются две ПОСЛЕДОВАТЕЛЬНЫЕ ИЗМЕРЕННЫЕ позиции, а не соседние строки
## таблицы. Позиция без данных в игре пропускается — её ранг и цена не факт, а ноль,
## и «порядок сломан» на таком нуле было бы следствием, а не причиной (причину
## называет проверка id выше). Но пропуск цепочку НЕ рвёт: раньше сравнение шло по
## соседним строкам, и инверсия через пропущенную позицию терялась — две измеренные
## позиции расходились с правилом, а сторож молчал. Цепочки достаточно: если каждая
## измеренная позиция не меньше предыдущей ИЗМЕРЕННОЙ, вся последовательность
## неубывающая (сравнение соседних в цепочке транзитивно).
##
## Ранг и цену берут те же источники, что и покупка: `SkillsData.find_skill` (поле
## `rank` — по нему решает `SkillsData.can_buy`) и `_must_buy_price`. Вторая копия
## порядка «что дороже» разошлась бы с покупкой молча.
func _buy_order_problems() -> Array[String]:
	var out: Array[String] = []
	# Последняя позиция, у которой ранг и цена — ФАКТ. Пустая — ни одной ещё не было.
	var prev: Dictionary = {}
	var prev_rank := 0
	var prev_price := 0
	for entry in BUY_ORDER:
		var kind := String(entry["kind"])
		# Категория без строки в MUST_BUY_KINDS пропускается ещё и потому, что читать
		# её прайс НЕЧЕМ: `_must_buy_price` берёт источник цены из MUST_BUY_KINDS и
		# падает на неизвестной категории (измерено).
		if not MUST_BUY_KINDS.has(kind):
			continue
		var id := String(entry["id"])
		if not _must_buy_missing_source(kind, id).is_empty():
			continue
		var cur_rank := _must_buy_rank(kind, id)
		var cur_price := _must_buy_price(kind, id)
		if not prev.is_empty() and (
			cur_rank < prev_rank or (cur_rank == prev_rank and cur_price < prev_price)
		):
			out.append("порядок покупок сломан: «%s» (ранг %d, цена %d) идёт после «%s» (ранг %d, цена %d), а правило — по возрастанию ранга, затем цены" % [
				_buy_order_key(entry), cur_rank, cur_price,
				_buy_order_key(prev), prev_rank, prev_price])
		prev = entry
		prev_rank = cur_rank
		prev_price = cur_price
	return out


## Подпись позиции порядка для отчёта: «совет:shipun».
func _buy_order_key(entry: Dictionary) -> String:
	return "%s:%s" % [String(entry["kind"]), String(entry["id"])]


## Требуемый ранг позиции: у навыка (и у руны — руна это навык) это поле `rank` из
## SkillsData, у оружия, брони и совета требования ранга нет вовсе — город продаёт их
## с первого ранга. Источник тот же, что у покупки: `SkillsData.can_buy` спрашивает
## ровно это поле.
func _must_buy_rank(kind: String, id: String) -> int:
	if kind == "skills" or kind == "runes":
		var s := SkillsData.find_skill(StringName(id))
		return int(s["rank"]) if not s.is_empty() else 0
	return 0


## Все ли категории набора описаны в MUST_BUY_KINDS. Отдельная функция, а не проверка
## «нет ли такой строки» по месту: имя категории — то, без чего не работает ни источник
## состояния (`_must_buy_source`), ни подпись в таблице отчёта.
func _must_buy_kinds_complete() -> bool:
	for kind in MUST_BUY.keys():
		if not MUST_BUY_KINDS.has(kind):
			return false
	return true


## Где искать данные позиции набора: пустая строка — всё на месте, иначе имя источника,
## в котором позиции нет. Ровно те источники, из которых позиция потом и покупается.
func _must_buy_missing_source(kind: String, id: String) -> String:
	var sid := StringName(id)
	match kind:
		"skills":
			return "" if not SkillsData.find_skill(sid).is_empty() else "SkillsData.find_skill"
		"runes":
			if SkillsData.find_skill(sid).is_empty():
				return "SkillsData.find_skill"
			return "" if SkillsData.RUNE_SKILLS.has(id) else "SkillsData.RUNE_SKILLS"
		"weapons":
			return "" if Database.weapon(sid) != null else "Database.weapon"
		"armor":
			return "" if Database.armor(sid) != null else "Database.armor"
		"advice":
			return "" if CityData.ADVICE_PRICES.has(id) else "CityData.ADVICE_PRICES"
	return "MUST_BUY_KINDS (категории «%s» нет в таблице)" % kind


## Ключ позиции в счётчике: «категория:id». По нему же строится таблица отчёта,
## поэтому ключ и подпись берутся из одной строки данных и разойтись не могут.
func _must_buy_key(kind: String, id: String) -> String:
	return "%s:%s" % [String(MUST_BUY_KINDS[kind]["prefix"]), id]


## Куплена ли позиция набора (или была у бота с начала). Источник — GameState, и
## только он: поле, выдуманное в замере, измерило бы выдумку. Источников ровно
## четыре, и они записаны в MUST_BUY_KINDS: навыки (вместе с рунами), оружие, броня,
## совет Старика.
func _must_buy_owned(kind: String, id: Variant) -> bool:
	var sid := StringName(id)
	match _must_buy_source(kind):
		"skill":
			return GameState.has_skill(sid)
		"weapon":
			return sid in GameState.owned_weapons
		"armor":
			return sid in GameState.owned_armors
		"advice":
			return GameState.advice_bought.has(String(id))
	return false


## Цена позиции набора — по ФАКТИЧЕСКИМ данным игры, а не по таблицам гипотез β:
## тех правок в игре нет. Нужна затем, чтобы отчёт говорил не только «куплено
## N из M», но и на сколько монет набор закрыт и сколько осталось докупить.
func _must_buy_price(kind: String, id: String) -> int:
	match String(MUST_BUY_KINDS[kind]["price_from"]):
		"skill":
			var s := SkillsData.find_skill(StringName(id))
			return int(s["price"]) if not s.is_empty() else 0
		"weapon":
			var w: WeaponData = Database.weapon(StringName(id))
			return w.price if w != null else 0
		"armor":
			var a: ArmorData = Database.armor(StringName(id))
			return a.price if a != null else 0
		"advice":
			return CityData.advice_price(StringName(id))
	return 0


## Отмечает купленное из узкого набора: «категория:id» -> ранг, на котором позиция
## впервые оказалась у бота. Оружие, броня, навыки и советы читаются из GameState — у
## него есть ВСЁ нужное: `has_skill`, `owned_weapons`, `owned_armors`, `advice_bought`
## (проверено разведкой, выдумывать поля не надо).
##
## Ранг берётся на момент отметки, то есть на конец охоты, в которой покупка
## случилась: точнее прогон не знает — бот тратит монеты ПОСЛЕ боя, а ранг к тому
## моменту уже пересчитан.
func _note_must_buy(got: Dictionary) -> void:
	for kind in MUST_BUY.keys():
		for id in MUST_BUY[kind]:
			if not _must_buy_owned(kind, id):
				continue
			var key := _must_buy_key(kind, String(id))
			if not got.has(key):
				got[key] = GameState.rank


## Сколько позиций набора замер ОТСЛЕЖИВАЕТ. Источник «none» (позиция, состояния
## которой в игре нет вовсе) в счёт не входит: «закрыт» по позиции, которой прогон не
## видит, — не измерение, а объявленный заранее результат. Сегодня таких нет.
func _must_buy_total() -> int:
	var total := 0
	for kind in MUST_BUY.keys():
		if _must_buy_source(kind) == "none":
			continue
		total += (MUST_BUY[kind] as Array).size()
	return total


## Блок отчёта об узком наборе: счётчик, деньги и таблица «позиция → ранг → цена».
##
## Таблица обязательна рядом со счётчиком. «Куплено N из M» одинаково выглядит и
## когда набор закрыт по ходу пути, и когда он докупается после Легенды, и когда
## позиции не покупались вовсе — по счётчику этого не различить, а приёмка этапа
## спрашивает именно «закрывается ли по ходу». Таблица называет каждую позицию.
func _must_buy_summary(got: Dictionary, start: Dictionary, done_at: int, spent: int) -> Array[String]:
	var out: Array[String] = []
	out.append("узкий набор: куплено %d из %d, закрыт на ранге %d, потрачено %d" % [
		got.size(), _must_buy_total(), done_at, spent])
	if done_at < 0:
		out.append("  (ранг -1 значит: набор целиком не закрыт ни на одном ранге)")
	var price := 0
	var closed := 0
	var paid := 0
	var unseen_count := 0
	var unseen_price := 0
	for kind in MUST_BUY.keys():
		for id in MUST_BUY[kind]:
			var kind_title := String(MUST_BUY_KINDS[kind]["title"])
			var cost := _must_buy_price(kind, String(id))
			price += cost
			if _must_buy_source(kind) == "none":
				unseen_count += 1
				unseen_price += cost
				out.append("  %-7s %-12s %4d  НЕ отслеживается (состояния в GameState нет)" % [
					kind_title, String(id), cost])
				continue
			var key := _must_buy_key(kind, String(id))
			var state := "не куплено"
			if start.has(key):
				state = "был с начала (F3), ранг %d" % int(start[key])
			elif got.has(key):
				state = "куплен на ранге %d" % int(got[key])
			out.append("  %-7s %-12s %4d  %s" % [kind_title, String(id), cost, state])
			if got.has(key):
				closed += cost
				if not start.has(key):
					paid += cost
	var tracked := price - unseen_price
	out.append("узкий набор: цена по прайсу %d, отслеживается %d, закрыто на %d (заплачено %d, стартовые по F3 бесплатны), осталось докупить на %d" % [
		price, tracked, closed, paid, tracked - closed])
	# Строка о неотслеживаемом — ТОЛЬКО когда такое есть: сегодня источников четыре
	# и все они в GameState. Постоянная строка «НЕ отслеживаются советы Старика»
	# после Task 3б стала бы ложью, которую читают как оговорку к счётчику.
	if unseen_count > 0:
		out.append("узкий набор: НЕ отслеживается %d позиций на %d: состояния покупки в GameState нет, поэтому в счёте «куплено» их нет" % [
			unseen_count, unseen_price])
	# Что докуплено ПОСЛЕ Легенды. Это и есть «набор не закрывается»: если такие
	# позиции есть, значит узкий набор собирался не по пути, а после цели.
	var at_legend: Array[String] = []
	for done_key in got.keys():
		if int(got[done_key]) >= 5:
			at_legend.append(String(done_key))
	at_legend.sort()
	out.append("докуплено после Легенды (ранг 5): %s" % [
		"нет" if at_legend.is_empty() else ", ".join(at_legend)])
	return out
