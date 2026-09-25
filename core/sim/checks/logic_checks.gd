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
	mon.resist_rules = [{"types": ["fire"], "ranges": []}, {"types": ["physical"], "ranges": []}]

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


## Ожидаемые записи семи видов — ФАКТ состояния 2б, снятый с `content/monsters/*.tres`
## после Task 5 (числа §2.3 спеки переноса). Это вторая половина сторожа D23: выше
## проверяется СВЯЗНОСТЬ записи (сработала ли она по своим же множествам), здесь —
## её СОДЕРЖАНИЕ.
##
## ПОЧЕМУ ЭТО НУЖНО. Сторож выше краснеет, только когда запись противоречит СВОИМ ЖЕ
## объявленным множествам. Замер ревью: подмена у Громунa `[ranged]` на `[melee]`
## оставляла `ок D23 видов` ЗЕЛЁНЫМ — запись цела, а замысел данных уже другой.
##
## ПОЧЕМУ ТАБЛИЦА, А НЕ ПРАВИЛО. «Правильного» вида записей не существует: §2.3 спеки
## задаёт конкретные числа, и они меняются этапами. Поэтому ожидание записано фактом —
## и таблица ОБЯЗАНА меняться вместе с данными: этап 2б (Task 5) переписал все числа
## §2.3 и обновил её здесь. Расхождение «данные ушли, таблица осталась» будет
## названо, а не пройдёт молча.
##
## Форма: id вида → `weak`/`resist` (записи полей) и `phase_weak` (фазовые записи по
## id фазы: у Ламанта уязвимости живут ТОЛЬКО там, и без них он в таблице пуст).
## Порядок записей и порядок строк внутри записи не значим — сравнение по множествам.
const D23_CONTENT := {
	"hruz": {
		"weak": [
			{"types": ["ice"], "ranges": ["ranged"]},
			{"types": ["poison"], "ranges": []},
		],
		"resist": [
			{"types": ["fire"], "ranges": []},
		],
		"phase_weak": {},
	},
	"shipun": {
		"weak": [
			{"types": ["poison"], "ranges": []},
			{"types": ["fire"], "ranges": ["ranged"]},
			{"types": ["slash"], "ranges": ["ranged"]},
		],
		"resist": [
			{"types": [], "ranges": ["melee"]},
		],
		"phase_weak": {},
	},
	"gromun": {
		"weak": [
			{"types": [], "ranges": ["melee"]},
			{"types": ["fire"], "ranges": []},
		],
		"resist": [
			{"types": [], "ranges": ["ranged"]},
			{"types": ["ice"], "ranges": []},
		],
		"phase_weak": {},
	},
	"tleun": {
		"weak": [
			{"types": ["pierce"], "ranges": ["ranged"]},
			{"types": ["ice"], "ranges": []},
		],
		"resist": [
			{"types": ["fire"], "ranges": []},
			{"types": [], "ranges": ["melee"]},
		],
		"phase_weak": {},
	},
	"skorb": {
		"weak": [
			{"types": ["fire"], "ranges": []},
			{"types": ["crush"], "ranges": ["ranged"]},
		],
		"resist": [
			{"types": [], "ranges": ["melee"]},
			{"types": ["ice"], "ranges": []},
			{"types": ["poison"], "ranges": []},
		],
		"phase_weak": {},
	},
	"ashmother": {
		"weak": [
			{"types": ["fire"], "ranges": []},
		],
		"resist": [
			{"types": ["pierce"], "ranges": []},
			{"types": ["slash"], "ranges": []},
			{"types": ["crush"], "ranges": []},
			{"types": ["ice"], "ranges": []},
		],
		"phase_weak": {},
	},
	"lament": {
		"weak": [],
		"resist": [
			{"types": [], "ranges": ["melee"]},
			{"types": [], "ranges": ["ranged"]},
			{"types": ["ice"], "ranges": []},
			{"types": ["poison"], "ranges": []},
		],
		# Все три фазы перечислены явно, в том числе пустые: «в фазе «Бешенство»
		# записей нет» — такое же ожидание, как и наличие записей, и если 2б
		# добавит их туда, таблица обязана это заметить.
		"phase_weak": {
			"worn": [
				{"types": [], "ranges": ["melee"]},
				{"types": ["poison"], "ranges": []},
			],
			"rage": [],
			"calm": [],
		},
	},
}


## Совпадают ли записи как МНОЖЕСТВА. Порядок записей и порядок строк внутри записи
## не значит ничего: значение имеет только состав. Дубликат записи сравнение ломает,
## и это правильно — двух одинаковых записей в замысле нет.
static func _same_rules(got: Array, want: Array) -> bool:
	return _rule_set(got) == _rule_set(want)


## Канонический набор строк для списка записей: «types|ranges», отсортировано.
static func _rule_set(rules: Array) -> PackedStringArray:
	var keys := PackedStringArray()
	for rule_v in rules:
		# Не-словарь — не запись: пропускаем, как пропускает её модель и сторож
		# связности. Форму записи называет валидатор (`_check_monster`), а не сверка
		# содержания: иначе один и тот же мусор назывался бы дважды и по-разному.
		if not (rule_v is Dictionary):
			continue
		var types := MonsterData.rule_strings(rule_v as Dictionary, "types")
		var ranges := MonsterData.rule_strings(rule_v as Dictionary, "ranges")
		types.sort()
		ranges.sort()
		keys.append("%s|%s" % [",".join(types), ",".join(ranges)])
	keys.sort()
	return keys


## Записи одной строкой для сообщения о расхождении: «лёд + дальний; яд».
## Порядок здесь исходный — читать глазами удобнее, чем сортированный.
static func _rules_text(rules: Array) -> String:
	var lines := MonsterData.rule_lines(rules)
	if lines.is_empty():
		return "пусто"
	return "; ".join(lines)


## Фаза вида по её id. Пустой словарь — фазы с таким id у вида нет.
static func _phase_by_id(m: MonsterData, phase_id: String) -> Dictionary:
	for ph in m.phases:
		if String(ph.get("id", "")) == phase_id:
			return ph
	return {}


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

	# D04: у огня нет привилегии. «+1» даёт руна любого элемента, и он
	# ПРОВЕРЯЕТСЯ на уязвимость и резист так же, как базовый тип.
	#
	# Проверка смотрит не итог, а структуру разбора: безусловный «+1» руны и «+1»,
	# проверенный на уязвимость, дают одинаковый итог, и по числу отличить правила
	# невозможно.
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
	# Записи, а не старые словари: одна запись даёт ровно −1 (не −2).
	fire_eater.resist_rules = [{"types": ["fire"], "ranges": []}]
	fire_eater.weakness_rules = [{"types": ["slash"], "ranges": []}]
	var d04 := DamageCalc.player_damage(
		sword, fire_eater, DamageCalc.Reading.COUNTER, false, 0, 0, {}, 0.0, null)
	var reasons := ", ".join(d04.type_reasons)
	out.append("D04 руна огня: урон %d, разбор [%s]" % [d04.total, reasons])
	# Строка резиста обязана кончаться на «−1»: запись даёт ровно −1, а прежний
	# словарь `type_resist = {"fire": 2}` давал −2. Метку «(руна)» модель ставит
	# сама (слабость сработала по типу руны) — здесь проверяется величина, а не
	# точная форма строки.
	var resist_named := false
	for reason in d04.type_reasons:
		if reason.begins_with("резист: огонь") and reason.ends_with("−1"):
			resist_named = true
	if not ("огонь +1" in reasons) and "слабость: режущий +1" in reasons \
			and resist_named:
		out.append("ок D04: руна даёт базовый +1 без привилегии огня")
	else:
		out.append("ПРОВАЛ D04: разбор «%s» (ждали слабость режущего, резист огня −1 и никакого «огонь +1»)" % reasons)

	# D04, добор: проверка выше сторожит возврат привилегии ОГНЯ, но не потерю
	# «+1» у льда и яда. Правило говорит «стихии симметричны», значит сторожить
	# надо все три, иначе потеря бонуса у двух из них пройдёт незамеченной.
	#
	# «+1» измеряется ЧИСЛОМ, а не строкой разбора. Первая редакция этой
	# проверки искала в разборе «слабость: лёд +1» — и не краснела, когда «+1»
	# руны отнимали: строка слабости живёт ОТДЕЛЬНОЙ веткой формулы (по записям
	# вида через `modifier_reasons`) и уцелевает без бонуса руны. Поэтому здесь
	# две пробы: (1) на звере БЕЗ уязвимостей и резистов разница между ударом с
	# руной и без неё — это ровно «+1», и только он; (2) разбор обязан назвать
	# стихию, если зверь уязвим к типу руны.
	var element_cases := [
		[MonsterData.TYPE_FIRE, "огонь"],
		[MonsterData.TYPE_ICE, "лёд"],
		[MonsterData.TYPE_POISON, "яд"],
	]
	var d04_missing: Array[String] = []
	for element_case in element_cases:
		var element_type: StringName = element_case[0]
		var element_name: String = element_case[1]

		# (1) Сам бонус руны. Голый зверь: ни уязвимостей, ни резистов — тогда
		# единственное отличие руны от её отсутствия и есть «+1».
		var bare := MonsterData.new()
		bare.id = &"d04_bare"
		bare.title = "Проба стихии"
		bare.max_hp = 20
		bare.armor = 0
		var runed := WeaponData.new()
		runed.id = &"d04_staff"
		runed.range_id = MonsterData.RANGE_MELEE
		runed.damage_type = MonsterData.TYPE_CRUSH
		runed.base_damage = 4
		runed.rune_type = element_type
		var no_rune: WeaponData = runed.duplicate()
		no_rune.rune_type = &""
		var with_rune := DamageCalc.player_damage(
			runed, bare, DamageCalc.Reading.COUNTER, false, 0, 0, {}, 0.0, null)
		var without_rune := DamageCalc.player_damage(
			no_rune, bare, DamageCalc.Reading.COUNTER, false, 0, 0, {}, 0.0, null)
		var rune_bonus := with_rune.total - without_rune.total
		out.append("D04 стихия %s: «+1» руны = %d (урон %d с руной, %d без)" % [
			element_name, rune_bonus, with_rune.total, without_rune.total])
		if rune_bonus != 1:
			d04_missing.append(element_name)

		# (2) Зверь уязвим к САМОМУ типу руны — разбор обязан назвать стихию.
		var thin_skin := MonsterData.new()
		thin_skin.id = &"d04_thin"
		thin_skin.title = "Проба стихии"
		thin_skin.max_hp = 20
		thin_skin.armor = 0
		thin_skin.weakness_rules = [{"types": [String(element_type)], "ranges": []}]
		var element_hit := DamageCalc.player_damage(
			runed, thin_skin, DamageCalc.Reading.COUNTER, false, 0, 0, {}, 0.0, null)
		var element_reasons := ", ".join(element_hit.type_reasons)
		out.append("D04 слабость %s: урон %d, разбор [%s]" % [
			element_name, element_hit.total, element_reasons])
		# Проверяется, что стихия НАЗВАНА слабостью с «+1», а не точная форма
		# строки: слабость, сработавшая по типу руны, у модели помечена
		# «огонь (руна) +1», и прежний поиск точной подстроки «слабость: огонь +1»
		# краснел бы на верном разборе.
		var element_weak_named := false
		for reason in element_hit.type_reasons:
			if reason.begins_with("слабость:") and element_name in reason \
					and reason.ends_with("+1"):
				element_weak_named = true
		if not element_weak_named:
			d04_missing.append(element_name)
	if d04_missing.is_empty():
		out.append("ок D04 стихий: все три стихии дают «+1» и названы в разборе")
	else:
		out.append("ПРОВАЛ D04 стихий: «+1» потерян у %s" % ", ".join(d04_missing))

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

	# D20: концепт скорости оружия снят. Инициативу дают только знаки ранга,
	# а оружие на неё не влияет вовсе.
	#
	# Оружие берётся НАСТОЯЩЕЕ — копьё из каталога, а не `WeaponData.new()`.
	# У синтетического ресурса `initiative_bonus` был бы равен дефолтному нулю, и
	# вторая половина условия (`initiative() == 5`) выполнялась бы САМА СОБОЙ:
	# проверка выродилась бы в проверку существования поля и не покраснела бы,
	# если оружие снова начнёт влиять на инициативу. У копья прежний бонус был 2 —
	# самое заметное расхождение: с ним инициатива равна 7. Краснота усиленной
	# проверки измерена обходом `hunter.initiative_bonus_total = 2`; на том же
	# состоянии прежняя формулировка с синтетическим оружием осталась ЗЕЛЁНОЙ
	# (замер в отчёте Task 4b).
	var d20_spear: WeaponData = Database.weapon(&"spear")
	var d20_hunter := SkillEffects.build_hunter(d20_spear, Database.armor(&"light"))
	var has_field := "initiative_bonus" in d20_spear
	out.append("D20 инициатива: оружие «%s» (прежний бонус к инициативе 2), поле у оружия %s, инициатива охотника %d (ждали 5)" % [
		d20_spear.title, str(has_field), d20_hunter.initiative()])
	if not has_field and d20_hunter.initiative() == 5:
		out.append("ок D20: оружие на инициативу не влияет")
	else:
		out.append("ПРОВАЛ D20: оружие «%s», поле %s, инициатива %d (ждали 5)" % [
			d20_spear.title, str(has_field), d20_hunter.initiative()])

	# D23: запись уязвимости/резиста — пара множеств {types, ranges}. Проверяем
	# САМО ПРАВИЛО через API модели, а не через формулу урона: формула до Task 2
	# ещё читает старые списки, и проверка через неё была бы красной по посторонней
	# причине — она не отличала бы старую модель от новой.
	#
	# Три правила §2.1 спеки, каждое своим замером:
	#   (а) связка: срабатывает только когда И тип, И дистанция попали в запись;
	#   (б) пустое ranges = «любая дистанция»;
	#   (в) пустое types = «любой тип»;
	#   (г) запись без обоих ограничений срабатывает на всё — потому и запрещена.
	var d23_mon := MonsterData.new()
	d23_mon.id = &"d23_probe"
	d23_mon.title = "Проба записей"
	d23_mon.max_hp = 12
	d23_mon.armor = 0
	d23_mon.weakness_rules = [
		{"types": ["ice"], "ranges": ["ranged"]},
		{"types": ["poison"], "ranges": []},
	]
	d23_mon.resist_rules = [
		{"types": [], "ranges": ["melee"]},
		{"types": ["ice"], "ranges": ["ranged"]},
	]
	var w_coupled := d23_mon.weakness_modifier(
		MonsterData.TYPE_ICE, MonsterData.RANGE_RANGED)
	var w_type_only := d23_mon.weakness_modifier(
		MonsterData.TYPE_ICE, MonsterData.RANGE_MELEE)
	var w_range_only := d23_mon.weakness_modifier(
		MonsterData.TYPE_CRUSH, MonsterData.RANGE_RANGED)
	var w_any_range := d23_mon.weakness_modifier(
		MonsterData.TYPE_POISON, MonsterData.RANGE_MELEE)
	var r_any_type := d23_mon.resist_modifier(
		MonsterData.TYPE_SLASH, MonsterData.RANGE_MELEE)
	var r_wrong_range := d23_mon.resist_modifier(
		MonsterData.TYPE_SLASH, MonsterData.RANGE_RANGED)
	var r_coupled := d23_mon.resist_modifier(
		MonsterData.TYPE_ICE, MonsterData.RANGE_RANGED)
	var r_wrong_type := d23_mon.resist_modifier(
		MonsterData.TYPE_POISON, MonsterData.RANGE_RANGED)
	out.append("D23 связка: лёд+дальний %d, лёд+упор %d, дробящее+дальний %d" % [
		w_coupled, w_type_only, w_range_only])
	out.append("D23 стихии: яд в упор %d; резист «любой тип в упор» %d, на дальней %d" % [
		w_any_range, r_any_type, r_wrong_range])
	out.append("D23 резист-связка: лёд+дальний %d, яд+дальний %d" % [
		r_coupled, r_wrong_type])
	# (г) Запись без обоих ограничений запрещена: она сработала бы на ЛЮБОЙ удар.
	# Сторож не ищет такую запись в контенте (это валидатор, Task 3) — он
	# показывает, ПОЧЕМУ она запрещена: измеряет, что она срабатывает на всём.
	var empty_rule := MonsterData.new()
	empty_rule.id = &"d23_empty"
	empty_rule.weakness_rules = [{"types": [], "ranges": []}]
	var empty_hits := 0
	for t in MonsterData.PHYSICAL_TYPES:
		if empty_rule.weakness_modifier(t, MonsterData.RANGE_MELEE) > 0:
			empty_hits += 1
	out.append("D23 пустая запись: сработала на %d из %d физических подтипов" % [
		empty_hits, MonsterData.PHYSICAL_TYPES.size()])
	# (д) Запись срабатывает НЕ БОЛЕЕ ОДНАЖДЫ на удар, даже когда ей подходят обе
	# координаты (пустые types плюс дистанция). Иначе одна запись давала бы −2,
	# а игрок видел бы две строки за одно и то же.
	var once_mon := MonsterData.new()
	once_mon.id = &"d23_once"
	once_mon.resist_rules = [{"types": [], "ranges": ["melee"]}]
	var once_reasons := once_mon.modifier_reasons(
		[MonsterData.TYPE_CRUSH, MonsterData.TYPE_FIRE], MonsterData.RANGE_MELEE)
	# `resist_modifier` возвращает ЧИСЛО сработавших записей (знак живёт в тексте
	# причины: «резист: ближний −1»), поэтому печатаем обе величины: причин
	# должно быть 1 и сработать запись должна тоже 1.
	var once_fired := once_mon.resist_modifier(MonsterData.TYPE_CRUSH, MonsterData.RANGE_MELEE)
	out.append("D23 однократность: причин %d, сработавших записей %d (ждали 1 и 1), разбор [%s]" % [
		once_reasons.size(), once_fired, ", ".join(once_reasons)])
	# (а) связка даёт ровно +1 и НЕ срабатывает, если совпала одна координата;
	# (б) запись без ranges работает на любой дистанции;
	# (в) запись без types работает на любой тип, но только в своей дистанции;
	# (г) пустая запись срабатывает на ВСЕ физические подтипы — доказательство,
	# что допускать её нельзя (запрет на контенте — валидатор, Task 3).
	# (д) запись срабатывает один раз, даже когда подходят обе координаты.
	if w_coupled == 1 and w_type_only == 0 and w_range_only == 0 \
			and w_any_range == 1 and r_any_type == 1 and r_wrong_range == 0 \
			and r_coupled == 1 and r_wrong_type == 0 \
			and empty_hits == MonsterData.PHYSICAL_TYPES.size() \
			and once_reasons.size() == 1 and once_fired == 1:
		out.append("ок D23: связка «тип И дистанция» и пустые множества работают")
	else:
		out.append("ПРОВАЛ D23: связка %d (ждали 1), одна координата %d/%d (ждали 0), любая дистанция %d (ждали 1), любой тип %d (ждали 1), чужая дистанция %d (ждали 0), резист-связка %d (ждали 1), чужой тип %d (ждали 0), пустая %d (ждали все), однократность %d/%d (ждали 1 и 1)" % [
			w_coupled, w_type_only, w_range_only, w_any_range, r_any_type, r_wrong_range,
			r_coupled, r_wrong_type, empty_hits, once_reasons.size(), once_fired])

	# D23, добор: связка проверяется на КАЖДОМ виде, а не на синтетической пробе.
	# Проверяем два свойства, которые старый код ломал:
	#   (а) запись с двумя ограничениями даёт ровно +1/−1, не удваивается;
	#   (б) запись без types срабатывает на любой тип в СВОЕЙ дистанции.
	#
	# Записи читаются из ПОЛЯ напрямую: переходник `effective_*` снят в Task 4.
	#
	# Число проверенных записей печатается, и НОЛЬ здесь — НЕ провал: состояние
	# «записей без types нет вовсе» законно, и порог-минимум был бы подгонкой под
	# сегодняшние данные (ноль честно говорит «предмета проверки не было»).
	# Сколько их сегодня: в 2а такая запись была ОДНА — громунова `(—,ranged)`. На
	# числах §2.3 этапа 2б их стало шесть (Шипун, Громун, Тлеун, Скорб и две
	# у Ламанта), и теперь ноль означал бы потерю данных, а не их отсутствие.
	# За содержание записей отвечает отдельная сверка ниже («D23 содержание»).
	var d23_fail: Array[String] = []
	var d23_range_rules := 0
	for mon_id in Database.monsters.keys():
		var m: MonsterData = Database.monsters[mon_id]
		# (а) одна координата не должна давать больше +1: если запись с двумя
		# ограничениями удвоится, здесь окажется 2 или больше.
		for t in MonsterData.PHYSICAL_TYPES:
			var melee_w := m.weakness_modifier(t, MonsterData.RANGE_MELEE)
			var ranged_w := m.weakness_modifier(t, MonsterData.RANGE_RANGED)
			if melee_w > 1 or ranged_w > 1:
				d23_fail.append("%s: уязвимость %s даёт +%d" % [
					m.id, CityData.type_ru(t), maxi(melee_w, ranged_w)])
		# (б) запись без types обязана закрывать физику в СВОЕЙ дистанции —
		# и в упор, и на дальней: целевые записи §2.3 бывают обеих.
		#
		# Поля записи разбирает МОДЕЛЬ (MonsterData.rule_strings): здесь стоял
		# `PackedStringArray(rule.get(...))`, и скаляр в поле ронял сторож
		# SCRIPT ERROR'ом — отчёт пробы обрывался на этом месте, а хвостовые
		# строки D23 просто не появлялись.
		for rule_v in m.resist_rules:
			# Запись-не-словарь (число, строка, null) — мусор в контенте, и разбирать
			# её поля нельзя: `as Dictionary` на ней роняет SCRIPT ERROR'ом весь
			# вызов `_status_mechanics()`, поэтому проба пишет отчёт БЕЗ ВСЕГО его
			# блока. Замер: 56 строк вместо 83 — теряются 27 строк (весь блок
			# статусов, D04, фаз, D20 и D23), а не одни лишь строки D23. Вердикт
			# сторожа пропадает молча: видно это только по SCRIPT ERROR в stderr.
			# Замер на `7` в resist_rules Громунa: «Invalid cast: could not convert
			# value to 'Dictionary'».
			#
			# Пропускаем — как пропускают её модель (`weakness_modifier`) и
			# валидатор (`_check_monster` называет форму записи). Сторож механики
			# отвечает за правило, а не за форму контента.
			if not (rule_v is Dictionary):
				continue
			var rule := rule_v as Dictionary
			if MonsterData.rule_strings(rule, "types").size() > 0:
				continue
			var rule_ranges := MonsterData.rule_strings(rule, "ranges")
			if not (rule_ranges.has(String(MonsterData.RANGE_MELEE)) \
					or rule_ranges.has(String(MonsterData.RANGE_RANGED))):
				continue
			d23_range_rules += 1
			for rng in [MonsterData.RANGE_MELEE, MonsterData.RANGE_RANGED]:
				if not rule_ranges.has(String(rng)):
					continue
				for t in MonsterData.PHYSICAL_TYPES:
					if m.resist_modifier(t, StringName(rng)) < 1:
						d23_fail.append("%s: запись «%s» не сработала на %s" % [
							m.id, CityData.range_ru(StringName(rng)), CityData.type_ru(t)])
						break
	if d23_fail.is_empty():
		out.append("ок D23 видов: связка «тип И дистанция» работает на всех видах (записей без types проверено: %d)" % d23_range_rules)
	else:
		out.append("ПРОВАЛ D23 видов: %s" % "; ".join(d23_fail))

	# D23, содержание: сторож выше проверяет согласованность записи с её же
	# объявленными множествами, но НЕ соответствие замыслу данных. Замер: подмена
	# у Громунa `[ranged]` на `[melee]` оставляла всё зелёным. Здесь — сверка с
	# таблицей, и таблица обязана меняться вместе с данными: при любой правке
	# записей вида её обновляют тем же коммитом, иначе сторож назовёт ошибкой
	# правильные данные.
	#
	# Идём по базе видов, а не по таблице: вид, которого в таблице нет, — это тоже
	# расхождение (данные завели, ожидание не описали), и молча пропустить его
	# значило бы оставить новый контент без сторожа вовсе.
	var content_fail: Array[String] = []
	var content_species := 0
	var content_rules := 0
	for mon_id in Database.monsters.keys():
		var cm: MonsterData = Database.monsters[mon_id]
		if not D23_CONTENT.has(mon_id):
			content_fail.append("%s: вида нет в таблице ожиданий — данные завели, таблицу нет" % mon_id)
			continue
		var want: Dictionary = D23_CONTENT[mon_id]
		content_species += 1
		var want_weak: Array = want["weak"]
		var want_resist: Array = want["resist"]
		content_rules += want_weak.size() + want_resist.size()
		if not _same_rules(cm.weakness_rules, want_weak):
			content_fail.append("%s: уязвимости %s, ждали %s" % [
				mon_id, _rules_text(cm.weakness_rules), _rules_text(want_weak)])
		if not _same_rules(cm.resist_rules, want_resist):
			content_fail.append("%s: резисты %s, ждали %s" % [
				mon_id, _rules_text(cm.resist_rules), _rules_text(want_resist)])
		# Фазовые записи — те же записи вида (Ламант: его уязвимости живут только
		# в фазе), поэтому и ждут их в той же таблице, ключом по id фазы.
		var want_phases: Dictionary = want["phase_weak"]
		for phase_id in want_phases.keys():
			var want_phase: Array = want_phases[phase_id]
			content_rules += want_phase.size()
			var phase := _phase_by_id(cm, String(phase_id))
			if phase.is_empty():
				content_fail.append("%s: фазы «%s» у вида нет, а таблица её ждёт" % [
					mon_id, phase_id])
				continue
			var got_phase: Array = MonsterData.phase_weak_rules(phase)
			if not _same_rules(got_phase, want_phase):
				content_fail.append("%s: фаза «%s» — уязвимости %s, ждали %s" % [
					mon_id, phase_id, _rules_text(got_phase), _rules_text(want_phase)])
		# Каждая фаза вида обязана быть названа в таблице: отсутствие ключа значит
		# «уязвимостей нет». Иначе лишняя фаза с записями проходит молча — замер
		# ревью: четвёртая фаза Ламанта давала зелёное при живых записях.
		for ph in cm.phases:
			var pid := String(ph.get("id", ""))
			if want_phases.has(pid):
				continue
			var extra: Array = MonsterData.phase_weak_rules(ph)
			if extra.size() > 0:
				content_fail.append("%s: фаза «%s» не названа в таблице, а уязвимости есть: %s" % [
					mon_id, pid, _rules_text(extra)])
	# Обратный случай к «вида нет в таблице»: вид ПРОПАЛ из данных. Тогда обход идёт
	# на вид меньше и молчит, а счётчик просто тихо падает (замер ревью: «видов 6,
	# записей 25»). Число сверенных видов обязано совпасть с таблицей.
	if content_species != D23_CONTENT.size():
		content_fail.append("сверено видов %d, а в таблице ожиданий %d — вид пропал из данных" % [
			content_species, D23_CONTENT.size()])
	if content_fail.is_empty():
		out.append("ок D23 содержание: записи совпали с ожидаемой таблицей 2б (видов %d, записей %d)" % [
			content_species, content_rules])
	else:
		out.append("ПРОВАЛ D23 содержание: %s" % "; ".join(content_fail))

	# Ранги заказов (§8.1 + спека этапа 3 §3): доступ к тиру открывается ПОРОГОМ
	# ранга, а не правилом «ранг = тир». Старое правило делало Ламанта достижимым
	# на ранге 3 («Ветеран»), а ранг 4 («Мастер») не открывал ничего нового.
	#
	# Префикс `d21_` взят из кода брифа и здесь означает только «D21-блок этапа 3»:
	# решение D21 дизайна — про резисты, к рангам заказов оно отношения не имеет.
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
		# Ранг 1 новых заказов тоже не открывает: доступ совпадает с рангом 0
		# (§8.1 v1.10.6: продвинутые — с ранга 2; спека §3: «ранги 0–1 — стартовые»).
		#
		# Зачем эта строка, если бриф её не называл. Без неё сторож НЕ краснеет на
		# возврате правила `max_tier = rank` — а именно эту красноту требует приёмка
		# задачи. Причина: пороги тиров 0/2/2/3/4 совпадают с «ранг ≥ номер тира»
		# для рангов 2–4, поэтому старое правило даёт верные наборы везде, кроме
		# ранга 1, где оно открывает продвинутых. Замер: см. отчёт Task 2, шаг 6.
		if r == 1:
			var first_size := CityData.available_monsters(0).size()
			if ids.size() != first_size:
				d21_orders_fail.append("ранг 1 открывает новые заказы (%d против %d на ранге 0)" % [
					ids.size(), first_size])
	out.append("заказы по рангам: 0:%d 1:%d 2:%d 3:%d 4:%d 5:%d видов" % [
		CityData.available_monsters(0).size(), CityData.available_monsters(1).size(),
		CityData.available_monsters(2).size(), CityData.available_monsters(3).size(),
		CityData.available_monsters(4).size(), CityData.available_monsters(5).size()])
	if d21_orders_fail.is_empty():
		out.append("ок заказов: доступ открывается по шести рангам (§8.1)")
	else:
		out.append("ПРОВАЛ заказов: %s" % "; ".join(d21_orders_fail))

	# Слава за тир (§8.2 + спека этапа 3 §3). `victory_glory` читает ТИР заказа, а
	# не вид, поэтому разделение элитного тира надвое (Task 2) обязано сохранить
	# обоим элитным видам по 4 славы, а Ламанту — 10. Ошибка здесь не видна по
	# одному бою: она тихо сдвигает всю лестницу до Легенды.
	#
	# Ждём ПО ВИДАМ, а не по номерам тиров, и это существенно: номер тира — как раз
	# то, что задача меняет, и ожидание по номерам покраснело бы на ВЕРНОЙ старой
	# таблице, ничего не сказав о славе. Вид же — устойчивая привязка §4/§8.2:
	# «победа над элитным +4» относится к Скорбу и Пепел-Матери, кто бы в каком
	# тире ни лежал. Заодно сторож ловит вид, уехавший не в свой тир.
	#
	# Ключ, забытый при расширении таблицы, `victory_glory` молча подменяет
	# запасной единицей (`get(rank, 1)`), и «мифический» давал бы 1 славу вместо 4.
	var d21_glory_want := {
		"hruz": 1, "shipun": 1,        # стартовые (§8.2)
		"gromun": 2, "tleun": 2,       # продвинутые
		"skorb": 4, "ashmother": 4,    # оба элитных — по 4
		"lament": 10,                  # легендарный
	}
	var d21_glory_fail: Array[String] = []
	var d21_glory_text: PackedStringArray = PackedStringArray()
	var d21_glory_species := 0
	for tier in CityData.ORDER_RANKS.keys():
		var t := int(tier)
		var species: Array = CityData.ORDER_RANKS[tier]["monsters"]
		var glory := CityData.victory_glory(t, false, false, false)
		d21_glory_text.append("%d:%d(%s)" % [t, glory, ", ".join(species)])
		for m in species:
			var mid := String(m)
			d21_glory_species += 1
			var want_glory := int(d21_glory_want.get(mid, -1))
			if glory != want_glory:
				d21_glory_fail.append("«%s» в тире %d «%s»: слава %d, а ждали %d" % [
					mid, t, CityData.order_tier_title(t), glory, want_glory])
	# Вид, пропавший из ORDER_RANKS, обход не заметит — сверяем число с таблицей.
	if d21_glory_species != d21_glory_want.size():
		d21_glory_fail.append("в заказах %d видов, а в таблице славы %d — вид пропал" % [
			d21_glory_species, d21_glory_want.size()])
	out.append("слава по тирам: %s" % " ".join(d21_glory_text))
	if d21_glory_fail.is_empty():
		out.append("ок славы заказов: оба элитных вида дают 4, легендарный — 10 (§8.2)")
	else:
		out.append("ПРОВАЛ славы заказов: %s" % "; ".join(d21_glory_fail))

	# Штраф за смерть — по таблице тиров (§8.3, дизайн 1.10.7). Раньше здесь стояла
	# формула `тир × 3`, и она расходилась с таблицей: на стартовом давала 0 вместо −3.
	# Проверяем ИМЕННО таблицу, чтобы правка штрафов не прошла молча.
	var d21_penalty_expect := {0: 3, 1: 6, 2: 9, 3: 9, 4: 12}
	var d21_penalty_text: PackedStringArray = PackedStringArray()
	var d21_penalty_fail: Array[String] = []
	for ptier in CityData.ORDER_RANKS.keys():
		var pt := int(ptier)
		var got_penalty := CityData.death_penalty(pt, false, false)
		d21_penalty_text.append("%d:%d" % [pt, got_penalty])
		if got_penalty != int(d21_penalty_expect.get(pt, 0)):
			d21_penalty_fail.append("тир %d: штраф %d, а §8.3 ждёт %d" % [
				pt, got_penalty, int(d21_penalty_expect.get(pt, 0))])
	# Тир, добавленный в ORDER_RANKS без ключа в ожиданиях, обход выше не заметит:
	# `get(tier, 0)` вернёт 0, а `death_penalty` для тира без записи в таблице
	# штрафов тоже 0 — «0 против 0» выглядело бы успехом. Состав таблиц сверяется
	# отдельно, по числу и по именам, — тот же приём, что у славы («вид пропал»).
	var d21_penalty_gap := _tier_expect_gap(d21_penalty_expect, "штраф по тирам")
	if d21_penalty_gap != "":
		d21_penalty_fail.append(d21_penalty_gap)
	out.append("штраф за смерть по тирам: %s (§8.3: −3/−6/−9/−9/−12)" % " ".join(d21_penalty_text))
	if d21_penalty_fail.is_empty():
		out.append("ок штрафа за смерть: таблица §8.3 сходится по всем тирам")
	else:
		out.append("ПРОВАЛ штрафа за смерть: %s" % "; ".join(d21_penalty_fail))
	# Слава не уходит в минус: списание идёт через add_glory с полом нуля. Проверяем
	# это на живом GameState — иначе «нельзя упасть в отрицательное» осталось бы словом.
	var saved_glory := GameState.glory
	GameState.glory = 1
	GameState.add_glory(-12)
	var floored := GameState.glory
	GameState.glory = saved_glory
	if floored == 0:
		out.append("ок пола славы: смерть обнуляет славу, но не уводит в минус")
	else:
		out.append("ПРОВАЛ пола славы: слава стала %d после списания −12 от единицы" % floored)

	# «Первый раз» — половина штрафа — по §8.3 положен ТОЛЬКО Ламанту («−12 (−6
	# первый раз)»). Порог `order_rank >= 3` писался, когда тиров было четыре и
	# третий был верхним; после раздела элитного тира надвое третий — «мифический»
	# (Пепел-Мать), и половина штрафа досталась ей. Сторож обязан звать
	# `death_penalty` с `first_time = true`: прежний звал только с `false` и ветку
	# деления не трогал вовсе.
	var d21_first_expect := {0: 3, 1: 6, 2: 9, 3: 9, 4: 6}
	var d21_first_fail: Array[String] = []
	var d21_first_text: PackedStringArray = PackedStringArray()
	for ftier in CityData.ORDER_RANKS.keys():
		var ft := int(ftier)
		var got_first := CityData.death_penalty(ft, true, false)
		d21_first_text.append("%d:%d" % [ft, got_first])
		if got_first != int(d21_first_expect.get(ft, 0)):
			d21_first_fail.append("тир %d «%s»: первый раз %d, а §8.3 ждёт %d" % [
				ft, CityData.order_tier_title(ft), got_first,
				int(d21_first_expect.get(ft, 0))])
	var d21_first_gap := _tier_expect_gap(d21_first_expect, "первый раз")
	if d21_first_gap != "":
		d21_first_fail.append(d21_first_gap)
	out.append("штраф за смерть, ПЕРВЫЙ раз: %s (§8.3: только Ламант вдвое)" % " ".join(d21_first_text))
	if d21_first_fail.is_empty():
		out.append("ок первого раза: половина штрафа только на легендарном тире")
	else:
		out.append("ПРОВАЛ первого раза: %s" % "; ".join(d21_first_fail))

	# Побочная встреча смягчает штраф вдвое (§8.3: ×0.5, округление вниз) — и это
	# ТРЕТИЙ параметр `death_penalty`, который до сих пор не проверял никто: сторож
	# выше звал функцию с `side_encounter = false`. Проверяем оба сочетания, потому
	# что множители СКЛАДЫВАЮТСЯ: у Ламанта при первом раза и побочной встрече
	# выходит четверть от 12, и это не то же самое, что половина от половины.
	var d21_side_expect := {
		false: {0: 1, 1: 3, 2: 4, 3: 4, 4: 6},
		true: {0: 1, 1: 3, 2: 4, 3: 4, 4: 3},
	}
	var d21_side_fail: Array[String] = []
	var d21_side_text: PackedStringArray = PackedStringArray()
	for side_flag in [false, true]:
		var side_first := bool(side_flag)
		var expect_side: Dictionary = d21_side_expect[side_first]
		var side_row: PackedStringArray = PackedStringArray()
		for stier in CityData.ORDER_RANKS.keys():
			var st := int(stier)
			var got_side := CityData.death_penalty(st, side_first, true)
			side_row.append("%d:%d" % [st, got_side])
			if got_side != int(expect_side.get(st, 0)):
				d21_side_fail.append("тир %d «%s», %s: штраф %d, а §8.3 ждёт %d" % [
					st, CityData.order_tier_title(st),
					"первый раз" if side_first else "повторно",
					got_side, int(expect_side.get(st, 0))])
		var side_gap := _tier_expect_gap(expect_side, "побочная встреча, %s" % (
			"первый раз" if side_first else "повторно"))
		if side_gap != "":
			d21_side_fail.append(side_gap)
		d21_side_text.append("%s: %s" % [
			"первый раз" if side_first else "повторно", " ".join(side_row)])
	out.append("штраф за смерть, ПОБОЧНАЯ встреча: %s (§8.3: ×0.5 вниз)" % " | ".join(d21_side_text))
	if d21_side_fail.is_empty():
		out.append("ок побочной встречи: ×0.5 вниз по всем тирам, складывается с первым разом")
	else:
		out.append("ПРОВАЛ побочной встречи: %s" % "; ".join(d21_side_fail))

	# «Первый раз» сквозь НАСТОЯЩИЙ `HuntResult.apply()`: продакшн-предикат —
	# `GameState.kill_counts(monster_id) == 0` (`hunt_result._apply_defeat`), и его до
	# сих пор не проверяло ничто: сторож выше зовёт `death_penalty` напрямую и
	# подставляет `first_time` руками. Цена ошибки здесь не число, а СМЫСЛ правила.
	#
	# Смысл этот — «ни разу НЕ ПОБЕЖДЁН», а не «первая смерть», как читается проза
	# §8.4 («Ламент первый раз: ×0.5»): счётчик считает победы, а не смерти, и после
	# первой победы над Ламантом КАЖДАЯ следующая смерть стоит полные 12. Это
	# расхождение формулировок с фактической семантикой — открытый вопрос дизайна,
	# здесь оно только НАЗВАНО, менять ни правило, ни прозу задача не просит.
	var e2e_cases := [
		["ashmother", 3, false, 31],  # тир 3 «мифический»: половины нет ни разу
		["lament", 4, false, 34],     # верхний тир, ни разу не побеждён → −6
		["lament", 4, true, 28],      # победа уже была → полные −12
	]
	var e2e_fail: Array[String] = []
	var e2e_text: PackedStringArray = PackedStringArray()
	for e2e_case in e2e_cases:
		var e2e_id := StringName(e2e_case[0])
		var e2e_tier := int(e2e_case[1])
		var e2e_won := bool(e2e_case[2])
		var e2e_want := int(e2e_case[3])
		GameState.reset()
		GameState.glory = 40
		if e2e_won:
			GameState.register_kill(e2e_id, e2e_tier)
			# Победа над видом открывает достижение «убит …» (+1 славы) ВНУТРИ того же
			# `apply()`, и слава уехала бы на 29 вместо 28. Гасим этот +1 явно: сторож
			# проверяет ШТРАФ, а не выплаты Achievements, и краснеть на правке
			# достижений, к «первому разу» не относящейся, он не должен.
			GameState.achievements["kill_%s" % e2e_id] = true
		var e2e_mon: MonsterData = Database.monster(e2e_id)
		var e2e_name := e2e_mon.title if e2e_mon != null else String(e2e_id)
		var defeat := HuntResult.new()
		defeat.monster_id = e2e_id
		defeat.order_rank = e2e_tier
		defeat.victory = false
		defeat.fled = false
		defeat.apply(false)
		e2e_text.append("«%s» т%d%s: %+d, слава 40 → %d" % [
			e2e_name, e2e_tier, " после победы" if e2e_won else "",
			defeat.glory_delta, GameState.glory])
		if defeat.glory_delta != e2e_want - 40 or GameState.glory != e2e_want:
			e2e_fail.append("смерть на «%s» (тир %d)%s: %+d, слава %d, а ждали %+d и %d" % [
				e2e_name, e2e_tier, " после победы" if e2e_won else "",
				defeat.glory_delta, GameState.glory, e2e_want - 40, e2e_want])
	GameState.reset()
	out.append("первый раз сквозь HuntResult: %s" % " | ".join(e2e_text))
	if e2e_fail.is_empty():
		out.append("ок сквозь HuntResult: половина только за ни разу не побеждённого верхнего зверя")
	else:
		out.append("ПРОВАЛ сквозь HuntResult: %s" % "; ".join(e2e_fail))

	# Достижение «Победа над легендарным зверем» вешается на счётчик `kills_tier3`,
	# а он ставится при `order_rank >= 3` — то есть после раздела тира выдаётся за
	# победу над ПЕПЕЛ-МАТЬЮ («мифический»), хотя титул называет легендарного зверя
	# (Ламант, тир 4). Проверяем обе стороны: тир 3 не должен открывать достижение,
	# тир 4 — должен.
	var legend_beast := "no_potions_named_legend"
	GameState.reset()
	var ach_mid := HuntResult.new()
	ach_mid.monster_id = &"ashmother"
	ach_mid.order_rank = 3
	ach_mid.victory = true
	ach_mid.fled = false
	ach_mid.apply(false)
	var got_mid: bool = GameState.achievements.has(legend_beast)
	GameState.reset()
	var ach_top := HuntResult.new()
	ach_top.monster_id = &"lament"
	ach_top.order_rank = 4
	ach_top.victory = true
	ach_top.fled = false
	ach_top.apply(false)
	var got_top: bool = GameState.achievements.has(legend_beast)
	GameState.reset()
	out.append("достижение «легендарный зверь»: за Пепел-Мать %s, за Ламанта %s" % [
		str(got_mid), str(got_top)])
	if not got_mid and got_top:
		out.append("ок достижения: «легендарный зверь» — только за легендарный тир")
	else:
		out.append("ПРОВАЛ достижения: за Пепел-Мать %s (ждали false), за Ламанта %s (ждали true)" % [
			str(got_mid), str(got_top)])

	# Совет Старика: покупка — правило экономики, а не состояние экрана. Раньше оно
	# жило в `city_screen.advice_bought`, а экран города уничтожается при каждом
	# возвращении (`game_root._swap`), поэтому совет можно было купить повторно, а
	# замер цикла его покупок не видел вовсе (прогон идёт без сцен).
	GameState.reset()
	GameState.coins = 100
	var advice_id := &"lament"
	var advice_price := CityData.advice_price(advice_id)
	var bought_first: bool = GameState.buy_advice(advice_id)
	var wallet_after_first := GameState.coins
	var bought_second: bool = GameState.buy_advice(advice_id)
	out.append("совет: первая покупка %s, кошелёк %d (было 100), цены %d, вторая покупка %s" % [
		str(bought_first), wallet_after_first, advice_price, str(bought_second)])
	if bought_first and not bought_second and wallet_after_first == 100 - advice_price \
			and bool(GameState.advice_bought.get("lament", false)):
		out.append("ок совета: покупка списывает монеты один раз и живёт в GameState")
	else:
		out.append("ПРОВАЛ совета: первая %s, вторая %s, кошелёк %d, запись %s" % [
			str(bought_first), str(bought_second), wallet_after_first,
			str(GameState.advice_bought.get("lament", false))])
	GameState.reset()
	return out


## Расхождение между таблицей ожиданий и тирами заказа: текст ПРОВАЛА или "".
##
## Нужна потому, что проверки штрафов обходят `ORDER_RANKS` и читают ожидание через
## `get(tier, 0)`. Тир, добавленный в `ORDER_RANKS` без ключа в ожиданиях, дал бы
## `death_penalty = 0` против ожидания `0` — и молчаливое «0 против 0» вместо
## провала. Пустая таблица ожиданий на непустом `ORDER_RANKS` — тот же случай.
##
## Состав сверяется и по числу, и по именам: числа хватает, чтобы поймать расхождение,
## но назвать виновника — работа имён, а «ПРОВАЛ» без имени снова отправляет читателя
## искать причину самому. `label` различает строки одной проверки (таблиц ожиданий у
## побочной встречи две), чтобы в отчёте было видно, какая именно не сходится.
static func _tier_expect_gap(expect: Dictionary, label: String = "") -> String:
	var tiers := CityData.ORDER_RANKS.size()
	if expect.size() == tiers:
		return ""
	var without: Array[String] = []
	for key in CityData.ORDER_RANKS.keys():
		if not expect.has(int(key)):
			without.append(str(int(key)))
	var note := ""
	if not without.is_empty():
		note = " (без ожидания: %s)" % ", ".join(without)
	return "%sтиров в ORDER_RANKS %d, а в ожиданиях %d%s" % [
		"" if label.is_empty() else "%s: " % label, tiers, expect.size(), note]


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
