@echo off
setlocal

set ROOT_DIR=%~dp0
set "file_base=%JSON_FILE_NAME:.json=%"
set "output_file=%ROOT_DIR%\folder-gml\%file_base%.gml"

echo === Run Python Script for: %file_base%.gml ===
python3.11 "%ROOT_DIR%bbox.py" "%output_file%" --no-backup

endlocal
