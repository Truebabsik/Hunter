extends Control
## Экран боя. Тонкий слой: вся логика — в BattleEngine, здесь только показ.
##
## Трёхслойная схема:
##   ArtLayer  — фон и зверь. Сейчас пуст, картинки подключаются сюда без правок ядра.
##   HudLayer  — HP, статусы, карточки, инструмент.
##   ProseLayer — проза. Главное на экране (GDD 11.1).
##
## Экран собирает HuntResult, но НЕ применяет его: прогрессию меняет HuntResult.apply
## в корневом узле. Так прогрессию можно проверить одним headless-прогоном.

signal battle_finished(result: HuntResult)

const ART_MONSTER_SIZE := Vector2(420, 420)

var engine: BattleEngine
var hunter: HunterState
var monster: MonsterData
var weapon: WeaponData

# --- Узлы
var art_layer: ArtSlot
var monster_name_label: Label
var monster_hp_label: Label
var hunter_hp_label: Label
var round_label: Label
var prose_label: RichTextLabel
var cards_box: HBoxContainer
var tool_box: VBoxContainer
var result_label: RichTextLabel
var continue_button: Button
var escape_button: Button
## Кнопки смены оружия и руны: перестраиваются на каждом обновлении, потому что
## зависят от того, что куплено и что открыто.
var weapon_box: HBoxContainer
var rune_box: HBoxContainer
var hint_label: Label
## Строка «Быстрая смена готова»: навык не израсходован, смена не отнимет удар.
var free_swap_label: Label
## Окно досье в бою (навык «Досье в бою») и был ли он уже использован за этот бой.
var battle_dossier: DossierWindow
var dossier_used: bool = false

var selected_range: StringName = MonsterData.RANGE_RANGED
var selected_type: StringName = MonsterData.TYPE_PHYSICAL
var selected_guess: StringName = &""
var pending_outcome: Dictionary = {}
## Выбранный ответ на раунд: каким оружием и с какой руной бить. Клик по кнопке
## только ВЫБИРАЕТ, исполняет «ПОДТВЕРДИТЬ»: до хода игрок может передумать.
## Если `staged_weapon_id` не совпадает с текущим оружием, удар берёт его с собой.
var staged_weapon_id: StringName = &""
var staged_rune: StringName = &""

# --- Учёт для HuntResult
##
## Счётчики живут в core (BattleTally): число урона, промахов и идеальных чтений
## решает правило, а не экран. Отсюда их читает и достижение «без единого промаха».
var _tally := BattleTally.new()
var _dossier := DossierRecorder.new()

## Побег разрешён один раз за раунд: иначе кнопку можно долбить до успеха,
## и угроза смерти исчезает.
var _escaped_this_round: bool = false

## Для достижений: менял ли игрок инструмент и видел ли подсказку о тупике.
## Сменил ли игрок инструмент В ЭТОМ ХОДУ. Нужен для строки исхода: без неё
## непонятно, почему урон отличается от того, с чем раунд начинался.
var _switched_weapon: bool = false

## Сменил ли игрок инструмент ЗА ВЕСЬ БОЙ. Отдельный флаг, потому что первый
## сбрасывается каждый раунд, а итог охоты читается один раз в конце.
##
## Раньше отдельного флага не было, и достижение «Победа одним оружием» получало
## ЗНАЧЕНИЕ ПОСЛЕДНЕГО РАУНДА: hunt_result награждает, если switched_weapon ложно,
## а _on_continue обнуляет его при переходе к следующему раунду. То есть игрок мог
## менять оружие весь бой и всё равно получить достижение — достаточно было не
## менять его в последнем ходу.
var _switched_any_weapon: bool = false
var _saw_hint: bool = false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_ui()
	# Если экран открыли напрямую (не через город) — запускаем Хруза.
	if monster == null:
		setup_hunt(&"hruz", 0)


## Точка входа охоты: снаряжение и навыки берутся из GameState.
func setup_hunt(monster_id: StringName, order_rank: int) -> void:
	monster = Database.monster(monster_id)
	if monster == null:
		_show_fatal("Вид «%s» не загружен. Проверь content/monsters." % monster_id)
		return
	weapon = Database.weapon(GameState.equipped_weapon)
	if weapon == null:
		weapon = Database.weapon(&"bow")
	if weapon == null:
		_show_fatal("Оружие не загружено.")
		return

	# Сборка охотника — в core (SkillEffects.build_hunter): те же числа считает
	# прогон баланса, поэтому экран не может разойтись с ним в правилах навыков.
	# Раньше здесь стояли свои копии формул, и они уже разошлись: прогон не считал
	# бонус к побегу, а «Второе дыхание» и «Феникс» не включал никто.
	var armor: ArmorData = Database.armor(GameState.equipped_armor)
	hunter = SkillEffects.build_hunter(weapon, armor, GameState.has_skill(&"wpn_swap"))
	hunter.weapon_id = weapon.id

	# Досье в бою — расход на БОЙ, а не на забег: сбрасываем при входе в охоту.
	# Окно при этом переживает бой: оно привязано к экрану, а экран создаётся
	# заново на каждую охоту, так что отдельная уборка не нужна.
	dossier_used = false

	selected_range = weapon.range_id
	selected_type = CityData.effective_damage_type(weapon)
	selected_guess = &""
	pending_outcome = {}
	_tally.reset()
	_escaped_this_round = false
	_switched_weapon = false
	_switched_any_weapon = false
	staged_weapon_id = weapon.id
	staged_rune = weapon.rune_type
	_saw_hint = false
	_dossier.begin(monster, GameState.dossier_entry(monster_id))

	engine = BattleEngine.new()
	engine.setup(monster, hunter, weapon)

	monster_name_label.text = "%s, %s" % [monster.title, monster.epithet]
	monster_name_label.add_theme_color_override("font_color", monster.accent())
	_drain_events()
	_refresh()


# --------------------------------------------------------------------------
# Навыки
# --------------------------------------------------------------------------
#
# Формул эффектов здесь больше нет: они в core/model/skill_effects.gd, потому
# что их считает и прогон баланса. Экран ЗАПРАШИВАЕТ числа, а не решает их.
# Копии в экране уже разошлись с симулятором — прогон не знал про бонус побега,
# а «Второе дыхание» и «Феникс» не включались нигде.


# --------------------------------------------------------------------------
# Построение интерфейса
# --------------------------------------------------------------------------

func _build_ui() -> void:
	var root := MarginContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("margin_left", 24)
	root.add_theme_constant_override("margin_right", 24)
	root.add_theme_constant_override("margin_top", 16)
	root.add_theme_constant_override("margin_bottom", 16)
	add_child(root)

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 16)
	root.add_child(columns)

	# --- Левая колонка: арт-зона + карточка зверя
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(ART_MONSTER_SIZE.x + 40, 0)
	left.add_theme_constant_override("separation", 10)
	columns.add_child(left)

	art_layer = ArtSlot.new()
	art_layer.custom_minimum_size = ART_MONSTER_SIZE
	left.add_child(art_layer)

	monster_name_label = Label.new()
	monster_name_label.add_theme_font_size_override("font_size", 20)
	left.add_child(monster_name_label)

	monster_hp_label = Label.new()
	left.add_child(monster_hp_label)

	hunter_hp_label = Label.new()
	left.add_child(hunter_hp_label)

	round_label = Label.new()
	round_label.add_theme_color_override("font_color", Color("#8d8578"))
	left.add_child(round_label)

	# --- Правая колонка
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 10)
	columns.add_child(right)

	var prose_panel := PanelContainer.new()
	prose_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(prose_panel)

	var prose_margin := MarginContainer.new()
	prose_margin.add_theme_constant_override("margin_left", 16)
	prose_margin.add_theme_constant_override("margin_right", 16)
	prose_margin.add_theme_constant_override("margin_top", 12)
	prose_margin.add_theme_constant_override("margin_bottom", 12)
	prose_panel.add_child(prose_margin)

	prose_label = RichTextLabel.new()
	prose_label.bbcode_enabled = true
	prose_label.scroll_active = false
	prose_label.add_theme_font_size_override("normal_font_size", 18)
	prose_margin.add_child(prose_label)

	hint_label = Label.new()
	hint_label.add_theme_color_override("font_color", Color("#8d8578"))
	right.add_child(hint_label)

	var cards_title := Label.new()
	cards_title.text = "ЧТО ОН СДЕЛАЕТ?"
	cards_title.add_theme_color_override("font_color", Color("#8d8578"))
	right.add_child(cards_title)

	cards_box = HBoxContainer.new()
	cards_box.add_theme_constant_override("separation", 8)
	right.add_child(cards_box)

	var tool_title := Label.new()
	tool_title.text = "ЧЕМ БИТЬ?"
	tool_title.add_theme_color_override("font_color", Color("#8d8578"))
	right.add_child(tool_title)

	tool_box = VBoxContainer.new()
	tool_box.add_theme_constant_override("separation", 6)
	right.add_child(tool_box)

	# Строка состояния навыка «Быстрая смена»: пока он не израсходован, смена
	# оружия НЕ отнимает удар. Игрок должен знать это ДО хода, иначе навык
	# срабатывает «сам» и выглядит случайностью.
	free_swap_label = Label.new()
	free_swap_label.add_theme_color_override("font_color", Color("#d8b45a"))
	right.add_child(free_swap_label)

	# Действия хода: кнопка на каждое ОБЛАДАЕМОЕ оружие. Клик — это удар им же,
	# поэтому смена инструмента и удар происходят в одном ходу: сменил — бьёшь
	# новым. Руны живут на оружии, поэтому «ударить с руной» отдельная строка.
	weapon_box = HBoxContainer.new()
	weapon_box.add_theme_constant_override("separation", 6)
	right.add_child(weapon_box)

	# Смена руны на текущем оружии (GDD 12.3). Кнопки строятся по открытым
	# навыкам-рунам, поэтому до покупки навыка их просто нет.
	rune_box = HBoxContainer.new()
	rune_box.add_theme_constant_override("separation", 6)
	right.add_child(rune_box)

	result_label = RichTextLabel.new()
	result_label.bbcode_enabled = true
	result_label.fit_content = true
	result_label.custom_minimum_size = Vector2(0, 110)
	right.add_child(result_label)

	continue_button = Button.new()
	continue_button.text = "ПОДТВЕРДИТЬ"
	continue_button.disabled = true
	continue_button.pressed.connect(_on_continue)
	right.add_child(continue_button)

	# Побег доступен в любой момент (GDD 2.5) и показан рядом с ходом: игрок должен
	# видеть шанс, а не гадать. Плата за попытку — риск удара, а не потеря хода.
	escape_button = Button.new()
	escape_button.pressed.connect(_on_escape)
	right.add_child(escape_button)


# --------------------------------------------------------------------------
# Обновление
# --------------------------------------------------------------------------

func _drain_events() -> void:
	if engine == null:
		return
	for ev in engine.take_events():
		_handle_event(ev)


func _handle_event(ev: Dictionary) -> void:
	match ev["t"]:
		"combo":
			result_label.append_text("\n[color=#d8b45a]⚡ КОМБО: %s[/color]" % ev["title"])
			art_layer.flash_combo()
		"crit":
			result_label.append_text("\n[color=#d8b45a]КРИТ[/color]")
			art_layer.flash_combo()
		"monster_damaged":
			art_layer.flash_hit()
		"monster_stunned", "status_tick":
			art_layer.shake()
		"counter":
			result_label.append_text("\n[color=#c96a4a]🛡 КОНТР-ПРИЁМ: %s[/color]" % ev["title"])
			art_layer.shake()
		"fog_dispelled":
			art_layer.set_fog(false)
		"prose":
			art_layer.set_fog(bool(ev.get("fog", false)))


func _refresh() -> void:
	if engine == null:
		return
	var cap_note := ""
	if hunter.is_capped():
		cap_note = " (срез с %d)" % hunter.raw_absorption()
	monster_hp_label.text = "HP: %d / %d   панцирь %d" % [engine.monster_hp, monster.max_hp, monster.armor]
	hunter_hp_label.text = "Охотник HP: %d / %d   броня %d%s" % [
		hunter.hp, hunter.max_hp, hunter.total_absorption(), cap_note]
	# Срок богини и в бою: последние дни должны давить и здесь, а не только
	# в городе. После срока формулировка меняется — дальше ошибка последняя.
	var days := GameState.days_left()
	var deadline := "%d дн." % days if days > 0 else "СРОК ВЫШЕЛ"
	# Тип урона — с учётом руны: зачарованное оружие бьёт своим зачарованием,
	# а не базовым типом. Показываем ещё и саму руну, чтобы игрок видел,
	# что именно наложено, а не догадывался по названию типа.
	var rune_note := ""
	if weapon.rune_type != &"":
		rune_note = "  [руна: %s]" % CityData.rune_title(weapon.rune_type)
	round_label.text = "Раунд: %d   ·   %s (%s, %s)%s   ·   инициатива %d против %d   ·   %s" % [
		engine.round_index, weapon.title, CityData.range_ru(weapon.range_id),
		CityData.damage_types_title(weapon), rune_note,
		hunter.initiative(), monster.initiative, deadline]

	prose_label.text = _render_prose()
	# Арт следует за скрытым сценарием раунда: игрок видит ту же позу, что читает
	# в прозе. Контракт «сценарий → картинка» — прямое следствие GDD 3.2.
	var scenario_id := engine.current_scenario_id()
	if art_layer.current_scenario != scenario_id:
		art_layer.show_monster(
			monster,
			scenario_id,
			GameState.location_art_path(monster.id)
		)
		art_layer.set_fog(engine.fog_active)
	_build_cards()
	_build_tool()
	_build_actions()
	if pending_outcome.is_empty():
		continue_button.text = "ПОДТВЕРДИТЬ"
		continue_button.disabled = selected_guess == &""
	else:
		continue_button.text = "ПРОДОЛЖИТЬ" if not engine.is_over() else "ИТОГ"
		continue_button.disabled = false
	if engine.is_over():
		escape_button.visible = false
	else:
		escape_button.visible = true
		escape_button.disabled = not pending_outcome.is_empty()
		escape_button.text = "ПОБЕГ (шанс %d%%)" % roundi(engine.escape_chance() * 100.0)


## Проза с учётом навыков: опорные сигналы подсвечиваются, ложные следы скрываются.
## Данные для этого берутся из размеченной структуры — строку пришлось бы парсить.
##
## Когда читать нечего (туман обзора или слепота зверя), строк нет вовсе, и ядро
## кладёт готовый текст в `prose`. Его и показываем: пустая строка вместо
## «в тумане ничего не видно» оставила бы игрока без объяснения, почему проза
## исчезла. Подсветки в этом случае не бывает по построению — подсвечивать нечего.
func _render_prose() -> String:
	var prose: Dictionary = engine.current_prose()
	if prose.is_empty():
		return ""
	var lines: Array = prose.get("lines", [])
	if lines.is_empty():
		return str(prose.get("prose", ""))
	var highlight := SkillEffects.highlight_count()
	var hide_decoys := SkillEffects.hide_decoy_count()
	var core_seen := 0
	var decoy_hidden := 0
	var out: PackedStringArray = PackedStringArray()
	for l in lines:
		var text := str(l["text"])
		if l["role"] == Phrase.ROLE_CORE:
			if core_seen < highlight:
				text = "[color=#d8b45a][b]%s[/b][/color]" % text
			core_seen += 1
		else:
			if decoy_hidden < hide_decoys:
				decoy_hidden += 1
				continue
		out.append(text)
	return " ".join(out)


func _build_cards() -> void:
	for child in cards_box.get_children():
		child.queue_free()
	for scn in monster.scenarios:
		var b := Button.new()
		b.text = scn.card_label
		b.toggle_mode = true
		b.button_pressed = scn.id == selected_guess
		b.pressed.connect(_on_card_pressed.bind(scn.id))
		cards_box.add_child(b)


func _build_tool() -> void:
	for child in tool_box.get_children():
		child.queue_free()

	# Дальность и тип — справка, а не выбор. Раньше здесь были кнопки, которые
	# НЕ меняли оружие: нажав «БЛИЖНИЙ» с луком, игрок получал промах, потому что
	# дальность сверяется с оружием. Кнопка предлагала ошибку — теперь смену
	# оружия делают кнопки ниже, и она стоит хода (GDD 11.6).
	var tool_note := Label.new()
	tool_note.add_theme_color_override("font_color", Color("#8d8578"))
	# Справка про инструмент, которым игрок СОБИРАЕТСЯ ответить: выбранное оружие
	# может отличаться от того, что в руках, и справка обязана это показывать —
	# иначе игрок сверяется не с тем, чем ударит.
	var shown: WeaponData = Database.weapon(staged_weapon_id)
	if shown == null:
		shown = weapon
	if shown.rune_type != &"":
		tool_note.text = "%s · %s + %s (руна) · урон %d" % [
			CityData.range_ru(shown.range_id), CityData.type_ru(shown.damage_type),
			CityData.type_ru(shown.rune_type), shown.base_damage]
	else:
		tool_note.text = "%s · %s · урон %d" % [
			CityData.range_ru(shown.range_id), CityData.type_ru(CityData.effective_damage_type(shown)),
			shown.base_damage]
	tool_box.add_child(tool_note)


# --------------------------------------------------------------------------
# Реакции
# --------------------------------------------------------------------------

## Действия раунда: «чем отвечу». Клик по оружию ВЫБИРАЕТ ответ, а исполняет его
## «ПОДТВЕРДИТЬ» — потому что ответы разные по цене:
##
##   • ударить текущим оружием      — наносишь урон;
##   • взять другое оружие и ударить им — тоже урон, но инструмент меняется;
##   • сменить оружие/руну БЕЗ удара — урона нет: ход потрачен на смену.
##
## Выбор «сменить и не бить» — это и есть штраф за смену. Верное чтение при этом
## всё равно спасает от урона: знание защищает независимо от того, чем отвечал.
func _build_actions() -> void:
	for child in weapon_box.get_children():
		child.queue_free()
	for child in rune_box.get_children():
		child.queue_free()
	if engine.is_over() or not pending_outcome.is_empty():
		return

	var ready := selected_guess != &""
	free_swap_label.text = ("БЫСТРАЯ СМЕНА ГОТОВА: смена пройдёт вместе с ударом"
		if hunter.weapon_swap_free else "")

	# Оружие: строка «УДАРИТЬ» (взять и ударить) и строка «СМЕНИТЬ БЕЗ УДАРА».
	# Вторая нужна, чтобы смена была выбором, а не побочным эффектом удара.
	for id in GameState.owned_weapons:
		var w: WeaponData = Database.weapon(id)
		if w == null:
			continue
		var current := w.id == weapon.id
		var hit := Button.new()
		hit.text = "%s %s (%s, %s)" % [
			"УДАРИТЬ:" if current else "ВЗЯТЬ И УДАРИТЬ:",
			w.title, CityData.range_ru(w.range_id), CityData.damage_types_title(w)]
		hit.toggle_mode = true
		hit.button_pressed = staged_weapon_id == w.id
		hit.disabled = not ready
		hit.pressed.connect(_stage_attack.bind(w.id))
		weapon_box.add_child(hit)

		if not current:
			var swap := Button.new()
			swap.text = "СМЕНИТЬ БЕЗ УДАРА: %s" % w.title
			swap.disabled = not ready
			swap.pressed.connect(_submit_swap.bind(w))
			weapon_box.add_child(swap)

	# Руны: открытые навыками. Удар с руной — это удар текущим оружием, а смена без
	# удара — отдельная кнопка, как и у оружия.
	var known := SkillsData.known_runes(GameState.skills)
	for rune_type in known:
		var rb := Button.new()
		rb.text = "УДАРИТЬ С РУНОЙ: %s" % CityData.rune_title(rune_type).to_upper()
		rb.toggle_mode = true
		rb.button_pressed = weapon.rune_type == rune_type
		rb.disabled = not ready
		rb.pressed.connect(_stage_rune.bind(rune_type))
		rune_box.add_child(rb)
	if weapon.rune_type != &"":
		var off := Button.new()
		off.text = "СНЯТЬ РУНУ БЕЗ УДАРА"
		off.disabled = not ready
		off.pressed.connect(_submit_swap_rune.bind(&""))
		rune_box.add_child(off)

	# Навык «Досье в бою» (GDD 5.1, 29 навыков): заглянуть в свои записи посреди
	# боя. Один раз за бой — иначе досье под рукой всегда, и смотреть его перед
	# боем было бы незачем. Стоит НЕ хода: это чтение своих записей, а не действие
	# в бою. Показываем состояние кнопки словами, чтобы игрок понимал, почему
	# она молчит, а не искал поломку.
	if GameState.has_skill(&"read_dossier"):
		var db := Button.new()
		db.text = "ДОСЬЕ (УЖЕ СМОТРЕЛ)" if dossier_used else "ДОСЬЕ"
		db.disabled = dossier_used
		db.pressed.connect(_toggle_battle_dossier)
		rune_box.add_child(db)


## Открыть или закрыть досье прямо в бою. Содержимое — то же, что в городе и на
## подготовке: структуру собирает CityData.dossier_view(), окно её рисует. Экран
## боя своего досье не имеет и иметь не должен.
func _toggle_battle_dossier() -> void:
	if battle_dossier != null and battle_dossier.visible:
		battle_dossier.visible = false
		return
	if battle_dossier == null:
		battle_dossier = DossierWindow.new()
		battle_dossier.set_anchors_preset(Control.PRESET_FULL_RECT)
		battle_dossier.closed.connect(_on_battle_dossier_closed)
		add_child(battle_dossier)
	battle_dossier.setup(monster)
	battle_dossier.set_accept_text("ВЕРНУТЬСЯ В БОЙ")
	battle_dossier.visible = true
	# Расход один за бой — и он тратится В МОМЕНТ ПОКАЗА, а не при закрытии:
	# иначе игрок мог бы открыть досье и закрыть игру, оставив попытку.
	dossier_used = true
	_build_actions()


func _on_battle_dossier_closed() -> void:
	if battle_dossier != null:
		battle_dossier.visible = false


## Выбрать ответ «ударить этим оружием». Ничего не исполняет: исполняет
## «ПОДТВЕРДИТЬ». Так игрок может передумать до хода, ничего не потеряв.
func _stage_attack(weapon_id: StringName) -> void:
	staged_weapon_id = weapon_id
	_switched_weapon = weapon_id != weapon.id
	_refresh()


## Выбрать ответ «ударить с этой руной» на текущем оружии.
func _stage_rune(rune_type: StringName) -> void:
	staged_rune = rune_type
	_switched_weapon = rune_type != weapon.rune_type
	_refresh()


## Сменить оружие БЕЗ удара: ход потрачен на смену, урона нет. Верное чтение при
## этом защищает — это разбирает ядро (submit_read с attack = false).
func _submit_swap(w: WeaponData) -> void:
	if selected_guess == &"" or engine.is_over() or not pending_outcome.is_empty():
		return
	engine.equip_weapon(w)
	hunter.weapon_id = w.id
	GameState.equipped_weapon = w.id
	weapon = w
	staged_weapon_id = w.id
	_switched_weapon = true
	_submit_guess(false)

## Сменить или снять руну БЕЗ удара. Руна живёт на оружии, поэтому правим сам
## ресурс: иначе следующее обновление экрана вернуло бы старую.
func _submit_swap_rune(rune_type: StringName) -> void:
	if selected_guess == &"" or engine.is_over() or not pending_outcome.is_empty():
		return
	engine.equip_weapon(weapon)
	weapon.rune_type = rune_type
	staged_rune = rune_type
	_switched_weapon = true
	_submit_guess(false)


## Общий ход: отправить ставку и показать исход. Вынесено, чтобы удар оружием,
## удар руной и смена без удара считались одним и тем же путём.
## Отправить ставку и показать исход. Единственный путь хода: удар оружием, удар
## руной и смена без удара идут через него.
##
## Дальность и тип НЕ передаются в ядро: оно берёт их из оружия, которым игрок
## отвечает. Поля `selected_range`/`selected_type` остались только как справка для
## экрана — их читает режим `--smoke`.
func _submit_guess(attack: bool = true) -> void:
	selected_range = engine.weapon.range_id
	selected_type = CityData.effective_damage_type(engine.weapon)
	# Ход исполняется — значит смена инструмента, если она была, состоялась.
	# Ставим ЗА БОЙ здесь, в единственном пути хода, а не в трёх местах вызова:
	# иначе легко забыть одну ветку, и достижение снова начнёт врать.
	if _switched_weapon:
		_switched_any_weapon = true
	var outcome := engine.submit_read(selected_guess, attack)
	if outcome.is_empty():
		return
	_tally.add(outcome)
	_dossier.record(outcome)

	pending_outcome = outcome
	result_label.text = _format_outcome(outcome)
	_drain_events()
	_refresh()


func _on_card_pressed(scenario_id: StringName) -> void:
	selected_guess = scenario_id
	_refresh()


func _on_range_pressed(range_id: StringName) -> void:
	if selected_range != range_id:
		_switched_weapon = true
	selected_range = range_id
	_refresh()


## Попытка побега. Доступна и до хода, и после — но только один раз за раунд,
## иначе игрок просто долбил бы кнопку, пока не повезёт.
func _on_escape() -> void:
	if engine.is_over() or not pending_outcome.is_empty():
		return
	if _escaped_this_round:
		return
	_escaped_this_round = true
	var outcome := engine.attempt_escape()
	if outcome.is_empty():
		return
	hunter = engine.hunter
	if bool(outcome["success"]):
		result_label.text = "[b]ПОБЕГ[/b]\nЗверь потерял тебя из виду. Ты ушёл — без добычи, но живым."
		pending_outcome = outcome
	else:
		result_label.text = "[b]ПОБЕГ НЕ УДАЛСЯ[/b]\nЗверь успел ударить вдогонку: %d урона. Ход за тобой." % int(outcome["free_strike"])
	_drain_events()
	_refresh()


func _on_continue() -> void:
	if not pending_outcome.is_empty():
		pending_outcome = {}
		result_label.text = ""
		if engine.is_over():
			_finish()
			return
		engine.advance_round()
		_drain_events()
		selected_guess = &""
		_escaped_this_round = false
		# Ответ раунда сбрасывается на текущее оружие: выбор был на один ход.
		staged_weapon_id = weapon.id
		staged_rune = weapon.rune_type
		# Флаг «сменил инструмент» живёт один раунд: он показывает причину урона
		# в исходе этого хода, а не копится до конца боя.
		_switched_weapon = false
		_refresh()
		return

	if selected_guess == &"":
		return

	# Исполнить выбранный ответ. Если игрок выбрал другое оружие, оно встаёт в руку
	# ПЕРЕД ударом: ядро считает удар по тому оружию, что у него в `weapon`, поэтому
	# порядок здесь важен, а не косметичен.
	if staged_weapon_id != weapon.id:
		var prepared: WeaponData = Database.weapon(staged_weapon_id)
		if prepared != null:
			engine.equip_weapon(prepared)
			hunter.weapon_id = prepared.id
			GameState.equipped_weapon = prepared.id
			weapon = prepared
	if staged_rune != weapon.rune_type:
		weapon.rune_type = staged_rune
	_submit_guess()


func _format_outcome(o: Dictionary) -> String:
	var lines: PackedStringArray = PackedStringArray()
	var verdict := "ПРОМАХ"
	if o["reading"] == DamageCalc.Reading.PERFECT:
		verdict = "ИДЕАЛЬНОЕ ЧТЕНИЕ"
	elif o["reading"] == DamageCalc.Reading.COUNTER:
		verdict = "ПОЛНАЯ КОНТРАТАКА"
	elif o["reading"] == DamageCalc.Reading.PARTIAL:
		verdict = "ЧАСТИЧНОЕ ПРЕИМУЩЕСТВО"
	lines.append("[b]%s[/b]" % verdict)
	# Чем ударил: игрок выбрал инструмент в этом же ходу, и он мог отличаться от
	# того, с которым начинал раунд. Без этой строки непонятно, почему урон другой.
	if _switched_weapon:
		lines.append("Инструмент: [b]%s[/b] (%s, %s)" % [
			weapon.title, CityData.range_ru(weapon.range_id), CityData.damage_types_title(weapon)])
	if bool(o.get("free_swap", false)):
		# Навык «Быстрая смена»: смена состоялась И удар прошёл. Без этой строки
		# расход одноразового навыка выглядел бы как чудо.
		lines.append("[color=#d8b45a]Быстрая смена: инструмент сменён, и удар всё равно прошёл.[/color]")
	if bool(o.get("swap_only", false)):
		# Смена без удара: чтение верное, но ход потрачен на инструмент.
		lines.append("[color=#8d8578]Ход ушёл на смену инструмента — удара не было.[/color]")
	if bool(o["read_correct"]):
		lines.append("Ход зверя: [b]%s[/b] — прочитано верно." % o["scenario_label"])
		lines.append("Урон: %s" % o["damage_breakdown"])
	else:
		lines.append("Ты ждал «%s», а зверь сделал «%s»." % [o["guess_label"], o["scenario_label"]])
		lines.append("Урон тебе: %s" % o["hunter_damage_breakdown"])
		# Ложный след, который увёл: это то, что попадёт в досье.
		var decoy := str(o.get("fact_decoy", ""))
		if not decoy.is_empty():
			lines.append("[color=#8d8578]Тебя увёл ложный след: «%s».[/color]" % decoy)
	if not str(o.get("hint", "")).is_empty():
		_saw_hint = true
		lines.append("[color=#8d8578]%s[/color]" % o["hint"])
	# Подсказка о тупике держится на экране до конца боя: она про инструмент,
	# а не про текущий раунд.
	hint_label.text = str(o.get("hint", ""))
	return "\n".join(lines)


# --------------------------------------------------------------------------
# Итог
# --------------------------------------------------------------------------

func _finish() -> void:
	var result := HuntResult.new()
	result.monster_id = monster.id
	result.victory = engine.phase == BattleEngine.PHASE_VICTORY
	result.fled = engine.phase == BattleEngine.PHASE_FLED
	result.rounds = engine.round_index
	result.hp_left = hunter.hp
	# Числа боя переносит BattleTally: правило учёта одно на бой и на достижения.
	# Оружие — ЗА ВЕСЬ БОЙ, а не за последний ход: достижение «Победа одним оружием»
	# читает это поле один раз в конце, и флаг текущего хода дал бы ему ложную правду.
	_tally.apply_to(result, _switched_any_weapon, _saw_hint)
	# Что игрок делал в бою: нужно достижениям «без брони» и «одним оружием».
	result.had_armor = hunter.absorption > 0
	result.last_scenario_label = engine.scenario_label_for(engine.current_scenario_id())

	# Факты, накопленные за бой, записываем в досье и отдаём в итог.
	_dossier.commit()
	result.new_signals = _dossier.new_signals.duplicate()
	result.new_decoys = _dossier.new_decoys.duplicate()
	result.new_scenarios = _dossier.new_scenarios.duplicate()
	result.new_weaknesses = _dossier.new_weaknesses.duplicate()

	if result.victory:
		result.message = "Победа."
	elif result.fled:
		result.message = "Ты ушёл. Это не победа, но и не смерть."
	else:
		result.message = "Ты пал. Материя сгорела, знание осталось."
	battle_finished.emit(result)
	continue_button.disabled = true


## Снимок досье больше не нужен: DossierRecorder.begin сам берёт, что игрок знал,
## и считает новое относительно этого.
##
## Локальных _type_ru/_range_ru здесь больше нет: они были тонкими обёртками над
## CityData и всё равно разъехались — экран боя подписывал копьё «физикой», считая
## его колющим. Обёртка без логики не защищает от расхождения, а прячет его:
## вызов выглядит «своим». Теперь вызов идёт прямо в источник.


func _show_fatal(text: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", Color("#c96a4a"))
	add_child(l)
	push_error(text)
