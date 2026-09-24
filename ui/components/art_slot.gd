extends Control
class_name ArtSlot
## Слот арта для экрана боя: фон локации, силуэт зверя, эффекты по событиям.
##
## Ключевое требование: слот работает и БЕЗ картинок. Если текстуры нет, рисуется
## подпись вида цветом акцента — поэтому игра не ломается ни на одном виде, даже
## если арт ещё не нарисован. Ядро о графике не знает вообще: оно отдаёт
## сценарий, а слот сам решает, что показать.

## Сколько держится подсветка попадания.
const FLASH_TIME := 0.12

var backdrop: TextureRect
var silhouette: TextureRect
var placeholder: Label
var accent_bar: ColorRect

## Текущий сценарий — по нему выбирается поза (контракт «сценарий → картинка»).
var current_scenario: StringName = &""
var monster: MonsterData

var _base_position: Vector2 = Vector2.ZERO
var _shake_tween: Tween
var _flash_tween: Tween


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	backdrop = TextureRect.new()
	backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	backdrop.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)

	var veil := ColorRect.new()
	veil.name = "Veil"
	veil.color = Color(0.05, 0.05, 0.06, 0.35)
	veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(veil)

	silhouette = TextureRect.new()
	silhouette.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	silhouette.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	silhouette.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(silhouette)

	placeholder = Label.new()
	placeholder.set_anchors_preset(Control.PRESET_FULL_RECT)
	placeholder.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	placeholder.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	placeholder.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	placeholder.add_theme_font_size_override("font_size", 16)
	add_child(placeholder)

	accent_bar = ColorRect.new()
	accent_bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	accent_bar.custom_minimum_size = Vector2(0, 4)
	accent_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(accent_bar)

	_base_position = silhouette.position


## Показать вид. backdrop_path — фон локации, может быть пустым.
func show_monster(mon: MonsterData, scenario_id: StringName, backdrop_path: String = "") -> void:
	monster = mon
	current_scenario = scenario_id
	if mon == null:
		return

	var art: Texture2D = mon.by_scenario.get(String(scenario_id), null)
	if art == null:
		art = mon.portrait
	silhouette.texture = art
	silhouette.visible = art != null

	# Плейсхолдер вместо картинки: он должен читаться как «здесь будет арт»,
	# а не как ошибка. Цвет вида делает виды различимыми уже сейчас.
	placeholder.visible = art == null
	if art == null:
		placeholder.text = "%s\n%s\n\n%s" % [
			mon.title, mon.epithet, GameState.art_stub_note()]
		placeholder.add_theme_color_override("font_color", mon.accent())

	# Масштаб и смещение вида: массивный Хруз и низкий Шипун должны отличаться.
	silhouette.scale = Vector2.ONE * mon.art_scale
	silhouette.pivot_offset = size * 0.5
	silhouette.position = _base_position + mon.art_offset

	accent_bar.color = mon.accent()
	if not backdrop_path.is_empty():
		var bg: Texture2D = load(backdrop_path)
		if bg != null:
			backdrop.texture = bg
			backdrop.visible = true


## Зверь получил урон.
func flash_hit() -> void:
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	silhouette.modulate = Color(1.6, 0.7, 0.7)
	_flash_tween = create_tween()
	_flash_tween.tween_property(silhouette, "modulate", Color.WHITE, FLASH_TIME)


## Зверь оглушён или заморожен: короткая тряска.
func shake() -> void:
	if _shake_tween != null and _shake_tween.is_valid():
		_shake_tween.kill()
	var origin := silhouette.position
	_shake_tween = create_tween()
	for offset in [Vector2(6, 0), Vector2(-6, 2), Vector2(4, -2), Vector2.ZERO]:
		_shake_tween.tween_property(silhouette, "position", origin + offset, 0.05)


## Комбо: золотая вспышка.
func flash_combo() -> void:
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	silhouette.modulate = Color(1.5, 1.3, 0.6)
	_flash_tween = create_tween()
	_flash_tween.tween_property(silhouette, "modulate", Color.WHITE, 0.25)


## Сброс затемнения: туман обзора накладывается извне через set_fog.
func set_fog(active: bool) -> void:
	var veil := get_node_or_null("Veil") as ColorRect
	if veil != null:
		veil.color = Color(0.55, 0.58, 0.52, 0.55) if active else Color(0.05, 0.05, 0.06, 0.35)
