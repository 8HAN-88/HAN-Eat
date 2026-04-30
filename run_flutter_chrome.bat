@echo off
REM Запуск Flutter на Chrome с временными файлами на D: (если на C: нет места)
REM Если у вас диск не D:, измените D: на нужную букву (например E:)

if not exist "D:\Temp" mkdir "D:\Temp"
set TEMP=D:\Temp
set TMP=D:\Temp

cd /d "%~dp0"
echo TEMP is %TEMP%
flutter run -d chrome
pause
