@echo off
setlocal enabledelayedexpansion

:: Root direktori
set ROOT_DIR=%~dp0
set "JSON_DIR=%ROOT_DIR%folder-json"
set "LOG_DIR=%ROOT_DIR%folder-log"

:: Loop seluruh file JSON
for %%F in ("%JSON_DIR%\*.json") do (
    set "JSON_FILE_PATH=%%~fF"
    set "JSON_FILE_NAME=%%~nxF"
    set "ID_PREFIX=%%~nF_"

    echo ================================
    echo Memproses file: !JSON_FILE_NAME!
    echo ID Prefix     : !ID_PREFIX!
    echo ================================

    :: Kirim nama file & prefix sebagai variabel environment
    set "CURRENT_JSON_FILE=!JSON_FILE_PATH!"
    call "%ROOT_DIR%credentials.bat"
    call "%ROOT_DIR%importer.bat"
    call "%ROOT_DIR%exporter.bat"
    call "%ROOT_DIR%python.bat"
    call "%ROOT_DIR%db_reset.bat"

    echo --- Selesai memproses: !JSON_FILE_NAME! ---
    echo.
)

echo === Semua file telah selesai diproses ===
endlocal
pause
