extends Control
## Итог охоты. Один экран на пять состояний: победа, побег, падение,
## воскрешение, конец забега.
##
## Числа приходят уже применёнными (HuntResult.apply), здесь только показ:
## экран не имеет права менять прогрессию, иначе её нельзя будет проверить
## одним headless-прогоном. По той же причине экран НЕ решает, что показать:
## решение принимает Outcome.resolve, а сюда приходит готовое `outcome`.
##
## Почему один экран, а не пять сцен: пять сцен пришлось бы держать
## синхронными вручную, а рассинхронизация знаний в проекте уже была —
## два описания модификаторов в GDD (11.6 и 12.3).

signal continue_requested()

var result: HuntResult
## Какой из пяти экранов показывать. Ставит game_root до добавления в дерево.
var outcome: StringName = Outcome.VICTORY

var body: RichTextLabel
var headline: Label
var primary_button: Button

const HEADLINES := {
	&"victory": ["ПОБЕДА", "#d8b45a"],
	&"escape": ["ТЫ УШЁЛ", "#9fb08a"],
	&"defeat": ["ТЫ ПАЛ", "#c96a4a"],
	&"resurrection": ["ТЕБЯ ВЕРНУЛИ", "#c8b48a"],
	&"run_over": ["ЗАБЕГ ОКОНЧЕН", "#8d8578"],
}

const BUTTONS := {
	&"victory": "ПРОДОЛЖИТЬ",
	&"escape": "ПРОДОЛЖИТЬ",
	&"defeat": "ДАЛЬШЕ",
	&"resurrection": "ВЕРНУТЬСЯ В ГОРОД",
	&"run_over": "НОВЫЙ ЗАБЕГ",
}

## Сколько записей хроники показывать. Список обязательно ограничен и обрез
## обязан быть назван: молчаливое усечение читается как «хроника оборвалась».
const CHRONICLE_SHOWN := 40

## Разделы досье — для подсчёта накопленных фактов.
const DOSSIER_SECTIONS: Array[String] = ["signals", "decoys", "scenarios", "weaknesses", "combos"]


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build()
	_render()


func _build() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 60)
	margin.add_theme_constant_override("margin_right", 60)
	margin.add_theme_constant_override("margin_top", 40)
	margin.add_theme_constant_override("margin_bottom", 40)
	add_child(margin)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	margin.add_child(col)

	headline = Label.new()
	headline.add_theme_font_size_override("font_size", 24)
	col.add_child(headline)

	# Прокрутка обязательна: на конце забега приходит хроника, которая
	# не помещается на экран никогда.
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(scroll)

	body = RichTextLabel.new()
	body.bbcode_enabled = true
	body.fit_content = true
	body.custom_minimum_size = Vector2(0, 360)
	body.add_theme_font_size_override("normal_font_size", 18)
	scroll.add_child(body)

	primary_button = Button.new()
	primary_button.text = str(BUTTONS.get(outcome, "ПРОДОЛЖИТЬ"))
	primary_button.pressed.connect(_on_primary)
	col.add_child(primary_button)


func _render() -> void:
	var head: Array = HEADLINES.get(outcome, ["—", "#ffffff"])
	headline.text = str(head[0])
	headline.add_theme_color_override("font_color", Color(str(head[1])))
	primary_button.text = str(BUTTONS.get(outcome, "ПРОДОЛЖИТЬ"))
	if result == null:
		body.text = ""
		return
	match outcome:
		Outcome.ESCAPE:
			body.text = _text_escape()
		Outcome.DEFEAT:
			body.text = _text_defeat()
		Outcome.RESURRECTION:
			body.text = _text_resurrection()
		Outcome.RUN_OVER:
			body.text = _text_run_over()
		_:
			body.text = _text_victory()


func _mon_name() -> String:
	var mon: MonsterData = Database.monster(result.monster_id)
	return mon.title if mon != null else String(result.monster_id)


## Победа: награда и, что важнее, подтверждение чтения. Строка «Он задумывал»
## закрывает критерий GDD 13.2 — игрок должен видеть, что было на самом деле.
func _text_victory() -> String:
	var lines: PackedStringArray = PackedStringArray()
	lines.append("[b]%s[/b] — повержен" % _mon_name())
	lines.append("")
	lines.append("Слава: %+d" % result.glory_delta)
	# Добычи может не быть вовсе — тогда строку не показываем, а не печатаем
	# «Добыча:  → в ношу».
	if not result.trophies.is_empty():
		lines.append("Добыча: %s → в ношу" % ", ".join(result.trophies))
	if result.coins_gained > 0:
		lines.append("Ноша пополнилась на %d монет" % result.coins_gained)
	lines.append("")
	lines.append("[color=#d8b45a][b]ДОСЬЕ ПОПОЛНЕНО[/b][/color]")
	if not result.last_scenario_label.is_empty():
		lines.append("  Он задумывал: «%s»" % result.last_scenario_label)
	lines.append("  Новых фактов: %d" % result.dossier_gained)
	lines.append("")
	lines.append("Слава: %d / %d" % [GameState.glory, GameState.next_rank_glory()])
	return "\n".join(lines)


## Побег: не осуждаем. По GDD отступление стоит материи, а не репутации.
func _text_escape() -> String:
	var lines: PackedStringArray = PackedStringArray()
	lines.append("[b]%s[/b] — остался позади" % _mon_name())
	lines.append("")
	lines.append("Брошено добычи: %d монет" % result.bag_lost)
	lines.append("В ноше осталось: на %d монет" % GameState.bag_value())
	lines.append("[color=#9fb08a]Слава не пострадала: отступление не позор.[/color]")
	return "\n".join(lines)


## Падение: три удара по порядку боли. Ранг — настоящая цена, потому что
## жизнью игрок больше не платит (GDD 1.3.1).
func _text_defeat() -> String:
	var lines: PackedStringArray = PackedStringArray()
	lines.append("[b]%s[/b]" % _mon_name())
	lines.append("")
	lines.append("Монеты сгорели: %d" % result.coins_lost)
	lines.append("Ноша осталась там: %d" % result.bag_lost)
	lines.append("Слава: %+d" % result.glory_delta)
	if result.rank_down:
		lines.append("[color=#c96a4a][b]РАНГ ПОНИЖЕН: %s[/b][/color]" % GameState.rank_title())
		lines.append("Клеймо на знаке ранга.")
	else:
		lines.append("Ранг сохранён: %s" % GameState.rank_title())
	lines.append("")
	lines.append("[i]«Ты выжил. Гильдия помнит. Возвращайся.»[/i]")
	return "\n".join(lines)


## Воскрешение: уже не боль, а дар. Остаток дней обязателен — здесь срок
## становится осязаемым: игрок видит его прямо сейчас, а не «45 в начале забега».
func _text_resurrection() -> String:
	var lines: PackedStringArray = PackedStringArray()
	lines.append("Богиня не объясняет. Она просто не дала умереть.")
	lines.append("")
	var days := GameState.days_left()
	if days > 0:
		lines.append("[b]Осталось дней: %d[/b]" % days)
	else:
		lines.append("[color=#c96a4a][b]СРОК ВЫШЕЛ. Дольше она ждать не будет.[/b][/color]")
	lines.append("Этот поход стоил %d дн." % CityData.days_per_hunt())
	lines.append("")
	lines.append("Не сгорело:")
	lines.append("  • Досье: фактов %d" % _dossier_facts())
	lines.append("  • Навыков: %d" % GameState.skills.size())
	return "\n".join(lines)


## Конец забега: итог пути, а не «ты проиграл». Сводка говорит, ЧТО успел,
## хроника — КАК жил, поэтому она идёт после и в обратном порядке.
func _text_run_over() -> String:
	var lines: PackedStringArray = PackedStringArray()
	lines.append("Богиня больше не отвечает.")
	lines.append("")
	lines.append("Ранг: %s        Слава: %d" % [GameState.rank_title(), GameState.glory])
	lines.append("Прожито дней: %d из %d" % [GameState.day, GameState.SURVIVAL_DAYS])
	lines.append("Достижений: %d из %d" % [
		GameState.unlocked_achievements(), Achievements.total()])
	lines.append("")
	lines.append("[b]ХРОНИКА (%d записей)[/b]" % GameState.fame_log.size())
	var shown := 0
	for i in range(GameState.fame_log.size() - 1, -1, -1):
		if shown >= CHRONICLE_SHOWN:
			break
		var e: Dictionary = GameState.fame_log[i]
		lines.append("День %d  ▸ %s   %s" % [e["day"], str(e["kind"]).to_upper(), e["title"]])
		shown += 1
	if GameState.fame_log.size() > shown:
		lines.append("[color=#8d8578]…и ещё %d записей раньше[/color]" % (
			GameState.fame_log.size() - shown))
	return "\n".join(lines)


## Сколько фактов накоплено в досье по всем видам.
func _dossier_facts() -> int:
	var total := 0
	for id in GameState.dossier.keys():
		var e: Dictionary = GameState.dossier[id]
		for section in DOSSIER_SECTIONS:
			total += (e[section] as Array).size()
	return total


## Основная кнопка. Куда идти — решает game_root, здесь только сигнал:
## экран не имеет права знать о других экранах.
func _on_primary() -> void:
	continue_requested.emit()
