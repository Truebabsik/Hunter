extends RefCounted
class_name ArtPaths
## Пути к фонам: город, общий вид, лагерь подготовки.
##
## Вынесено из CityData, потому что это НЕ логика города: ни один расчёт баланса
## к арту не обращается, а сама таблица путей — данные для отрисовки. Держать её
## рядом с заказами и ценами значило заставлять читателя города пролистывать
## шесть десятков строк про картинки, чтобы дойти до славы за победу.
##
## Ключевое правило здесь — расширение подбирается В РАНТАЙМЕ, а не хранится в
## данных. Поэтому заглушка-силуэт (.svg) уже лежит в проекте и работает, а
## нарисованная картинка (.png) автоматически занимает её место, как только
## появится: ни правок в коде, ни правок в .tres для этого не требуется.

## Арт локаций города: вкладка → базовый путь без расширения.
const LOCATION_ART := {
	"guild": "res://art/city/guild",
	"market": "res://art/city/market",
	"master": "res://art/city/master",
	"dossier": "res://art/city/dossier",
	"tavern": "res://art/city/tavern",
}

## Общий вид города — показывается до входа в конкретную локацию.
const CITY_OVERVIEW_ART := "res://art/city/square"

## Фон экрана подготовки — лагерь охотника перед боем. Пусто = экран подготовки
## берёт фон локации вида (запасной путь, он и работает сейчас).
const PREP_ART := "res://art/locations/prep"

## Расширения в порядке приоритета: нарисованная картинка важнее заглушки.
const ART_EXTENSIONS: Array[String] = [".png", ".jpg", ".jpeg", ".webp", ".svg"]


## Путь к фону локации. Пустая строка, если арта для вкладки ещё нет.
static func location_art(tab: String) -> String:
	return _resolve_art(str(LOCATION_ART.get(tab, "")))


static func overview_art() -> String:
	return _resolve_art(CITY_OVERVIEW_ART)


## Фон экрана подготовки. Пустая строка — файла нет, экран возьмёт фон локации.
static func prep_art() -> String:
	return _resolve_art(PREP_ART)


## Первое существующее расширение из списка приоритетов.
static func _resolve_art(base_path: String) -> String:
	if base_path.is_empty():
		return ""
	for ext in ART_EXTENSIONS:
		var path: String = base_path + ext
		if ResourceLoader.exists(path):
			return path
	return ""
