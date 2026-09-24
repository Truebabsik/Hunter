extends RefCounted
class_name Report
## Отчёты проверок: ОДНО место, где решается, куда писать.
##
## Почему это отдельный модуль. Раньше путь отчёта был вписан руками в каждой
## проверке (`_write_out("F:/WORK/hunter/_validate_out.txt", ...)`) — восемнадцать
## раз, с абсолютным путём внутри игрового кода. Абсолютный путь ломается при
## переносе проекта, а восемнадцать копий нельзя поменять одной правкой.
##
## Имена файлов остались прежними (`_validate_out.txt` и так далее): на них
## завязаны `tools/run_headless.ps1` и рабочие привычки. Менять их — отдельное
## решение, а не побочный эффект переноса проверок.

## Каталог отчётов — КОРЕНЬ ПРОЕКТА, а не машина.
##
## Здесь стоял абсолютный путь `F:/WORK/hunter`. Это противоречило комментарию выше:
## он объясняет, что абсолютный путь ломается при переносе, — а сам путь оставался
## абсолютным. На чужой машине `FileAccess.open` вернул бы null, и проверки
## отработали бы МОЛЧА, не создав ни одного отчёта: инструмент рапортовал бы
## «NO REPORT» или, хуже, читал стухший файл.
##
## `res://` — тот же каталог проекта, но не зависящий от того, куда его положили.
## Пишется в исходном проекте (в редакторе и в headless). Проверено пробой:
## запись через res:// проходит, а `ProjectSettings.globalize_path("res://")` даёт
## абсолютный путь для тех мест, где он нужен (удаление файла).
##
## Для собранной игры это НЕ путь для записи: там `res://` только для чтения, и
## отчёты — инструмент разработки, а не часть игры. Сохранения забега (когда
## появятся) обязаны идти в `user://`, а не сюда.
const DIR := "res://"


## Полный путь к отчёту. Склейка без лишнего слэша: `DIR` уже кончается на `/`,
## а `res://_validate_out.txt` с двойным слэшем выглядит как опечатка в отчётах.
static func path(name: String) -> String:
	if name.begins_with("res://") or name.begins_with("F:/") or name.begins_with("user://"):
		return name
	return "%s%s" % [DIR, name]


## Записать отчёт. Возвращает путь, чтобы вызывающий мог сказать о нём в сводке.
static func write(name: String, lines: Array) -> String:
	var full := path(name)
	var f := FileAccess.open(full, FileAccess.WRITE)
	if f == null:
		push_warning("не удалось записать отчёт %s (код %d)" % [full, FileAccess.get_open_error()])
		return ""
	for line in lines:
		f.store_line(str(line))
	f.close()
	return full


## Дописать строку в файл трассировки. Нужно там, где прогон может зависнуть и
## обычного отчёта в конце не будет: по трассе видно, до какого шага дошло.
static func trace(name: String, text: String) -> void:
	var full := path(name)
	var mode := FileAccess.WRITE
	if FileAccess.file_exists(full):
		mode = FileAccess.READ_WRITE
	var f := FileAccess.open(full, mode)
	if f == null:
		return
	f.seek_end()
	f.store_line(text)
	f.close()
