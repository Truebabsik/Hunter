@echo off
rem ============================================================
rem  ОХОТНИК — запуск игры
rem  Двойной клик по этому файлу. Окно консоли даёт лог: если
rem  игра не запустится, здесь будет видно, почему.
rem ============================================================
setlocal
set GODOT=F:\WORK\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe
set PROJECT=F:\WORK\hunter

if not exist "%GODOT%" (
    echo НЕ НАЙДЕН Godot: "%GODOT%"
    echo Проверь путь к движку.
    pause
    exit /b 1
)

if not exist "%PROJECT%\project.godot" (
    echo НЕ НАЙДЕН проект: "%PROJECT%"
    pause
    exit /b 1
)

echo Запускаю ОХОТНИК...
"%GODOT%" --path "%PROJECT%"

echo.
echo Игра закрыта.
pause
