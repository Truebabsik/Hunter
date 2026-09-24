extends RefCounted
class_name BattleEngine
## Ядро боя. Чистая логика: ни Node, ни SceneTree, ни сцен.
##
## Порядок раунда (GDD 2.2):
##   1. Такт зверя (скрытый)      — scenario_picker выбирает сценарий;
##   2. Такт прозы (открытый)     — text_generator собирает размеченный абзац;
##   3. Такт решения (игрок)      — игрок называет сценарий и инструмент;
##   4. Исход                     — градиент 2.4, урон 12.5/12.6, статусы.
##
## Движок не показывает ничего сам: он копит события и отдаёт их через
## take_events(). Так его можно прогнать в симуляторе без единого пикселя.

const PHASE_AWAIT_INPUT := &"await_input"
const PHASE_VICTORY := &"victory"
const PHASE_DEFEAT := &"defeat"
const PHASE_FLED := &"fled"

## Базовый шанс побега (GDD 2.5: «успех — вероятность отвлечения»).
##
## В документе базовое число не задано, поэтому оно выбрано здесь и обосновано:
## 60% — это «чаще получается, чем нет», но не гарантия. Иначе побег стал бы
## бесплатным выходом из любого боя, и угроза смерти перестала бы что-то значить.
## Растёт от навыка «Быстрый побег» (+10%) и Плаща охотника (+10%).
const ESCAPE_BASE_CHANCE := 0.60

## Побег никогда не гарантирован: даже с полной прокачкой остаётся риск.
const ESCAPE_MAX_CHANCE := 0.95

## Побег стоит ДОБЫЧИ, а не славы: уходя, ты бросаешь часть ноши.
##
## Почему материя, а не слава: сквозная идея игры — «материя сгорает, знания
## остаются». Если побег отнимает славу, игрок сохраняет материю ценой репутации,
## и столп выворачивается наизнанку. Материальный штраф это чинит: ты ушёл живым,
## но с пустыми руками.
##
## До рынка штраф списывался монетами из кошелька. Теперь добыча копится в ноше,
## поэтому бросаешь именно предметы: пропорция та же, изменилось лишь то, что
## потерять можно только то, что несёшь.
const ESCAPE_COIN_PENALTY_FRACTION := 0.25

## Минимум, который теряется при побеге: если добыча ничтожна, отступление
## всё равно должно что-то стоить.
const ESCAPE_COIN_PENALTY_MIN := 1

## Сколько раз подряд можно ударить неэффективным инструментом, прежде чем
## зверь сам «выдаст» подсказку. Без этого тупики вроде Громуна превращаются
## в расход времени, а не в загадку (GDD 14.1, «Стены чтения»).
const INEFFECTIVE_HINT_THRESHOLD := 2

## Порог «слабого» урона, после которого инструмент считается неэффективным.
const INEFFECTIVE_DAMAGE := 1

## Длина окна повторов игрока для контр-приёма.
const REPEAT_WINDOW := 3

## Единственный источник: какие статусы движок РЕАЛЬНО умеет обрабатывать.
##
## Зачем список явно. Контент комбо задаёт `status_id`, и описания обещают эффект
## («зверь слепнет», «зверь открыт на 2 хода»), но обрабатываются далеко не все:
## у «blind» и «open» в коде не было НИ ОДНОГО упоминания, а их комбо при этом
## показывались игроку как действующие. Это тот же класс, что подпись типа урона,
## считавшегося иначе: текст обещает одно, механика делает другое.
##
## Правило: добавил статус — добавь его СЮДА и обработай в _tick_statuses().
## Валидатор сверяет контент с этим списком и ловит опечатку или недоделку.
const STATUS_STUN := &"stun"
const STATUS_FREEZE := &"freeze"
const STATUS_POISON := &"poison"

## «Слепота»: зверь слепнет и перестаёт выдавать читаемые сигналы — проза раунда
## идёт без опорных улик. Механика та же, что у тумана обзора, но короче и не
## снимается чтением: слепота держится назначенный срок.
const STATUS_BLIND := &"blind"

## «Открыт»: зверь пропустил защиту, и любой удар проходит на 1 глубже
## (см. DamageCalc.player_damage, target_open).
const STATUS_OPEN := &"open"

const STATUS_IDS: Array[StringName] = [
	STATUS_STUN, STATUS_FREEZE, STATUS_POISON, STATUS_BLIND, STATUS_OPEN,
]

var monster: MonsterData
var hunter: HunterState
var weapon: WeaponData

var monster_hp: int
var round_index: int = 0
var phase: StringName = PHASE_AWAIT_INPUT

## Статусы зверя: id -> {rounds:int, text:String}
var monster_statuses: Dictionary = {}

## Туман обзора: пока не прочитан ключевой сценарий, карточки скрыты (GDD 11.5).
var fog_active: bool = false

## Тикающий урон: сколько ещё раундов он капает (GDD 4.7).
var ticking_left: int = 0

## Фаза зверя: id текущей фазы (GDD 4.8). Пусто = фаз нет.
var current_phase_id: StringName = &""

## «Феникс»: одно возвращение за забег (GDD 7.4).
var phoenix_available: bool = false
var phoenix_used: bool = false

## «Второе дыхание»: +5 HP при HP ≤ 3, один раз за бой.
var second_wind_available: bool = false
var second_wind_used: bool = false

## Сколько раз игрок пытался бежать. Нужно симулятору и разбору боя.
var escape_attempts: int = 0

## Инициатива: зверь уже ударил превентивно в этом бою (GDD 2.6).
var preemptive_strike_done: bool = false

## Последние прочитанные игроком сценарии — считаем повторы игрока.
var player_reads: Array[StringName] = []

var picker := ScenarioPicker.new()
var log: Array[Dictionary] = []

## Источник сидов для headless-прогонов. Если задан — движок берёт потоки
## случайности из него, а не из глобального RNGService. Так симулятор полностью
## воспроизводим независимо от глобального состояния автолоада.
var seed_source: SeedSource = null

var _current_scenario: ScenarioData
var _current_prose: Dictionary = {}
var _events: Array[Dictionary] = []
var _ineffective_streak: int = 0
var _hint_shown: bool = false
var _counter_used_ids: Dictionary = {}


func setup(p_monster: MonsterData, p_hunter: HunterState, p_weapon: WeaponData) -> void:
	monster = p_monster
	hunter = p_hunter
	weapon = p_weapon
	# Навык «+1/+2/+3 урон» поднимает базовый урон оружия. Копируем ресурс целиком:
	# он общий для всех боёв, и правка на месте протекла бы в справочник.
	#
	# Почему duplicate(), а не копирование по полям. Раньше поля перечислялись
	# руками — одиннадцать строк, — и `accent_color` в них уже забыли. Следующее
	# поле в WeaponData потерялось бы так же молча: ресурс-копия выглядел бы
	# рабочим, а цвет или иконка в бою отличались бы от выбранных.
	if hunter.damage_skill_bonus != 0:
		var tuned: WeaponData = weapon.duplicate()
		tuned.base_damage = weapon.base_damage + hunter.damage_skill_bonus
		weapon = tuned
	monster_hp = monster.max_hp
	round_index = 0
	phase = PHASE_AWAIT_INPUT
	monster_statuses.clear()
	player_reads.clear()
	picker.clear()
	log.clear()
	_events.clear()
	_current_scenario = null
	_current_prose = {}
	_ineffective_streak = 0
	_hint_shown = false
	_counter_used_ids.clear()
	fog_active = monster.fog_enabled
	ticking_left = monster.ticking_damage
	current_phase_id = &""
	second_wind_available = hunter.second_wind
	second_wind_used = false
	# «Феникс» включается так же, как «Второе дыхание». Раньше этой строки не было
	# вовсе: движок проверял phoenix_available в двух местах (превентивный удар и
	# разбор хода), но выставить флаг было некому — навык за 100 монет не работал.
	phoenix_available = hunter.phoenix
	phoenix_used = false
	escape_attempts = 0
	preemptive_strike_done = false
	advance_round()
	# Инициатива (GDD 2.6): если зверь быстрее, он бьёт первым — до решения игрока.
	# По GDD при равенстве первым бьёт игрок, поэтому нужно СТРОГОе превосходство.
	if phase == PHASE_AWAIT_INPUT and hunter.monster_acts_first(monster):
		apply_preemptive_strike()


## Превентивный удар зверя: он быстрее и успевает до первого хода игрока.
## Это удар по базовому урону вида — приём он ещё не готовил.
func apply_preemptive_strike() -> Dictionary:
	if preemptive_strike_done or phase != PHASE_AWAIT_INPUT:
		return {}
	preemptive_strike_done = true
	var taken := DamageCalc.monster_damage(monster, null, hunter, false)
	hunter.take_damage(taken)
	_events.append({
		"t": "preemptive_strike",
		"amount": taken,
		"hp": hunter.hp,
		"monster_initiative": monster.initiative,
		"hunter_initiative": hunter.initiative(),
	})
	if hunter.hp <= 0:
		_handle_hunter_down({})
	return {"amount": taken, "hp": hunter.hp}


## Охотник на нуле: «Второе дыхание», «Феникс» или поражение.
##
## Три места боя решают этот вопрос — превентивный удар, провал побега и конец
## раунда, — и правило обязано быть одним. Раньше оно было скопировано трижды, и
## копии разошлись: в превентивном ударе «Второе дыхание» не проверялось вовсе,
## только «Феникс». Значит охотник с 1–3 HP, убитый быстрым зверем до своего
## первого хода, терял второй шанс, хотя навык куплен, — и заметить это можно было
## только в бою против того зверя, который бьёт первым.
##
## Порядок важен и сохранён: сначала «Второе дыхание» (оно спасает при HP ≤ 3),
## и только если охотник всё ещё на нуле — «Феникс».
func _handle_hunter_down(outcome: Dictionary) -> void:
	if second_wind_available and not second_wind_used and hunter.hp > 0 and hunter.hp <= 3:
		second_wind_used = true
		var healed := hunter.heal(5)
		outcome["second_wind"] = healed
		_events.append({"t": "second_wind", "amount": healed, "hp": hunter.hp})
	if hunter.hp <= 0:
		if phoenix_available and not phoenix_used:
			phoenix_used = true
			hunter.hp = 5
			outcome["phoenix"] = true
			_events.append({"t": "phoenix", "hp": hunter.hp})
		else:
			phase = PHASE_DEFEAT
			_events.append({"t": "battle_end", "result": "defeat", "rounds": round_index})


## Шанс успешного побега. Живёт в ядре, а не в экране: это боевое правило,
## и симулятор должен считать по нему же.
func escape_chance() -> float:
	var chance := ESCAPE_BASE_CHANCE + hunter.bonus_escape_chance
	return clampf(chance, 0.0, ESCAPE_MAX_CHANCE)


## Сработал ли навык «Быстрая смена» в текущем ходу: смена прошла С ударом.
## Экран показывает это игроку — иначе расход навыка выглядел бы как чудо.
var outcome_free_swap: bool = false


## Попытка побега (GDD 2.5): «в любой момент. Успех — вероятность отвлечения.
## Провал — зверь бьёт, но попытка не отменяет ход».
##
## Важное следствие формулировки: побег — это ОТДЕЛЬНОЕ действие, а не вместо
## удара. Поэтому и при провале, и при успехе ход игрока не тратится: он может
## бить в том же раунде. Плата за попытку — только риск получить удар.
func attempt_escape() -> Dictionary:
	if phase != PHASE_AWAIT_INPUT:
		return {}
	escape_attempts += 1
	var rng := _round_rng(round_index, &"mechanics")
	var success := rng.randf() < escape_chance()

	var outcome := {
		"t": "escape",
		"round": round_index,
		"success": success,
		"chance": escape_chance(),
		"free_strike": 0,
		"hp": hunter.hp,
	}

	if success:
		# Зверь отвлёкся: бой окончен, добычи нет.
		phase = PHASE_FLED
		_events.append({"t": "escape_resolved", "success": true, "chance": escape_chance()})
		_events.append({"t": "battle_end", "result": "fled", "rounds": round_index})
		return outcome

	# Провал: зверь бьёт. Удар идёт по базовому урону вида, а не по урону сценария:
	# это удар вдогонку уходящему, а не подготовленный приём.
	var taken := DamageCalc.monster_damage(monster, null, hunter, false)
	hunter.take_damage(taken)
	outcome["free_strike"] = taken
	outcome["hp"] = hunter.hp
	_events.append({
		"t": "escape_resolved",
		"success": false,
		"chance": escape_chance(),
		"damage": taken,
		"hp": hunter.hp,
	})

	# Удар вдогонку мог сбить охотника с ног — разбираем это общим правилом.
	_handle_hunter_down(outcome)

	return outcome


## Сколько СТОИМОСТИ НОШИ уйдёт, если уйти от этого зверя. Считается по добыче
## вида (пропорция + минимум), а отнимается уже из самой ноши в HuntResult:
## потерять можно только то, что несёшь. Навык «Без потерь» обнуляет штраф.
func escape_bag_loss(monster: MonsterData) -> int:
	if hunter.escape_penalty_negated:
		return 0
	if monster == null:
		return ESCAPE_COIN_PENALTY_MIN
	var loot := 0
	for price in monster.trophy_prices:
		loot += int(price)
	return maxi(ESCAPE_COIN_PENALTY_MIN, int(floor(float(loot) * ESCAPE_COIN_PENALTY_FRACTION)))


## Начать раунд: скрытый такт зверя + генерация прозы.
func advance_round() -> void:
	round_index += 1
	_events.append({"t": "round_started", "round": round_index})
	_tick_statuses()
	_tick_phase()

	var rng_mech := _round_rng(round_index, &"mechanics")
	_current_scenario = picker.pick(monster, rng_mech, round_index)
	_events.append({
		"t": "scenario_picked",
		"scenario_id": _current_scenario.id,
		"card_label": _current_scenario.card_label,
	})

	var rng_text := _round_rng(round_index, &"text")
	_current_prose = TextGenerator.generate(monster, _current_scenario, rng_text)
	# Туман обзора и слепота зверя: улик в этом раунде НЕТ.
	#
	# Раньше туман не скрывал ничего: он уходил в событие и в арт, а проза подавала
	# опорные сигналы как обычно. То есть «ТУМАН ОБЗОРА» был затемнением картинки,
	# а карточка в досье обещала механику. Теперь он скрывает улики — и об этом
	# честно сказано в прозе, чтобы игрок понимал, почему читать нечего.
	#
	# Слепота (статус blind) делает то же самое, но по другой причине: слеп ЗВЕРЬ,
	# он не подаёт знаков. Сообщения поэтому разные, а последствие одно.
	var fog_hides := fog_active
	var blind_hides := monster_statuses.has(STATUS_BLIND)
	if fog_hides or blind_hides:
		_current_prose["lines"] = []
		_current_prose["core_labels"] = PackedStringArray()
		_current_prose["prose"] = _hidden_prose_text(fog_hides)
	_events.append({
		"t": "prose",
		"scenario_id": _current_scenario.id,
		"prose": _current_prose["prose"],
		"lines": _current_prose["lines"],
		"core_labels": _current_prose["core_labels"],
		"fog": fog_active,
		"blind": blind_hides,
	})
	phase = PHASE_AWAIT_INPUT


## Текст раунда, когда читать нечего. Смысл один, причина разная: туман скрывает
## зверя от игрока, слепота — зверя от самого себя. Игроку важно и то и другое,
## поэтому формулировка зависит от причины, а не от того, кто её вызвал в коде.
##
## Текст вида `monster.fog_text` здесь НЕ показывается намеренно: он написан как
## сообщение о рассеивании («Туман осел. Ты снова видишь…») и в состоянии «ничего
## не видно» читался бы противоположно своему смыслу.
func _hidden_prose_text(by_fog: bool) -> String:
	if by_fog:
		return "Туман обзора: ни позы, ни звука не разобрать. Действуй наугад."
	return "Зверь ослеп и тычется вслепую — знаков он больше не подаёт. Действуй наугад."


## Игрок назвал сценарий и инструмент. Возвращает словарь исхода.
## Ход игрока: ставка + ответ.
##
## `attack = false` — это смена инструмента: игрок потратил ход на то, чтобы взять
## другое оружие или переложить руну, и НЕ бьёт. Штраф смены именно в этом, а не в
## отдельном пропущенном ходу: зверь бьёт один раз за раунд, но верное чтение
## спасает и здесь — знание защищает независимо от того, чем ты отвечал.
##
## Дальность и тип удара НЕ передаются параметрами. Раньше передавались, и это давало
## второй источник правды: движок считал верность инструмента по `weapon.range_id`, а
## урон — по `weapon`, тогда как комбо подбиралось по ПАРАМЕТРУ. Значения совпадали
## только потому, что экран их выставлял согласованно, — это не инвариант, а везение.
## Теперь единственный источник — оружие, которым игрок отвечает.
##
## Почему смену обрабатывает ЯДРО, а не экран: иначе верное чтение не спасало бы
## от урона при смене (экран не умеет отменять удар зверя), и правило боя жило бы
## в двух местах.
func submit_read(guess_scenario: StringName, attack: bool = true) -> Dictionary:
	if phase != PHASE_AWAIT_INPUT:
		return {}

	var read_correct := guess_scenario == _current_scenario.id

	# Навык «Быстрая смена»: сменил инструмент И ударил в том же ходу. Он снимает
	# штраф смены — отказ от удара, — поэтому проверяется здесь, а не в экране:
	# иначе навык работал бы на одном экране и не работал в прогоне.
	# Это ЕДИНСТВЕННОЕ место, где расходуется навык: раньше вторая копия жила в
	# swap_weapon, и та копия была недостижима из игры.
	if not attack and hunter.weapon_swap_free:
		hunter.weapon_swap_free = false
		attack = true
		outcome_free_swap = true
		_events.append({"t": "free_swap_used"})
	else:
		outcome_free_swap = false

	var combo: ComboData = _match_combo(guess_scenario)
	var combo_hit := combo != null and attack

	# Ступень чтения зависит только от того, угадан ли сценарий и нанёс ли игрок
	# удар. Отдельной «верности инструмента» больше нет: дальность и тип приходят
	# от оружия, и промахнуться инструментом нельзя. Раньше здесь стояла проверка
	# `tool_correct`, а параметры дальности и типа передавались снаружи — то есть
	# существовала возможность, что игрок бьёт не тем, чем объявил.
	var reading := DamageCalc.Reading.MISS
	if read_correct and attack:
		reading = DamageCalc.Reading.PERFECT if combo_hit else DamageCalc.Reading.COUNTER
	elif read_correct:
		reading = DamageCalc.Reading.PARTIAL

	_events.append({
		"t": "read_submitted",
		"guess": guess_scenario,
		"correct_scenario": _current_scenario.id,
		"read_correct": read_correct,
		"attack": attack,
	})

	var outcome := {
		"round": round_index,
		"guess": guess_scenario,
		"guess_label": _scenario_label(guess_scenario),
		"scenario_id": _current_scenario.id,
		"scenario_label": _current_scenario.card_label,
		"read_correct": read_correct,
		"reading": reading,
		"attack": attack,
		"free_swap": outcome_free_swap,
		"damage_to_monster": 0,
		"damage_breakdown": "",
		"damage_to_hunter": 0,
		"hunter_damage_breakdown": "",
		"combo_title": "",
		"combo_effect": "",
		"counter_title": "",
		"counter_text": "",
		"statuses_applied": PackedStringArray(),
		"hint": "",
		"fog_dispelled": false,
		"ticking_stopped": false,
		"ticking_damage": 0,
		"second_wind": 0,
		"phoenix": false,
		"phase_id": String(current_phase_id),
		# Факты для досье (GDD 5.2). Ядро их только называет — записывает GameState.
		"fact_scenario": String(_current_scenario.id),
		"fact_signals": _core_signal_labels(),
		"fact_decoy": _shown_decoy_label(),
	}

	if read_correct:
		player_reads.append(guess_scenario)
		# Верное чтение защищает в любом случае: это знание, а не удар. Поэтому
		# разбор идёт даже когда игрок сменил инструмент вместо удара.
		var phase := monster.phase_for_hp(monster_hp)
		var dmg := DamageCalc.player_damage(
			weapon,
			monster,
			reading,
			combo_hit,
			combo.damage_bonus if combo != null else 0,
			hunter.perfect_read_bonus,
			phase,
			hunter.crit_chance,
			_round_rng(round_index, &"crit"),
			# «Открыт» (комбо «Гашение»): пока статус на звере, удар идёт на 1 глубже.
			monster_statuses.has(STATUS_OPEN)
		)
		if attack:
			monster_hp = maxi(0, monster_hp - dmg.total)
			outcome["damage_to_monster"] = dmg.total
			outcome["damage_breakdown"] = dmg.breakdown()
			outcome["crit"] = dmg.crit
			if dmg.crit:
				_events.append({"t": "crit", "damage": dmg.total})
				# Комбо-навык «Оружие + Выживание»: крит оглушает (GDD 7.5).
				if hunter.crit_stuns:
					_apply_monster_status(STATUS_STUN, 1, "оглушён критом")
					outcome["statuses_applied"] = PackedStringArray(["оглушение на 1 ход"])
					_events.append({"t": "monster_stunned", "rounds": 1})
			_events.append({"t": "monster_damaged", "amount": dmg.total, "hp": monster_hp})
		else:
			# Смена инструмента: прочитал верно, но не ударил. Считаем, сколько
			# удара потеряно, чтобы игрок видел цену смены, а не пустую строку.
			outcome["swap_only"] = true
			outcome["damage_breakdown"] = "смена инструмента: удар не нанесён (был бы %d)" % dmg.total

		# Туман обзора рассеивается верным чтением ключевого сценария (GDD 11.5).
		if fog_active and guess_scenario == monster.fog_key_scenario:
			fog_active = false
			outcome["fog_dispelled"] = true
			_events.append({"t": "fog_dispelled", "text": monster.fog_text})
		# Тикающий урон прекращается на верном чтении ключевого сценария (GDD 4.7).
		if ticking_left > 0 and guess_scenario == monster.ticking_key_scenario:
			ticking_left = 0
			outcome["ticking_stopped"] = true
			_events.append({"t": "ticking_stopped", "text": monster.ticking_text})

		if combo_hit:
			outcome["combo_title"] = combo.title
			outcome["combo_effect"] = combo.effect_text
			var applied: PackedStringArray = PackedStringArray()
			if combo.status_id != &"":
				_apply_monster_status(combo.status_id, 2, combo.effect_text)
				applied.append(combo.effect_text)
			outcome["statuses_applied"] = applied
			_events.append({
				"t": "combo",
				"title": combo.title,
				"effect": combo.effect_text,
			})
		elif attack:
			# Подсказку о тупике (урон почти не проходит) при смене не считаем:
			# игрок и не бил, сравнивать нечего.
			_check_ineffective(dmg.total, outcome)

		# Контр-приём — реакция на серию верных чтений, а не на удар: он открывается
		# и в ход, потраченный на смену инструмента.
		_try_counter(outcome)
	else:
		# Промах: зверь бьёт своим сценарием. Броня смягчает урон и здесь (GDD 12.6),
		# кроме непробиваемых сценариев — от них спасает только чтение (GDD 4.4).
		player_reads.append(&"")
		if monster_statuses.has(STATUS_STUN):
			outcome["damage_to_hunter"] = 0
			outcome["hunter_damage_breakdown"] = "зверь оглушён и пропустил ход"
			_events.append({"t": "stun_skipped"})
		else:
			var taken := DamageCalc.monster_damage(monster, _current_scenario, hunter, false)
			hunter.take_damage(taken)
			outcome["damage_to_hunter"] = taken
			if _current_scenario.unblockable:
				outcome["hunter_damage_breakdown"] = "%d (сценарий %d, блок не работает)" % [
					taken, _scenario_damage()]
			else:
				outcome["hunter_damage_breakdown"] = "%d (сценарий %d − броня %d)" % [
					taken, _scenario_damage(), hunter.total_absorption()]
			_events.append({"t": "hunter_damaged", "amount": taken, "hp": hunter.hp})
		_ineffective_streak = 0

	_events.append({"t": "outcome", "outcome": outcome})
	log.append(outcome)

	# Конец раунда общий для всех путей: тикающий урон, «Второе дыхание», «Феникс»
	# и проверка смерти живут ТОЛЬКО здесь. Раньше блок тикающего урона был ещё и
	# в этом методе, то есть при пути «через чтение» он списывался дважды.
	_round_end(outcome)

	return outcome


## Смена инструмента БЕЗ хода: меняет оружие, которым игрок ответит, и ничего больше.
##
## Так смену делает экран: он берёт другое оружие и в ТОМ ЖЕ ходу отправляет ставку
## через `submit_read`. Отдельного «хода на смену» в игре нет, поэтому `cost_turn`
## здесь не нужен — режим «смена вместо удара» выражается параметром `attack` у
## `submit_read`, и он же единственное место, где расходуется навык «Быстрая смена».
##
## Раньше метод умел и то и другое (`cost_turn = true` со своей копией навыка и
## пропуском удара зверя). Копия оказалась недостижимой из игры: экран её не звал,
## и её проверяла только команда `--swap` — то есть проверка охраняла мёртвый путь
## и давала ложную уверенность.
func equip_weapon(new_weapon: WeaponData) -> void:
	if phase != PHASE_AWAIT_INPUT or new_weapon == null:
		return
	weapon = new_weapon
	_events.append({"t": "weapon_equipped", "weapon": String(new_weapon.id)})


## Завершение раунда: тикающий урон, спасение на грани смерти и проверки исхода.
## Вынесено из submit_read, чтобы ни один путь хода не дублировал эти правила.
func _round_end(outcome: Dictionary) -> void:
	# Тикающий урон (рой Пепел-Матери): капает в конце раунда, пока не сбит.
	if ticking_left > 0 and phase == PHASE_AWAIT_INPUT:
		ticking_left -= 1
		hunter.take_damage(monster.ticking_damage)
		outcome["ticking_damage"] = monster.ticking_damage
		_events.append({
			"t": "hunter_damaged",
			"amount": monster.ticking_damage,
			"hp": hunter.hp,
			"source": "ticking",
		})

	# Порядок проверок: сначала смерть зверя, потом смерть игрока — иначе
	# одновременный обмен ударами в одном раунде разрешался бы в пользу зверя.
	# Поэтому проверка охотника идёт веткой elif, а не внутри общего правила.
	if monster_hp <= 0:
		phase = PHASE_VICTORY
		_events.append({"t": "battle_end", "result": "victory", "rounds": round_index})
	elif hunter.hp <= 0:
		_handle_hunter_down(outcome)


## Забрать накопленные события. UI рендерит их, симулятор считает.
func take_events() -> Array[Dictionary]:
	var out := _events.duplicate(true)
	_events.clear()
	return out


func is_over() -> bool:
	return phase != PHASE_AWAIT_INPUT


func scenario_label_for(id: StringName) -> String:
	return _scenario_label(id)


func current_prose() -> Dictionary:
	return _current_prose


func current_scenario_id() -> StringName:
	return _current_scenario.id if _current_scenario != null else &""


## Метки опорных сигналов, показанных в прозе этого раунда. Это то, что игрок
## может занести в досье при верном чтении (GDD 5.2).
##
## Отдельной проверки статусов здесь нет намеренно: когда читать нечего (туман или
## слепота), строк в прозе не остаётся вовсе — их снимает advance_round. Второй
## механизм для того же самого стал бы вторым источником правды: однажды они
## разойдутся, и улики вернутся в досье «через чёрный ход».
func _core_signal_labels() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	if _current_prose.is_empty():
		return out
	for l in _current_prose["lines"]:
		if l["role"] == Phrase.ROLE_CORE:
			out.append(str(l["label"]))
	return out


## Метка ложного следа, который был в прозе. При промахе именно он уводит игрока
## в сторону, поэтому попадает в досье как «ложный след» (GDD 5.2).
func _shown_decoy_label() -> String:
	if _current_prose.is_empty():
		return ""
	for l in _current_prose["lines"]:
		if l["role"] == Phrase.ROLE_DECOY:
			return str(l["label"])
	return ""


# --------------------------------------------------------------------------
# Внутреннее
# --------------------------------------------------------------------------

## Комбо подбирается по СЦЕНАРИЮ и ДАЛЬНОСТИ оружия, а тип проверяется по ВСЕМ типам
## удара этого оружия.
##
## Почему не по одному «главному» типу, как было. У зачарованного оружия главным
## считался тип руны, и комбо, требующее базового подтипа, становилось недостижимым:
## наложив руну огня на молот, игрок терял комбо на дробящий — хотя урон по
## дробящему продолжал идти (руна ДОБАВЛЯЕТ тип, а не заменяет). Это то же
## расхождение «механика против подписи», что и в показе типа урона.
func _match_combo(scenario_id: StringName) -> ComboData:
	for c in monster.combos:
		if c.scenario_id != scenario_id:
			continue
		if c.required_range != &"any" and c.required_range != weapon.range_id:
			continue
		if c.required_type != &"any" and not weapon.damage_types().has(c.required_type):
			continue
		return c
	return null


func _scenario_label(id: StringName) -> String:
	var s := monster.find_scenario(id)
	if s != null:
		return s.card_label
	return String(id)


func _scenario_damage() -> int:
	if _current_scenario != null:
		return _current_scenario.damage_of(monster.base_damage)
	return monster.base_damage


## Пересчитать фазу зверя по текущему HP и сообщить о переходе (GDD 4.8).
## Фаза меняет шум, уязвимости и резисты — то есть правила раунда.
func _tick_phase() -> void:
	var phase_data := monster.phase_for_hp(monster_hp)
	var new_id := StringName(phase_data.get("id", ""))
	if new_id == current_phase_id:
		return
	current_phase_id = new_id
	if new_id == &"":
		return
	_events.append({
		"t": "phase_changed",
		"phase_id": new_id,
		"title": str(phase_data.get("title", "")),
		"note": str(phase_data.get("note", "")),
	})


## Текущая фаза зверя как словарь. Нужна симулятору и экрану.
func current_phase() -> Dictionary:
	return monster.phase_for_hp(monster_hp)


## Подсказка о тупике: если инструмент дважды подряд даёт минимальный урон,
## зверь сам показывает, что так его не взять. Это не подсказка о сценарии —
## только о бесполезности инструмента.
func _check_ineffective(damage: int, outcome: Dictionary) -> void:
	if damage <= INEFFECTIVE_DAMAGE:
		_ineffective_streak += 1
	else:
		_ineffective_streak = 0
	if _ineffective_streak >= INEFFECTIVE_HINT_THRESHOLD and not _hint_shown:
		_hint_shown = true
		var hint := "%s будто не замечает твоего удара: %s по нему почти не работает." % [
			monster.title,
			"%s, %s" % [CityData.range_ru(weapon.range_id, true), CityData.damage_type_names(weapon)],
		]
		outcome["hint"] = hint
		_events.append({"t": "hint", "text": hint})


## Контр-приём: игрок трижды подряд назвал один сценарий — зверь меняет повадку,
## и на один раунд его сигналы становятся нечитаемыми.
func _try_counter(outcome: Dictionary) -> void:
	if monster.counter_threshold <= 0:
		return
	if String(_current_scenario.id) in _counter_used_ids:
		return
	var streak := _player_repeat_streak()
	if streak < monster.counter_threshold:
		return
	_counter_used_ids[String(_current_scenario.id)] = true
	picker.mark_counter_used(_current_scenario.id, round_index)
	outcome["counter_title"] = monster.counter_title
	outcome["counter_text"] = monster.counter_text
	_events.append({
		"t": "counter",
		"title": monster.counter_title,
		"text": monster.counter_text,
		"scenario_id": _current_scenario.id,
	})


func _player_repeat_streak() -> int:
	if player_reads.is_empty():
		return 0
	var last: StringName = player_reads[player_reads.size() - 1]
	if last == &"":
		return 0
	var streak := 0
	for i in range(player_reads.size() - 1, -1, -1):
		if player_reads[i] == last:
			streak += 1
		else:
			break
	return streak


func _apply_monster_status(id: StringName, rounds: int, text: String) -> void:
	monster_statuses[id] = {"rounds": rounds, "text": text}


## Тик статусов зверя. Срок идёт ВНИЗ у всех, а побочный эффект — свой у каждого.
##
## Раньше это был набор копий на каждый статус: три почти одинаковых блока «уменьшить
## срок, записать событие, снять по нулю». С пятым статусом копий стало бы четыре, и
## каждый новый статус требовал бы не забыть три строки. Здесь срок и снятие — общие,
## а различается только то, что статус ДЕЛАЕТ.
##
## ВАЖНО: список STATUS_IDS описывает, что движок умеет, но НЕ равен этому циклу —
## туман обзора (`fog_active`) держится своим полем и снимается чтением ключевого
## сценария, а не сроком. Он идёт отдельной веткой ниже.
func _tick_statuses() -> void:
	for status_id in monster_statuses.keys():
		var st: Dictionary = monster_statuses[status_id]
		st["rounds"] = int(st["rounds"]) - 1

		match status_id:
			STATUS_STUN:
				_events.append({"t": "status_tick", "status": "stun",
					"text": "Зверь оглушён и пропускает ход."})
			STATUS_FREEZE:
				_events.append({"t": "status_tick", "status": "freeze",
					"text": "Зверь скован холодом."})
			STATUS_POISON:
				monster_hp = maxi(0, monster_hp - 1)
				_events.append({"t": "monster_damaged", "amount": 1,
					"hp": monster_hp, "source": "poison"})
			STATUS_BLIND:
				# Слепой зверь не выдаёт улик — это делает _core_signal_labels().
				# Здесь только сообщение, чтобы игрок понимал, почему проза пуста.
				_events.append({"t": "status_tick", "status": "blind",
					"text": "Зверь слеп и больше не подаёт знаков."})
			STATUS_OPEN:
				_events.append({"t": "status_tick", "status": "open",
					"text": "Зверь открыт: удар проходит глубже."})

		if int(st["rounds"]) <= 0:
			monster_statuses.erase(status_id)
			_events.append({"t": "status_ended", "status": String(status_id)})


## Названия типов и дистанций живут в CityData, и вызываются прямо оттуда.
##
## Локальных обёрток здесь больше нет намеренно. Они были без логики, но с
## РАЗНЫМ поведением по имени: здешняя range_ru() брала полную форму
## («ближний бой»), а точно так же названная в экране города — краткую.
## Одинаковое имя с разным смыслом опаснее дублирования: при переносе вызова
## между файлами он молча менял текст. Полная форма теперь видна на месте
## вызова: CityData.range_ru(id, true).


## Поток случайности на раунд. Механика и текст разведены солью: выбор
## инструмента игроком не должен сдвигать последовательность фраз.
func _round_rng(round: int, salt: StringName) -> RandomNumberGenerator:
	if seed_source != null:
		return seed_source.round_rng(round, salt)
	return RNGService.mechanics(round) if salt == &"mechanics" else RNGService.text(round)
