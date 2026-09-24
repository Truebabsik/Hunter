extends Control
## Подготовка перед боем: выбор оружия и наложение рун (GDD 10.2, фаза 5).
##
## Зачем экран, если в бою оружие всё равно можно сменить в ходу. Здесь выбор
## СВОБОДЕН: можно думать, сверяться с досье и перебирать варианты. В бою смена
## тоже доступна, но удар в этом ходу будет уже новым оружием — то есть менять
## его посреди боя значит отказаться от подготовленного удара.
##
## Экран ничего не решает о механике: он показывает то, что уже открыто
## (купленное оружие и навыки-руны) и МЕНЯЕТ СОСТОЯНИЕ забега, а не правила боя.
## Правило «руна добавляет второй тип урона» живёт в DamageCalc.

signal prep_finished()

## Вид охоты: по нему берётся фон локации и цвет акцента.
var monster: MonsterData

var backdrop: TextureRect
var veil: ColorRect
var title_label: Label
var summary_label: RichTextLabel
var weapons_box: VBoxContainer
var runes_box: HBoxContainer
var start_button: Button
var dossier_button: Button
var dossier_window: DossierWindow


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build()
	_rebuild()


func _build() -> void:
	# Фон локации на весь экран: подготовка происходит там же, где охота.
	backdrop = TextureRect.new()
	backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	backdrop.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)

	veil = ColorRect.new()
	veil.color = Color(0.05, 0.05, 0.06, 0.70)
	veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(veil)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 60)
	margin.add_theme_constant_override("margin_right", 60)
	margin.add_theme_constant_override("margin_top", 40)
	margin.add_theme_constant_override("margin_bottom", 40)
	add_child(margin)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	# Колонка обязана ВПИСЫВАТЬСЯ в экран, а не расти по сумме минимумов детей.
	# Без EXPAND_FILL суммарная высота детей (досье в прокрутке + кнопки) выходит
	# больше 720, контейнер вылезает за низ, и кнопки уезжают за кадр — прокрутке
	# при этом нечего сжимать, потому что её минимум считается обязательным.
	col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(col)

	var progress := Label.new()
	progress.text = "СЛЕД · ПОДГОТОВКА"
	progress.add_theme_color_override("font_color", Color("#8d8578"))
	col.add_child(progress)

	title_label = Label.new()
	title_label.add_theme_font_size_override("font_size", 22)
	col.add_child(title_label)

	var hint := Label.new()
	hint.text = "Что взять в руку? В бою оружие можно сменить прямо в ходу — но удар будет уже им."
	hint.add_theme_color_override("font_color", Color("#8d8578"))
	col.add_child(hint)

	summary_label = RichTextLabel.new()
	summary_label.bbcode_enabled = true
	summary_label.fit_content = true
	summary_label.custom_minimum_size = Vector2(0, 120)
	summary_label.add_theme_font_size_override("normal_font_size", 18)
	col.add_child(summary_label)

	var weapons_title := Label.new()
	weapons_title.text = "ОРУЖИЕ"
	weapons_title.add_theme_color_override("font_color", Color("#d8b45a"))
	col.add_child(weapons_title)

	weapons_box = VBoxContainer.new()
	weapons_box.add_theme_constant_override("separation", 6)
	col.add_child(weapons_box)

	var runes_title := Label.new()
	runes_title.text = "РУНЫ НА ВЫБРАННОМ ОРУЖИИ"
	runes_title.add_theme_color_override("font_color", Color("#d8b45a"))
	col.add_child(runes_title)

	runes_box = HBoxContainer.new()
	runes_box.add_theme_constant_override("separation", 6)
	col.add_child(runes_box)

	# Распорка прижимает кнопки к низу, когда досье закрыто. С открытым досье она
	# больше ни с чем не делится: разбор живёт в отдельной панели.
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(spacer)

	start_button = Button.new()
	start_button.text = "К БОЮ"
	start_button.pressed.connect(func(): prep_finished.emit())
	col.add_child(start_button)

	# Досье — бесплатно и именно ЗДЕСЬ (GDD 5.1). Смотреть в свои записи перед
	# боем это не навык, а подготовка: досье даёт названия сценариев и сигналы,
	# то есть то, что охотник и так записал. Навык «Досье в бою» открывает
	# ДРУГОЕ — заглянуть в записи посреди боя, когда думать некогда.
	dossier_button = Button.new()
	dossier_button.text = "ДОСЬЕ"
	dossier_button.pressed.connect(_toggle_dossier)
	col.add_child(dossier_button)

	_build_dossier_window()


## Досье живёт в ОТДЕЛЬНОМ ОКНЕ на весь экран (DossierWindow), а не в колонке
## выбора.
##
## Почему так. Разбор по атакам длинный: у вида с тремя атаками это под 600
## пикселей. В колонке он не помещался вместе с разделами выбора: сколько ни
## подбирай минимумы, сумма детей больше 720, и низ экрана уезжал за кадр.
## Вариант «сжать прокрутку до остатка» давал полоску в 200 пикселей, где текст
## формально есть, а читать нечего.
##
## Почему отдельным компонентом, а не панелью здесь. То же окно открывается и из
## города. Две реализации одного досье — это ровно те грабли, из-за которых
## сборка текста уже переезжала в core (ARCHITECTURE §15).
func _build_dossier_window() -> void:
	dossier_window = DossierWindow.new()
	dossier_window.set_anchors_preset(Control.PRESET_FULL_RECT)
	dossier_window.visible = false
	dossier_window.closed.connect(_toggle_dossier)
	add_child(dossier_window)


## Фон и цвет берутся из локации вида. Вызывается корневым узлом после
## инстанцирования: до _ready() узлы сцены ещё не созданы.
func setup_location(mon: MonsterData) -> void:
	monster = mon
	if mon == null:
		return
	title_label.text = "Перед охотой: %s" % mon.title
	title_label.add_theme_color_override("font_color", mon.accent())
	var path := GameState.location_art_path(mon.id)
	if path.is_empty():
		return
	var tex: Texture2D = load(path)
	if tex != null:
		backdrop.texture = tex


## Перестроить экран из текущего состояния забега. Вызывается после каждой
## смены: держать список рассинхронизированным с состоянием — это ложь на экране.
func _rebuild() -> void:
	_rebuild_summary()
	_rebuild_weapons()
	_rebuild_runes()


func _rebuild_summary() -> void:
	var w: WeaponData = Database.weapon(GameState.equipped_weapon)
	var lines: PackedStringArray = PackedStringArray()
	if w != null:
		lines.append("[b]Сейчас в руке:[/b] %s — %s, урон %d" % [
			w.title, _hit_types_text(w), w.base_damage])
	else:
		lines.append("[b]Оружие не выбрано.[/b]")
	lines.append("")
	lines.append("[color=#8d8578]Руна добавляет второй тип урона: удар несёт и тип оружия, "
		+ "и тип руны, а уязвимости считаются по обоим.[/color]")
	summary_label.text = "\n".join(lines)


## Строка типов удара: базовый и, если есть, тип руны.
func _hit_types_text(w: WeaponData) -> String:
	if w.rune_type == &"":
		return CityData.type_ru(w.damage_type)
	return "%s + %s (руна)" % [CityData.type_ru(w.damage_type), CityData.type_ru(w.rune_type)]


func _rebuild_weapons() -> void:
	for child in weapons_box.get_children():
		child.queue_free()
	for id in GameState.owned_weapons:
		var w: WeaponData = Database.weapon(id)
		if w == null:
			continue
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var label := Label.new()
		var mark := "●" if w.id == GameState.equipped_weapon else "○"
		label.text = "%s %s — %s, урон %d" % [
			mark, w.title, _hit_types_text(w), w.base_damage]
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		if w.id != GameState.equipped_weapon:
			var b := Button.new()
			b.text = "ВЗЯТЬ"
			b.pressed.connect(_on_take.bind(w.id))
			row.add_child(b)
		weapons_box.add_child(row)


func _rebuild_runes() -> void:
	for child in runes_box.get_children():
		child.queue_free()
	var w: WeaponData = Database.weapon(GameState.equipped_weapon)
	if w == null:
		return
	var known := SkillsData.known_runes(GameState.skills)
	if known.is_empty():
		var tip := Label.new()
		tip.text = "Руны не открыты: их дают навыки ветки «Оружие»."
		tip.add_theme_color_override("font_color", Color("#8d8578"))
		runes_box.add_child(tip)
		return
	for rune_type in known:
		var rb := Button.new()
		rb.text = CityData.rune_title(rune_type).to_upper()
		rb.toggle_mode = true
		rb.button_pressed = w.rune_type == rune_type
		rb.pressed.connect(_on_rune.bind(rune_type))
		runes_box.add_child(rb)
	var off := Button.new()
	off.text = "БЕЗ РУНЫ"
	off.toggle_mode = true
	off.button_pressed = w.rune_type == &""
	off.pressed.connect(_on_rune.bind(&""))
	runes_box.add_child(off)


## Взять оружие в руку. Здесь бесплатно: подготовка не тратит ход.
func _on_take(weapon_id: StringName) -> void:
	GameState.equipped_weapon = weapon_id
	_rebuild()


## Наложить руну на текущее оружие. Руна живёт на ОРУЖИИ, поэтому меняем
## у ресурса: иначе следующая охота начнётся со старой руной.
func _on_rune(rune_type: StringName) -> void:
	var w: WeaponData = Database.weapon(GameState.equipped_weapon)
	if w == null:
		return
	w.rune_type = rune_type
	_rebuild()


## Открыть или закрыть окно досье по тому виду, на кого идём. Структуру окна
## собирает core (CityData.dossier_view), поэтому город и подготовка показывают
## одно и то же по построению, а не по договорённости.
func _toggle_dossier() -> void:
	if dossier_window.visible:
		dossier_window.visible = false
		dossier_button.text = "ДОСЬЕ"
		return
	dossier_window.setup(monster)
	dossier_window.set_accept_text("НАЧАТЬ ОХОТУ" if monster != null else "ЗАКРЫТЬ")
	dossier_window.visible = true
	dossier_button.text = "СКРЫТЬ ДОСЬЕ"
