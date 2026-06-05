# Microstock Metadata AI

Aplikasi desktop Flutter untuk membuat metadata gambar microstock menggunakan API 9router/OpenAI-compatible.

## Fitur Utama

- Import gambar `JPG`, `JPEG`, `JFIF`, `PNG`, dan `WEBP`.
- Import folder gambar secara batch.
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
- Settings API 9router dan prompt template tersimpan lokal.

## Menjalankan Aplikasi

```bash
cd /home/kaligata77/Android/apps/tester
flutter pub get
flutter run -d linux
```

Untuk build Linux:

```bash
flutter build linux
```

## Import Gambar di Linux

Tombol `Import` dan `Folder` memakai dialog file native. Di beberapa Linux desktop, dialog ini membutuhkan `zenity` atau `kdialog`.

Fedora:

```bash
sudo dnf install -y zenity
```

Ubuntu/Debian:

```bash
sudo apt install -y zenity
```

Jika dialog import gagal, gunakan field `Import path fallback` di panel `Library`:

- Isi path folder, contoh `/home/user/Pictures`.
- Atau isi path file, contoh `/home/user/Pictures/image001.jpg`.
- Klik `Import Path`.

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

Cek instalasi:

```bash
exiftool -ver
```

## Pengaturan API 9router

Isi panel `Settings 9router`:

- `Base URL`: contoh `http://192.168.x.x:xxxxx/v1`
- `API Key`: isi jika API membutuhkan token.
- `Model`: model vision yang dipakai, contoh `gpt-5.5`.
- `Timeout`: batas waktu request dalam detik.
- `Retry`: jumlah retry otomatis.
- `Max keywords`: batas maksimal keyword validasi.

Klik `Test` untuk cek koneksi. Endpoint yang dipakai adalah OpenAI-compatible:

```text
POST /chat/completions
```

Jika Base URL sudah berakhiran `/v1`, aplikasi otomatis memanggil `/v1/chat/completions`.

## Alur Single Image

1. Klik `Import`.
2. Pilih gambar.
3. Pilih gambar di `Library`.
4. Klik `Generate` atau `Regenerate`.
5. Review dan edit metadata.
6. Klik `Save metadata` untuk menyimpan lokal.
7. Klik `Rename file` jika ingin membuat atau mengganti nama file output di folder `microstock_output`.
8. Klik `Write to file` untuk menulis metadata ke file output di folder `microstock_output`.
9. Klik `Export CSV` jika ingin export spreadsheet.

## Rename File

`Rename file` tidak mengubah file original. Jika gambar masih original, aplikasi membuat satu file output di folder `microstock_output`. Jika gambar sudah berada di `microstock_output`, aplikasi me-rename file output yang sama, bukan membuat duplikat baru.

Ada dua cara rename output:

- Edit field `Filename`, lalu klik `Rename file`.
- Biarkan `Filename` sama, isi `Title`, lalu klik `Rename file`. Aplikasi membuat nama file otomatis dari title.

Contoh:

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

Catatan: aplikasi menjalankan `exiftool` dengan `-overwrite_original`, sehingga tidak membuat file backup `_original` di folder output. File original tetap aman karena metadata hanya ditulis ke file di `microstock_output`.

## Alur Batch

1. Klik `Folder` atau `Import` untuk memasukkan banyak gambar.
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

## Apakah Batch Langsung Rename dan Write Metadata?

Tidak otomatis saat tombol `Batch` ditekan.

Alasannya: rename dan write metadata tetap merupakan aksi perubahan file, walaupun sekarang dilakukan pada file output di folder `microstock_output`. Karena itu aplikasi memisahkan aksi batch menjadi tiga tombol:

- `Batch`: hanya generate metadata dan simpan lokal.
- `Batch Rename`: buat file output jika belum ada, atau rename file output yang sudah ada, berdasarkan title metadata.
- `Batch Write`: buat file output jika belum ada, lalu tulis metadata; jika sudah ada, tulis ke file output yang sama.

Ini lebih aman karena pengguna bisa review metadata sebelum membuat file output, file original tetap utuh, dan proses berikutnya tidak membuat duplikat baru.

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

Jika `Write to file` gagal dengan pesan `exiftool tidak ditemukan`, install `exiftool` sesuai OS.

Jika generate gagal, cek:

- Base URL benar.
- API key benar.
- Model mendukung vision/image input.
- Endpoint compatible dengan `/chat/completions`.
- Timeout cukup besar.

Jika rename gagal, cek:

- File original masih ada.
- File tidak sedang dibuka aplikasi lain.
- Folder punya permission write.
- Nama file tidak mengandung `/` atau `\`.
