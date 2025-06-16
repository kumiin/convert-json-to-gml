# Tutorial Script Converter json to gml
## 3dcity importer-exporter
1. Download dan install java jdk, bisa pakai versi 21 : https://www.oracle.com/java/technologies/downloads/#jdk21-windows (x64 MSI Installer)
2. Download 3dcity-importer-exporter versi zip : https://github.com/3dcitydb/importer-exporter/releases/download/v5.4.0/3DCityDB-Importer-Exporter-5.4.0.zip
3. unzip `3DCityDB-Importer-Exporter-5.4.0.zip` dan dapatkan path-nya. Contoh path : `C:\Users\User\geo-ai\3DCityDB-Importer-Exporter-5.4.0`

## Python
1. Install python 3.13
2. Jika versi berbeda maka perlu mengubah file `python.bat` pada bagian `python3.13`. Contoh:
   - versi existing di OS : `3.11`
   - ubah file menjadi `python3.11 "%ROOT_DIR%bbox.py" "%output_file%" --no-backup`, lihat : https://prnt.sc/TMgGGJ0BIYQh

## Penggunaan Script
1. Pull script dari git
2. Edit `credentials.bat`, dan sesuaikan bagian di bawah ini, berikut contoh hasil edit : https://prnt.sc/iermUwVkjj0r
   - `DB_USER` (user postgre)
   - `DB_PASS` (pass user postgre)
   - `DB_HOST` (host postgre)
   - `DB_NAME` (db postgre)
   - `DB_SCHEMA=citydb`
   - `DB_PORT` (port postgre)
3. Edit file `importer.bat` dan `exporter.bat` pada bagian:
   - `IMPEXP_PATH` (path ke file bin 3dcity-importer-exporter). Contoh : `C:\Users\User\geo-ai\3DCityDB-Importer-Exporter-5.4.0\bin\impexp.bat`. Lalu simpan file `importer.bat` dan `exporter.bat`, lihat contoh : https://prnt.sc/7a8FThrai_Jn
4. convert json to gml
   - Cara 1 : default path import and export
     1. Pindahkan file `.json` ke dalam folder `folder-json`
     2. Jalankan file `converter-json-to-gml.bat`
     3. Tunggu sampai proses selesai berjalan
     4. Lihat hasilnya pada `folder-gml`
     5. copy file `.gml` dari `folder-gml` ke server nfs
   - Cara 2 : custom path import and export
     1. Edit file `converter-json-to-gml.bat`, sesuaikan nilai variabel `JSON_DIR`, lihat contoh : https://prnt.sc/T_aCcYZZqPsK
     2. Edit file `exporter.bat`, sesuaikan nilai variabel `output_file`, lihat contoh : https://prnt.sc/RKLjufe_sf_9
     3. Jalankan file `converter-json-to-gml.bat`
     4. Lihat hasilnya pada path variabel `output_file`

## Update kedepan
1. Log setiap proses