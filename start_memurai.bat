@echo off
REM Запуск Memurai (Redis для Windows) вручную
REM Служба Memurai может не запускаться после 10-дневного лимита - запускайте этот скрипт
if exist "D:\memurai.exe" (
    start "" "D:\memurai.exe" "D:\memurai.conf"
    echo Memurai запущен. Проверка: D:\memurai-cli.exe ping
) else (
    echo Memurai не найден в D:\. Установите с https://www.memurai.com/get-memurai
    pause
)
