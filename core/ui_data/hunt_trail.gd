extends RefCounted
class_name HuntTrail
## Нарратив охоты между городом и боем (GDD 10).
##
## «След» — не подсказка: он не выдаёт сценарии зверя и не даёт игроку знаний.
## Его задача — связать город с боем и дать тон. Поэтому он не влияет на механику
## и не попадает в досье.

## Порядок фаз (GDD 10.2).
const PHASES: Array[StringName] = [&"exit", &"signs", &"approach", &"meeting"]

## Короткий «след» для побочной встречи (GDD 10.7).
const SIDE_PHASES: Array[StringName] = [&"side_alert", &"side_meeting"]

const TRAIL_PATH := "res://content/trails/trail.txt"

## Записи: массив {monster_id, phase, location, tone, text}
static var _entries: Array[Dictionary] = []
static var _loaded: bool = false


static func load_entries() -> void:
	_entries.clear()
	_loaded = true
	var text := FileAccess.get_file_as_string(TRAIL_PATH)
	if text.is_empty():
		push_warning("HuntTrail: пустой или недоступный %s" % TRAIL_PATH)
		return
	var cur: Dictionary = {}
	var buf: Array[String] = []
	for raw_line in text.split("\n"):
		var line := raw_line.strip_edges()
		if line.begins_with("=="):
			_flush(cur, buf)
			cur = _parse_header(line)
			buf = []
		elif line.is_empty() or line.begins_with("#") or line.begins_with("---"):
			continue
		else:
			buf.append(line)
	_flush(cur, buf)


static func _flush(cur: Dictionary, buf: Array[String]) -> void:
	if cur.is_empty() or buf.is_empty():
		return
	var entry := cur.duplicate()
	entry["text"] = " ".join(buf)
	_entries.append(entry)


static func _parse_header(line: String) -> Dictionary:
	# == monster_id | stage | location | tone
	var parts := line.substr(2).split("|")
	var out := {"monster_id": &"*", "phase": &"", "location": &"", "tone": &"первый"}
	if parts.size() > 0:
		out["monster_id"] = StringName(parts[0].strip_edges())
	if parts.size() > 1:
		out["phase"] = StringName(parts[1].strip_edges())
	if parts.size() > 2:
		out["location"] = parts[2].strip_edges()
	if parts.size() > 3:
		out["tone"] = parts[3].strip_edges()
	return out


## Собрать «след» для вида. is_repeat выбирает тон «знакомый» (GDD 10.6),
## side_encounter — короткий вариант из двух фаз.
static func build(monster: MonsterData, is_repeat: bool, side_encounter: bool, rng: RandomNumberGenerator) -> Array[Dictionary]:
	if not _loaded:
		load_entries()
	var tone := &"знакомый" if is_repeat else &"первый"
	var phases: Array[StringName] = SIDE_PHASES if side_encounter else PHASES
	var out: Array[Dictionary] = []
	for phase in phases:
		var text := _pick_text(monster.id, phase, tone, rng)
		if text.is_empty():
			continue
		out.append({
			"phase": phase,
			"title": phase_title(phase),
			"text": text,
		})
	return out


static func _pick_text(monster_id: StringName, phase: StringName, tone: StringName, rng: RandomNumberGenerator) -> String:
	if _entries.is_empty():
		return ""
	# Приоритет: точное совпадение вида → общая запись «*».
	var exact: Array[String] = []
	var generic: Array[String] = []
	for e in _entries:
		if e["phase"] != phase:
			continue
		if e["monster_id"] == monster_id and e["tone"] == tone:
			exact.append(str(e["text"]))
		elif e["monster_id"] == &"*" and e["tone"] == tone:
			generic.append(str(e["text"]))
	var pool: Array[String] = exact if not exact.is_empty() else generic
	if pool.is_empty():
		# Тона может не быть (например, у побочной встречи) — берём любой.
		for e in _entries:
			if e["phase"] == phase and (e["monster_id"] == monster_id or e["monster_id"] == &"*"):
				pool.append(str(e["text"]))
	if pool.is_empty():
		return ""
	return pool[rng.randi_range(0, pool.size() - 1)]


static func phase_title(phase: StringName) -> String:
	match phase:
		&"exit":
			return "ВЫХОД"
		&"signs":
			return "ПРИМЕТЫ"
		&"approach":
			return "ПРИБЛИЖЕНИЕ"
		&"meeting":
			return "ВСТРЕЧА"
		&"side_alert":
			return "ПОБОЧНАЯ ВСТРЕЧА"
		&"side_meeting":
			return "ПОБОЧНАЯ ВСТРЕЧА"
		_:
			return String(phase).to_upper()


## Локация вида — нужна для отображения «следа» и для арта фона.
static func location_for(monster_id: StringName) -> String:
	if not _loaded:
		load_entries()
	for e in _entries:
		if e["phase"] == &"meeting" and (e["monster_id"] == monster_id or e["monster_id"] == &"*"):
			return str(e["location"])
	return ""


## Сколько записей загружено — для валидатора.
static func entry_count() -> int:
	if not _loaded:
		load_entries()
	return _entries.size()


## Фазы, для которых есть отрывки — проверить, что у вида «след» вообще существует.
static func phases_for(monster_id: StringName) -> Dictionary:
	if not _loaded:
		load_entries()
	var out: Dictionary = {}
	for e in _entries:
		if e["monster_id"] == monster_id or e["monster_id"] == &"*":
			out[e["phase"]] = true
	return out
