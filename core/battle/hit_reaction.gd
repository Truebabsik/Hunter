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
