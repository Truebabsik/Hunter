extends RefCounted
class_name UiChecks
## Проверки, которым НУЖНЫ сцены и дерево узлов.
##
## Они живут в `ui/`, а не в `core/`, по той же причине, по которой там живут
## экраны: `core/` — чистый GDScript без Node, и проверка экрана не должна его
## пачкать. Чистые проверки лежат в `core/sim/checks/logic_checks.gd`.
##
## Все методы принимают `host: Node` — узел, к которому можно прицепить сцену и у
## которого есть дерево. Так точка входа (`main.gd`) не обязана быть тем, кто
## выполняет проверку: она только разбирает аргументы.

const PREP_REPORT := "_prep_out.txt"
const SMOKE_REPORT := "_smoke_out.txt"
const UI_REPORT := "_ui_out.txt"
const SHOTS_DIR := "res://_shots"


## Проверка экрана подготовки: он обязан МЕНЯТЬ состояние забега, а не только
## показывать его. Проверяем наложение руны и смену оружия — то, ради чего экран
## существует. Без этого «0 провалов» означало бы лишь, что экран открылся.
##
## Живёт в `ui/`, хотя часть проверок внутри — про данные: они проверяют то, что
## экран СДЕЛАЛ с состоянием забега, а для этого экран надо создать и нажать.
static func prep(host: Node) -> String:
	var out: Array[String] = []
	var failed := 0
	## Число выполненных проверок считаем сами: вписанный руками знаменатель уже
	## разъехался с реальностью, когда добавились проверки досье.
	var checks := 0

	GameState.reset()
	# Даём то, что игрок добыл бы игрой: второе оружие и навык-руну.
	GameState.owned_weapons.append(&"blade")
	GameState.skills["wpn_mod"] = true

	var packed: PackedScene = load("res://ui/screens/prep/prep_screen.tscn")
	if packed == null:
		Report.write(PREP_REPORT, ["экран подготовки не загрузился"])
		return "экран подготовки не загрузился"
	var scr: Node = packed.instantiate()
	host.add_child(scr)
	await host.get_tree().process_frame
	scr.setup_location(Database.monster(&"hruz"))
	await host.get_tree().process_frame

	# Руна накладывается на текущее оружие и ЖИВЁТ НА ОРУЖИИ, а не в состоянии игрока.
	checks += 1
	scr._on_rune(&"fire")
	var bow: WeaponData = Database.weapon(&"bow")
	if bow.rune_type == &"fire":
		out.append("ок: руна огня наложена на лук (rune_type = fire)")
	else:
		failed += 1
		out.append("ПРОВАЛ: руна не наложилась (rune_type = «%s»)" % bow.rune_type)

	# Смена оружия на экране подготовки бесплатна и меняет состояние забега.
	checks += 1
	scr._on_take(&"blade")
	if GameState.equipped_weapon == &"blade":
		out.append("ок: оружие сменено на клинок")
	else:
		failed += 1
		out.append("ПРОВАЛ: оружие не сменилось (в руке «%s»)" % GameState.equipped_weapon)

	# Руна осталась на луке, а не «переехала» вместе с рукой: чары живут на предмете.
	checks += 1
	if bow.rune_type == &"fire":
		out.append("ок: руна осталась на луке после смены оружия")
	else:
		failed += 1
		out.append("ПРОВАЛ: руна исчезла с лука при смене оружия")

	# И руна обязана доходить до урона, иначе экран — декорация.
	checks += 1
	var mon: MonsterData = Database.monster(&"hruz")
	var with_rune := DamageCalc.player_damage(
		bow, mon, DamageCalc.Reading.COUNTER, false, 0, 0, {}, 0.0, null).type_reasons
	var rune_in_reasons := false
	for reason in with_rune:
		if "огонь" in String(reason):
			rune_in_reasons = true
	if rune_in_reasons:
		out.append("ок: руна учтена в расчёте урона (%s)" % ", ".join(with_rune))
	else:
		failed += 1
		out.append("ПРОВАЛ: руна не попала в расчёт урона (%s)" % ", ".join(with_rune))

	# Досье: закрыто — кнопка молчит, открыто — показывает то же, что город.
	# Проверяем оба состояния, потому что «кнопка есть» не значит «кнопка работает».
	# Сначала наполняем досье: на пустом досье проверка прошла бы, ничего не проверив.
	GameState.dossier_add(&"hruz", "signals", "припадает к земле")
	GameState.dossier_add(&"hruz", "signals", "ракушки дребезжат")
	GameState.dossier_add(&"hruz", "signals", "шипит")
	GameState.dossier_add(&"hruz", "decoys", "вода идёт рябью")
	checks += 1
	scr._toggle_dossier()
	if scr.dossier_window.visible and not scr.dossier_window.monster == null:
		out.append("ок: окно досье открылось")
	else:
		failed += 1
		out.append("ПРОВАЛ: окно досье не показалось")
	scr._toggle_dossier()
	checks += 1
	if scr.dossier_window.visible:
		failed += 1
		out.append("ПРОВАЛ: окно досье не скрылось по повторному нажатию")
	else:
		out.append("ок: окно досье скрывается повторным нажатием")

	# Главное в досье — связь «атака → её улики». Проверка держит именно её:
	# сигнал «припадает к земле» принадлежит сценарию «Прыгнет», и он обязан
	# оказаться в СТРУКТУРЕ этой атаки, а не в общем списке улик.
	checks += 1
	var view := CityData.dossier_view(Database.monster(&"hruz"))
	var pounce: Dictionary = {}
	for attack in (view["attacks"] as Array):
		if bool(attack["known"]) and "Прыгнет" in String(attack["label"]):
			pounce = attack
	if not pounce.is_empty() and (pounce["signals"] as PackedStringArray).has("припадает к земле"):
		out.append("ок: улика «припадает к земле» лежит в атаке «Прыгнет»")
	else:
		failed += 1
		out.append("ПРОВАЛ: улика не привязана к атаке (блоков атак: %d)" % (view["attacks"] as Array).size())

	# Улика ЧУЖОЙ атаки не имеет права оказаться в этом блоке: «шипит» — это
	# сценарий «Ударит клешнёй».
	checks += 1
	if not (pounce["signals"] as PackedStringArray).has("шипит"):
		out.append("ок: улика чужой атаки не попала в блок «Прыгнет»")
	else:
		failed += 1
		out.append("ПРОВАЛ: в блок «Прыгнет» попала улика чужой атаки")

	# Ложный след обязан лежать в блоке ТОЙ атаки, которую он маскирует:
	# «вода идёт рябью» маскирует claw, а не pounce.
	checks += 1
	var claw: Dictionary = {}
	for attack in (view["attacks"] as Array):
		if bool(attack["known"]) and "Ударит клешнёй" in String(attack["label"]):
			claw = attack
	if not claw.is_empty() and (claw["decoys"] as PackedStringArray).has("вода идёт рябью"):
		out.append("ок: обман лежит в блоке маскируемой атаки")
	else:
		failed += 1
		out.append("ПРОВАЛ: обман не привязан к маскируемой атаке")

	# Город и подготовка показывают досье из ОДНОЙ структуры (dossier_view), а не
	# из своих строк. Проверка держит то, на что оба экрана опираются: заголовок
	# вида и счёт «сколько атак ещё закрыто». Второе — не украшение: по нему
	# игрок в списке города видит, осталось ли ему что открывать.
	#
	# Раньше здесь проверялся строковый рендер CityData.dossier_lines. Он удалён:
	# его не звал ни один экран, и эта проверка давала зелёный отчёт о функции,
	# которую игрок никогда не видел.
	checks += 1
	var shared := CityData.dossier_view(Database.monster(&"hruz"))
	var identity: Dictionary = shared["identity"]
	var shared_ok := String(identity["level_title"]) != "" and String(identity["title"]) != ""
	var unlearned := int(shared["unlearned"])
	var total_attacks := (shared["attacks"] as Array).size()
	if shared_ok and unlearned >= 0 and unlearned <= total_attacks:
		out.append("ок: общая структура досье даёт заголовок «%s» и %d закрытых атак из %d" % [
			identity["level_title"], unlearned, total_attacks])
	else:
		failed += 1
		out.append("ПРОВАЛ: структура досье без заголовка или со сломанным счётом атак")

	# --- Эффекты навыков: один источник на бой и на прогон баланса -------------
	#
	# Проверки ниже сторожат ПРОВОДКУ, а не числа: числа считать нечего. Дефект,
	# который они ловят, — «механика есть, но включателя нет». Так было с «Вторым
	# дыханием» и «Фениксом»: движок честно проверял second_wind_available и
	# phoenix_available, но первое поле не выставлялось ни в одном файле, а второе
	# не выставлялось даже из hunter.phoenix. Два навыка по 80 и 100 монет не
	# делали ничего, и в отчёте симулятора это было видно: second_wind_rate и
	# phoenix_rate равны 0.0 во ВСЕХ сборках.
	GameState.reset()
	GameState.skills["surv_escape"] = true
	GameState.equipped_armor = &"cloak"
	GameState.skills["surv_hp1"] = true
	var probe_weapon: WeaponData = Database.weapon(&"bow")
	var probe_armor: ArmorData = Database.armor(&"light")
	checks += 1
	var eff_hunter := SkillEffects.build_hunter(probe_weapon, probe_armor)
	if is_equal_approx(eff_hunter.bonus_escape_chance, 0.20) and eff_hunter.max_hp == 25:
		out.append("ок навыков: побег +%d%% (навык и плащ), HP %d от навыка" % [
			roundi(eff_hunter.bonus_escape_chance * 100.0), eff_hunter.max_hp])
	else:
		failed += 1
		out.append("ПРОВАЛ навыков: побег %f (ждали 0.20), HP %d (ждали 25)" % [
			eff_hunter.bonus_escape_chance, eff_hunter.max_hp])

	# «Феникс»: навык включён в охотнике и ДОХОДИТ до движка. Проверяем настоящим
	# боем, а не флагом.
	#
	# Условия подобраны по числам, и это не придирки — на них я уже ошибся дважды:
	#  * зверь обязан быть БЫСТРЕЕ охотника, иначе превентивного удара не будет.
	#    Бонус оружия к инициативе обнуляем, а штраф брони задаём явно: с луком
	#    (+1) и без штрафа охотник быстрее Ламента, и первый вариант проверки молча
	#    ничего не проверял;
	#  * зверь обязан ПРОБИТЬ поглощение. С Шипуном урон 2 при поглощении 3 даёт 0,
	#    и охотник с 1 HP выжил бы без всякого «Феникса». У Ламента урон 7.
	GameState.reset()
	GameState.skills["surv_phoenix"] = true
	var phoenix_weapon: WeaponData = Database.weapon(&"bow")
	phoenix_weapon.initiative_bonus = 0
	var phoenix_armor: ArmorData = Database.armor(&"heavy")
	phoenix_armor.initiative_penalty = 2
	var phoenix_hunter := SkillEffects.build_hunter(phoenix_weapon, phoenix_armor)
	phoenix_hunter.hp = 1
	checks += 1
	if phoenix_hunter.phoenix:
		var phoenix_engine := BattleEngine.new()
		var fast: MonsterData = Database.monster(&"lament")
		phoenix_engine.setup(fast, phoenix_hunter, phoenix_weapon)
		if phoenix_engine.phoenix_available and phoenix_engine.hunter.hp == 5:
			out.append("ок навыков: «Феникс» поднял охотника с 1 HP (%s быстрее: %d против %d, удар %d при поглощении %d)" % [
				fast.title, fast.initiative, phoenix_engine.hunter.initiative(),
				fast.base_damage, phoenix_engine.hunter.total_absorption()])
		else:
			failed += 1
			out.append("ПРОВАЛ навыков: «Феникс» не поднял охотника с 1 HP (HP %d, доступен %s, зверь бил первым %s)" % [
				phoenix_engine.hunter.hp, str(phoenix_engine.phoenix_available),
				str(phoenix_engine.preemptive_strike_done)])
	else:
		failed += 1
		out.append("ПРОВАЛ навыков: «Феникс» куплен, но не включён в охотнике")

	# «Второе дыхание»: флаг обязан доходить до движка тем же путём.
	GameState.reset()
	GameState.skills["surv_second_wind"] = true
	var wind_hunter := SkillEffects.build_hunter(probe_weapon, probe_armor)
	checks += 1
	if wind_hunter.second_wind:
		out.append("ок навыков: «Второе дыхание» включено в охотнике")
	else:
		failed += 1
		out.append("ПРОВАЛ навыков: «Второе дыхание» куплено, но не включено в охотнике")

	# Гейт достижения «Победа одним оружием»: счётчик растёт ТОЛЬКО когда инструмент
	# за бой не менялся. Проверяем оба исхода прямо, потому что на прогоне баланса
	# этого не видно: бот оружие в бою не меняет, и верный гейт там неотличим от
	# неверного. Дефект, который здесь сторожится, был настоящим: achievement читал
	# флаг ПОСЛЕДНЕГО раунда, а тот обнулялся при переходе к следующему, — значит
	# достижение выдавалось за победу с перебором оружия, если в последнем ходу
	# игрок оружие не менял.
	GameState.reset()
	checks += 1
	var no_switch := HuntResult.new()
	no_switch.monster_id = &"hruz"
	no_switch.victory = true
	no_switch.had_armor = true
	no_switch.misses = 3
	no_switch.apply(false)
	var after_no_switch := int(GameState.counters.get("kills_one_weapon", 0))
	GameState.reset()
	var with_switch := HuntResult.new()
	with_switch.monster_id = &"hruz"
	with_switch.victory = true
	with_switch.had_armor = true
	with_switch.switched_weapon = true
	with_switch.misses = 3
	with_switch.apply(false)
	var after_switch := int(GameState.counters.get("kills_one_weapon", 0))
	if after_no_switch == 1 and after_switch == 0:
		out.append("ок достижений: «одним оружием» засчитана без смены (%d) и НЕ засчитана со сменой (%d)" % [
			after_no_switch, after_switch])
	else:
		failed += 1
		out.append("ПРОВАЛ достижений: счётчик «одним оружием» без смены %d (ждали 1), со сменой %d (ждали 0)" % [
			after_no_switch, after_switch])

	out.append("")
	out.append("ПРОВАЛОВ: %d из %d" % [failed, checks])
	Report.write(PREP_REPORT, out)
	scr.queue_free()
	return "ПРОВАЛОВ: %d из %d" % [failed, checks]


## Дым: экран боя проходит бой без человека. Проверяет не только «не падает», но и
## то, что досье наполняется по ходу боя.
static func smoke(host: Node) -> String:
	var out: Array[String] = []
	GameState.reset()
	GameState.coins = 100
	# Проверяем и навыки, влияющие на показ прозы: подсветка опоры и скрытие обмана.
	GameState.skills["read_signal"] = true

	var packed: PackedScene = load("res://ui/screens/battle/battle_screen.tscn")
	if packed == null:
		Report.write(SMOKE_REPORT, ["SMOKE FAILED: сцена не загрузилась"])
		return "сцена боя не загрузилась"
	var screen: Node = packed.instantiate()
	host.add_child(screen)
	var captured := {"result": null}
	screen.battle_finished.connect(func(r): captured["result"] = r)
	await host.get_tree().process_frame
	out.append("экран создан: %s" % screen.get_class())
	screen.setup_hunt(&"hruz", 0)
	await host.get_tree().process_frame

	if screen.engine == null:
		out.append("SMOKE FAILED: движок не стартовал")
		Report.write(SMOKE_REPORT, out)
		return "движок не стартовал"

	var engine: BattleEngine = screen.engine
	out.append("зверь: %s, HP %d, панцирь %d" % [
		engine.monster.title, engine.monster_hp, engine.monster.armor])
	out.append("охотник: HP %d, броня %d, срез: %s" % [
		screen.hunter.max_hp, screen.hunter.total_absorption(), str(screen.hunter.is_capped())])

	var rounds := 0
	var guard := 0
	# Переключаем оружие ПОСРЕДИ боя, чтобы проверить учёт «сменил за весь бой».
	# Именно здесь ломалось достижение «Победа одним оружием»: экран читал флаг
	# последнего раунда, а тот обнулялся при переходе к следующему.
	var switch_round := 2
	while not engine.is_over() and guard < 60:
		guard += 1
		if rounds < 3:
			out.append("--- раунд %d ---" % engine.round_index)
			out.append("проза (с подсветкой навыка): %s" % screen._render_prose())
			out.append("карточек: %d" % screen.cards_box.get_child_count())
		rounds += 1
		if rounds == 1:
			screen.selected_guess = &"__нет_такого__"
		else:
			screen.selected_guess = engine.current_scenario_id()
		if rounds == switch_round:
			# Настоящий ход экрана, а не обход: так проверяются и учёт, и запись
			# в досье — то, что раньше тест делал за экран руками.
			screen._submit_swap(Database.weapon(&"blade"))
			out.append("на раунде %d сменил оружие на клинок" % rounds)
			if screen._switched_any_weapon:
				out.append("ок учёта: смена на раунде %d запомнена за бой" % rounds)
			else:
				out.append("ПРОВАЛ учёта: смена на раунде %d не запомнена за бой" % rounds)
		else:
			screen._submit_guess()
		if not engine.is_over():
			screen._on_continue()
		await host.get_tree().process_frame

	# Бой кончился на ПОСЛЕДНЕМ ходу, и цикл выше не позвал _on_continue: он зовётся
	# только пока бой идёт. Поэтому завершаем явно — иначе итог не будет выдан и
	# проверка смены оружия в итоге стала бы проверкой пустоты.
	if captured["result"] == null:
		screen._on_continue()
		await host.get_tree().process_frame

	out.append("--- итог ---")
	out.append("фаза: %s, раундов: %d, HP охотника: %d, HP зверя: %d" % [
		engine.phase, engine.round_index, screen.hunter.hp, engine.monster_hp])
	# Учёт боя: он должен вестись экраном через BattleTally, а не тестом.
	out.append("учёт боя: урон нанесён %d, получен %d, промахов %d, идеальных %d" % [
		screen._tally.damage_dealt, screen._tally.damage_taken,
		screen._tally.misses, screen._tally.perfect_reads])
	if screen._tally.damage_taken != 0 and screen._tally.misses > 0:
		out.append("ок учёта: экран считает урон и промахи сам")
	else:
		out.append("ПРОВАЛ учёта: счётчики экрана пусты (урон получен %d, промахов %d)" % [
			screen._tally.damage_taken, screen._tally.misses])
	# Смена оружия обязана дойти до ИТОГА, а не только до флага экрана: достижение
	# «Победа одним оружием» читает именно result.switched_weapon.
	var res = captured["result"]
	if res != null and res.switched_weapon:
		out.append("ок учёта: смена оружия попала в итог охоты (achievement увидит её)")
	else:
		out.append("ПРОВАЛ учёта: в итог охоты смена НЕ попала (result.switched_weapon = %s)" % (
			str(res.switched_weapon) if res != null else "итог не пришёл"))
	# Записываем накопленное в досье — так же, как это делает _finish в игре.
	var gained: int = screen._dossier.commit()
	out.append("в досье записано новых фактов: %d" % gained)
	out.append("досье: сигналов %d, сценариев %d, ложных следов %d, уязвимостей %d" % [
		(GameState.dossier_entry(&"hruz")["signals"] as Array).size(),
		(GameState.dossier_entry(&"hruz")["scenarios"] as Array).size(),
		(GameState.dossier_entry(&"hruz")["decoys"] as Array).size(),
		(GameState.dossier_entry(&"hruz")["weaknesses"] as Array).size()])
	out.append("уровень досье: %d (0 нет / 1 наблюдение / 2 анализ / 3 мастерство)" % GameState.dossier_level(&"hruz"))
	Report.write(SMOKE_REPORT, out)
	return "фаза %s, раундов %d, фактов в досье %d" % [engine.phase, engine.round_index, gained]


## Замер геометрии интерфейса: какие области экрана занимают панели. Нужно, чтобы
## требования к арту («нижняя треть тёмная») опирались на настоящие координаты,
## а не на догадку. Запускается БЕЗ `--headless`: размеры считаются от окна.
static func measure_ui(host: Node) -> String:
	var out: Array[String] = []
	var root: Node = load("res://ui/game_root.tscn").instantiate()
	host.add_child(root)
	await host.get_tree().process_frame
	await host.get_tree().process_frame
	var screen: Node = root.current
	if screen == null:
		Report.write(UI_REPORT, ["экран города не создан"])
		return "экран города не создан"
	out.append("окно: %s" % str(host.get_viewport().get_visible_rect().size))
	_dump_rects(host, screen, out, 0)
	_economy_check(screen, out)
	Report.write(UI_REPORT, out)
	return "замерено панелей: %d" % out.size()


## Экономика города: трата обязана ОТКАЗАТЬ, когда монет не хватает.
##
## Зачем отдельная проверка. Инвариант в прогоне баланса (`--loop`) следит за тем,
## что кошелёк не уходит в минус, но он проверяет только путь симулятора: там
## доступность цены спрашивают через can_afford() снаружи. Путь ЭКРАНА он не
## трогает вовсе, а именно там жили три копии защиты (оружие, броня, совет).
## Проверено опытом: со снятой защитой внутри spend_coins прогон остался зелёным.
##
## Поэтому здесь вызывается настоящий обработчик кнопки города, а не игровой
## справочник. Проверки три, и они различают три разные ошибки:
##  1. не хватило монет — обработчик НЕ имеет права списать ничего и выдать товар;
##  2. монет ровно впритык — покупка обязана пройти (иначе защита строже правды);
##  3. при отказе состав снаряжения не меняется (иначе «купил бесплатно»).
##
## Берётся САМОЕ ДЕШЁВОЕ оружие с ценой > 0, и это не придирка: в базе есть
## оружие за 0, и на нём отказ был бы вакуумным — не хватить не может.
static func _economy_check(screen: Node, out: Array[String]) -> void:
	var cheapest: WeaponData = null
	for id in Database.weapons.keys():
		var w: WeaponData = Database.weapons[id]
		if w == null or w.price <= 0:
			continue
		if cheapest == null or w.price < cheapest.price:
			cheapest = w
	if cheapest == null:
		out.append("ПРОВАЛ экономики: в базе нет оружия с ценой > 0 — проверка траты ничего не проверила")
		return

	# 1. Не хватает одной монеты.
	GameState.reset()
	GameState.coins = cheapest.price - 1
	var owned_before := GameState.owned_weapons.size()
	screen._buy_or_equip_weapon(cheapest.id)
	if GameState.coins == cheapest.price - 1 and GameState.owned_weapons.size() == owned_before:
		out.append("ок экономики: без монет «%s» (цена %d) не куплено и не списано" % [
			cheapest.title, cheapest.price])
	else:
		out.append("ПРОВАЛ экономики: при нехватке монет «%s» цена %d — кошелёк %d (был %d), оружия %d (было %d)" % [
			cheapest.title, cheapest.price, GameState.coins, cheapest.price - 1,
			GameState.owned_weapons.size(), owned_before])

	# 2. Монет ровно впритык — покупка обязана состояться.
	# Пополняем кошелёк заново: после отказа в нём осталось на монету меньше, и без
	# этой строки проверка падала бы на собственной ошибке, а не на ошибке кода.
	GameState.coins = cheapest.price
	screen._buy_or_equip_weapon(cheapest.id)
	if GameState.coins == 0 and cheapest.id in GameState.owned_weapons:
		out.append("ок экономики: за ровно %d монет «%s» куплено, кошелёк пуст" % [
			cheapest.price, cheapest.title])
	else:
		out.append("ПРОВАЛ экономики: за ровно %d монет «%s» не куплено (кошелёк %d, в руках: %s)" % [
			cheapest.price, cheapest.title, GameState.coins, str(GameState.owned_weapons)])


static func _dump_rects(host: Node, node: Node, out: Array[String], depth: int) -> void:
	if node is Control:
		var c: Control = node
		var r := c.get_global_rect()
		var vp := host.get_viewport().get_visible_rect().size
		if r.size.x * r.size.y > 20000.0:
			out.append("%s%s [%s] x=%d..%d y=%d..%d (%.0f%% ширины, %.0f%% высоты)" % [
				"  ".repeat(depth), c.name, c.get_class(),
				int(r.position.x), int(r.position.x + r.size.x),
				int(r.position.y), int(r.position.y + r.size.y),
				r.size.x * 100.0 / maxf(1.0, vp.x), r.size.y * 100.0 / maxf(1.0, vp.y)])
	for child in node.get_children():
		_dump_rects(host, child, out, depth + 1)


## Скриншоты экранов без участия человека. Нужны потому, что посмотреть на игру
## иначе нечем: MCP-сервер умеет снимать кадр, но у его аддона переполняется
## исходящий буфер WebSocket на большом PNG (wsl_peer.cpp: ERR_OUT_OF_MEMORY),
## и кадр до нас не доходит. Здесь кадр берётся самим движком и кладётся на диск.
static func capture_shots(host: Node) -> String:
	var out: Array[String] = []
	DirAccess.make_dir_recursive_absolute(SHOTS_DIR)
	GameState.reset()
	# Деньги и добыча: пустой экран честен, но по нему не видно, читаются ли
	# списки и кнопки. Поэтому даём игре монеты и наполняем ношу добычей.
	GameState.coins = 120
	for mon_id in Database.monsters.keys():
		var mon: MonsterData = Database.monsters[mon_id]
		if mon == null:
			continue
		out.append("ноша: %s -> добычи на %d" % [mon.title, GameState.add_drop(mon)])
		if GameState.bag.size() >= 3:
			break

	var packed: PackedScene = load("res://ui/game_root.tscn")
	if packed == null:
		Report.write("%s/_shots_out.txt" % SHOTS_DIR, ["экран города не загрузился"])
		return "экран города не загрузился"
	host.add_child(packed.instantiate())
	# Два кадра: первый строит дерево, второй рисует его. Снимать раньше —
	# получить пустой или недостроенный кадр.
	await host.get_tree().process_frame
	await host.get_tree().process_frame

	var err := _save_shot(host, "%s/01_city.png" % SHOTS_DIR)
	out.append("01_city.png: %s" % ("ок" if err == OK else "ошибка %d" % err))
	Report.write("%s/_shots_out.txt" % SHOTS_DIR, out)
	return "01_city.png: %s" % ("ок" if err == OK else "ошибка %d" % err)


## Сохранить текущий кадр окна в PNG. Возвращает код ошибки Godot.
static func _save_shot(host: Node, path: String) -> int:
	var tex := host.get_viewport().get_texture()
	if tex == null:
		return FAILED
	var img: Image = tex.get_image()
	if img == null:
		return FAILED
	return img.save_png(path)
