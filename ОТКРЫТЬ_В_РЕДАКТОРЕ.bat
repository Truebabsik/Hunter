@echo off
rem ============================================================
rem  ОХОТНИК — открыть проект в редакторе Godot
rem  Нужен, если хочешь посмотреть сцены, .tres-ресурсы,
rem  покрутить интерфейс мышью или запустить игру по F5.
rem ============================================================
setlocal
set GODOT=F:\WORK\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe
set PROJECT=F:\WORK\hunter

if not exist "%GODOT%" (
    echo НЕ НАЙДЕН Godot: "%GODOT%"
    pause
    exit /b 1
)

echo Открываю редактор Godot с проектом ОХОТНИК...
"%GODOT%" --editor --path "%PROJECT%"
