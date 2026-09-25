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
## Советы Старика перечислены, хотя замер их НЕ ВИДИТ: состояния покупки совета в
## GameState нет (оно живёт в экране города, `city_screen.advice_bought`), а прогон
## цикла идёт без сцен. Поэтому у них источник состояния «none»: в счёт «куплено»
## они не входят, и отчёт говорит об этом прямо, а не молчит — иначе «куплено N из
## M» читалось бы как «набор закрыт».
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
	"advice": {"title": "совет", "prefix": "advice", "source": "none", "price_from": "advice"},
}


## Как играет бот.
class Player:
	var read_accuracy: float
	var title: String
	var smart_tools: bool

	func _init(p_title: String, p_read: float, p_smart: bool) -> void:
		title = p_title
		read_accuracy = p_read
		smart_tools = p_smart


func run(hunts: int, out: Array[String], run_seed: int = 20260922) -> void:
	var players := [
		Player.new("новичок (лук, чтение 45%)", 0.45, false),
		Player.new("опытный (лучший инструмент, чтение 75%)", 0.75, true),
	]
	for p in players:
		out.append("")
		out.append("========== %s ==========" % p.title)
		_run_player(p, hunts, out, run_seed)


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


func _run_player(player: Player, max_hunts: int, out: Array[String], run_seed: int = 20260922) -> void:
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
	rng.seed = hash("%s:%d" % [player.title, run_seed])

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
	var rank_history: Array[String] = []
	var reached_legend_at := -1
	## Сколько раз бот ходил на каждый вид. Нужен для ротации заказов: без неё
	## прогон всегда бьёт одного и того же зверя и не меряет игру (см. _pick_order).
	var order_seen: Dictionary = {}
	## День, в который достигнута Легенда: главное число для срока богини.
	var legend_day := 0

	while hunt_no < max_hunts and GameState.rank < 5:
		hunt_no += 1
		_milestone(out, "охота %d: выбор заказа" % hunt_no)
		var order := _pick_order(order_seen)
		if order.is_empty():
			out.append("нет доступных заказов — тупик прогрессии")
			break
		var mon: MonsterData = Database.monster(StringName(order["monster_id"]))
		if mon == null:
			break
		var mon_key := String(mon.id)
		order_seen[mon_key] = int(order_seen.get(mon_key, 0)) + 1

		# --- След (нарратив; проверяем, что он вообще собирается)
		var is_repeat := GameState.kill_counts(mon.id) > 0
		var stages := HuntTrail.build(mon, is_repeat, false, RNGService.mechanics(0))
		if stages.is_empty():
			out.append("ПРЕДУПРЕЖДЕНИЕ: пустой след для %s" % mon.id)

		# --- Снаряжение: умный бот берёт то, к чему зверь уязвим
		if player.smart_tools:
			_equip_best_tool(mon)
		var weapon: WeaponData = Database.weapon(GameState.equipped_weapon)
		if weapon == null:
			break

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
		var armor: ArmorData = Database.armor(GameState.equipped_armor)
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
		# ведёт для этого отдельный флаг, потому что там смену делает игрок; здесь
		# её делает _equip_best_tool, и достаточно сравнить начало и конец.
		tally.apply_to(result, engine.weapon != null and engine.weapon.id != weapon_at_start, false)
		result.apply(false)
		# Диагностика исхода: при побеге и смерти видно, сколько добычи потеряно,
		# а не только что «охота прошла». Без этого механика ноши невидима в логе.
		_trace("охота %d: фаза %s, раундов %d, ноша %d, потеряно %d, монет %d" % [
			hunt_no, engine.phase, result.rounds, GameState.bag_value(),
			result.bag_lost, GameState.coins])

		if result.run_over:
			run_overs += 1
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
		coins_spent += _spend_coins(player)
		# Учёт узкого набора — ПОСЛЕ трат, а не до: иначе позиция, купленная на
		# этой охоте, была бы записана рангом предыдущей.
		_note_must_buy(must_buy_got)
		if must_buy_done_at < 0 and must_buy_got.size() >= _must_buy_total():
			must_buy_done_at = GameState.rank
		min_coins = mini(min_coins, GameState.coins)
		if GameState.rank >= 5 and reached_legend_at < 0:
			reached_legend_at = hunt_no
			legend_day = GameState.day

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
	# Контроль экономики. Два условия, и оба обязательны:
	#  1) кошелёк не уходил в минус — значит цену проверяли ДО списания;
	#  2) траты вообще были — иначе первое условие зелено на прогоне, где бот
	#     ничего не купил, то есть не проверилось ничего. Ровно так «проверка»
	#     строкового рендера досье сторожила функцию, которой никто не пользовался.
	var spends := int(GameState.counters.get("coins_spent", 0))
	if min_coins < 0:
		out.append("ПРОВАЛ ЭКОНОМИКИ: кошелёк уходил в минус (минимум %d) — где-то цена проверялась отдельно от списания" % min_coins)
	elif spends == 0:
		out.append("ПРОВАЛ ЭКОНОМИКИ: ни одной траты за прогон — инвариант кошелька не проверился")
	else:
		out.append("контроль экономики: трат %d, минимум на счету %d, остаток %d — в минус не уходили" % [
			spends, min_coins, GameState.coins])
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


## Какой заказ берём: самый дорогой, но с РОТАЦИЕЙ видов внутри тира.
##
## Почему не «первый из максимального тира», как было. Раньше бот брал `usable[0]`
## среди заказов высшего доступного тира, то есть вид, который в таблице идёт
## первым. Это дало за прогон 4 Скорба подряд и 3 Ламента при том, что Пепел-Мать
## (тот же тир 2) не встретилась ни разу: 907 монет против 767 в кривой спеки.
##
## Расхождение было не в ценах, а в ТОМ, ЧТО МЫ МЕРИЛИ. Кривая §12.12 описывает
## путь с ротацией видов — 1 Хруз, 3 Шипуна, 3 Громуна, 1 Тлеун, 2 Скорба,
## 2 Пепел-Матери, 1 Ламент. Бот же всегда брал самый дорогой заказ, и три
## Ламента по 180 монет дали больше, чем весь спекулятивный бюджет.
##
## Ротация нужна и по второй причине: без неё бот НИКОГДА не встречает новый вид,
## а значит не наполняет досье и не проходит через «первую встречу» — то есть
## прогон не касается половины механик. Проверка, которая всегда ходит на одного
## и того же зверя, меряет не игру, а одну арену.
##
## Правило: среди заказов высшего доступного тира берём тот вид, на которого
## ходили РЕЖЕ ВСЕГО. При равенстве — первый по таблице (устойчиво между прогонами).
## Фильтр по загруженности обязателен: в таблице есть виды без файлов, и выбор
## «пустого» заказа молча обрывал прогон.
func _pick_order(order_seen: Dictionary) -> Dictionary:
	var orders := CityData.available_monsters(GameState.rank)
	var usable: Array = []
	for o in orders:
		if Database.monster(StringName(o["monster_id"])) != null:
			usable.append(o)
	if usable.is_empty():
		return {}
	var best_tier := 0
	for o in usable:
		best_tier = maxi(best_tier, int(o["tier"]))
	var best: Dictionary = {}
	var best_seen := -1
	for o in usable:
		if int(o["tier"]) != best_tier:
			continue
		var seen := int(order_seen.get(String(o["monster_id"]), 0))
		if best.is_empty() or seen < best_seen:
			best = o
			best_seen = seen
	return best


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


## Бот берёт инструмент, к которому зверь уязвим НА ЭТОЙ ДИСТАНЦИИ (D23): запись
## уязвимости — пара «тип И дистанция». Запасного «по типу» здесь нет намеренно, и
## вот почему: он сравнивал ОДНУ координату — `w.damage_type == hint`, — тогда как
## запись и оружие совпадают ПАРОЙ. Сравнение одного типа без дистанции запись не
## выражает, поэтому выбор получался произвольным, а не «по уязвимости»: у Громунa
## хинт дробящий, но его запись требует ещё и упор; у Тлеуна хинт — яд, а третий тип
## его записей — колющий, и в хинт не попадает вовсе. Произвольный выбор хуже
## отсутствия выбора: отчёт баланса показывал бы преимущество, которого механика не
## даёт. Отсутствие выбора честнее мнимого.
##
## Перебор идёт по `GameState.owned_weapons`, и так было ДО Task 4 (проверено по
## истории: 038dcab, 1d06879, f6ccc31, 2b6e3e5, d44c312 — цикл везде тот же).
## Изменился только СПОСОБ выбора пары: раньше брались первый тип и первая
## дистанция из двух списков, теперь — точная пара из записи.
func _equip_best_tool(mon: MonsterData) -> void:
	for id in GameState.owned_weapons:
		var w: WeaponData = Database.weapon(id)
		if w == null:
			continue
		if mon.weakness_modifier(w.damage_type, w.range_id) > 0:
			GameState.equipped_weapon = w.id
			return


## Бот тратит монеты: сначала обязательные навыки, потом снаряжение.
func _spend_coins(player: Player) -> int:
	var spent := 0
	var priority: Array[StringName] = []
	if player.smart_tools:
		priority = [&"read_signal", &"surv_hp1", &"read_double", &"wpn_dmg1"]
	else:
		priority = [&"surv_hp1", &"read_signal", &"wpn_dmg1", &"surv_armor1"]
	for sid in priority:
		var s := SkillsData.find_skill(sid)
		if s.is_empty() or GameState.has_skill(sid):
			continue
		if GameState.rank >= int(s["rank"]) and GameState.can_afford(int(s["price"])):
			GameState.buy_skill(sid, int(s["price"]))
			spent += int(s["price"])
	# Снаряжение после навыков.
	if player.smart_tools:
		for id in Database.weapons.keys():
			var w: WeaponData = Database.weapons[id]
			if w.id in GameState.owned_weapons:
				continue
			if w.price > 0 and GameState.spend_coins(w.price):
				GameState.owned_weapons.append(w.id)
				spent += w.price
	if GameState.rank >= 3 and not (GameState.has_skill(&"surv_armor2")):
		var s2 := SkillsData.find_skill(&"surv_armor2")
		if not s2.is_empty() and GameState.can_afford(int(s2["price"])):
			GameState.buy_skill(&"surv_armor2", int(s2["price"]))
			spent += int(s2["price"])
	return spent


## Откуда берётся «куплено ли» для категории набора: none значит «замер этого не
## видит» (советы Старика — их состояние живёт в экране города, не в GameState).
func _must_buy_source(kind: String) -> String:
	return String(MUST_BUY_KINDS[kind]["source"])


## Ключ позиции в счётчике: «категория:id». По нему же строится таблица отчёта,
## поэтому ключ и подпись берутся из одной строки данных и разойтись не могут.
func _must_buy_key(kind: String, id: String) -> String:
	return "%s:%s" % [String(MUST_BUY_KINDS[kind]["prefix"]), id]


## Куплена ли позиция набора (или была у бота с начала). Источник — GameState, и
## только он: поле, выдуманное в замере, измерило бы выдумку. Источников ровно три,
## и они записаны в MUST_BUY_KINDS: навыки (вместе с рунами), оружие, броня.
func _must_buy_owned(kind: String, id: Variant) -> bool:
	var sid := StringName(id)
	match _must_buy_source(kind):
		"skill":
			return GameState.has_skill(sid)
		"weapon":
			return sid in GameState.owned_weapons
		"armor":
			return sid in GameState.owned_armors
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
## впервые оказалась у бота. Оружие, броня и навыки читаются из GameState — у него
## есть ВСЁ нужное: `has_skill`, `owned_weapons`, `owned_armors` (проверено
## разведкой, выдумывать поля не надо).
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


## Сколько позиций набора замер ОТСЛЕЖИВАЕТ. Советы в счёт не входят (см.
## MUST_BUY_KINDS.source): «закрыт» по позиции, которой прогон не видит, — не
## измерение, а объявленный заранее результат.
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
	out.append("узкий набор: НЕ отслеживаются советы Старика — %d позиций на %d: состояния покупки совета в GameState нет (оно живёт в экране города), поэтому в счёте «куплено» их нет" % [
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
