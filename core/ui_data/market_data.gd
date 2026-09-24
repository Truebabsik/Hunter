extends RefCounted
class_name MarketData
## Рынок трофеев: цены, ноша, продажа.
##
## Здесь только правила и числа — никакого UI, как и в CityData. Поэтому рынок
## целиком проверяется в headless-прогоне: сколько добычи доехало до Лиса,
## сколько потеряно в побеге и сколько осталось в сумке.
##
## НОША (сумка) устроена по видам зверя:
##     bag[monster_id] = [количество предмета 0, количество предмета 1, ...]
## Порядок совпадает с MonsterData.trophy_names / trophy_prices, поэтому
## предмет — это индекс, а не отдельная сущность. Предметы одного вида
## взаимозаменяемы: важно, сколько их, а не какой именно.

## Множитель экономики. 1.0 — цены из .tres как есть. Поднимать его — отдельное
## решение про длину пути до Легенды (GDD 12.10), и принимать его надо по замеру
## прогона, а не заранее. Всё остальное считается уже с учётом множителя, так что
## поменять баланс можно одной этой строкой.
const PRICE_MULTIPLIER := 1.0


## Цена одного предмета вида по индексу. 0, если предмета с таким индексом нет.
static func item_price(mon: MonsterData, index: int) -> int:
	if mon == null or index < 0 or index >= mon.trophy_prices.size():
		return 0
	return int(round(float(mon.trophy_prices[index]) * PRICE_MULTIPLIER))


## Название предмета по индексу. Пустая строка, если такого нет.
static func item_name(mon: MonsterData, index: int) -> String:
	if mon == null or index < 0 or index >= mon.trophy_names.size():
		return ""
	return mon.trophy_names[index]


## Сколько предметов даёт победа над видом. По одному каждого вида — это и была
## прежняя награда, просто раньше она сразу превращалась в монеты.
static func drop_for(mon: MonsterData) -> Array[int]:
	var out: Array[int] = []
	if mon == null:
		return out
	for i in mon.trophy_prices.size():
		out.append(1)
	return out


## Положить добычу в ношу. Возвращает, сколько монет она стоила бы на рынке —
## это «стоимость добычи», и она попадает в итог охоты как справочная цифра.
static func add_drop(bag: Dictionary, mon: MonsterData) -> int:
	if mon == null:
		return 0
	var key := String(mon.id)
	if not bag.has(key):
		var empty: Array[int] = []
		for i in mon.trophy_prices.size():
			empty.append(0)
		bag[key] = empty
	var counts: Array = bag[key]
	var value := 0
	for i in mon.trophy_prices.size():
		counts[i] = int(counts[i]) + 1
		value += item_price(mon, i)
	return value


## Стоимость всей ноши.
static func total_value(bag: Dictionary) -> int:
	var sum := 0
	for key in bag.keys():
		var mon: MonsterData = Database.monster(StringName(key))
		if mon == null:
			continue
		var counts: Array = bag[key]
		for i in counts.size():
			sum += int(counts[i]) * item_price(mon, i)
	return sum


## Продать один предмет вида по индексу. Возвращает выручку (0, если продавать
## нечего). Ноша меняется на месте — так же, как её меняет побег или смерть.
static func sell_one(bag: Dictionary, monster_id: StringName, index: int) -> int:
	var key := String(monster_id)
	if not bag.has(key):
		return 0
	var counts: Array = bag[key]
	if index < 0 or index >= counts.size() or int(counts[index]) <= 0:
		return 0
	var mon: MonsterData = Database.monster(monster_id)
	var price := item_price(mon, index)
	counts[index] = int(counts[index]) - 1
	return price


## Продать всё. Возвращает выручку.
static func sell_all(bag: Dictionary) -> int:
	var total := 0
	for key in bag.keys():
		var mon: MonsterData = Database.monster(StringName(key))
		if mon == null:
			continue
		var counts: Array = bag[key]
		for i in counts.size():
			total += int(counts[i]) * item_price(mon, i)
			counts[i] = 0
	return total


## Что именно теряется при побеге: список {monster_id, index, count} на сумму
## не меньше target_value. Это «брошенная ноша» — игрок уходил налегке.
##
## Предметы берутся от дешёвых к дорогим: терять самое ценное первым было бы
## наказанием за удачный бой, а не за неудачный побег.
static func escape_loss(bag: Dictionary, target_value: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if target_value <= 0:
		return out
	# Все предметы ноши одной плоской таблицей, с сортировкой по цене.
	var items: Array[Dictionary] = []
	for key in bag.keys():
		var mon: MonsterData = Database.monster(StringName(key))
		if mon == null:
			continue
		var counts: Array = bag[key]
		for i in counts.size():
			var count := int(counts[i])
			if count <= 0:
				continue
			items.append({
				"monster_id": key,
				"index": i,
				"count": count,
				"price": item_price(mon, i),
			})
	items.sort_custom(func(a, b): return int(a["price"]) < int(b["price"]))
	var lost := 0
	for item in items:
		if lost >= target_value:
			break
		var take := 0
		var price := int(item["price"])
		var have := int(item["count"])
		if price <= 0:
			# Бесплатный предмет ничего не возмещает — берём один как жест.
			take = mini(1, have)
			lost += 1
		else:
			while take < have and lost < target_value:
				take += 1
				lost += price
		out.append({
			"monster_id": item["monster_id"],
			"index": int(item["index"]),
			"count": take,
			"price": price,
			"value": take * price,
		})
	return out


## Забрать из ноши перечисленное. Возвращает фактически отнятую стоимость.
static func remove_items(bag: Dictionary, items: Array) -> int:
	var removed := 0
	for it in items:
		var key := String(it["monster_id"])
		if not bag.has(key):
			continue
		var counts: Array = bag[key]
		var index := int(it["index"])
		if index < 0 or index >= counts.size():
			continue
		var take := mini(int(it["count"]), int(counts[index]))
		counts[index] = int(counts[index]) - take
		removed += take * int(it["price"])
	return removed


## Сколько предметов осталось в ноше. Нужно для инварианта «ничего не исчезло
## бесследно» и для отчётов прогона.
static func item_count(bag: Dictionary) -> int:
	var total := 0
	for key in bag.keys():
		var counts: Array = bag[key]
		for c in counts:
			total += int(c)
	return total


## Ноша пуста?
static func is_empty(bag: Dictionary) -> bool:
	return item_count(bag) == 0


## Строки для журнала и отчётов: «панцирная пластина x2 — 20».
static func describe(bag: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for key in bag.keys():
		var mon: MonsterData = Database.monster(StringName(key))
		if mon == null:
			continue
		var counts: Array = bag[key]
		for i in counts.size():
			var count := int(counts[i])
			if count <= 0:
				continue
			out.append("%s x%d — %d" % [
				item_name(mon, i), count, count * item_price(mon, i)])
	return out
