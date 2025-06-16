@echo off
setlocal enabledelayedexpansion

:: Ambil direktori aktif
set ROOT_DIR=%~dp0
set PGCLIENT_DIR=%ROOT_DIR%postgresql-client
set BACKUP_FILE=%ROOT_DIR%db-backup-before-import.sql
set TRUNCATE_SQL=%ROOT_DIR%truncate_all.sql

call "%ROOT_DIR%credentials.bat"
set PGPASSWORD=%DB_PASS%


echo ================================
echo      RESET DATABASE TOOL
echo ================================

:: Cek file backup
if not exist "%BACKUP_FILE%" (
    echo ERROR: File backup "%BACKUP_FILE%" tidak ditemukan.
    goto end
)

:: Cek file truncate SQL
if not exist "%TRUNCATE_SQL%" (
    echo ERROR: File SQL truncate "%TRUNCATE_SQL%" tidak ditemukan.
    goto end
)

:: Cek direktori postgresql-client
if not exist "%PGCLIENT_DIR%" (
    echo ERROR: Direktori postgresql-client tidak ditemukan.
    goto end
)

:: Konfirmasi user
echo Backup ditemukan: %BACKUP_FILE%
echo Akan menggunakan psql dari direktori: %PGCLIENT_DIR%
echo Database akan dikembalikan ke kondisi sebelum import.
@REM pause

:: Masuk ke direktori postgresql-client
pushd "%PGCLIENT_DIR%"

:: 1. Truncate semua isi database
echo Menghapus seluruh isi database...
psql -U %DB_USER% -h %DB_HOST% -d %DB_NAME% -f "%TRUNCATE_SQL%"
if errorlevel 1 (
    echo Gagal menghapus isi database. Proses dibatalkan.
    popd
    goto end
)

:: 2. Restore dari file .sql menggunakan psql
echo Melakukan restore dari file backup (.sql)...
pg_restore -U %DB_USER% -h %DB_HOST% -d %DB_NAME% -c "%BACKUP_FILE%"
if errorlevel 1 (
    echo Restore gagal. Silakan periksa kembali file backup atau koneksi database.
) else (
    echo Database berhasil di-reset ke kondisi sebelum import.
)

popd

:end
endlocal
@REM pause
