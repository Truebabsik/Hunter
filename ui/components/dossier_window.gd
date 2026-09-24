extends Control
class_name DossierWindow
## Окно вида: слева зверь и его правила, справа — что он делает.
##
## Зачем отдельным компонентом. Досье открывается из ДВУХ мест (город и подготовка
## перед боем), и второй реализации быть не должно: расхождение между экранами уже
## было граблями этого проекта (см. ARCHITECTURE §15). Окно знает только про
## DossierView из core и про то, как его разложить.
##
## Почему не портянка текста. Первая версия печатала досье строками, и у вида с
## пятью атаками это 600+ пикселей текста: игрок листал, чтобы сопоставить улику с
## атакой. Здесь улики стоят прямо под своей атакой и всё помещается без прокрутки.
##
## Решает не окно, а core: `CityData.dossier_view()` собирает структуру, окно её
## только рисует. Поэтому проверять форму окна можно прогоном, а не глазами.

signal closed()

const LEFT_WIDTH := 380

var monster: MonsterData
var _view: Dictionary = {}

var _portrait: TextureRect
var _portrait_box: Control
var _title: Label
var _subtitle: Label
var _stats: Label
var _weak: RichTextLabel
var _lore: RichTextLabel
var _attacks_box: VBoxContainer
var _special_box: VBoxContainer
var _back_button: Button
var _accept_button: Button


func setup(mon: MonsterData) -> void:
	monster = mon
	_view = CityData.dossier_view(mon)
	_fill()


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build()
	if monster != null:
		_fill()


## Кнопка главного действия. На подготовке это «в бой», в городе — просто закрыть:
## окно не должно диктовать экрану, что делать дальше.
func set_accept_text(text: String) -> void:
	if _accept_button != null:
		_accept_button.text = text


func accept_button() -> Button:
	return _accept_button


## Раскладка: слева ЗВЕРЬ (портрет, числа, уязвимости, особые правила), справа
## ПОВЕДЕНИЕ (атаки во всю ширину).
##
## Почему так, а не наоборот. В узкой колонке (595 px) описания и улики
## переносятся на вторую строку, и три атаки Хруза занимают ~800 px — прокрутка
## возвращается. Во всю ширину (1224 px) тот же разбор укладывается примерно в
## 690 px и виден целиком: ради этого окно и делалось. Лор и правила при этом не
## теряются — им как раз хватает места под портретом.
func _build() -> void:
	var veil := ColorRect.new()
	veil.color = Color(0.03, 0.03, 0.04, 0.96)
	veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(veil)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	add_child(margin)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(col)

	# Верхняя полоса: назад слева, название рядом с ним.
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 16)
	col.add_child(top)

	_back_button = Button.new()
	_back_button.text = "← НАЗАД"
	_back_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_back_button.pressed.connect(func(): closed.emit())
	top.add_child(_back_button)

	var head := VBoxContainer.new()
	head.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_theme_constant_override("separation", 0)
	top.add_child(head)

	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 22)
	head.add_child(_title)

	_subtitle = Label.new()
	_subtitle.add_theme_color_override("font_color", Color("#8d8578"))
	head.add_child(_subtitle)

	# Основная часть: слева зверь, справа поведение.
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 24)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(body)

	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(LEFT_WIDTH, 0)
	left.add_theme_constant_override("separation", 8)
	body.add_child(left)

	# Кадр под портрет: фиксированная высота, чтобы числа не «прыгали» от того,
	# есть картинка или нет (у части видов портрет ещё не нарисован).
	_portrait_box = Control.new()
	_portrait_box.custom_minimum_size = Vector2(LEFT_WIDTH, 230)
	left.add_child(_portrait_box)

	_portrait = TextureRect.new()
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_portrait.set_anchors_preset(Control.PRESET_FULL_RECT)
	_portrait_box.add_child(_portrait)

	_stats = Label.new()
	_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	left.add_child(_stats)

	_weak = RichTextLabel.new()
	_weak.bbcode_enabled = true
	_weak.fit_content = true
	_weak.scroll_active = false
	_weak.add_theme_font_size_override("normal_font_size", 16)
	left.add_child(_weak)

	# Правила живут слева, под числами: это свойства ЗВЕРЯ, а не его атак.
	var special_scroll := ScrollContainer.new()
	special_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	special_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(special_scroll)

	_special_box = VBoxContainer.new()
	_special_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_special_box.add_theme_constant_override("separation", 8)
	special_scroll.add_child(_special_box)

	# Правая колонка: только разбор атак, во всю оставшуюся ширину.
	var right_scroll := ScrollContainer.new()
	right_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(right_scroll)

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 10)
	right_scroll.add_child(right)

	_lore = RichTextLabel.new()
	_lore.bbcode_enabled = true
	_lore.fit_content = true
	_lore.scroll_active = false
	_lore.add_theme_font_size_override("normal_font_size", 17)
	right.add_child(_lore)

	_attacks_box = VBoxContainer.new()
	_attacks_box.add_theme_constant_override("separation", 10)
	right.add_child(_attacks_box)

	var bottom := HBoxContainer.new()
	col.add_child(bottom)

	_accept_button = Button.new()
	_accept_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_accept_button.pressed.connect(func(): closed.emit())
	bottom.add_child(_accept_button)


## Разложить структуру по узлам. Всё, что здесь есть, приходит из core: если
## строка не появилась, значит её нет в данных, а не «забыли нарисовать».
func _fill() -> void:
	var ident: Dictionary = _view.get("identity", {})
	if ident.is_empty():
		_title.text = "Досье пусто"
		return

	_title.text = "%s, %s" % [ident["title"], ident["epithet"]]
	_subtitle.text = "Уровень досье: %s" % ident["level_title"]

	var stats: Dictionary = _view.get("stats", {})
	_stats.text = "HP %d · панцирь %d · бьёт на %d · инициатива %d" % [
		int(stats.get("hp", 0)), int(stats.get("armor", 0)),
		int(stats.get("damage", 0)), int(stats.get("initiative", 0))]

	_portrait.texture = monster.portrait
	_portrait.visible = monster.portrait != null
	if _portrait.visible:
		_portrait.scale = Vector2.ONE * monster.art_scale
		_portrait.pivot_offset = Vector2(LEFT_WIDTH, 140) * 0.5
		_portrait.position = monster.art_offset

	var lore := str(ident.get("lore", ""))
	_lore.text = ("[i]%s[/i]" % lore) if not lore.is_empty() else "[i]Гильдия не оставила записей.[/i]"

	_fill_attacks()
	_fill_special()
	_fill_weak()


func _fill_attacks() -> void:
	for child in _attacks_box.get_children():
		child.queue_free()

	var attacks: Array = _view.get("attacks", [])
	var unlearned := int(_view.get("unlearned", 0))
	if attacks.is_empty():
		_add_note(_attacks_box, "Ты ещё не связал ни одну улику с атакой.")
	else:
		for attack in attacks:
			_attacks_box.add_child(_attack_block(attack))

	if unlearned > 0:
		_add_note(_attacks_box, "Закрыто атак: %d. Их названия и улики откроются в бою." % unlearned)

	# Обманы, которые не принадлежат ни одной атаке: они подмешиваются в прозу
	# любой из них, поэтому «своей» атаки у них нет.
	var unbound: PackedStringArray = _view.get("unbound_decoys", PackedStringArray())
	if not unbound.is_empty():
		_add_note(_attacks_box, "Обманы без своей атаки (подмешиваются в любую): %s" % ", ".join(unbound))


## Блок одной атаки. Улики идут ПОД своей атакой: это и есть ответ на вопрос
## «что мне делать с тем, что я видел».
##
## Неизученная атака остаётся на своём месте ЗАКРЫТОЙ: название, описание,
## улики, обманы, комбо и урон заменяются знаками вопроса. Показывать её целиком
## нельзя — это и есть то, что игрок покупает боями, — а выбрасывать из списка
## нельзя тоже: тогда непонятно, сколько ещё осталось открыть.
func _attack_block(attack: Dictionary) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)

	var known := bool(attack["known"])
	var head := Label.new()
	head.add_theme_font_size_override("font_size", 19)
	head.add_theme_color_override("font_color", monster.accent())
	# Без процентов: частота атаки — внутренняя механика, а не то, что игроку
	# выдают на руки. Поведение читается по уликам и по боям.
	var label := str(attack["label"]) if known else _mask(str(attack["label"]))
	head.text = "• %s" % label
	box.add_child(head)

	if not known:
		_add_note(box, "    атаку ещё не связал с её уликами")
		var hidden_tail := Label.new()
		hidden_tail.add_theme_color_override("font_color", Color("#6f6a60"))
		hidden_tail.text = "    бьёт на ?"
		box.add_child(hidden_tail)
		return box

	# Описания атаки здесь НЕТ намеренно. В контенте у сценария есть
	# `description`, и оно дословно повторяло формулировки опорных сигналов
	# («припадает к земле»). Игрок читал его как подсказку и ждал в прозе не тот
	# признак: проза выдаёт ОДИН сигнал из списка, а описание статично. Строка
	# была одновременно бесполезной и обманчивой, поэтому в досье её нет.
	# Поле осталось в ScenarioData — оно нужно разбору после боя.
	for sig in (attack["signals"] as PackedStringArray):
		var sig_label := Label.new()
		sig_label.text = "    ▸ %s" % sig
		box.add_child(sig_label)

	var hidden := int(attack["hidden_signals"])
	if hidden > 0:
		var hidden_label := Label.new()
		hidden_label.add_theme_color_override("font_color", Color("#6f6a60"))
		hidden_label.text = "    (улик этой атаки не видел: %d)" % hidden
		box.add_child(hidden_label)

	for decoy in (attack["decoys"] as PackedStringArray):
		var decoy_label := Label.new()
		decoy_label.add_theme_color_override("font_color", Color("#a8846a"))
		decoy_label.text = "    обман: %s" % decoy
		box.add_child(decoy_label)

	for combo in (attack["combos"] as Array):
		var combo_label := Label.new()
		combo_label.add_theme_color_override("font_color", Color("#c8bfa8"))
		combo_label.text = "    КОМБО «%s»: %s, +%d — %s" % [
			combo["title"], combo["requirement"], int(combo["bonus"]), combo["effect"]]
		box.add_child(combo_label)
	if bool(attack["has_combo"]) and (attack["combos"] as Array).is_empty():
		_add_note(box, "    комбо к этой атаке ещё не открыто")

	# Броня вида уже показана в числах слева: повторять её под каждой атакой —
	# тратить строку на то, что игрок и так видит.
	var tail := "    бьёт на %d" % int(attack["damage"])
	if bool(attack["unblockable"]):
		tail += ". Блок НЕ спасает — только уворот"
	var tail_label := Label.new()
	tail_label.add_theme_color_override("font_color", Color("#6f6a60"))
	tail_label.text = tail
	box.add_child(tail_label)

	return box


## Заменить текст знаками вопроса, сохранив длину слов. Так видно, что название
## состоит из двух слов, но не видно самих слов: форма подсказки, а не подсказка.
func _mask(text: String) -> String:
	var out := PackedStringArray()
	for word in text.split(" "):
		if word.strip_edges().is_empty():
			continue
		out.append("?".repeat(maxi(1, word.length())))
	var result := " ".join(out)
	return result if not result.is_empty() else "???"


## Особые правила вида: туман, тлеющий урон, фазы, привыкание, контр-приём.
func _fill_special() -> void:
	for child in _special_box.get_children():
		child.queue_free()

	var special: Array = _view.get("special", [])
	if special.is_empty():
		return

	var head := Label.new()
	head.add_theme_font_size_override("font_size", 18)
	head.add_theme_color_override("font_color", Color("#c8866a"))
	head.text = "ОСОБЫЕ ПРАВИЛА"
	_special_box.add_child(head)

	for rule in special:
		var label := Label.new()
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.text = "⚠ %s: %s" % [rule["title"], rule["text"]]
		_special_box.add_child(label)


func _fill_weak() -> void:
	var bits := PackedStringArray()
	# Явный тип обязателен: `_view.get()` возвращает Variant, и вывод типа из него
	# здесь приравнен к ошибке парсинга (предупреждения = ошибки).
	var weak: PackedStringArray = _view.get("weaknesses", PackedStringArray())
	if weak.is_empty():
		bits.append("Уязвимостей нет.")
	else:
		bits.append("[b]Уязвим:[/b] %s." % ", ".join(weak))
	var res: PackedStringArray = _view.get("resists", PackedStringArray())
	if res.is_empty():
		bits.append("Резистов нет.")
	else:
		bits.append("[b]Резист:[/b] %s." % ", ".join(res))
	bits.append("[color=#8d8578]Огонь всегда +1 к урону.[/color]")
	_weak.text = "\n".join(bits)


func _add_note(parent: Node, text: String) -> void:
	var label := Label.new()
	label.add_theme_color_override("font_color", Color("#6f6a60"))
	label.text = text
	parent.add_child(label)
