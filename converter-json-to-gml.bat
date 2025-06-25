@echo off
setlocal enabledelayedexpansion

:: Root direktori
set ROOT_DIR=%~dp0
set "JSON_DIR=%ROOT_DIR%folder-json"
set "LOG_DIR=%ROOT_DIR%folder-log"
set "LOG_FILE=%LOG_DIR%\converter-json-to-gml.log"

:: Buat folder log jika belum ada
if not exist "%LOG_DIR%" (
    mkdir "%LOG_DIR%"
)

:: Hitung total file JSON
set "COUNT=0"
for %%F in ("%JSON_DIR%\*.json") do (
    set /a COUNT+=1
)

:: Tulis header log
echo ===== Proses konversi dimulai: %DATE% %TIME% ===== >> "%LOG_FILE%"

:: Inisialisasi progress
set /a CURRENT=0
set "PROGRESS_BAR_WIDTH=30"

:: Loop seluruh file JSON
for %%F in ("%JSON_DIR%\*.json") do (
    set /a CURRENT+=1
    set "JSON_FILE_PATH=%%~fF"
    set "JSON_FILE_NAME=%%~nxF"
    set "ID_PREFIX=%%~nF_"

    (
    echo ================================
    echo Memproses file: !JSON_FILE_NAME!
    echo ID Prefix     : !ID_PREFIX!
    echo ================================

    set "CURRENT_JSON_FILE=!JSON_FILE_PATH!"
    call "%ROOT_DIR%credentials.bat"
    call "%ROOT_DIR%importer.bat"
    call "%ROOT_DIR%exporter.bat"
    call "%ROOT_DIR%python.bat"
    call "%ROOT_DIR%db_reset.bat"

    echo --- Selesai memproses: !JSON_FILE_NAME! ---
    echo.
    ) >> "%LOG_FILE%" 2>&1

    :: Hitung progress
    set /a PERCENT=100*CURRENT/COUNT
    set /a DONE=PROGRESS_BAR_WIDTH*CURRENT/COUNT
    set /a LEFT=PROGRESS_BAR_WIDTH-DONE

    set "BAR="
    for /L %%A in (1,1,!DONE!) do set "BAR=!BAR!#"
    for /L %%B in (1,1,!LEFT!) do set "BAR=!BAR!."

    echo [!BAR!] !PERCENT!%% 
  
)

echo.
echo === Semua file telah selesai diproses ===
echo ===== Proses selesai: %DATE% %TIME% ===== >> "%LOG_FILE%"
endlocal
pause
