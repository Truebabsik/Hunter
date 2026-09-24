extends Control
## Экран «следа»: четыре фазы нарратива между городом и боем (GDD 10.2).
##
## След не влияет на механику — это сцена, которая готовит к бою. Поэтому здесь
## нет ни одной проверки и ни одного броска: только текст и «далее».

signal trail_finished()
signal trail_aborted()

var stages: Array[Dictionary] = []
## Вид охоты: по нему берётся фон локации и цвет акцента.
var monster: MonsterData

var backdrop: TextureRect
var veil: ColorRect
var title_label: Label
var prose_label: RichTextLabel
var progress_label: Label
var next_button: Button

var _index: int = 0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build()
	_show_stage(0)


func _build() -> void:
	# Фон локации на весь экран: «след» — это сцена, а не текст на пустоте.
	backdrop = TextureRect.new()
	backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	backdrop.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)

	veil = ColorRect.new()
	veil.color = Color(0.05, 0.05, 0.06, 0.62)
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
	col.add_theme_constant_override("separation", 16)
	margin.add_child(col)

	progress_label = Label.new()
	progress_label.add_theme_color_override("font_color", Color("#8d8578"))
	col.add_child(progress_label)

	title_label = Label.new()
	title_label.add_theme_font_size_override("font_size", 22)
	title_label.add_theme_color_override("font_color", Color("#d8cfc0"))
	col.add_child(title_label)

	prose_label = RichTextLabel.new()
	prose_label.bbcode_enabled = true
	prose_label.fit_content = true
	prose_label.add_theme_font_size_override("normal_font_size", 19)
	prose_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(prose_label)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	col.add_child(row)

	var back := Button.new()
	back.text = "ВЕРНУТЬСЯ В ГОРОД"
	back.pressed.connect(func(): trail_aborted.emit())
	row.add_child(back)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)

	next_button = Button.new()
	next_button.text = "ДАЛЬШЕ"
	next_button.pressed.connect(_on_next)
	row.add_child(next_button)


func _show_stage(index: int) -> void:
	if index >= stages.size():
		trail_finished.emit()
		return
	_index = index
	var s := stages[index]
	progress_label.text = "СЛЕД · %d из %d" % [index + 1, stages.size()]
	title_label.text = str(s.get("title", ""))
	# Абзац подаём как есть: это литературный текст, а не разметка.
	prose_label.text = str(s.get("text", ""))
	next_button.text = "К БОЮ" if index == stages.size() - 1 else "ДАЛЬШЕ"


## Фон берётся из локации вида. Вызывается корневым узлом перед показом.
func setup_location(mon: MonsterData) -> void:
	monster = mon
	if mon == null:
		return
	title_label.add_theme_color_override("font_color", mon.accent())
	var path := GameState.location_art_path(mon.id)
	if path.is_empty():
		return
	var tex: Texture2D = load(path)
	if tex != null:
		backdrop.texture = tex
		veil.color = Color(0.05, 0.05, 0.06, 0.55)


func _on_next() -> void:
	_show_stage(_index + 1)
