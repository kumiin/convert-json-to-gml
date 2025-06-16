@echo off
setlocal

set ROOT_DIR=%~dp0
call "%ROOT_DIR%credentials.bat"

:: Ubah nama output file .json menjadi .gml
set "file_base=%JSON_FILE_NAME:.json=%"
set "output_file=%ROOT_DIR%\folder-gml\%file_base%.gml"

set "IMPEXP_PATH=C:\Users\User\geo-ai\3DCityDB-Importer-Exporter-5.4.0\bin\impexp.bat"

echo === Export ke GML: %file_base%.gml ===
"%IMPEXP_PATH%" ^
    export ^
    -T postgresql ^
    -H %DB_HOST% ^
    -P %DB_PORT% ^
    -d %DB_NAME% ^
    -S %DB_SCHEMA% ^
    -u %DB_USER% ^
    -p %DB_PASS% ^
    -o "%output_file%" ^
    --compressed-format citygml ^
    --replace-ids ^
    --id-prefix "%ID_PREFIX%"

endlocal
