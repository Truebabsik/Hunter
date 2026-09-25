extends RefCounted
class_name HitReaction
## Вердикт удара игрока (D19): тип удара наткнулся на защиту зверя, нашёл щель
## или прошёл нейтрально.
##
## Вердикт — про ТИП, а не про силу удара. Источник — сумма причин «слабость +1 /
## резист −1» (поле `DamageResult.type_reasons_sum`), БЕЗ безусловного «+1» элемента
## руны (D04): в `type_multiplier` элемент уже прибавлен и в резист гасит штраф,
## поэтому удар руной в стену даёт там ноль — и по множителю проза сказала бы
## «нейтрально» там, где разбор называет резист (измерено на Ламанте).

const VERDICT_RESIST := &"resist"
const VERDICT_WEAK := &"weak"
const VERDICT_NEUTRAL := &"neutral"

## Слоты пула деталей реакции (D19). Идентификаторы живут ЗДЕСЬ, а не литералами
## у каждого читателя: сборка (Task 3) и проверка покрытия спрашивают одни и те же
## ведра, и вторая копия строки «reaction_verb» разошлась бы с первой молча
## (AGENTS.md §4). Значения обязаны совпадать с колонкой `slot` в
## `content/phrases/reactions.csv`.
const SLOT_CARRIER := &"reaction_carrier"
const SLOT_VERB := &"reaction_verb"
const SLOT_WEAPON := &"reaction_weapon"
const SLOT_ELEMENT := &"reaction_element"
const SLOT_INTRO := &"reaction_intro"

## Вердикт по знаку СУММЫ ПРИЧИН вида («слабость +1 / резист −1») без «+1» элемента
## руны (D04). Ноль — взаимодействия нет.
static func verdict_of(reasons_sum: int) -> StringName:
	if reasons_sum < 0:
		return VERDICT_RESIST
	if reasons_sum > 0:
		return VERDICT_WEAK
	return VERDICT_NEUTRAL


## Пунктуация принадлежит СБОРЩИКУ, а не данным: иначе знак пришлось бы дублировать
## в каждой строке CSV, и «двойная запятая» стала бы вопросом данных, а не правила.
## Пробел между носителем и глаголом — тот же случай: это разделитель шаблона, и
## сторож шва обязан спрашивать ЕГО, а не держать свою копию строки.
const P_AFTER_INTRO := ". "
const P_BEFORE_VERB := " "
const P_BEFORE_WEAPON := " — "
const P_BEFORE_ELEMENT := ", "
const P_END := "."


## Группа вводной: ступень серии, но примерка перебивает ступень — смена оружия
## без удара не повтор удара.
static func intro_role(verdict: StringName, run: int, is_swap: bool) -> StringName:
	if is_swap:
		return &"swap"
	if run >= 3:
		return StringName("%s_hard" % verdict)
	if run == 2:
		return StringName("%s_again" % verdict)
	return verdict


## Сборка строки реакции из деталей пула (D19, §5 спеки).
##
## Шаблон `{вводная}. {носитель} {глагол} — {отпечаток}, {стихия}.` живёт ЗДЕСЬ, а
## детали — в данных. Пустая строка — это «сборки нет»: шаблон обязан быть собран
## целиком, обрубок соврал бы (правило «контент обещает — контент выполняет»),
## поэтому нехватка любой ОБЯЗАТЕЛЬНОЙ детали возвращает пусто, а не часть фразы.
##
## Первый аргумент `pick_phrase` — не везде id вида: `Database.phrases_for`
## откатывается ТОЛЬКО по сценарию, поэтому общие вёдра (у них пустой `monster`)
## достижимы лишь при `&""`. С id вида вернулся бы пустой массив, и дыра в пуле
## выглядела бы как «нет данных» вместо «нет фразы» — но обе ветки дают пустую
## строку, и молчать об этом сборщик не имеет права.
static func assemble(
	monster: MonsterData,
	weapon: WeaponData,
	verdict: StringName,
	run: int,
	is_swap: bool,
	rng: RandomNumberGenerator
) -> String:
	if monster == null or weapon == null:
		return ""
	var intro := TextGenerator.pick_phrase(&"", &"", SLOT_INTRO, intro_role(verdict, run, is_swap), rng)
	var carrier := TextGenerator.pick_phrase(monster.id, &"", SLOT_CARRIER, &"", rng)
	var verb := TextGenerator.pick_phrase(&"", &"", SLOT_VERB, verdict, rng)
	var print_weapon := TextGenerator.pick_phrase(&"", &"", SLOT_WEAPON, StringName(weapon.id), rng)
	if intro == null or carrier == null or verb == null or print_weapon == null:
		return ""
	var line: String = str(intro.text) + P_AFTER_INTRO \
		+ str(carrier.text) + P_BEFORE_VERB + str(verb.text) \
		+ P_BEFORE_WEAPON + str(print_weapon.text)
	# Без руны стихийная часть опускается вместе со своей запятой (§5). Это правило
	# сборщика: отдельные детали «пустой стихии» в пуле не нужны. И только если руна
	# ДОБАВЛЯЕТ тип: при `rune_type == damage_type` её выбрасывает
	# `WeaponData.damage_types_with`, второй тип удара не наносится — и стихийная
	# клауза пообещала бы удар, которого нет. Условие повторяет правило оружия, а не
	# заводит своё: источник — там же, где `damage_types()`.
	if weapon.rune_type != &"" and weapon.rune_type != weapon.damage_type:
		var element := TextGenerator.pick_phrase(
			&"", &"", SLOT_ELEMENT, StringName(weapon.rune_type), rng)
		if element != null:
			line += P_BEFORE_ELEMENT + str(element.text)
	return line + P_END
