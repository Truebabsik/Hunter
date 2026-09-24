extends Control
## Город: пять локаций (GDD 9.1) и доска заказов.
##
## Каждая локация — вкладка в одной панели. Логика цен и требований живёт
## в CityData, здесь только показ и нажатия.

signal order_taken(monster_id: StringName, order_rank: int, side_encounter: bool)
signal quit_requested()

var content: VBoxContainer
var status_label: Label
var log_label: RichTextLabel
var current_tab: String = ""

## Какая из трёх «бумажных» вкладок открыта внутри гильдии (GDD 11.8).
var guild_view: String = "board"
## Фильтр экрана истории: Все / Победы / Смерти / Повышения / Откаты.
var history_filter: String = "все"

## Фон локации. Пусто, пока арт не нарисован: тогда экран остаётся на тёмном фоне.
var backdrop: TextureRect
var veil: ColorRect
## Окно вида для досье: одно на экран, создаётся при первом открытии.
var dossier_window: DossierWindow

## Какую мысль Старика игрок уже купил: monster_id -> true.
var advice_bought: Dictionary = {}


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build()
	_show_tab("guild")


func _build() -> void:
	# Фон локации: слой под всем интерфейсом. Если файла нет — просто не появится.
	backdrop = TextureRect.new()
	backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	backdrop.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)

	veil = ColorRect.new()
	veil.color = Color(0.05, 0.05, 0.06, 0.68)
	veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(veil)

	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 10)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 14)
	margin.add_child(root)
	add_child(margin)

	status_label = Label.new()
	status_label.add_theme_font_size_override("font_size", 18)
	root.add_child(status_label)

	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 6)
	for pair in [
		["guild", "ГИЛЬДИЯ"], ["market", "РЫНОК"], ["master", "МАСТЕР"],
		["dossier", "ДОСЬЕ"], ["tavern", "ТАВЕРНА"],
	]:
		var b := Button.new()
		b.text = pair[1]
		b.pressed.connect(_show_tab.bind(pair[0]))
		tabs.add_child(b)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs.add_child(spacer)
	var quit_btn := Button.new()
	quit_btn.text = "ВЫХОД"
	quit_btn.pressed.connect(func(): quit_requested.emit())
	tabs.add_child(quit_btn)
	root.add_child(tabs)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(scroll)

	content = VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 8)
	scroll.add_child(content)

	log_label = RichTextLabel.new()
	log_label.bbcode_enabled = true
	log_label.fit_content = true
	log_label.custom_minimum_size = Vector2(0, 70)
	root.add_child(log_label)


func _refresh_status() -> void:
	var to_next := GameState.glory_to_next()
	var next_text := "максимум" if to_next < 0 else str(to_next)
	# Срок богини (GDD 1.3.1) стоит первым: это не ещё одна цифра, а условие,
	# на котором держится весь забег. Поэтому он всегда на виду — и меняет
	# формулировку, когда благодать кончилась.
	var days := GameState.days_left()
	var deadline := "СРОК: %d дн." % days if days > 0 else "СРОК ВЫШЕЛ — смерть окончательна"
	status_label.text = "%s   Ранг: %s [%s]   Слава: %d / %d   Монеты: %d" % [
		deadline, GameState.rank_title(), GameState.rank_sign(), GameState.glory,
		GameState.next_rank_glory(), GameState.coins]
	# Когда срок вышел, цифра перестаёт быть цифрой — её надо заметить.
	status_label.add_theme_color_override("font_color",
		Color(0.85, 0.30, 0.25) if days <= 0 else Color(1, 1, 1))


func _clear_content() -> void:
	for c in content.get_children():
		c.queue_free()


func _show_tab(tab: String) -> void:
	current_tab = tab
	_apply_backdrop(tab)
	_refresh_status()
	_clear_content()
	match tab:
		"guild":
			_build_guild()
		"market":
			_build_market()
		"master":
			_build_master()
		"dossier":
			_build_dossier()
		"tavern":
			_build_tavern()


func _say(text: String) -> void:
	log_label.append_text(text + "\n")


## Фон под текущую вкладку. Требования к картинкам — в docs/ART_CITY.md:
## нижняя треть тёмная, потому что поверх ложится панель текста.
func _apply_backdrop(tab: String) -> void:
	var path := CityData.location_art(tab)
	if path.is_empty():
		backdrop.visible = false
		veil.color = Color(0.05, 0.05, 0.06, 0.0)
		return
	var tex: Texture2D = load(path)
	if tex == null:
		backdrop.visible = false
		return
	backdrop.texture = tex
	backdrop.visible = true
	# Замерено: интерфейс занимает x 20..1260, y 14..706, то есть почти весь
	# экран. Арт здесь — фон под текстом, а не картинка в рамке, поэтому
	# затемнение плотнее, чем на экране «следа».
	veil.color = Color(0.05, 0.05, 0.06, 0.68)


# --------------------------------------------------------------------------
# Гильдия: заказы и доска славы
# --------------------------------------------------------------------------

func _build_guild() -> void:
	_add_header("ГИЛЬДИЯ", "Старший охотник Бран смотрит на тебя со своего стола.")
	_add_header("ЗАКАЗЫ", "")

	var orders := CityData.available_monsters(GameState.rank)
	var any := false
	for o in orders:
		var mon: MonsterData = Database.monster(StringName(o["monster_id"]))
		if mon == null:
			continue
		any = true
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var info := Label.new()
		var known := GameState.dossier_level(mon.id)
		var know_text: String = ["не изучен", "наблюдение", "анализ", "мастерство"][clampi(known, 0, 3)]
		info.text = "%s, %s — %s · HP %d · панцирь %d · досье: %s" % [
			mon.title, mon.epithet, o["tier_title"], mon.max_hp, mon.armor, know_text]
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(info)
		var b := Button.new()
		b.text = "ВЗЯТЬ ЗАКАЗ"
		b.pressed.connect(func(): _take_order(mon.id, int(o["tier"]), false))
		row.add_child(b)
		var side := Button.new()
		side.text = "ПОБОЧНАЯ ВСТРЕЧА"
		side.tooltip_text = "Монстр рангом ниже. Короткий след, слава вдвое меньше"
		side.pressed.connect(func(): _take_order(mon.id, maxi(0, int(o["tier"]) - 1), true))
		row.add_child(side)
		content.add_child(row)
	if not any:
		_add_text("Заказов нет. Гильдия молчит.")

	_add_header("ДОСКА СЛАВЫ", "")
	_add_text("Слава: %d. До следующего ранга: %s." % [
		GameState.glory,
		"максимум" if GameState.glory_to_next() < 0 else str(GameState.glory_to_next())])
	_add_text("Побед: %d, смертей: %d, идеальных чтений: %d, уходов: %d" % [
		GameState.counters["kills"], GameState.counters["deaths"],
		GameState.counters["perfect_reads"], int(GameState.counters.get("escapes", 0))])

	# Три экрана доски славы из GDD 11.8: сама доска, достижения и Хроника.
	var nav := HBoxContainer.new()
	nav.add_theme_constant_override("separation", 6)
	for pair in [["board", "ДОСКА"], ["achievements", "ДОСТИЖЕНИЯ"], ["history", "ИСТОРИЯ"], ["chronicle", "ХРОНИКА"]]:
		var b := Button.new()
		b.text = pair[1]
		b.disabled = guild_view == pair[0]
		b.pressed.connect(_set_guild_view.bind(pair[0]))
		nav.add_child(b)
	content.add_child(nav)

	match guild_view:
		"achievements":
			_build_achievements()
		"history":
			_build_history()
		"chronicle":
			_build_chronicle()
		_:
			_build_board()


func _set_guild_view(view: String) -> void:
	guild_view = view
	_show_tab("guild")


# --------------------------------------------------------------------------
# Доска славы: три экрана (GDD 11.8)
# --------------------------------------------------------------------------

func _build_board() -> void:
	var to_next := GameState.glory_to_next()
	var bar := ""
	var span := maxi(1, GameState.next_rank_glory() - int(GameState.RANKS[GameState.rank]["glory"]))
	var filled := clampi(int(round(float(GameState.glory) / float(maxi(1, GameState.next_rank_glory())) * 20.0)), 0, 20)
	bar = "█".repeat(filled) + "░".repeat(20 - filled)
	_add_text("СЛАВА: %s %d / %d" % [bar, GameState.glory, GameState.next_rank_glory()])
	_add_text("Знак ранга: %s. %s" % [
		GameState.rank_sign(),
		"Клеймо: было падение." if GameState.lowest_rank_after_fall >= 0 else ""])
	if to_next >= 0:
		_add_text("ДО СЛЕДУЮЩЕГО РАНГА: %d славы." % to_next)

	_add_header("ПОСЛЕДНИЕ СОБЫТИЯ", "")
	var recent := GameState.recent_fame(5)
	if recent.is_empty():
		_add_text("Хроника пуста. Гильдия ждёт твоих дел.")
	for e in recent:
		_add_text("  ▸ День %d: %s %+d — %s" % [e["day"], e["title"], e["delta"], e["subtitle"]])
	_add_header("СТАРШИЙ ОХОТНИК", "")
	_add_text(_bran_line())


## Старший охотник говорит по делу: реплики из GDD 9.4, плюс реакция на падение.
func _bran_line() -> String:
	if GameState.rank >= 5:
		return "«Ты — легенда. Гильдия будет рассказывать о тебе новичкам.»"
	if GameState.lowest_rank_after_fall >= 0:
		return "«Ты падал. Гильдия помнит и это. Возвращайся — и мы забудем.»"
	if GameState.rank >= 3:
		return "«Ты — один из нас. Теперь — элита.»"
	return "«Гильдия ждёт. Приноси заказы, а не оправдания.»"


func _build_achievements() -> void:
	var unlocked := GameState.unlocked_achievements()
	_add_text("ПРОГРЕСС: %d / %d достижений" % [unlocked, Achievements.total()])
	# Группировку получаем один раз: вызов внутри for-заголовка парсер принимает
	# за Callable и падает на .keys().
	var groups: Dictionary = Achievements.by_group()
	for group in groups.keys():
		_add_header(str(group), "")
		for a in groups[group]:
			var mark := "☑" if GameState.achievements.has(str(a["id"])) else "☐"
			var reward := "" if int(a["glory"]) == 0 else " +%d славы" % int(a["glory"])
			_add_text("  %s %s%s" % [mark, a["title"], reward])


func _build_history() -> void:
	var filter := HBoxContainer.new()
	filter.add_theme_constant_override("separation", 6)
	var filters := {
		"все": "Все", "победа": "Победы", "смерть": "Смерти",
		"повышение": "Повышения", "откат": "Откаты",
	}
	for key in filters.keys():
		var b := Button.new()
		b.text = filters[key]
		b.disabled = history_filter == key
		b.pressed.connect(_set_history_filter.bind(key))
		filter.add_child(b)
	content.add_child(filter)

	var shown := 0
	for i in range(GameState.fame_log.size() - 1, -1, -1):
		var e: Dictionary = GameState.fame_log[i]
		if history_filter != "все" and str(e["kind"]) != history_filter:
			continue
		shown += 1
		_add_text("ДЕНЬ %d  %+d  %s" % [e["day"], e["delta"], str(e["kind"]).to_upper()])
		_add_text("  %s" % e["title"])
		_add_text("  %s" % e["subtitle"])
		_add_text("  Слава: %d" % e["glory_after"])
	if shown == 0:
		_add_text("По этому фильтру записей нет.")


func _set_history_filter(key: String) -> void:
	history_filter = key
	_show_tab("guild")


## Хроника — память гильдии (GDD 15.10): все события по дням, без фильтров.
func _build_chronicle() -> void:
	_add_text("Писарь ведёт Хронику с первого твоего дня. Здесь — вся память гильдии.")
	if GameState.fame_log.is_empty():
		_add_text("Пока пусто.")
		return
	var by_day: Dictionary = {}
	for e in GameState.fame_log:
		var d := int(e["day"])
		if not by_day.has(d):
			by_day[d] = []
		by_day[d].append(e)
	var days := by_day.keys()
	days.sort()
	for d in days:
		_add_header("ДЕНЬ %d" % d, "")
		for e in by_day[d]:
			_add_text("  %s — %s" % [str(e["kind"]).to_upper(), e["title"]])


func _take_order(monster_id: StringName, order_rank: int, side: bool) -> void:
	order_taken.emit(monster_id, order_rank, side)


# --------------------------------------------------------------------------
# Рынок трофеев
# --------------------------------------------------------------------------

func _build_market() -> void:
	_add_header("РЫНОК ТРОФЕЕВ", "Лис перебирает твою ношу и щурится.")
	# Добыча НЕ продаётся сама: она лежит в ноше, пока её не сбудешь здесь.
	# Поэтому у рынка две роли — показать, что несёшь, и дать это продать.
	_add_text("В ноше на %d монет. В кошельке: %d." % [GameState.bag_value(), GameState.coins])

	var shown := 0
	for id in GameState.bag.keys():
		var mon: MonsterData = Database.monster(StringName(id))
		if mon == null:
			continue
		var counts: Array = GameState.bag[id]
		for i in counts.size():
			var count := int(counts[i])
			if count <= 0:
				continue
			shown += 1
			var price := MarketData.item_price(mon, i)
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 10)
			var info := Label.new()
			info.text = "  %s · %s — %d за штуку · всего %d" % [
				MarketData.item_name(mon, i), mon.title, price, price * count]
			info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(info)
			var b := Button.new()
			b.text = "ПРОДАТЬ (%d)" % count
			b.pressed.connect(_sell_trophy.bind(mon.id, i))
			row.add_child(b)
			content.add_child(row)

	if shown == 0:
		_add_text("Ноша пуста. Принеси добычу с охоты — и Лис заговорит иначе.")

	_add_header("КОШЕЛЁК", "")
	_add_text("Монет: %d" % GameState.coins)
	if shown > 0:
		var sell_all := Button.new()
		sell_all.text = "ПРОДАТЬ ВСЁ (%d)" % GameState.bag_value()
		sell_all.pressed.connect(_sell_everything)
		content.add_child(sell_all)
	# Виды, которых игрок ещё не встречал, здесь не показываются: пустая ноша
	# не должна выдавать список зверей. Цены видны только по знакомой добыче.


## Продать один предмет вида. После продажи экран перестраивается: число штук
## и кошелёк меняются, а держать рассинхронизированный список — это ложь на экране.
func _sell_trophy(monster_id: StringName, index: int) -> void:
	var price := GameState.sell_trophy(monster_id, index)
	if price <= 0:
		return
	var mon: MonsterData = Database.monster(monster_id)
	_say("[color=#c9a227]Лис отсчитывает %d монет за «%s».[/color]" % [
		price, MarketData.item_name(mon, index)])
	_show_tab("market")


func _sell_everything() -> void:
	var total := GameState.sell_all_trophies()
	if total <= 0:
		_say("Лис разводит руками: «Пусто у тебя.»")
		return
	_say("[color=#c9a227]Лис сгрёб всё: %d монет.[/color]" % total)
	_show_tab("market")


# --------------------------------------------------------------------------
# Мастер навыков
# --------------------------------------------------------------------------

func _build_master() -> void:
	_add_header("МАСТЕР НАВЫКОВ", "Гунн ворчит, не поднимая головы: «Держи. Носи. Помни.»")

	_add_header("ВЕТКИ", "")
	for branch in ["read", "weapon", "survival"]:
		var skills := SkillsData.skills_of_branch(branch)
		var owned_count := 0
		for s in skills:
			if GameState.has_skill(StringName(s["id"])):
				owned_count += 1
		_add_text("%s: куплено %d из %d" % [SkillsData.BRANCH_TITLES[branch], owned_count, skills.size()])
		for s in skills:
			var sid := StringName(s["id"])
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 10)
			var info := Label.new()
			var status := "КУПЛЕНО"
			if not GameState.has_skill(sid):
				var check := SkillsData.can_buy(sid, GameState.coins, GameState.rank, GameState.skills)
				status = "КУПИТЬ" if check["ok"] else str(check["reason"]).to_upper()
			info.text = "  ур.%d · %s — %s · %d монет [%s]" % [
				s["tier"], s["title"], s["effect"], s["price"], status]
			info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(info)
			var b := Button.new()
			b.text = "КУПИТЬ"
			b.disabled = GameState.has_skill(sid)
			b.pressed.connect(_buy_skill.bind(sid))
			row.add_child(b)
			content.add_child(row)

	_add_header("СНАРЯЖЕНИЕ", "")
	for id in Database.weapons.keys():
		var w: WeaponData = Database.weapons[id]
		var owned := w.id in GameState.owned_weapons
		var row := HBoxContainer.new()
		var info := Label.new()
		info.text = "  %s — %s, %s, урон %d · %d монет%s" % [
			w.title, CityData.range_ru(w.range_id), CityData.type_ru(w.damage_type), w.base_damage, w.price,
			" [КУПЛЕНО]" if owned else ""]
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(info)
		var b := Button.new()
		b.text = "НАДЕТЬ" if owned else "КУПИТЬ"
		b.pressed.connect(_buy_or_equip_weapon.bind(w.id))
		row.add_child(b)
		content.add_child(row)

	for id in Database.armors.keys():
		var a: ArmorData = Database.armors[id]
		var owned := a.id in GameState.owned_armors
		var row := HBoxContainer.new()
		var info := Label.new()
		info.text = "  %s — поглощение %d · %d монет%s" % [
			a.title, a.absorption, a.price, " [КУПЛЕНО]" if owned else ""]
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(info)
		var b := Button.new()
		b.text = "НАДЕТЬ" if owned else "КУПИТЬ"
		b.pressed.connect(_buy_or_equip_armor.bind(a.id))
		row.add_child(b)
		content.add_child(row)

	var cap_note := Label.new()
	cap_note.text = "  Потолок поглощения — %d. Выше броня не складывается: иначе бой теряет смысл." % HunterState.ABSORPTION_CAP
	cap_note.add_theme_color_override("font_color", Color("#8d8578"))
	content.add_child(cap_note)


func _buy_skill(skill_id: StringName) -> void:
	var s := SkillsData.find_skill(skill_id)
	if s.is_empty():
		return
	var check := SkillsData.can_buy(skill_id, GameState.coins, GameState.rank, GameState.skills)
	if not check["ok"]:
		_say("[color=#c96a4a]%s[/color]" % check["reason"])
		_show_tab("master")
		return
	GameState.buy_skill(skill_id, int(s["price"]))
	_say("Куплено: %s" % s["title"])
	_show_tab("master")


func _buy_or_equip_weapon(weapon_id: StringName) -> void:
	var w: WeaponData = Database.weapon(weapon_id)
	if w == null:
		return
	if w.id in GameState.owned_weapons:
		GameState.equipped_weapon = w.id
		_say("В руках: %s" % w.title)
	else:
		# Проверка цены и списание — одна операция (GameState.spend_coins).
		# Проверять отдельно, а списывать следом нельзя: тогда побочные действия
		# ниже выполнятся даже при отказе, и игрок получит товар бесплатно.
		if not GameState.spend_coins(w.price):
			_say("[color=#c96a4a]Не хватает %d монет[/color]" % (w.price - GameState.coins))
		else:
			GameState.owned_weapons.append(w.id)
			GameState.equipped_weapon = w.id
			_say("Куплено и взято: %s" % w.title)
	_show_tab("master")


func _buy_or_equip_armor(armor_id: StringName) -> void:
	var a: ArmorData = Database.armor(armor_id)
	if a == null:
		return
	if a.id in GameState.owned_armors:
		GameState.equipped_armor = a.id
		_say("Надето: %s" % a.title)
	else:
		if not GameState.spend_coins(a.price):
			_say("[color=#c96a4a]Не хватает %d монет[/color]" % (a.price - GameState.coins))
		else:
			GameState.owned_armors.append(a.id)
			GameState.equipped_armor = a.id
			_say("Куплено и надето: %s" % a.title)
	_show_tab("master")


# --------------------------------------------------------------------------
# Досье
# --------------------------------------------------------------------------

## Главный экран досье — СПИСОК видов с уровнем (GDD 5.6), а не свалка всех
## разборов подряд. Раньше здесь печатались досье всех шести видов одним потоком:
## чтобы дойти до нужного, приходилось листать чужие записи.
##
## Разбор вида открывается тем же окном, что и на подготовке (DossierWindow):
## структура собирается в core, поэтому два экрана не могут разъехаться.
func _build_dossier() -> void:
	_add_header("ДОСЬЕ", "Писарь Тик молча подвигает тебе книгу.")
	var titles := ["не изучен", "НАБЛЮДЕНИЕ", "АНАЛИЗ", "МАСТЕРСТВО"]
	for id in Database.monsters.keys():
		var mon: MonsterData = Database.monsters[id]
		var level := GameState.dossier_level(mon.id)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		content.add_child(row)

		var text := Label.new()
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.text = "%s, %s — %s" % [mon.title, mon.epithet, titles[clampi(level, 0, 3)]]
		text.add_theme_color_override("font_color",
			Color("#8d8578") if level == 0 else Color("#d8cfc0"))
		row.add_child(text)

		var open := Button.new()
		open.text = "СМОТРЕТЬ"
		open.pressed.connect(_open_dossier.bind(mon))
		row.add_child(open)


## Открыть окно вида. Окно одно на экран и создаётся при первом обращении:
## держать шесть окон ради списка незачем.
func _open_dossier(mon: MonsterData) -> void:
	if dossier_window == null:
		dossier_window = DossierWindow.new()
		dossier_window.set_anchors_preset(Control.PRESET_FULL_RECT)
		dossier_window.closed.connect(_close_dossier)
		add_child(dossier_window)
	dossier_window.setup(mon)
	dossier_window.set_accept_text("ЗАКРЫТЬ")
	dossier_window.visible = true


func _close_dossier() -> void:
	if dossier_window != null:
		dossier_window.visible = false


func _to_strings(arr: Array) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for x in arr:
		out.append(str(x))
	return out


# --------------------------------------------------------------------------
# Таверна: Старик
# --------------------------------------------------------------------------

func _build_tavern() -> void:
	_add_header("ТАВЕРНА", "В углу, у огня, сидит Старик. Перед ним — глиняная чашка.")
	_add_header("СОВЕТЫ", "Первый совет бесплатный. Остальные — за монеты.")
	for id in Database.monsters.keys():
		var mon: MonsterData = Database.monsters[id]
		var price := CityData.advice_price(mon.id)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var info := Label.new()
		info.text = "%s — %s" % [mon.title, "бесплатно" if price == 0 else "%d монет" % price]
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(info)
		var b := Button.new()
		b.text = "СПРОСИТЬ"
		b.pressed.connect(_ask_advice.bind(mon.id, price))
		row.add_child(b)
		content.add_child(row)
	_add_text("Совет не записывается в досье. Помни сам.")


func _ask_advice(monster_id: StringName, price: int) -> void:
	if advice_bought.has(String(monster_id)):
		_say("Ты это уже слышал.")
		return
	if not GameState.spend_coins(price):
		_say("[color=#c96a4a]Старик: «Приходи, когда будет чем платить.»[/color]")
		return
	advice_bought[String(monster_id)] = true
	var mon: MonsterData = Database.monster(monster_id)
	_say(_advice_text(mon))
	_refresh_status()


## Совет — это опыт, а не подсказка (GDD 9.3): он называет опорные сигналы
## и слабость, но не даёт частот сценариев и не пишется в досье.
func _advice_text(mon: MonsterData) -> String:
	if mon == null:
		return ""
	var weak_parts: PackedStringArray = PackedStringArray()
	for t in mon.weakness_types:
		weak_parts.append(CityData.type_ru(StringName(t)))
	for r in mon.weakness_ranges:
		weak_parts.append(CityData.range_ru(StringName(r)))
	var lines: PackedStringArray = PackedStringArray()
	lines.append("[b]«%s. %s.»[/b]" % [mon.title, mon.epithet])
	for scn in mon.scenarios:
		var sigs: PackedStringArray = PackedStringArray()
		for sig in scn.signals:
			sigs.append("«%s»" % sig.label)
		lines.append("  %s — %s" % [scn.card_label, ", ".join(sigs)])
	if not weak_parts.is_empty():
		lines.append("Бей: %s. Понял?" % ", ".join(weak_parts))
	return "\n".join(lines)


# --------------------------------------------------------------------------
# Помощники
# --------------------------------------------------------------------------

func _add_header(text: String, sub: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 18)
	l.add_theme_color_override("font_color", Color("#d8cfc0"))
	content.add_child(l)
	if not sub.is_empty():
		_add_text(sub)


func _add_text(text: String) -> void:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_color_override("font_color", Color("#b0a696"))
	content.add_child(l)
