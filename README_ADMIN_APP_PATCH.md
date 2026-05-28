# Admin MyPresence Flutter App Patch

Patch ini memasukkan hasil catatan perubahan admin app ke project baru `adminmypresence`.

Package Android tidak diubah:

```text
com.adminmypresence
```

File Firebase yang sudah ada dipertahankan:

```text
lib/firebase_options.dart
android/app/google-services.json
```

Fitur yang masuk:

```text
[✓] Firebase init
[✓] Login owner/admin
[✓] Dashboard
[✓] Karyawan list/search/tambah/edit/aktif-nonaktif
[✓] Approval pending approve/reject
[✓] Jadwal kerja menu
[✓] Jadwal lembur create/list/toggle
[✓] Pengumuman + push queue Firestore
[✓] Log notifikasi
[✓] Laporan ringkas
```

Jalankan:

```powershell
flutter clean
flutter pub get
flutter analyze
flutter build apk --debug
```
