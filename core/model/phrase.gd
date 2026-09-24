extends RefCounted
class_name Phrase
## Одна фраза пула: готовое предложение для одного слота прозы.
##
## Фразы — это данные, а не строки в коде. Из них собирается проза, из них же
## берётся подсветка опорного сигнала (навык «Опорный сигнал») и удаление
## ложного следа (навык «Чистая проза»), поэтому роль и слот — обязательные поля.

const ROLE_CORE := &"core"
const ROLE_DECOY := &"decoy"

var id: String = ""
var monster_id: StringName = &""
var scenario_id: StringName = &""
var slot: StringName = &""
var role: StringName = ROLE_CORE
var text: String = ""
var weight: int = 10
var tags: PackedStringArray = PackedStringArray()


func key() -> String:
	return make_key(monster_id, scenario_id, slot, role)


static func make_key(
	monster_id: StringName,
	scenario_id: StringName,
	slot: StringName,
	role: StringName
) -> String:
	return "%s|%s|%s|%s" % [monster_id, scenario_id, slot, role]


static func from_record(rec: Dictionary) -> Phrase:
	var p := Phrase.new()
	p.id = str(rec.get("id", "")).strip_edges()
	p.monster_id = StringName(str(rec.get("monster", "")).strip_edges())
	p.scenario_id = StringName(str(rec.get("scenario", "")).strip_edges())
	p.slot = StringName(str(rec.get("slot", "")).strip_edges())
	p.role = StringName(str(rec.get("role", "core")).strip_edges())
	p.text = str(rec.get("text", "")).strip_edges()
	p.weight = maxi(1, int(str(rec.get("weight", "10")).strip_edges()))
	var tag_str := str(rec.get("tags", "")).strip_edges()
	if not tag_str.is_empty():
		p.tags = tag_str.split(";", false)
	return p
