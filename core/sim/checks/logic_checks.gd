extends RefCounted
class_name LogicChecks
## Проверки, которым НЕ нужны сцены и дерево узлов.
##
## Все они считаются на чистом ядре и автозагрузках, поэтому живут в `core/` рядом
## с тем, что проверяют. Проверки, которым нужен узел (подготовка, дым, замер окон,
## скриншоты), лежат в `ui/checks/ui_checks.gd`: в `core/` нет и не должно быть Node.
##
## Перенесено из `main.gd`, где проверки занимали больше половины файла и были
## перемешаны с рантаймом. Точка входа теперь только разбирает аргументы, а что
## именно проверять — дело этих модулей.
##
## Каждый метод сам пишет отчёт через `Report` и возвращает КОРОТКУЮ сводку для
## журнала: чтобы по запуску было видно, чем кончилось, не открывая файл.

const VALIDATE_REPORT := "_validate_out.txt"
const OUTCOMES_REPORT := "_outcomes_out.txt"
const SWAP_REPORT := "_swap_out.txt"
const ART_REPORT := "_art_out.txt"
const REPEAT_REPORT := "_repeat_out.txt"
const PROSE_REPORT := "_prose_out.txt"
const PROBE_REPORT := "_probe_out.txt"
const LOOP_REPORT := "_loop_out.txt"
const LOOP_TRACE := "_loop_trace.txt"


## Инварианты контента (см. ContentValidator).
static func validate() -> String:
	var v: RefCounted = load("res://core/sim/content_validator.gd").new()
	var problems: Array = v.validate_all()
	var out: Array[String] = []
	if problems.is_empty():
		out.append("VALIDATION OK: контент прошёл все инварианты")
	else:
		out.append("VALIDATION FAILED: %d проблем" % problems.size())
		for p in problems:
			out.append("  - %s" % str(p))
	Report.write(VALIDATE_REPORT, out)
	return out[0]


## Таблица решений резолвера исхода. Проверяет ровно то, что легко сломать правкой
## вёрстки или новым условием: какой экран показать после боя.
##
## Почему таблицей, а не глазами: выбор экрана — это логика прогрессии, и её ошибка
## не видна в отчётах боя. Так мы уже ловили симулятор, считавший побег поражением.
static func outcomes() -> String:
	var out: Array[String] = []
	var failed := 0
	# победа, побег, конец забега, откат ранга, ожидаемый экран
	var cases := [
		[true, false, false, false, Outcome.VICTORY],
		[false, true, false, false, Outcome.ESCAPE],
		[false, false, false, true, Outcome.DEFEAT],
		[false, false, false, false, Outcome.DEFEAT],
		[false, false, true, true, Outcome.RUN_OVER],
		[false, false, true, false, Outcome.RUN_OVER],
	]
	for c in cases:
		var got: StringName = Outcome.resolve(c[0], c[1], c[2], c[3])
		var ok: bool = got == c[4]
		if not ok:
			failed += 1
		out.append("%s: победа=%s побег=%s конец=%s откат=%s → %s (ждали %s)" % [
			"ок" if ok else "ПРОВАЛ", c[0], c[1], c[2], c[3], str(got), str(c[4])])
	out.append("")
	out.append("ПРОВАЛОВ: %d из %d" % [failed, cases.size()])
	Report.write(OUTCOMES_REPORT, out)
	return "ПРОВАЛОВ: %d из %d" % [failed, cases.size()]


## Ход в бою со сменой инструмента: смена не даёт ударить, а навык «Быстрая смена»
## снимает именно этот штраф.
##
## Проверяем БОЕВОЙ путь (`submit_read(attack = false)`), а не вспомогательный метод
## ядра. Раньше здесь гонялся `swap_weapon(cost_turn = true)`, которого экран не
## звал вовсе, — то есть проверка была зелёной на мёртвом коде и давала ложную
## уверенность. Верное чтение берём явно, иначе исход зависел бы от сценария раунда.
static func swap() -> String:
	var out: Array[String] = []
	var failed := 0
	var checks := 0

	# 1. Смена без удара: урона зверю нет, а по верному чтению нет и урона охотнику.
	checks += 1
	var r1 := _swap_probe(false)
	if int(r1["to_monster"]) != 0:
		failed += 1
	out.append("%s: смена без удара — урон зверю %d (ждали 0)" % [
		"ок" if int(r1["to_monster"]) == 0 else "ПРОВАЛ", int(r1["to_monster"])])
	checks += 1
	if int(r1["to_hunter"]) != 0:
		failed += 1
	out.append("%s: смена при верном чтении — урон охотнику %d (ждали 0)" % [
		"ок" if int(r1["to_hunter"]) == 0 else "ПРОВАЛ", int(r1["to_hunter"])])
	checks += 1
	if String(r1["weapon"]) != String(r1["expected"]):
		failed += 1
	out.append("%s: инструмент сменился на %s" % [
		"ок" if String(r1["weapon"]) == String(r1["expected"]) else "ПРОВАЛ", r1["weapon"]])

	# 2. Навык «Быстрая смена»: смена проходит ВМЕСТЕ с ударом, и навык сгорает.
	checks += 1
	var r2 := _swap_probe(true)
	if int(r2["to_monster"]) <= 0:
		failed += 1
	out.append("%s: «Быстрая смена» — урон зверю %d (ждали >0)" % [
		"ок" if int(r2["to_monster"]) > 0 else "ПРОВАЛ", int(r2["to_monster"])])
	checks += 1
	if not bool(r2["free_used"]):
		failed += 1
	out.append("%s: навык израсходован" % ("ок" if bool(r2["free_used"]) else "ПРОВАЛ"))

	# 3. Навык сгорел: следующий ход того же охотника снова без удара. Проверяем на
	# ОДНОМ состоянии: новый прогон выдал бы свежий навык, и «сгорел» не проверилось бы.
	checks += 1
	var r3 := _swap_probe(true)
	var engine3: BattleEngine = r3["engine"]
	var hunter3: HunterState = r3["hunter"]
	engine3.advance_round()
	engine3.equip_weapon(Database.weapon(&"bow"))
	var second: Dictionary = engine3.submit_read(engine3.current_scenario_id(), false)
	var second_dmg := int(second.get("damage_to_monster", -1))
	if second_dmg != 0:
		failed += 1
	out.append("%s: после расхода навыка смена опять без удара — урон зверю %d (ждали 0)" % [
		"ок" if second_dmg == 0 else "ПРОВАЛ", second_dmg])
	checks += 1
	if hunter3.weapon_swap_free:
		failed += 1
	out.append("%s: навык остался израсходованным" % (
		"ок" if not hunter3.weapon_swap_free else "ПРОВАЛ"))

	out.append("")
	out.append("ПРОВАЛОВ: %d из %d" % [failed, checks])
	Report.write(SWAP_REPORT, out)
	return "ПРОВАЛОВ: %d из %d" % [failed, checks]


## Один ход со сменой инструмента. `free_swap` — выдан ли навык «Быстрая смена».
## Чтение всегда верное: иначе исход зависел бы от случайного сценария раунда.
static func _swap_probe(free_swap: bool) -> Dictionary:
	var mon: MonsterData = Database.monster(&"hruz")
	var weapon: WeaponData = Database.weapon(&"bow")
	var other: WeaponData = Database.weapon(&"blade")
	if mon == null or weapon == null or other == null:
		return {"to_monster": -1, "to_hunter": -1, "weapon": "", "expected": "",
			"free_used": false, "engine": null, "hunter": null}

	var hunter := HunterState.new()
	hunter.max_hp = 20
	hunter.hp = 20
	hunter.absorption = 1
	hunter.weapon_swap_free = free_swap
	var engine := BattleEngine.new()
	engine.seed_source = SeedSource.new(1, 1)
	engine.setup(mon, hunter, weapon)
	engine.advance_round()
	engine.equip_weapon(other)
	var outcome: Dictionary = engine.submit_read(engine.current_scenario_id(), false)
	return {
		"to_monster": int(outcome.get("damage_to_monster", -1)),
		"to_hunter": int(outcome.get("damage_to_hunter", -1)),
		"weapon": String(engine.weapon.id),
		"expected": String(other.id),
		"free_used": not hunter.weapon_swap_free,
		# Отдаём состояние наружу: проверка «навык сгорел» требует ВТОРОГО хода того
		# же охотника. Новый прогон выдал бы свежий навык — и проверка ничего не значит.
		"engine": engine,
		"hunter": hunter,
	}


## Арт: то, что нельзя увидеть в headless, можно измерить.
##
## Считаем не «есть ли файл», а ПРИГОДНОСТЬ файла — числами, а не на глаз:
## размер кадра, средняя яркость и пик, РОВНОТУ ФОНА по краям. Последнее главное
## для картинок зверей: по ровному фону вырезается альфа.
static func art() -> String:
	var out: Array[String] = []
	var problems := 0
	for id in Database.monsters.keys():
		var mon: MonsterData = Database.monsters[id]
		out.append("=== %s (%s) ===" % [mon.title, mon.id])
		out.append("  карточка: %s" % _tex_info(mon.portrait))
		if mon.portrait != null:
			out.append("  метрики карточки: %s" % _image_metrics(mon.portrait))
		out.append("  силуэт: %s" % _tex_info(mon.silhouette))
		out.append("  цвет акцента: %s" % mon.accent())
		out.append("  масштаб %s, смещение %s" % [mon.art_scale, mon.art_offset])
		if mon.portrait == null:
			out.append("  !! нет карточки вида")
			problems += 1
		var missing := 0
		for scn in mon.scenarios:
			var art_res: Texture2D = mon.by_scenario.get(String(scn.id), null)
			if art_res == null:
				missing += 1
			else:
				out.append("    поза %s: %s" % [scn.id, _image_metrics(art_res)])
		out.append("  поз по сценариям: %d из %d (нет %d) — пока берётся карточка" % [
			mon.scenarios.size() - missing, mon.scenarios.size(), missing])
		var loc := GameState.location_art_path(mon.id)
		if loc.is_empty():
			out.append("  !! не определена локация для вида")
			problems += 1
		else:
			out.append("  фон локации %s: %s" % [loc.get_file(), _tex_info(load(loc))])
			if load(loc) == null:
				problems += 1
	out.append("")
	out.append("=== локации города ===")
	var city := CityData.overview_art()
	out.append("  общий вид: %s" % ("нет файла" if city.is_empty() else _tex_info(load(city))))
	for tab in ["guild", "market", "master", "dossier", "tavern"]:
		var path := CityData.location_art(tab)
		out.append("  %s: %s" % [tab, "нет файла" if path.is_empty() else _tex_info(load(path))])
	out.append("")
	out.append("=== фон подготовки (лагерь) ===")
	var prep := CityData.prep_art()
	if prep.is_empty():
		out.append("  файла нет — экран подготовки берёт фон локации")
	else:
		var prep_tex: Texture2D = load(prep)
		out.append("  %s: %s" % [prep.get_file(), _tex_info(prep_tex)])
		if prep_tex != null:
			out.append("  метрики: %s" % _image_metrics(prep_tex))
	out.append("")
	out.append("итог: проблем %d" % problems)
	Report.write(ART_REPORT, out)
	return "проблем %d" % problems


## Метрики картинки числом: средняя яркость, пик и РОВНОТА КРАЁВ.
##
## Ровнота краёв — главная метрика для картинок зверей: фон должен быть одним и тем
## же цветом по всему кадру, потому что по нему вырезается альфа. Считаем разброс
## яркости по рамке в 4 пикселя: у ровного фона он единицы, у градиента с виньеткой
## десятки.
static func _image_metrics(tex: Texture2D) -> String:
	var img := tex.get_image()
	if img == null:
		return "нет данных"
	var w := img.get_width()
	var h := img.get_height()
	var step := maxi(1, int(maxf(float(w), float(h)) / 160.0))
	var total := 0.0
	var count := 0
	var peak := 0.0
	var edge_min := 255.0
	var edge_max := 0.0
	for y in range(0, h, step):
		for x in range(0, w, step):
			var v := img.get_pixel(x, y).get_luminance() * 255.0
			total += v
			count += 1
			peak = maxf(peak, v)
			# Рамка кадра: 4 пикселя от каждого края — по ней и режется альфа.
			if x < 4 or y < 4 or x >= w - 4 or y >= h - 4:
				edge_min = minf(edge_min, v)
				edge_max = maxf(edge_max, v)
	var mean := total / maxf(1.0, float(count))
	var spread := edge_max - edge_min
	return "%dx%d, средняя %.0f, пик %.0f, разброс краёв %.0f%s" % [
		w, h, mean, peak, spread,
		"  !! фон неровный" if spread > 8.0 else ""]


static func _tex_info(tex: Texture2D) -> String:
	if tex == null:
		return "НЕТ"
	return "%dx%d" % [tex.get_width(), tex.get_height()]


## Измерение повторов текста. Критерий GDD 13.2: «текст не повторяется заметно в
## течение 10 боёв». Доля повторов тут не годится — при сотнях раундов она стремится
## к 100% у любого конечного пула. Считаем ГЛУБИНУ повтора: сколько раундов проходит,
## прежде чем фраза встречается снова. Именно глубина переживается игроком.
static func repeats() -> String:
	var out: Array[String] = []
	var rounds := 400
	out.append("глубина повтора: сколько раундов между двумя появлениями одной фразы")
	out.append("(чем больше, тем свежее текст; цель — не меньше 10 раундов)")
	out.append("")
	var worst_min := 10_000
	for id in Database.monsters.keys():
		var mon: MonsterData = Database.monsters[id]
		var per_scenario: Dictionary = {}
		TextGenerator.reset_history()
		var rng := RandomNumberGenerator.new()
		rng.seed = hash("repeat:" + String(mon.id))
		for i in rounds:
			var scn: ScenarioData = mon.scenarios[i % mon.scenarios.size()]
			var gen := TextGenerator.generate(mon, scn, rng)
			for line in gen["lines"]:
				var key := "%s|%s" % [scn.id, str(line["phrase_id"])]
				if not per_scenario.has(key):
					per_scenario[key] = []
				per_scenario[key].append(i)
		var min_gap := 10_000
		var sum_gap := 0
		var gaps := 0
		var worst := ""
		for key in per_scenario.keys():
			var hits: Array = per_scenario[key]
			if hits.size() < 2:
				continue
			for k in range(1, hits.size()):
				var gap: int = int(hits[k]) - int(hits[k - 1])
				if gap < min_gap:
					min_gap = gap
					worst = str(key)
				sum_gap += gap
				gaps += 1
		var avg := 0.0 if gaps == 0 else snappedf(float(sum_gap) / float(gaps), 1)
		var verdict := "свежо" if min_gap >= 10 else ("приемлемо" if min_gap >= 5 else "ЗАМЕТНО")
		out.append("%s: минимальная глубина %d, средняя %s, повторов %d — %s" % [
			mon.title, min_gap, avg, gaps, verdict])
		if min_gap < worst_min:
			worst_min = min_gap
		if min_gap < 10 and not worst.is_empty():
			out.append("    самый частый повтор: %s" % worst)
	out.append("")
	out.append("=== то же по абзацам: сколько раз целиком совпал абзац ===")
	for id in Database.monsters.keys():
		var mon2: MonsterData = Database.monsters[id]
		TextGenerator.reset_history()
		var rng2 := RandomNumberGenerator.new()
		rng2.seed = hash("para:" + String(mon2.id))
		var seen_paras: Dictionary = {}
		var para_repeats := 0
		var last_seen: Dictionary = {}
		var min_para_gap := 10_000
		for i in 400:
			var scn2: ScenarioData = mon2.scenarios[i % mon2.scenarios.size()]
			var gen2 := TextGenerator.generate(mon2, scn2, rng2)
			var text := str(gen2["prose"])
			if last_seen.has(text):
				var gap: int = i - int(last_seen[text])
				if gap < min_para_gap:
					min_para_gap = gap
				para_repeats += 1
			last_seen[text] = i
			seen_paras[text] = true
		out.append("  %s: разных абзацев %d из 400, точных совпадений %d, минимальный промежуток %d" % [
			mon2.title, seen_paras.size(), para_repeats, min_para_gap])
	out.append("")
	out.append("Ориентир: за один бой проходит 5–25 раундов, значит глубина 10+ раундов")
	out.append("означает, что одна и та же фраза приходит не чаще раза за бой.")
	Report.write(REPEAT_REPORT, out)
	return "минимальная глубина: %d раундов" % worst_min


## Дамп прозы по раундам: глазами проверить, что опорные сигналы всегда на месте,
## а ложные следы не занимают их слоты.
##
## Веса и проценты здесь ОСТАЮТСЯ намеренно: это внутренний отчёт для проверки
## баланса. Игроку частота атак не показывается — веса сценариев внутренняя
## механика, поэтому в досье и окне вида процентов нет.
static func prose() -> String:
	var out: Array[String] = []
	for monster_id in Database.monsters.keys():
		var mon: MonsterData = Database.monsters[monster_id]
		out.append("=== %s (%s) ===" % [mon.title, mon.id])
		var total_weight := mon.total_weight()
		for scn in mon.scenarios:
			var chance := snappedf(scn.chance_percent(total_weight), 0.1)
			out.append("")
			out.append("-- сценарий %s «%s», вес %d (%.1f%%), урон сценария %d" % [
				scn.id, scn.card_label, scn.weight, chance,
				scn.damage_override if scn.damage_override > 0 else mon.base_damage])
			for sig in scn.signals:
				out.append("   опора [%s] %s" % [sig.slot, sig.label])
			for run_i in 3:
				var rng := RandomNumberGenerator.new()
				rng.seed = hash("%s:%s:%d" % [mon.id, scn.id, run_i])
				var gen := TextGenerator.generate(mon, scn, rng)
				var roles: PackedStringArray = PackedStringArray()
				for l in gen["lines"]:
					roles.append("%s:%s" % [l["role"], l["slot"]])
				out.append("   сборка %d: %s" % [run_i + 1, gen["prose"]])
				out.append("            состав: %s" % ", ".join(roles))
	Report.write(PROSE_REPORT, out)
	return "видов: %d" % Database.monsters.size()


## Один раз: ResourceSaver пишет .tres в том же формате, который читает
## ResourceLoader. Может понадобиться при апгрейде версии Godot.
##
## Временный файл создаётся в папке проекта, поэтому за собой УБИРАЕМ: иначе Godot
## видит его как контент, и следующий запуск грузит мусорный вид.
static func probe() -> String:
	var out: Array[String] = []
	var mon := MonsterData.new()
	mon.id = &"probe"
	mon.title = "Проба"
	mon.max_hp = 12
	mon.armor = 2

	var scn := ScenarioData.new()
	scn.id = &"pounce"
	scn.card_label = "Прыгнет"
	scn.weight = 60
	scn.damage_override = 4

	var sig := SignalData.new()
	sig.id = &"probe.pose"
	sig.slot = &"pose"
	sig.label = "припадает к земле"
	scn.signals.append(sig)
	mon.scenarios.append(scn)
	mon.type_resist = {"fire": 1, "physical": 1}

	var temp := "res://_probe.tres"
	var err := ResourceSaver.save(mon, temp)
	out.append("save err = %d" % err)
	var back: MonsterData = null
	if err == OK:
		out.append(FileAccess.get_file_as_string(temp))
		back = load(temp)
	if back == null:
		out.append("LOAD FAILED")
	else:
		out.append("loaded: id=%s hp=%d armor=%d scenarios=%d" % [
			back.id, back.max_hp, back.armor, back.scenarios.size()])
	if err == OK:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temp))
		out.append("временный файл удалён: %s" % str(not FileAccess.file_exists(temp)))
	out.append_array(_status_mechanics())
	out.append_array(_status_from_content())
	out.append_array(_second_wind_preemptive())
	out.append_array(_fog_mechanics())
	out.append_array(_weapon_after_death())
	Report.write(PROBE_REPORT, out)
	return out[0]


## Обе механики на ЖИВОМ контенте: Пепел-Мать и её комбо «Ядовитое жало».
##
## Синтетическая проба выше проверяет, что свойства работают. Здесь проверяется
## другое, и это важнее: что контент до них ДОХОДИТ. Комбо лежит в .tres, движок
## читает `status_id` и обязан наложить статус — раньше вся эта цепочка вела в
## никуда: статус накладывался, а обрабатывать его было нечем.
##
## Сид перебирается намеренно: сценарий выбирается по весам, и «Укусит» (нужный
## для комбо) выпадает не в каждом бою. Проверка, которая «иногда проходит», хуже
## отсутствующей, поэтому перебор детерминирован — сиды идут по порядку.
static func _status_from_content() -> Array[String]:
	var out: Array[String] = []
	var mon: MonsterData = Database.monster(&"ashmother")
	if mon == null:
		out.append("ПРОВАЛ контента: Пепел-Мать не загружена")
		return out
	# Комбо требует ближнего боя и яда: клинок с руной яда.
	var weapon: WeaponData = Database.weapon(&"blade").duplicate()
	weapon.rune_type = &"poison"

	var found_blind := false
	var sighted_signals := 0
	var blind_signals := -1
	var combo_title := ""
	for seed_value in range(1, 60):
		var hunter := SkillEffects.build_hunter(weapon, Database.armor(&"light"))
		var engine := BattleEngine.new()
		engine.seed_source = SeedSource.new(seed_value, 5)
		engine.setup(mon, hunter, weapon)
		# Бьём по сценарию верно и бьём: иначе комбо не сработает.
		var outcome := engine.submit_read(engine.current_scenario_id(), true)
		if String(outcome.get("combo_title", "")) == "Ядовитое жало":
			combo_title = "Ядовитое жало"
			if engine.monster_statuses.has(BattleEngine.STATUS_BLIND):
				found_blind = true
				# Следующий раунд: проза должна идти без опорных улик.
				engine.advance_round()
				var blind_out := engine.submit_read(engine.current_scenario_id(), true)
				blind_signals = (blind_out.get("fact_signals", PackedStringArray()) as PackedStringArray).size()
				break
		elif sighted_signals == 0:
			sighted_signals = (outcome.get("fact_signals", PackedStringArray()) as PackedStringArray).size()

	if not found_blind:
		out.append("ПРОВАЛ контента: комбо «Ядовитое жало» не встретилось за 59 сидов")
		return out
	out.append("контент: комбо «%s» наложило слепоту; улик зрячим %d, слепым %d" % [
		combo_title, sighted_signals, blind_signals])
	if combo_title == "Ядовитое жало" and blind_signals == 0 and sighted_signals > 0:
		out.append("ок контента: статус из .tres дошёл до механики и скрыл улики")
	else:
		out.append("ПРОВАЛ контента: статус не скрыл улики (зрячим %d, слепым %d)" % [
			sighted_signals, blind_signals])
	return out


## Что происходит с ОРУЖИЕМ, когда игрок погиб и богиня его вернула.
##
## Вопрос не праздный: если при смерти теряется оружие или «рука» начинает указывать
## на предмет, которого нет, игрок остаётся без удара вовсе — это softlock, а не
## сложность. Проверка держит три вещи, каждая из которых ломала бы игру:
##   1. арсенал переживает смерть (смерть забирает материю: монеты и ношу);
##   2. «в руке» указывает на своё оружие, а не на проданное или потерянное;
##   3. зачарование не переезжает в СЛЕДУЮЩИЙ забег (руна лежит в ресурсе базы,
##      а не в состоянии забега, поэтому сброс её не снимает).
static func _weapon_after_death() -> Array[String]:
	var out: Array[String] = []
	GameState.reset()
	# Даём игроку арсенал и чары: без этого проверка была бы про пустоту.
	GameState.owned_weapons.append(&"blade")
	var mace: WeaponData = Database.weapon(&"mace")
	mace.rune_type = &"fire"
	GameState.equipped_weapon = &"mace"

	# Смерть при живой благодати: богиня возвращает, забег продолжается.
	var result := HuntResult.new()
	result.monster_id = &"hruz"
	result.order_rank = 0
	result.victory = false
	result.fled = false
	result.apply(false)

	var kept := GameState.owned_weapons.duplicate()
	var in_hand: WeaponData = Database.weapon(GameState.equipped_weapon)
	var still_owned: bool = GameState.equipped_weapon in GameState.owned_weapons
	var resurrected: bool = not result.run_over
	out.append("после смерти: арсенал %s, в руке «%s» (%s), воскрешён %s" % [
		str(kept), in_hand.title if in_hand != null else "—",
		"своё" if still_owned else "ЧУЖОЕ", str(resurrected)])
	if resurrected and kept.size() == 3 and still_owned and in_hand != null:
		out.append("ок воскрешения: арсенал цел, в руке своё оружие — ударить есть чем")
	else:
		out.append("ПРОВАЛ воскрешения: арсенал %d, «своё» %s, оружие %s" % [
			kept.size(), str(still_owned), str(in_hand != null)])

	# Зачарование и НОВЫЙ ЗАБЕГ — проверяем СОГЛАСОВАННОСТЬ, а не исчезновение чар.
	#
	# Почему остаток чар — НЕ дефект. Руна — навык, а не предмет: изучив «Руну огня»,
	# игрок знает её навсегда, и знание после смерти остаётся (решение зафиксировано
	# в docs/WORKPLAN.md, раздел «Руны и подготовка»). Поэтому зачарованный молот в
	# новом забеге — следствие знания, а не подарок: игрок вправе зачаровать любое
	# СВОЁ оружие. Я сначала счёл это эксплуатацией и ошибся: рассуждал так, будто
	# руну надо покупать каждый раз заново.
	#
	# Что здесь действительно проверяется: зачарование не появляется САМО, без
	# знания. Требовать «чары исчезли» было бы неверно — это противоречило бы
	# решению, что руна есть знание.
	GameState.reset()
	GameState.skills[SkillsData.RUNE_SKILLS.keys()[0]] = true
	var rune_type := StringName(SkillsData.RUNE_SKILLS.values()[0])
	var mace_next: WeaponData = Database.weapon(&"mace")
	var known := SkillsData.has_rune(GameState.skills, rune_type)
	var mace_hit := mace_next.damage_types()
	out.append("новый забег: знание руны «%s» есть %s, молот бьёт %s, чары на нём «%s»" % [
		rune_type, str(known), str(mace_hit), mace_next.rune_type])
	if known and mace_next.rune_type != &"":
		out.append("ок зачарования: чары в новом забеге идут вместе со знанием руны")
	elif known and mace_next.rune_type == &"":
		out.append("ок зачарования: знание руны есть, оружие чистое — зачаровать можно за ход")
	else:
		out.append("ПРОВАЛ зачарования: руна действует, а знания нет")
	return out
##
## Туман включён ровно у одного вида — Тлеуна (`fog_enabled`, ключ «Плюнет туманом»),
## поэтому проверка идёт на нём, а не на подставном виде: важно, что механика
## работает с настоящим контентом.
##
## Две вещи проверяются РАЗДЕЛЬНО, потому что вместе они дают противоречие: прозу
## раунда строит `advance_round()` в начале раунда, а чтение идёт позже. Значит на
## том ходу, когда туман снимается, проза уже скрыта — и это правильно. Смешав
## проверки, я получил бы «туман не скрывает» на верном READING и «туман не
## снимается» на проверке скрытия.
static func _fog_mechanics() -> Array[String]:
	var out: Array[String] = []
	var tleun: MonsterData = Database.monster(&"tleun")
	if tleun == null:
		out.append("ПРОВАЛ тумана: Тлеун не загружен")
		return out
	var weapon: WeaponData = Database.weapon(&"blade").duplicate()

	# 1. Туман активен: строк в прозе нет, и есть объяснение вместо пустоты.
	var engine := BattleEngine.new()
	engine.setup(tleun, SkillEffects.build_hunter(weapon, Database.armor(&"light")), weapon)
	engine.fog_active = true
	engine.advance_round()
	var fogged: Dictionary = engine.current_prose()
	var fog_lines := (fogged.get("lines", []) as Array).size()
	var fog_text := str(fogged.get("prose", ""))
	var dossier_out := engine.submit_read(engine.current_scenario_id(), true)
	var fog_signals := (dossier_out.get("fact_signals", PackedStringArray()) as PackedStringArray).size()
	out.append("туман: строк прозы %d, улик в досье %d, текст «%s»" % [
		fog_lines, fog_signals, fog_text])
	var says_blind := "наугад" in fog_text
	if fog_lines == 0 and fog_signals == 0 and says_blind:
		out.append("ок тумана: пока туман держится, улик нет и сказано, что читать нечего")
	else:
		out.append("ПРОВАЛ тумана: строк %d, улик %d, сказано про наугад: %s" % [
			fog_lines, fog_signals, str(says_blind)])

	# 2. Верное чтение ключевого сценария снимает туман.
	#
	# Сценарий раунда выбирается по весам, поэтому «Плюнет туманом» выпадает не
	# сразу: сценарий перебирается по сидам, а не берётся первый попавшийся. Иначе
	# проверка читала бы мимо ключа и «туман не снимается» — это была бы ошибка
	# теста, а не движка (на ней я уже ошибся один раз).
	var dispelled := false
	var fog_after := true
	var after_lines := 0
	var found_key := false
	var key_round := 0
	for seed_value in range(1, 40):
		var e := BattleEngine.new()
		e.seed_source = SeedSource.new(seed_value, 11)
		e.setup(tleun, SkillEffects.build_hunter(weapon, Database.armor(&"light")), weapon)
		e.fog_active = true
		e.advance_round()
		if e.current_scenario_id() != tleun.fog_key_scenario:
			continue
		found_key = true
		key_round = e.round_index
		var lifted := e.submit_read(tleun.fog_key_scenario, true)
		dispelled = bool(lifted.get("fog_dispelled", false))
		fog_after = e.fog_active
		# Следующий раунд обязан снова дать улики — иначе туман «снялся» на словах.
		e.advance_round()
		after_lines = (e.current_prose().get("lines", []) as Array).size()
		break

	out.append("туман снят чтением «%s»: ключ выпал %s (раунд %d), рассеян %s, улик дальше %d" % [
		tleun.fog_key_scenario, str(found_key), key_round, str(dispelled), after_lines])
	if found_key and dispelled and not fog_after and after_lines > 0:
		out.append("ок тумана: верное чтение ключа рассеяло туман, улики вернулись")
	elif not found_key:
		out.append("ПРОВАЛ тумана: ключевой сценарий не выпал за 39 сидов — проверка не состоялась")
	else:
		out.append("ПРОВАЛ тумана: рассеян %s, туман %s, улик %d" % [
			str(dispelled), str(fog_after), after_lines])
	return out
##
## Правило «охотник на нуле» жило в трёх копиях, и копия превентивного удара
## проверяла только «Феникса». Значит охотник с 1–3 HP, убитый быстрым зверем до
## своего первого хода, терял второй шанс, хотя навык куплен.
##
## Проверка бьёт по ОБЩЕМУ правилу (`_handle_hunter_down`) и по обоим исходам
## сразу: с навыком охотник обязан подняться, без навыка — пасть. Одного исхода
## мало: подъём мог бы дать «Феникс», и тогда проверка «Второго дыхания» ничего
## не проверяла бы. Обе ветки идут на охотнике с 1 HP и на нуле жизни.
##
## Почему не через engine.setup(). Настроить HP «до» боя нельзя: setup()
## пересобирает охотника и выставляет hp = max_hp. Ставить hp = 1 ПОСЛЕ настройки
## бессмысленно — превентивный удар уже прошёл внутри setup(). А гонять бой до
## низкого HP нельзя по другой причине: и превентивный удар, и симуляторы бьют
## только пока бой идёт, и охотник может погибнуть раньше нужного момента.
static func _second_wind_preemptive() -> Array[String]:
	var out: Array[String] = []
	var weapon: WeaponData = Database.weapon(&"blade").duplicate()
	var mon := MonsterData.new()
	mon.id = &"preempt_probe"
	mon.title = "Проба правила смерти"
	mon.max_hp = 30
	mon.armor = 0
	mon.base_damage = 6
	mon.initiative = 20
	var scn := ScenarioData.new()
	scn.id = &"pounce"
	scn.card_label = "Прыгнет"
	scn.weight = 100
	mon.scenarios.append(scn)

	# С навыком: HP 1 — на грани. Правило обязано поднять на 5 (то есть до 6).
	GameState.reset()
	GameState.skills["surv_second_wind"] = true
	var engine := BattleEngine.new()
	engine.setup(mon, SkillEffects.build_hunter(weapon, Database.armor(&"light")), weapon)
	engine.hunter.hp = 1
	engine.second_wind_used = false
	engine._handle_hunter_down({})
	var hp_with := engine.hunter.hp
	GameState.reset()

	# И тот же случай БЕЗ навыка: подъёма быть не должно. Одного исхода мало —
	# иначе подъём мог бы дать «Феникс», и проверка «Второго дыхания» была бы пустой.
	var engine2 := BattleEngine.new()
	engine2.setup(mon, SkillEffects.build_hunter(weapon, Database.armor(&"light")), weapon)
	engine2.hunter.hp = 1
	engine2._handle_hunter_down({})
	var hp_without := engine2.hunter.hp

	# И третье: на НУЛЕ жизни без навыков правило обязано закрыть бой поражением,
	# а не оставить его висеть в ожидании хода мёртвого охотника.
	var engine3 := BattleEngine.new()
	engine3.setup(mon, SkillEffects.build_hunter(weapon, Database.armor(&"light")), weapon)
	engine3.hunter.hp = 0
	engine3._handle_hunter_down({})
	var phase_dead := engine3.phase

	out.append("правило смерти: HP 1 с навыком → %d, без навыка → %d; HP 0 без навыков → фаза %s" % [
		hp_with, hp_without, phase_dead])
	if hp_with == 6 and hp_without == 1 and phase_dead == BattleEngine.PHASE_DEFEAT:
		out.append("ок «Второго дыхания»: на грани поднимает, без навыка не трогает, на нуле закрывает бой")
	else:
		out.append("ПРОВАЛ «Второго дыхания»: ждали 6 / 1 / defeat, получили %d / %d / %s" % [
			hp_with, hp_without, phase_dead])

	# Копия оружия под навык «+урон»: раньше она собиралась по полям вручную, и
	# `accent_color` в списке уже не было. Теперь это duplicate(), и проверка держит
	# две вещи разом: базовый урон вырос, а ОСТАЛЬНЫЕ поля ресурса не потерялись.
	GameState.reset()
	GameState.skills["wpn_dmg3"] = true
	var tuned_src: WeaponData = Database.weapon(&"blade")
	var engine4 := BattleEngine.new()
	engine4.setup(mon, SkillEffects.build_hunter(tuned_src, Database.armor(&"light")), tuned_src)
	var tuned: WeaponData = engine4.weapon
	GameState.reset()
	out.append("копия оружия: «%s» %s урон %d → %d, акцент «%s», дальность %s, руна «%s»" % [
		tuned.title, tuned.id, tuned_src.base_damage, tuned.base_damage,
		tuned.accent_color, tuned.range_id, tuned.rune_type])
	if (tuned.base_damage == tuned_src.base_damage + 3
			and tuned.title == tuned_src.title
			and tuned.accent_color == tuned_src.accent_color
			and tuned.range_id == tuned_src.range_id):
		out.append("ок копии оружия: урон поднят, остальные поля сохранены")
	else:
		out.append("ПРОВАЛ копии оружия: потеряны поля (урон %d, акцент «%s», дальность %s)" % [
			tuned.base_damage, tuned.accent_color, tuned.range_id])
	return out


## Механики статусов «слепота» и «открыт» — прямой проверкой свойств.
##
## Зачем отдельная проверка. Оба статуса жили в контенте как ОБЕЩАНИЕ: комбо
## Пепел-Матери и Шипуна писали «зверь слепнет», комбо Тлеуна — «зверь открыт»,
## и ни одного упоминания в коде не было. Валидатор ловит отсутствие статуса в
## списке движка, но не проверяет, что статус ЧТО-ТО ДЕЛАЕТ. Здесь проверяется
## именно действие, и проверка умеет краснеть: см. условия ниже.
static func _status_mechanics() -> Array[String]:
	var out: Array[String] = []
	var mon := MonsterData.new()
	mon.id = &"status_probe"
	mon.title = "Проба статусов"
	mon.max_hp = 30
	mon.armor = 0

	var scn := ScenarioData.new()
	scn.id = &"pounce"
	scn.card_label = "Прыгнет"
	scn.weight = 100
	var sig := SignalData.new()
	sig.id = &"sp.pose"
	sig.slot = &"pose"
	sig.label = "припадает к земле"
	scn.signals.append(sig)
	mon.scenarios.append(scn)

	# --- «Открыт»: удар обязан пройти на 1 глубже
	var weapon := WeaponData.new()
	weapon.id = &"probe_blade"
	weapon.range_id = MonsterData.RANGE_MELEE
	weapon.damage_type = MonsterData.TYPE_SLASH
	weapon.base_damage = 4

	# Считаем чистой формулой, без боя: проверяем РАЗНИЦУ от статуса, а не течение боя.
	var plain := DamageCalc.player_damage(
		weapon, mon, DamageCalc.Reading.COUNTER, false, 0, 0, {}, 0.0, null, false)
	var opened := DamageCalc.player_damage(
		weapon, mon, DamageCalc.Reading.COUNTER, false, 0, 0, {}, 0.0, null, true)
	out.append("открыт: урон %d без статуса, %d со статусом (разбор: %s)" % [
		plain.total, opened.total, opened.breakdown()])
	if opened.total == plain.total + 1 and opened.open_bonus == 1:
		out.append("ок статуса «открыт»: удар проходит на 1 глубже")
	else:
		out.append("ПРОВАЛ статуса «открыт»: урон не изменился (%d против %d)" % [
			plain.total, opened.total])

	# --- «Слепота»: проза раунда не должна давать опорных улик
	var engine2 := BattleEngine.new()
	engine2.seed_source = SeedSource.new(777, 2)
	var hunter2 := HunterState.new()
	hunter2.max_hp = 20
	hunter2.hp = 20
	hunter2.weapon_id = weapon.id
	engine2.setup(mon, hunter2, weapon)
	var sighted := engine2.submit_read(&"pounce")
	var sighted_signals: PackedStringArray = sighted.get("fact_signals", PackedStringArray())

	var engine3 := BattleEngine.new()
	engine3.seed_source = SeedSource.new(777, 3)
	var hunter3 := HunterState.new()
	hunter3.max_hp = 20
	hunter3.hp = 20
	hunter3.weapon_id = weapon.id
	engine3.setup(mon, hunter3, weapon)
	engine3.monster_statuses[BattleEngine.STATUS_BLIND] = {"rounds": 2, "text": "слеп"}
	# Проза раунда строится в setup(), поэтому после наложения статуса её нужно
	# перестроить: иначе проверка читает прозу, собранную ещё до слепоты. На этом
	# я уже ошибся — статус был наложен «слишком поздно», и улики уцелели.
	engine3.advance_round()
	var blinded := engine3.submit_read(&"pounce")
	var blind_signals: PackedStringArray = blinded.get("fact_signals", PackedStringArray())

	out.append("слепота: улик в досье %d зрячим, %d слепым" % [
		sighted_signals.size(), blind_signals.size()])
	if sighted_signals.size() > 0 and blind_signals.size() == 0:
		out.append("ок статуса «слепота»: слепой зверь не выдаёт улик")
	else:
		out.append("ПРОВАЛ статуса «слепота»: улики %s" % (
			"не скрыты" if blind_signals.size() > 0 else "не было и у зрячего"))
	return out


## Аргумент-число, идущий СРАЗУ за флагом. Если следующего токена нет или это другой
## флаг — возвращается `fallback`.
##
## Зачем так, а не `int(args[i + 1])` напрямую. Прямое приведение дало уже один тихий
## баг: `--loop --log-file X` превращалось в `hunts = 0`, потому что `int("--log-file")`
## равно нулю. Прогон выполнялся с нулём охот, все контрольные суммы сходились на
## пустоте, и отчёт выглядел успешным. Молчаливый ноль хуже падения.
static func _int_arg(args: PackedStringArray, flag: String, fallback: int) -> int:
	for i in args.size():
		if args[i] == flag and i + 1 < args.size():
			var raw := args[i + 1]
			if raw.is_valid_int():
				return int(raw)
	return fallback


## Симулятор баланса. Аргументы: `--battles N`, `--out путь`.
##
## По умолчанию 200 боёв, а не 2000. Замер: 200 боёв — 34 секунды, значит 2000 — около
## шести минут. Такой режим не должен стоять в списке быстрых проверок: полный прогон
## `tools\run_checks.cmd` из-за него превращался в десятиминутное ожидание, что и
## выяснилось, когда починка разбора аргументов впервые дала симулятору реально
## считать. Для глубокого анализа числа зовут явно: `--sim --battles 2000`.
static func sim(args: PackedStringArray) -> String:
	var sim_obj: RefCounted = load("res://core/sim/balance_sim.gd").new()
	var battles := _int_arg(args, "--battles", 200)
	var out_path := "res://sim_report.json"
	for i in args.size():
		if args[i] == "--out" and i + 1 < args.size():
			out_path = args[i + 1]
	sim_obj.run(battles, out_path)
	return "боёв: %d, отчёт: %s" % [battles, out_path]


## Полный цикл «город → заказ → след → бой → итог → город» без графики. Это и
## проверка связки, и способ посмотреть на прогрессию в числах: сколько охот нужно
## до Легенды и сколько монет накопит живой игрок. Аргументы: `--loop N`, `--seed S`.
static func loop(args: PackedStringArray) -> String:
	var hunts := _int_arg(args, "--loop", 10)
	## Сид забега. Нужен, чтобы измерить РАЗБРОС: срок богини (GDD 1.3.1) имеет смысл
	## только вместе с разбросом, иначе одно удачное число выдаётся за норму.
	var run_seed := _int_arg(args, "--seed", 20260922)

	var out: Array[String] = []
	Report.trace(LOOP_TRACE, "вход в loop, hunts=%d, seed=%d" % [hunts, run_seed])
	var script: Resource = load("res://core/sim/loop_sim.gd")
	Report.trace(LOOP_TRACE, "скрипт загружен: %s" % str(script != null))
	if script == null:
		return "скрипт прогона не загрузился"
	var loop_obj: RefCounted = script.new()
	Report.trace(LOOP_TRACE, "объект создан: %s" % str(loop_obj != null))
	loop_obj.run(hunts, out, run_seed)
	Report.trace(LOOP_TRACE, "прогон завершён, строк: %d" % out.size())
	Report.write(LOOP_REPORT, out)
	Report.trace(LOOP_TRACE, "отчёт записан")
	return "охот: %d, строк отчёта: %d" % [hunts, out.size()]
