extends Node
## Загрузка и валидация контента: виды-звери и пул фраз.
##
## Контент живёт в двух форматах намеренно:
##   content/monsters/*.tres — структура (типизировано, правится в инспекторе);
##   content/phrases/*.csv   — тексты (тысячи строк править в инспекторе нельзя).

const MONSTERS_DIR := "res://content/monsters"
const PHRASES_DIR := "res://content/phrases"

var monsters: Dictionary = {}                 ## monster_id:String -> MonsterData
var phrases: Dictionary = {}                  ## ключ "monster|scenario|slot|role" -> Array[Phrase]
var weapons: Dictionary = {}                  ## weapon_id -> WeaponData
var armors: Dictionary = {}                   ## armor_id -> ArmorData
var load_errors: Array[String] = []


func _ready() -> void:
	load_all()


func load_all() -> void:
	monsters.clear()
	phrases.clear()
	weapons.clear()
	armors.clear()
	load_errors.clear()
	_load_monsters()
	_load_weapons()
	_load_phrases()


func _load_monsters() -> void:
	for path in _list_files(MONSTERS_DIR, ".tres"):
		var res: Resource = load(path)
		if res == null:
			load_errors.append("не загрузился ресурс: %s" % path)
			continue
		if res is not MonsterData:
			load_errors.append("не MonsterData: %s" % path)
			continue
		var mon: MonsterData = res
		if mon.id == &"":
			load_errors.append("у вида пустой id: %s" % path)
			continue
		if monsters.has(String(mon.id)):
			load_errors.append("дубликат id вида: %s" % mon.id)
			continue
		monsters[String(mon.id)] = mon


func _load_weapons() -> void:
	for path in _list_files("res://content/weapons", ".tres"):
		var res: Resource = load(path)
		if res is WeaponData:
			var w: WeaponData = res
			weapons[String(w.id)] = w
		else:
			load_errors.append("не WeaponData: %s" % path)
	for path in _list_files("res://content/armor", ".tres"):
		var res: Resource = load(path)
		if res is ArmorData:
			var a: ArmorData = res
			armors[String(a.id)] = a
		else:
			load_errors.append("не ArmorData: %s" % path)


func _load_phrases() -> void:
	for path in _list_files(PHRASES_DIR, ".csv"):
		var text := FileAccess.get_file_as_string(path)
		if text.is_empty():
			load_errors.append("пустой или нечитаемый CSV: %s" % path)
			continue
		var rows := parse_csv(text)
		if rows.is_empty():
			load_errors.append("в CSV нет строк: %s" % path)
			continue
		var header: PackedStringArray = rows[0]
		for i in range(1, rows.size()):
			var row: PackedStringArray = rows[i]
			if row.size() == 1 and row[0].strip_edges().is_empty():
				continue
			if row.size() < header.size():
				load_errors.append("%s: строка %d короче заголовка" % [path, i + 1])
				continue
			var rec := {}
			for c in header.size():
				rec[header[c].strip_edges()] = row[c]
			var phrase := Phrase.from_record(rec)
			if phrase.text.is_empty():
				continue
			var bucket_key := phrase.key()
			if not phrases.has(bucket_key):
				phrases[bucket_key] = []
			var bucket: Array = phrases[bucket_key]
			bucket.append(phrase)


func monster(id: StringName) -> MonsterData:
	return monsters.get(String(id), null)


func weapon(id: StringName) -> WeaponData:
	return weapons.get(String(id), null)


func armor(id: StringName) -> ArmorData:
	return armors.get(String(id), null)


## Фразы под конкретный сигнал: вид + сценарий + слот + роль.
## Если для сценария фраз нет — берём общие фразы вида (ложные следы).
func phrases_for(
	monster_id: StringName,
	scenario_id: StringName,
	slot: StringName,
	role: StringName
) -> Array:
	var exact: Array = phrases.get(Phrase.make_key(monster_id, scenario_id, slot, role), [])
	if not exact.is_empty():
		return exact
	var generic: Array = phrases.get(Phrase.make_key(monster_id, &"", slot, role), [])
	return generic


## Синтаксический разбор CSV с поддержкой кавычек — FileAccess.get_csv_line здесь
## не подходит: он не даёт заголовок и плохо переносит запятые внутри текста.
static func parse_csv(text: String) -> Array:
	var rows: Array = []
	var row: PackedStringArray = PackedStringArray()
	var field := ""
	var in_quotes := false
	var i := 0
	var n := text.length()
	while i < n:
		var ch := text[i]
		if in_quotes:
			if ch == "\"":
				if i + 1 < n and text[i + 1] == "\"":
					field += "\""
					i += 2
					continue
				in_quotes = false
				i += 1
				continue
			field += ch
			i += 1
			continue
		match ch:
			"\"":
				in_quotes = true
				i += 1
			",":
				row.append(field)
				field = ""
				i += 1
			"\r":
				i += 1
			"\n":
				row.append(field)
				field = ""
				rows.append(row)
				row = PackedStringArray()
				i += 1
			_:
				field += ch
				i += 1
	if not field.is_empty() or row.size() > 0:
		row.append(field)
		rows.append(row)
	# нормализуем: убираем хвостовые пустые строки
	while rows.size() > 0 and rows[rows.size() - 1].size() == 1 and rows[rows.size() - 1][0].strip_edges().is_empty():
		rows.remove_at(rows.size() - 1)
	return rows


func _list_files(dir_path: String, suffix: String) -> PackedStringArray:
	var result: PackedStringArray = PackedStringArray()
	var dir := DirAccess.open(dir_path)
	if dir == null:
		load_errors.append("нет каталога: %s" % dir_path)
		return result
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if not dir.current_is_dir() and name.ends_with(suffix):
			result.append(dir_path.path_join(name))
		name = dir.get_next()
	dir.list_dir_end()
	result.sort()
	return result
