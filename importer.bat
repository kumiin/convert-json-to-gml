@echo off
setlocal

set ROOT_DIR=%~dp0
call "%ROOT_DIR%credentials.bat"

:: Gunakan variabel dari main.bat
set "json_file=%CURRENT_JSON_FILE%"
set "IMPEXP_PATH=C:\Users\User\geo-ai\3DCityDB-Importer-Exporter-5.4.0\bin\impexp.bat"

echo === Import file JSON ke database ===
echo File yang diimport: %json_file%

"%IMPEXP_PATH%" ^
    import ^
    -T postgresql ^
    -H %DB_HOST% ^
    -P %DB_PORT% ^
    -d %DB_NAME% ^
    -S %DB_SCHEMA% ^
    -u %DB_USER% ^
    -p %DB_PASS% ^
    "%json_file%"

endlocal
