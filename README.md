# Microstock Metadata AI

Aplikasi desktop Flutter untuk membuat metadata gambar microstock menggunakan API AI OpenAI-compatible.

## Dukungan Platform

Aplikasi ini bisa berjalan di:

- Linux desktop.
- Windows 10/11.

Project Flutter sudah memiliki folder `linux/` dan `windows/`, jadi bisa dibuild untuk kedua platform selama Flutter desktop support dan toolchain OS tersebut sudah terpasang.

## Fitur Utama

- Import gambar `JPG`, `JPEG`, `JFIF`, `PNG`, dan `WEBP`.
- Import folder gambar secara batch.
- Fallback import manual dari path file/folder.
- Preview gambar, ukuran file, resolusi, dan status proses.
- Generate metadata AI: title, description, keywords, category, editorial, commercial use, AI generated, warnings.
- Edit metadata manual.
- Rename output file dari field `Filename` atau otomatis dari `Title`.
- Write metadata ke file output memakai `exiftool`.
- Batch generate metadata.
- Batch rename file berdasarkan title hasil metadata.
- Batch write metadata ke file gambar.
- Retry gambar yang gagal.
- Remove selected import atau remove semua import dari library tanpa menghapus file di disk.
- Export CSV.
- Settings API dan prompt template tersimpan lokal.

## Menjalankan di Linux

```bash
cd /home/kaligata77/Android/apps/tester
flutter pub get
flutter run -d linux
```

Build release Linux:

```bash
flutter build linux
```

Output build Linux biasanya ada di:

```text
build/linux/x64/release/bundle/
```

## Menjalankan di Windows

Jalankan dari mesin Windows dengan Flutter SDK terpasang:

```powershell
cd path\to\tester
flutter pub get
flutter run -d windows
```

Build release Windows:

```powershell
flutter build windows
```

Output build Windows biasanya ada di:

```text
build\windows\x64\runner\Release\
```

Catatan: build Windows sebaiknya dilakukan di Windows karena membutuhkan Visual Studio Build Tools dengan workload C++ desktop.

## Import Gambar

Tombol `Import` dan `Folder` memakai dialog file native.

Jika dialog import gagal di Linux, install dialog helper:

Fedora:

```bash
sudo dnf install -y zenity
```

Ubuntu/Debian:

```bash
sudo apt install -y zenity
```

Alternatif tanpa dialog native:

- Isi field `Import path fallback` di panel `Library`.
- Masukkan path folder, contoh `/home/user/Pictures`.
- Atau path file, contoh `/home/user/Pictures/image001.jpg`.
- Klik `Import Path`.

Di Windows, isi path manual bisa memakai format seperti:

```text
C:\Users\User\Pictures
```

## Konfigurasi API AI

Aplikasi mendukung API AI yang kompatibel dengan format OpenAI Chat Completions.

Isi panel `Settings AI API`:

- `Base URL`: contoh `http://localhost:8000/v1` atau URL provider API lain.
- `API Key`: isi jika provider membutuhkan token.
- `Model`: nama model vision yang dipakai.
- `Timeout`: batas waktu request dalam detik.
- `Retry`: jumlah retry otomatis.
- `Max keywords`: batas maksimal keyword validasi.

Endpoint yang dipakai:

```text
POST /chat/completions
```

Jika `Base URL` sudah berakhiran `/v1`, aplikasi otomatis memanggil:

```text
/v1/chat/completions
```

Model yang dipakai harus mendukung input gambar/vision.

## Install ExifTool

Fitur `Write to file` dan `Batch Write` membutuhkan `exiftool`.

Fedora:

```bash
sudo dnf install -y perl-Image-ExifTool
```

Ubuntu/Debian:

```bash
sudo apt install -y libimage-exiftool-perl
```

Windows:

- Download ExifTool dari `https://exiftool.org/`.
- Pastikan executable `exiftool` tersedia di `PATH`.
- Cek dari terminal:

```powershell
exiftool -ver
```

## Alur Single Image

1. Klik `Import` atau isi `Import path fallback` lalu klik `Import Path`.
2. Pilih gambar di `Library`.
3. Klik `Generate` atau `Regenerate`.
4. Review dan edit metadata.
5. Klik `Save metadata` untuk menyimpan lokal.
6. Klik `Rename file` jika ingin membuat atau mengganti nama file output di folder `microstock_output`.
7. Klik `Write to file` untuk menulis metadata ke file output di folder `microstock_output`.
8. Klik `Export CSV` jika ingin export spreadsheet.

## Rename File

`Rename file` tidak mengubah file original. Jika gambar masih original, aplikasi membuat satu file output di folder `microstock_output`. Jika gambar sudah berada di `microstock_output`, aplikasi me-rename file output yang sama, bukan membuat duplikat baru.

Contoh title:

```text
Fresh Vegetables on Wooden Table
```

Menjadi:

```text
fresh-vegetables-on-wooden-table.jpg
```

Jika nama file sudah ada di folder output, aplikasi otomatis menambahkan angka seperti `-2`, `-3`, dan seterusnya.

## Write Metadata ke File

Klik `Write to file` untuk menulis metadata gambar terpilih ke file output di folder `microstock_output`.

Tag yang ditulis:

- `XMP-dc:Title`
- `XMP-dc:Description`
- `XMP-dc:Subject`
- `XMP-photoshop:Category`
- `IPTC:ObjectName`
- `IPTC:Caption-Abstract`
- `IPTC:Keywords`

File original tidak diubah. Jika file yang sedang dipilih belum berada di folder `microstock_output`, aplikasi menyalinnya dulu satu kali, lalu menulis metadata pada file output tersebut. Jika file sudah berada di `microstock_output`, aplikasi menulis ke file yang sama dan tidak membuat duplikat baru.

Aplikasi menjalankan `exiftool` dengan `-overwrite_original`, sehingga tidak membuat file backup `_original` di folder output.

## Alur Batch

1. Klik `Folder`, `Import`, atau gunakan `Import Path`.
2. Isi settings API.
3. Klik `Batch` untuk generate metadata banyak gambar.
4. Review hasil yang statusnya `Perlu review` atau `Gagal`.
5. Klik `Retry Failed` jika ada yang gagal.
6. Klik `Batch Rename` untuk membuat atau me-rename file output dari semua file yang sudah punya title.
7. Klik `Batch Write` untuk menulis metadata ke file output dari semua file yang valid.
8. Klik `Export CSV` untuk export metadata.

## Menghapus Import dari Library

- `Delete selected`: menghapus item terpilih dari daftar library saja.
- `Remove all imports`: menghapus semua item import dari daftar library.

Kedua aksi ini tidak menghapus file gambar di disk.

## Catatan Batch

Tombol `Batch` tidak otomatis rename dan write metadata.

- `Batch`: hanya generate metadata dan simpan lokal.
- `Batch Rename`: buat file output jika belum ada, atau rename file output yang sudah ada, berdasarkan title metadata.
- `Batch Write`: buat file output jika belum ada, lalu tulis metadata; jika sudah ada, tulis ke file output yang sama.

File original tetap utuh, dan proses berikutnya tidak membuat duplikat baru.

## Penyimpanan Lokal

Data library, metadata, settings API, dan prompt disimpan lokal menggunakan JSON di application support directory Flutter.

## Validasi Metadata

Aplikasi memberi status review jika:

- Title kosong.
- Description kosong.
- Keyword kurang dari 5.
- Keyword lebih dari batas `Max keywords`.
- Category kosong.
- Ada keyword terlalu panjang.

## Troubleshooting

Jika `Write to file` gagal dengan pesan `exiftool tidak ditemukan`, install `exiftool` dan pastikan tersedia di `PATH`.

Jika generate gagal, cek:

- Base URL benar.
- API key benar jika diperlukan.
- Model mendukung vision/image input.
- Endpoint compatible dengan `/chat/completions`.
- Timeout cukup besar.

Jika import skip semua file, cek log di bagian bawah aplikasi. Log akan menampilkan alasan seperti duplicate, unsupported extension, missing, atau error.
