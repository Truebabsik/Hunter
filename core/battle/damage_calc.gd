extends RefCounted
class_name DamageCalc
## Единственное место, где считаются формулы урона. Реализация — по GDD 12.5 и 12.6
## в редакции от 2026-09-22 (правки внесены в документ, см. gdd_pravki.md).

enum Reading { MISS, PARTIAL, COUNTER, PERFECT }


## Урон игрока (GDD 12.5):
##   оружие + модификатор + чтение + комбо − панцирь зверя − резист
## где «модификатор + резист» сведены в type_multiplier:
##   огонь +1 всегда; уязвимость +1; резист по типу −N; резист по дальности −N.
##
## phase — активная фаза зверя (GDD 4.8). Фаза может давать уязвимость
## и снимать резист: «в истощении он открыт».
##
## `target_open` — на звере статус «открыт» (комбо Тлеуна «Гашение»): любой удар
## проходит на 1 глубже, независимо от типа. Это НЕ уязвимость: она не привязана
## к типу и складывается с ним.
static func player_damage(
	weapon: WeaponData,
	monster: MonsterData,
	reading: Reading,
	combo_hit: bool,
	combo_bonus: int,
	perfect_read_bonus: int,
	phase: Dictionary = {},
	crit_chance: float = 0.0,
	rng: RandomNumberGenerator = null,
	target_open: bool = false
) -> DamageResult:
	var r := DamageResult.new()
	r.weapon_damage = weapon.base_damage

	match reading:
		Reading.PERFECT:
			r.reading_bonus = 1 + perfect_read_bonus
		Reading.COUNTER:
			r.reading_bonus = 1
		_:
			r.reading_bonus = 0

	if combo_hit and reading == Reading.PERFECT:
		r.combo_bonus = combo_bonus

	# Крит (GDD 7.3): навык даёт шанс, множитель — +50% базового урона оружия.
	# Считается от оружия, а не от итога: иначе крит усиливал бы и чтение, и комбо,
	# и один удачный бросок решал бы бой.
	if crit_chance > 0.0 and rng != null and rng.randf() < crit_chance:
		r.crit = true
		r.crit_bonus = maxi(1, int(round(float(weapon.base_damage) * 0.5)))

	# --- типовой множитель: уязвимости и резисты вида по БАЗОВОМУ типу и по руне
	r.type_multiplier = 0

	var weak_types := monster.weakness_types
	var weak_ranges := monster.weakness_ranges
	# Фаза переопределяет уязвимости, если они у неё заданы.
	if phase.has("weak_types"):
		weak_types = PackedStringArray(phase["weak_types"])
		weak_ranges = PackedStringArray(phase.get("weak_ranges", []))
		r.type_reasons.append("фаза: %s" % str(phase.get("title", "")))

	# Руна ДОБАВЛЯЕТ второй тип, а не заменяет базовый (GDD 12.3): удар несёт
	# и базовый тип оружия, и тип руны, а уязвимости с резистами считаются
	# по ОБОИМ. Иначе руна могла бы сделать хуже — снять физическую уязвимость
	# и добавить ледяной резист.
	var hit_types: Array[StringName] = [weapon.damage_type]
	if weapon.rune_type != &"" and weapon.rune_type != weapon.damage_type:
		hit_types.append(weapon.rune_type)

	var phase_has_resist := phase.has("resist_types") or phase.has("resist_ranges")
	for hit_type in hit_types:
		var is_rune := hit_type != weapon.damage_type
		var mark := " (руна)" if is_rune else ""

		# Огонь как тип даёт +1 всегда, независимо от вида (GDD 12.3).
		if hit_type == MonsterData.TYPE_FIRE:
			r.type_multiplier += 1
			r.type_reasons.append("огонь +1%s" % mark)

		if weak_types.has(String(hit_type)):
			r.type_multiplier += 1
			r.type_reasons.append("слабость: %s +1%s" % [CityData.type_ru(hit_type), mark])

		# Резисты фазы заменяют резисты вида целиком: в истощении зверь теряет защиту.
		var type_res := 0
		if phase_has_resist:
			type_res = int((phase.get("resist_types", {}) as Dictionary).get(String(hit_type), 0))
		else:
			type_res = monster.type_resist_for(hit_type)
		if type_res > 0:
			r.type_multiplier -= type_res
			r.type_reasons.append("резист: %s −%d%s" % [CityData.type_ru(hit_type), type_res, mark])

	# Дальность — свойство оружия, руна её не меняет, поэтому проверяется один раз.
	if weak_ranges.has(String(weapon.range_id)):
		r.type_multiplier += 1
		r.type_reasons.append("слабость: %s +1" % CityData.range_ru(weapon.range_id))

	var range_res := 0
	if phase_has_resist:
		range_res = int((phase.get("resist_ranges", {}) as Dictionary).get(String(weapon.range_id), 0))
	else:
		range_res = monster.range_resist_for(weapon.range_id)
	if range_res > 0:
		r.type_multiplier -= range_res
		r.type_reasons.append("резист: %s −%d" % [CityData.range_ru(weapon.range_id), range_res])

	r.monster_armor = monster.armor

	# «Открыт»: зверь пропустил защиту, любой удар идёт глубже на 1. В разбор
	# попадает отдельным слагаемым (DamageResult.open_bonus) — второй записи в
	# type_reasons быть не должно, иначе строка называет одно и то же дважды.
	if target_open:
		r.open_bonus = 1

	var raw := (
		r.weapon_damage
		+ r.reading_bonus
		+ r.combo_bonus
		+ r.type_multiplier
		+ r.crit_bonus
		+ r.open_bonus
		- r.monster_armor
	)
	# Минимум 1: непроходимых из-за округления боёв нет (GDD 12.5, п. 53–57).
	r.min_clamped = raw < 1
	r.total = maxi(1, raw)
	return r


## Урон зверя (GDD 12.6): базовый урон или урон сценария − броня игрока.
## Панцирь зверя на его собственный урон не влияет.
##
## Особый случай: сценарий может быть непробиваемым (GDD 4.4, «Вой-паралич не
## пробивается блоком»). Тогда броня не помогает вообще — спасает только чтение.
static func monster_damage(
	monster: MonsterData,
	scenario: ScenarioData,
	hunter: HunterState,
	softened: bool
) -> int:
	var base := monster.base_damage
	if scenario != null:
		base = scenario.damage_of(monster.base_damage)
	if softened:
		# «Частичное преимущество»: сценарий прочитан, инструмент — нет.
		# Зверь бьёт ослабленно (GDD 2.4).
		base = maxi(1, base - 1)
	if scenario != null and scenario.unblockable:
		return maxi(0, base)
	return maxi(0, base - hunter.total_absorption())


## Ожидаемый урон за раунд — только для симулятора и диагностики «стен чтения».
## Не участвует в боевых расчётах: бой всегда считает по факту.
static func expected_damage_per_round(weapon: WeaponData, monster: MonsterData) -> float:
	var d := player_damage(
		weapon,
		monster,
		Reading.COUNTER,
		false,
		0,
		0
	)
	return float(d.total)
