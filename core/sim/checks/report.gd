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

## Каталог отчётов. Пустая строка — папка проекта, как было до переноса.
const DIR := "F:/WORK/hunter"


static func path(name: String) -> String:
	return "%s/%s" % [DIR, name]


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
