extends RefCounted
class_name Achievements
## Достижения гильдии (GDD 11.8, 8.7). Ровно 22, как в документе.
##
## Каждое — это запись со списком событий-признаков "kind:" и требованиями
## к счётчикам. Проверка идёт после каждой охоты: раз в охоту, а не в бою,
## потому что часть условий требует знания исхода забега.
##
## Слава за достижение начисляется один раз — по флагу в GameState.achievements.

## Порядок задаёт и порядок вывода на экране: сначала убийства, потом мастерство,
## потом серии, потом падения.
const LIST := [
	{"id": "kill_hruz", "title": "Хруз, береговой трущобник", "group": "УБИЙСТВА",
	 "glory": 1, "cond": "kills", "monster": "hruz"},
	{"id": "kill_shipun", "title": "Шипун, скользун-кочка", "group": "УБИЙСТВА",
	 "glory": 1, "cond": "kills", "monster": "shipun"},
	{"id": "kill_gromun", "title": "Громун, гривастая гарпуна", "group": "УБИЙСТВА",
	 "glory": 1, "cond": "kills", "monster": "gromun"},
	{"id": "kill_tleun", "title": "Тлеун, болотный ходячий панцирь", "group": "УБИЙСТВА",
	 "glory": 1, "cond": "kills", "monster": "tleun"},
	{"id": "kill_skorb", "title": "Скорб, костяная башня", "group": "УБИЙСТВА",
	 "glory": 1, "cond": "kills", "monster": "skorb"},
	{"id": "kill_ashmother", "title": "Пепел-Мать, роевая носительница", "group": "УБИЙСТВА",
	 "glory": 1, "cond": "kills", "monster": "ashmother"},
	{"id": "kill_lament", "title": "Ламент, коронованный пожиратель", "group": "УБИЙСТВА",
	 "glory": 1, "cond": "kills", "monster": "lament"},

	{"id": "first_perfect", "title": "Первое идеальное чтение", "group": "МАСТЕРСТВО",
	 "glory": 1, "cond": "counter", "counter": "perfect_reads", "at": 1},
	{"id": "perfect_25", "title": "25 идеальных чтений", "group": "МАСТЕРСТВО",
	 "glory": 2, "cond": "counter", "counter": "perfect_reads", "at": 25},
	{"id": "flawless", "title": "Победа без единого промаха", "group": "МАСТЕРСТВО",
	 "glory": 2, "cond": "counter", "counter": "kills_flawless", "at": 1},
	{"id": "no_armor", "title": "Победа без брони", "group": "МАСТЕРСТВО",
	 "glory": 2, "cond": "counter", "counter": "kills_no_armor", "at": 1},
	{"id": "one_weapon", "title": "Победа одним оружием", "group": "МАСТЕРСТВО",
	 "glory": 1, "cond": "counter", "counter": "kills_one_weapon", "at": 1},

	{"id": "streak_3", "title": "3 победы подряд", "group": "СЕРИИ",
	 "glory": 1, "cond": "streak", "at": 3},
	{"id": "streak_5", "title": "5 побед подряд", "group": "СЕРИИ",
	 "glory": 2, "cond": "streak", "at": 5},
	{"id": "streak_10", "title": "10 побед подряд", "group": "СЕРИИ",
	 "glory": 3, "cond": "streak", "at": 10},

	{"id": "first_fall", "title": "Первое падение", "group": "ПАДЕНИЯ И ВОССТАНОВЛЕНИЯ",
	 "glory": 0, "cond": "counter", "counter": "deaths", "at": 1},
	{"id": "first_recovery", "title": "Первое восстановление", "group": "ПАДЕНИЯ И ВОССТАНОВЛЕНИЯ",
	 "glory": 1, "cond": "log", "kind": "повышение", "after_fall": true},
	{"id": "recovery_beyond", "title": "Восстановление с превосхождением", "group": "ПАДЕНИЯ И ВОССТАНОВЛЕНИЯ",
	 "glory": 2, "cond": "counter", "counter": "recoveries_beyond", "at": 1},
	{"id": "lament_after_fall", "title": "Победа над Ламентом после падения", "group": "ПАДЕНИЯ И ВОССТАНОВЛЕНИЯ",
	 "glory": 5, "cond": "log", "kind": "победа", "monster": "lament", "after_fall": true},

	{"id": "no_hint", "title": "Победа, не увидев подсказки о тупике", "group": "ГИЛЬДИЯ",
	 "glory": 1, "cond": "counter", "counter": "kills_without_hint", "at": 1},
	{"id": "escapes_3", "title": "Три ухода живым", "group": "ГИЛЬДИЯ",
	 "glory": 1, "cond": "counter", "counter": "escapes", "at": 3},
	{"id": "no_potions_named_legend", "title": "Победа над легендарным зверем", "group": "ГИЛЬДИЯ",
	 "glory": 3, "cond": "counter", "counter": "kills_tier3", "at": 1},
]


## Проверить все достижения после охоты. Возвращает список id, открытых СЕЙЧАС.
## Слава начисляется здесь же: иначе порядок вызовов начнёт влиять на результат.
static func check_after_hunt(result: HuntResult) -> Array[String]:
	var opened: Array[String] = []
	for a in LIST:
		var id := str(a["id"])
		if GameState.achievements.has(id):
			continue
		if not _is_unlocked(a, result):
			continue
		GameState.achievements[id] = true
		var glory := int(a["glory"])
		if glory > 0:
			GameState.add_glory(glory)
			GameState.log_fame("достижение", "Достижение: %s" % a["title"],
				"Гильдия отметила твоё деяние.", glory)
		opened.append(id)
	return opened


static func _is_unlocked(a: Dictionary, result: HuntResult) -> bool:
	match str(a["cond"]):
		"kills":
			return GameState.kill_counts(StringName(a["monster"])) > 0
		"counter":
			var key := str(a["counter"])
			return int(GameState.counters.get(key, 0)) >= int(a["at"])
		"streak":
			return GameState.win_streak >= int(a["at"])
		"log":
			return _log_has(a, result)
	return false


## Поиск подходящего события в Хронике. after_fall требует, чтобы игрок
## к этому моменту уже падал: иначе «восстановление» не восстановление.
static func _log_has(a: Dictionary, result: HuntResult) -> bool:
	var want_kind := str(a.get("kind", ""))
	var want_monster := str(a.get("monster", ""))
	var after_fall := bool(a.get("after_fall", false))
	if after_fall and GameState.lowest_rank_after_fall < 0:
		return false
	for entry in GameState.fame_log:
		if str(entry["kind"]) != want_kind:
			continue
		if not want_monster.is_empty() and str(entry.get("monster", "")) != want_monster:
			continue
		return true
	# Событие текущей охоты ещё не записано в Хронику: проверяем сам результат.
	if want_kind == "победа" and result.victory:
		if not want_monster.is_empty() and String(result.monster_id) != want_monster:
			return false
		return true
	return false


static func by_group() -> Dictionary:
	var out: Dictionary = {}
	for a in LIST:
		var g := str(a["group"])
		if not out.has(g):
			out[g] = []
		out[g].append(a)
	return out


static func find(id: StringName) -> Dictionary:
	for a in LIST:
		if StringName(a["id"]) == id:
			return a
	return {}


static func total() -> int:
	return LIST.size()
