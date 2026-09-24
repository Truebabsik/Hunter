extends RefCounted
class_name BalanceSim
## Монте-Карло проверка баланса. Запуск:
##   Godot_..._console.exe --headless --path F:\WORK\hunter -- --sim --battles 2000
##
## Зачем: GDD 12.11 проверял баланс руками и трижды ошибся в арифметике. Здесь
## числа считаются по настоящим формулам, с настоящим выбором сценариев и с
## настоящими промахами — то есть ровно с тем, чего в ручных таблицах не было.
##
## Главная метрика игры — не «сколько урона», а «сколько промахов позволяет
## выжить». Поэтому точность чтения перебирается отдельной осью.

## Сборки: ССЫЛКИ на данные игры, а не вписанные числа.
##
## Раньше здесь лежали урон, тип, дальность и поглощение руками, и `_make_tool`
## собирал оружие с нуля. Числа совпадали с .tres, поэтому расхождение не бросалось
## в глаза, — а производные разошлись сразу:
##   * «поглощение 6» у мастерской сборки при HunterState.ABSORPTION_CAP = 3:
##     в игре столько недостижимо, и сборка выглядела вдвое живучее, чем есть;
##   * знак штрафа инициативы: здесь стояло +1, а heavy.tres хранит −1;
##   * крит вписывался руками (0.10) мимо SkillEffects.crit_chance();
##   * «Второе дыхание» и «Феникс» не включались вовсе, хотя отчёт печатает их
##     частоты — они и были нулями во всех сборках.
##
## Теперь сборка называет оружие, броню, руну и набор навыков, а всё остальное
## считает игра: оружие берётся из Database, эффекты — из SkillEffects.
##
## ВАЖНО про природу этих сборок: это СПРОЕКТИРОВАННЫЕ состояния (мастерская
## сборка владеет навыками, которых игрок в прогоне цикла не покупает), поэтому
## они показывают потолок сборки, а не достижимую прогрессию. Достижимую меряет
## `--loop`.
const LOADOUTS := {
	"лук_физ": {
		"title": "Лук (дальний, колющий), лёгкая броня",
		"weapon": &"bow",
		"armor": &"light",
	},
	"лук_лёд": {
		"title": "Лук + лёд (дальний, лёд), лёгкая броня",
		"weapon": &"bow",
		"armor": &"light",
		"rune": &"ice",
	},
	"клинок_физ": {
		"title": "Клинок (ближний, режущий), лёгкая броня",
		"weapon": &"blade",
		"armor": &"light",
	},
	"клинок_яд": {
		"title": "Клинок + яд (ближний, яд), лёгкая броня",
		"weapon": &"blade",
		"armor": &"light",
		"rune": &"poison",
	},
	"клинок_огонь_мастер": {
		"title": "Клинок + огонь, +3 урон, тяжёлая броня +2",
		"weapon": &"blade",
		"armor": &"heavy",
		"rune": &"fire",
		"master": true,
	},
}

## Как часто игрок уходит в побег. Ось симуляции: побег — это выход из боя,
## и его цена должна быть видна в числах, а не только в описании.
const ESCAPE_HP_THRESHOLD := 0.30

## Навыки «мастерской» сборки: потолок веток, а не покупка. Крит и броня берутся
## отсюда, поэтому частота крита в отчёте — это частота ИГРОВОЙ формулы, а не
## вписанное число.
const MASTER_SKILLS := {
	"surv_armor1": true,
	"surv_armor2": true,
	"surv_armor3": false,
	"wpn_dmg1": true,
	"wpn_crit": true,
	"wpn_crit2": false,
	"read_signal": true,
	"surv_no_penalty": false,
	"surv_escape": false,
	"surv_second_wind": true,
	"surv_phoenix": true,
}

## Как часто игрок угадывает сценарий. Ось симуляции, а не свойство сборки.
const READ_LEVELS := {
	"новичок": 0.45,
	"середина": 0.70,
	"знаток": 0.90,
	"идеал": 1.0,
}


func run(battles: int, out_path: String) -> void:
	# Сид фиксирован: отчёт должен воспроизводиться.
	var run_seed := 20260922
	TextGenerator.reset_history()

	var report := {
		"battles_per_case": battles,
		"seed": run_seed,
		"read_levels": READ_LEVELS,
		"cases": [],
	}

	for monster_id in Database.monsters.keys():
		var mon: MonsterData = Database.monsters[monster_id]
		if mon == null:
			report["cases"].append({"monster": monster_id, "error": "вид не найден"})
			continue
		for loadout_id in LOADOUTS.keys():
			for read_id in READ_LEVELS.keys():
				report["cases"].append(_run_case(mon, loadout_id, read_id, battles, run_seed))

	var f := FileAccess.open(out_path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(report, "  "))
		f.close()
		print("SIM: отчёт записан в %s" % out_path)
	else:
		print("SIM: не удалось записать %s (код %d)" % [out_path, FileAccess.get_open_error()])
	_print_summary(report)


func _run_case(
	mon: MonsterData,
	loadout_id: String,
	read_id: String,
	battles: int,
	run_seed: int
) -> Dictionary:
	var load: Dictionary = LOADOUTS[loadout_id]
	var read_accuracy: float = READ_LEVELS[read_id]
	var tool := _make_tool(load)
	var armor: ArmorData = Database.armor(StringName(load.get("armor", "light")))
	# Оружие и броня теперь приходят из базы по идентификатору, значит опечатка в
	# сборке дала бы пустой ресурс и падение посреди прогона. Лучше сказать прямо.
	if tool == null:
		return {"monster": String(mon.id), "loadout_id": loadout_id,
			"read_level": read_id, "error": "оружие «%s» не найдено" % load.get("weapon", "")}
	if armor == null:
		return {"monster": String(mon.id), "loadout_id": loadout_id,
			"read_level": read_id, "error": "броня «%s» не найдена" % load.get("armor", "")}

	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%s:%s:%s:%d" % [mon.id, loadout_id, read_id, run_seed])

	var wins := 0
	var losses := 0
	var total_rounds := 0
	var rounds_on_win := 0
	var damage_dealt := 0
	var damage_taken := 0
	var misses := 0
	var hints := 0
	var counters := 0
	var combos := 0
	var fog_dispels := 0
	var ticking_stops := 0
	var phase_shifts := 0
	var second_winds := 0
	var phoenixes := 0
	var escapes_attempted := 0
	var escapes_succeeded := 0
	var escapes_won := 0
	var crits := 0
	var preemptive := 0
	var hp_left_on_win := 0
	var death_rounds := 0
	var histogram: Dictionary = {}
	## Строка эффектов сборки: заполняется в первом бою, пока навыки включены.
	var case_effects := ""

	for battle in battles:
		# Охотник собирается ИГРОЙ: HP, броня, крит, побег, «Второе дыхание» и
		# «Феникс» считает SkillEffects по навыкам, которые сборка объявила. Раньше
		# здесь стояли вписанные числа, и отчёт мерил не игровые формулы: крит был
		# назначен руками, поглощение не проходило через потолок, а два навыка
		# выживания не включались вовсе.
		var restore := _apply_master_skills(load)
		var hunter := SkillEffects.build_hunter(tool, armor)
		# Эффекты снимаем ЗДЕСЬ, пока навыки включены: строка отчёта строится уже
		# после _restore_skills, и там SkillEffects вернул бы нули. На этом я уже
		# ошибся — отчёт показал «крит 0%» при фактических 20% в бою.
		if battle == 0:
			case_effects = _effects_note(armor, load)
		_restore_skills(restore)
		# HP во всех сборках — 20, как и было: навык «+HP» в набор мастерской сборки
		# не входит, и добавлять его значило бы сдвинуть числа по причине, которой в
		# прежней таблице не было. Починка касается производных (потолок брони, крит,
		# знак штрафа, «Феникс»), а не состава сборок.
		hunter.max_hp = 20
		hunter.hp = hunter.max_hp

		var engine := BattleEngine.new()
		engine.seed_source = SeedSource.new(run_seed, battle)
		engine.setup(mon, hunter, tool)

		var guard := 0
		while not engine.is_over() and guard < 300:
			guard += 1
			# Побег: живой игрок уходит, когда бой идёт плохо. Модель простая —
			# HP ниже порога, значит хватит смекалки отступить.
			if float(hunter.hp) / float(hunter.max_hp) <= ESCAPE_HP_THRESHOLD:
				escapes_attempted += 1
				var esc := engine.attempt_escape()
				if bool(esc.get("success", false)):
					escapes_succeeded += 1
				if engine.is_over():
					break
			var scn := mon.find_scenario(engine.current_scenario_id())
			var guess := _simulate_guess(mon, scn, read_accuracy, rng)
			var outcome := engine.submit_read(guess)

			damage_dealt += int(outcome.get("damage_to_monster", 0))
			damage_taken += int(outcome.get("damage_to_hunter", 0))
			if not bool(outcome.get("read_correct", false)):
				misses += 1
			if not str(outcome.get("hint", "")).is_empty():
				hints += 1
			if not str(outcome.get("counter_title", "")).is_empty():
				counters += 1
			if not str(outcome.get("combo_title", "")).is_empty():
				combos += 1
			# Особые механики видов: важно видеть, срабатывают ли они вообще.
			if bool(outcome.get("fog_dispelled", false)):
				fog_dispels += 1
			if bool(outcome.get("ticking_stopped", false)):
				ticking_stops += 1
			if int(outcome.get("second_wind", 0)) > 0:
				second_winds += 1
			if bool(outcome.get("phoenix", false)):
				phoenixes += 1
			if bool(outcome.get("crit", false)):
				crits += 1
			# Тикающие статусы (отравление) добавляют урон зверю вне хода игрока.
			for ev in engine.take_events():
				if ev["t"] == "monster_damaged" and ev.get("source", "") == "poison":
					damage_dealt += int(ev.get("amount", 0))
				elif ev["t"] == "phase_changed":
					phase_shifts += 1
				elif ev["t"] == "preemptive_strike":
					preemptive += 1

			if not engine.is_over():
				engine.advance_round()

		total_rounds += engine.round_index
		histogram[str(engine.round_index)] = int(histogram.get(str(engine.round_index), 0)) + 1
		if engine.phase == BattleEngine.PHASE_VICTORY:
			wins += 1
			rounds_on_win += engine.round_index
			hp_left_on_win += hunter.hp
		elif engine.phase == BattleEngine.PHASE_FLED:
			# Побег — третий исход, а не поражение: их нельзя смешивать, иначе
			# отчёт показывает «100 поражений» там, где игрок ушёл живым.
			escapes_won += 1
		else:
			losses += 1
			death_rounds += engine.round_index

	return {
		"monster": String(mon.id),
		"monster_title": "%s, %s" % [mon.title, mon.epithet],
		"monster_hp": mon.max_hp,
		"monster_armor": mon.armor,
		"loadout_id": loadout_id,
		"loadout_title": load["title"],
		"tool": "%s / %s%s / урон %d%s" % [
			tool.range_id, tool.damage_type,
			"" if tool.rune_type == &"" else " + %s (руна)" % tool.rune_type,
			tool.base_damage,
			"" if armor == null else " / броня %d (с потолком %d)" % [
				armor.absorption, mini(HunterState.ABSORPTION_CAP, armor.absorption)]],
		"read_level": read_id,
		"read_accuracy": read_accuracy,
		# Фактические эффекты сборки: по ним видно, что игра действительно выдала.
		# Раньше отчёт не показывал ни крита, ни поглощения, поэтому «поглощение 6»
		# при потолке 3 жило незамеченным.
		"effects": case_effects,
		"battles": battles,
		"win_rate": _pct(wins, battles),
		"escape_rate_pct": _pct(escapes_won, battles),
		"wins": wins,
		"losses": losses,
		"avg_rounds": _avg(total_rounds, battles, 2),
		"avg_rounds_on_win": _avg(rounds_on_win, maxi(1, wins), 2),
		"avg_hp_left_on_win": _avg(hp_left_on_win, maxi(1, wins), 2),
		"avg_death_round": _avg(death_rounds, maxi(1, losses), 2),
		"avg_damage_dealt": _avg(damage_dealt, battles, 2),
		"avg_damage_taken": _avg(damage_taken, battles, 2),
		"avg_misses": _avg(misses, battles, 2),
		"hint_rate": _pct(hints, maxi(1, total_rounds)),
		"counter_rate": _pct(counters, maxi(1, total_rounds)),
		"combo_rate": _pct(combos, maxi(1, total_rounds)),
		"fog_rate": _pct(fog_dispels, maxi(1, battles)),
		"ticking_stop_rate": _pct(ticking_stops, maxi(1, battles)),
		"phase_shift_rate": _pct(phase_shifts, maxi(1, battles)),
		"second_wind_rate": _pct(second_winds, maxi(1, battles)),
		"phoenix_rate": _pct(phoenixes, maxi(1, battles)),
		"escape_rate": _pct(escapes_won, maxi(1, battles)),
		"escape_attempt_rate": _pct(escapes_attempted, maxi(1, battles)),
		"escape_wins": escapes_won,
		"escape_tries": escapes_attempted,
		"crit_rate": _pct(crits, maxi(1, total_rounds)),
		"crit_count": crits,
		"preemptive_rate": _pct(preemptive, maxi(1, battles)),
		"total_rounds_played": total_rounds,
		"rounds_histogram": histogram,
	}


## Модель живого игрока: с вероятностью read_accuracy называет настоящий сценарий,
## иначе — случайный из остальных. Идеальный игрок (1.0) нужен как верхняя граница,
## а не как эталон баланса.
func _simulate_guess(
	mon: MonsterData,
	scn: ScenarioData,
	read_accuracy: float,
	rng: RandomNumberGenerator
) -> StringName:
	if scn == null:
		return &""
	if rng.randf() < read_accuracy:
		return scn.id
	var others: Array[StringName] = []
	for s in mon.scenarios:
		if s.id != scn.id:
			others.append(s.id)
	if others.is_empty():
		return scn.id
	return others[rng.randi_range(0, others.size() - 1)]


## Оружие сборки — из базы, а не собранное с нуля. Копия обязательна: руна
## пишется В РЕСУРС, а Database отдаёт один и тот же объект, поэтому без копии
## руна одной сборки протекла бы в остальные и в сам справочник.
func _make_tool(load: Dictionary) -> WeaponData:
	var src: WeaponData = Database.weapon(StringName(load.get("weapon", "bow")))
	if src == null:
		return null
	var w: WeaponData = src.duplicate()
	var rune_type: StringName = StringName(load.get("rune", &""))
	if rune_type != &"":
		w.rune_type = rune_type
	return w


## Включить навыки сборки на время сборки охотника: SkillEffects читает GameState,
## как и в игре. Возвращает прежнее содержимое, чтобы вернуть его после.
func _apply_master_skills(load: Dictionary) -> Dictionary:
	var saved := GameState.skills.duplicate()
	if bool(load.get("master", false)):
		GameState.skills = MASTER_SKILLS.duplicate()
	return saved


func _restore_skills(saved: Dictionary) -> void:
	GameState.skills = saved


## Есть ли навык у сборки (только у мастерской). Нужно для строки эффектов в
## отчёте: она читается ПОСЛЕ восстановления GameState, поэтому спрашивать
## GameState.has_skill() там уже нельзя.
func _master_flag(load: Dictionary, skill_id: String) -> bool:
	if not bool(load.get("master", false)):
		return false
	return bool(MASTER_SKILLS.get(skill_id, false))


## Строка эффектов сборки. Вызывается, пока навыки сборки включены: иначе
## SkillEffects вернёт нули, и отчёт покажет «крит 0%» при работающем крите.
func _effects_note(armor: ArmorData, load: Dictionary) -> String:
	var raw := armor.absorption + SkillEffects.armor_bonus()
	return "крит %d%% / поглощение сырое %d, итог %d (потолок %d) / 2-е дыхание %s / феникс %s" % [
		roundi(SkillEffects.crit_chance() * 100.0),
		raw, mini(HunterState.ABSORPTION_CAP, raw), HunterState.ABSORPTION_CAP,
		"да" if _master_flag(load, "surv_second_wind") else "нет",
		"да" if _master_flag(load, "surv_phoenix") else "нет"]


func _print_summary(report: Dictionary) -> void:
	print("")
	print("=== СИМУЛЯЦИЯ БАЛАНСА: %d боёв на случай, сид %d ===" % [
		report["battles_per_case"], report["seed"]])
	print("%-7s %-38s %-8s %8s %8s %9s %8s" % [
		"зверь", "сборка", "чтение", "побед%", "раундов", "урона нам", "промахов"])
	for case in report["cases"]:
		if case.has("error"):
			print("%-7s ОШИБКА: %s" % [case["monster"], case["error"]])
			continue
		print("%-7s %-38s %-8s %8s %8s %9s %8s" % [
			case["monster"],
			str(case["loadout_title"]).substr(0, 38),
			case["read_level"],
			"%s%%" % case["win_rate"],
			case["avg_rounds"],
			case["avg_damage_taken"],
			case["avg_misses"],
		])


func _pct(part: int, total: int) -> float:
	if total <= 0:
		return 0.0
	return snappedf(float(part) * 100.0 / float(total), 0.1)


func _avg(sum: int, count: int, digits: int) -> float:
	if count <= 0:
		return 0.0
	return snappedf(float(sum) / float(count), pow(0.1, digits))
