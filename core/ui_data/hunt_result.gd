extends RefCounted
class_name HuntResult
## Применение исхода охоты к мета-состоянию: слава, ранг, монеты, досье, трофеи.
##
## Вся прогрессия собрана в одном месте намеренно: раньше её правила были размазаны
## по GDD (8.2, 8.3, 8.4, 5.2), и именно там накопились противоречия. Здесь один
## проход, который можно прогнать в headless и проверить числами.

## Что произошло в бою — заполняется экраном боя или симулятором.
var monster_id: StringName = &""
var order_rank: int = 0
var victory: bool = false
## Побег: охота окончена без добычи. Смерть — не побег, у них разные последствия.
var fled: bool = false
var rounds: int = 0
var perfect_reads: int = 0
var misses: int = 0
var damage_taken: int = 0
var hp_left: int = 0
var damage_dealt: int = 0

## Что игрок делал в бою: нужно для достижений (победа без брони, одним оружием).
var had_armor: bool = true
var switched_weapon: bool = false
## Показывалась ли подсказка о неэффективном инструменте.
var saw_hint: bool = false
## Название последнего хода зверя: попадает в Хронику как причина смерти.
var last_scenario_label: String = ""

## Досье: накопленные факты за бой.
var new_signals: Array[String] = []
var new_decoys: Array[String] = []
var new_scenarios: Array[String] = []
var new_weaknesses: Array[String] = []
var new_combos: Array[String] = []

## Итоги применения.
var glory_delta: int = 0
var coins_gained: int = 0
var trophies: Array[String] = []
var rank_up: bool = false
var rank_down: bool = false
var old_rank: int = 0
var new_rank: int = 0
var message: String = ""
var dossier_gained: int = 0
## Сколько стоимости ноши потеряно в этой охоте: при побеге — брошенная часть,
## при смерти — вся ноша. Раньше здесь были монеты из кошелька, но с рынком
## теряется добыча, а не деньги: кошелёк пустым делает только смерть.
var bag_lost: int = 0
## Сколько монет сгорело при падении. Отдельно от bag_lost: монеты и ноша
## теряются по-разному, и на экране поражения это две разные строки.
var coins_lost: int = 0
## Смерть была окончательной: срок богини вышел, воскрешения не будет.
## По этому полю экран исхода выбирает «конец забега» вместо «падения».
var run_over: bool = false
## Достижения, открытые этой охотой (id).
var achievements_opened: Array[String] = []


## Посчитать и применить исход. side_encounter смягчает штраф (GDD 8.4).
func apply(side_encounter: bool = false) -> void:
	old_rank = GameState.rank
	var mon: MonsterData = Database.monster(monster_id)
	# Поход стоит не один день, а три (GDD 1.3.1): дорога, охота, возврат.
	# Возврат здесь не потому, что мы его уже сделали, а потому что заказ
	# закрывается только по возвращении — уйти и вернуться это одно действие.
	for _i in CityData.days_per_hunt():
		GameState.next_day()

	if victory:
		_apply_victory(mon, side_encounter)
	elif fled:
		_apply_escape(mon)
	else:
		_apply_defeat(side_encounter)

	_update_counters()
	_apply_dossier()
	_update_rank()
	_log_to_chronicle(mon)
	# Достижения проверяются последними: им нужны и ранг, и счётчики, и Хроника.
	achievements_opened = Achievements.check_after_hunt(self)
	# Между боями: регенерация от навыка и Амулет стойкости (GDD 7.4, 12.8).
	if victory:
		if GameState.has_skill(&"surv_regen"):
			hp_left = mini(20, hp_left + 1)
		if GameState.equipped_armor == &"amulet":
			hp_left = mini(20, hp_left + 1)


## Счётчики для достижений: только то, что нельзя вывести из исхода напрямую.
func _update_counters() -> void:
	var c := GameState.counters
	if victory:
		if not had_armor:
			c["kills_no_armor"] = int(c.get("kills_no_armor", 0)) + 1
		if not switched_weapon:
			c["kills_one_weapon"] = int(c.get("kills_one_weapon", 0)) + 1
		if misses == 0:
			c["kills_flawless"] = int(c.get("kills_flawless", 0)) + 1
		if not saw_hint:
			c["kills_without_hint"] = int(c.get("kills_without_hint", 0)) + 1
		if order_rank >= 3:
			c["kills_tier3"] = int(c.get("kills_tier3", 0)) + 1


## Запись в Хронику гильдии: победа, смерть или уход. По ней работают фильтры
## экрана истории (GDD 11.8) и часть достижений.
func _log_to_chronicle(mon: MonsterData) -> void:
	var name_text := mon.title if mon != null else String(monster_id)
	var tool_text := "инструмент: %s" % GameState.equipped_weapon
	if victory:
		var note := "Заказ: %s. Промахов: %d." % [CityData.order_tier_title(order_rank), misses]
		GameState.log_fame("победа", name_text, "%s. %s" % [tool_text, note], glory_delta)
	elif fled:
		var lost_note := "Ничего не бросил." if bag_lost <= 0 else "Брошено добычи на %d монет." % bag_lost
		GameState.log_fame("охота", name_text, "Ты ушёл. %s" % lost_note, 0)
	else:
		# Причину смерти берём из последнего разобранного раунда: у итога нет
		# доступа к журналу движка, но сценарий последнего удара в нём есть.
		var bag_note := "" if bag_lost <= 0 else " Ноша осталась там: %d монет." % bag_lost
		GameState.log_fame("смерть", name_text,
			"Заказ: %s. Последний ход зверя: «%s». Промахов: %d.%s" % [
				CityData.order_tier_title(order_rank), last_scenario_label, misses, bag_note],
			glory_delta)


func _apply_victory(mon: MonsterData, side_encounter: bool) -> void:
	# Слава (GDD 8.2): база по рангу заказа + бонусы за качество.
	var sign_bonus := GameState.rank >= 4
	glory_delta = CityData.victory_glory(order_rank, perfect_reads > 0, damage_taken == 0, sign_bonus)
	if side_encounter:
		glory_delta = maxi(1, int(glory_delta / 2.0))
	# Комбо-навыки веток: «Чтение + Оружие» и «Все три» (GDD 7.5).
	if GameState.has_skill(&"read_signal") and GameState.has_skill(&"wpn_dmg1"):
		glory_delta += 1
	if (GameState.has_skill(&"read_signal") and GameState.has_skill(&"wpn_dmg1")
			and GameState.has_skill(&"surv_armor1")):
		glory_delta += 1
	GameState.add_glory(glory_delta)

	# Монеты: трофеи вида. С появлением рынка добыча НЕ продаётся автоматически —
	# она падает в ношу, а монеты за неё даёт Лис. coins_gained здесь означает
	# стоимость добычи, а не пополнение кошелька: это справочная цифра для итога.
	if mon != null:
		for i in mon.trophy_names.size():
			trophies.append(mon.trophy_names[i])
		coins_gained = GameState.add_drop(mon)

	GameState.register_kill(monster_id, order_rank)
	GameState.counters["perfect_reads"] = int(GameState.counters["perfect_reads"]) + perfect_reads
	if perfect_reads > 0:
		message = "Досье пополнено."
	else:
		message = "Победа. Гильдия запомнит."


## Побег: добычи нет, и часть НОШИ приходится бросить — ты уходил налегке.
## Слава не страдает: отступление не позор, но оно стоит добра.
func _apply_escape(mon: MonsterData) -> void:
	var penalty := 0
	if not GameState.has_skill(&"surv_no_penalty"):
		var loot := 0
		if mon != null:
			for price in mon.trophy_prices:
				loot += int(price)
		var target := maxi(
			BattleEngine.ESCAPE_COIN_PENALTY_MIN,
			int(floor(float(loot) * BattleEngine.ESCAPE_COIN_PENALTY_FRACTION))
		)
		# Штраф считается по добыче ВИДА, а отнимается из ноши: потерять можно
		# только то, что несёшь. Если ноша дешевле штрафа — теряешь её всю.
		penalty = GameState.drop_bag_part(target)
	bag_lost = penalty
	glory_delta = 0
	GameState.win_streak = 0
	var name_text := mon.title if mon != null else String(monster_id)
	if penalty > 0:
		message = "Ты ушёл от %s. Часть ноши пришлось бросить — добычи на %d монет." % [
			name_text, penalty]
	else:
		message = "Ты ушёл от %s. Никто не вправе упрекнуть: ты жив и не потерял ничего." % name_text
	GameState.counters["escapes"] = int(GameState.counters.get("escapes", 0)) + 1


func _apply_defeat(side_encounter: bool) -> void:
	var mon: MonsterData = Database.monster(monster_id)
	# Штраф = ранг заказа × 3 (GDD 8.4), с модификаторами.
	var first_time := GameState.kill_counts(monster_id) == 0
	var penalty := CityData.death_penalty(order_rank, first_time, side_encounter)
	glory_delta = -penalty
	GameState.add_glory(-penalty)
	GameState.counters["deaths"] = int(GameState.counters["deaths"]) + 1
	GameState.win_streak = 0
	# Смерть сжигает материю (GDD 1.3): монеты и ноша теряются, знания и навыки — нет.
	coins_lost = GameState.coins
	GameState.coins = 0
	bag_lost = GameState.drop_bag_all()
	# Правило двух цен (GDD 1.3.1): срок идёт — богиня вернёт, смерть обратима.
	# Срок вышел — возвращать некому, и это конец забега. Логика только здесь,
	# чтобы её нельзя было рассинхронизировать с экраном.
	run_over = not GameState.grace_active()
	message = "Ты пал на %s. Знания остались." % (mon.title if mon != null else monster_id)


func _apply_dossier() -> void:
	for s in new_signals:
		if GameState.dossier_add(monster_id, "signals", s):
			dossier_gained += 1
	for d in new_decoys:
		if GameState.dossier_add(monster_id, "decoys", d):
			dossier_gained += 1
	for s in new_scenarios:
		if GameState.dossier_add(monster_id, "scenarios", s):
			dossier_gained += 1
	for w in new_weaknesses:
		if GameState.dossier_add(monster_id, "weaknesses", w):
			dossier_gained += 1
	for c in new_combos:
		if GameState.dossier_add(monster_id, "combos", c):
			dossier_gained += 1


## Ранг растёт только вверх сам по себе, вниз — по защите от спирали (GDD 8.4).
func _update_rank() -> void:
	GameState.refresh_rank()
	if GameState.rank > old_rank:
		rank_up = true
		GameState.log_fame("повышение", "РАНГ ПОВЫШЕН: %s" % GameState.rank_title(),
			"Гильдия признала твои заслуги.", GameState.glory)
		# Восстановление с превосхождением: поднялся ВЫШЕ, чем был до падения.
		if GameState.lowest_rank_after_fall >= 0 and GameState.rank > GameState.lowest_rank_after_fall:
			GameState.counters["recoveries_beyond"] = int(GameState.counters.get("recoveries_beyond", 0)) + 1
			GameState.lowest_rank_after_fall = -1
	if GameState.rank < old_rank:
		rank_down = true
		# Запоминаем, докуда упал: по этому порогу считается восстановление.
		if GameState.lowest_rank_after_fall < 0 or GameState.rank < GameState.lowest_rank_after_fall:
			GameState.lowest_rank_after_fall = old_rank
		GameState.log_fame("откат", "РАНГ ПОНИЖЕН: %s" % GameState.rank_title(),
			"Клеймо на знаке ранга. Исчезнет, когда поднимешься выше.", 0)
	new_rank = GameState.rank


## Человекочитаемая сводка — для экрана и для headless-прогона.
func summary_lines() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	if victory:
		out.append("ПОБЕДА")
	elif fled:
		out.append("ПОБЕГ")
	else:
		out.append("ПОРАЖЕНИЕ")
	out.append("Раундов: %d, идеальных чтений: %d, промахов: %d" % [rounds, perfect_reads, misses])
	out.append("Урон нанесён: %d, получен: %d" % [damage_dealt, damage_taken])
	out.append("Слава: %+d (итого %d, до следующего ранга %s)" % [
		glory_delta, GameState.glory,
		"максимум" if GameState.glory_to_next() < 0 else str(GameState.glory_to_next())])
	if fled:
		out.append("Брошено добычи: %d монет (в кошельке %d)" % [bag_lost, GameState.coins])
	elif victory:
		out.append("Добыча взята: %d монет (в ноше всего %d, в кошельке %d)" % [
			coins_gained, GameState.bag_value(), GameState.coins])
	else:
		out.append("Ноша потеряна: %d монет (в кошельке %d)" % [bag_lost, GameState.coins])
	if not trophies.is_empty():
		out.append("Трофеи: %s" % ", ".join(trophies))
	if not fled and not GameState.bag.is_empty():
		out.append("В ноше: %s" % "; ".join(MarketData.describe(GameState.bag)))
	if dossier_gained > 0:
		out.append("Досье пополнено: %d новых фактов" % dossier_gained)
	if rank_up:
		out.append("РАНГ ПОВЫШЕН: %s" % GameState.rank_title())
	if rank_down:
		out.append("РАНГ ПОНИЖЕН: %s" % GameState.rank_title())
	return out
