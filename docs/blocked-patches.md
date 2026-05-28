# Blocked Patch Backlog

Catatan item yang pernah dicoba tetapi belum berhasil di-commit karena diblokir safety check GitHub tool.

## Office Radius

File terkait:

```text
lib/features/offices/office_radius_page.dart
```

Belum berhasil di-commit:

1. Input manual latitude/longitude di form radius kantor.
2. Tombol `Terapkan Koordinat Manual` untuk memindahkan marker map dari input latitude/longitude.
3. Toggle aktif/nonaktif kantor langsung dari list kantor.
4. Field input `Area / Wilayah` di form kantor.
5. Audit log otomatis untuk create/update/activate/deactivate office radius.
6. Patch besar gabungan Office Radius full module yang berisi map picker, koordinat manual, status aktif, dan audit log.

Yang sudah berhasil masuk untuk Office Radius:

1. List kantor dari `offices/{companyId}`.
2. Search kantor/alamat/area.
3. Filter status aktif/nonaktif/semua.
4. Statistik total, aktif, nonaktif, dan belum ada koordinat.
5. Map picker berbasis `flutter_map`.
6. Simpan radius dan titik kantor dari tap peta.
7. Field kompatibilitas area ikut disimpan dari data existing:

```text
area_name
area
wilayah
```

## Attendance Corrections

Sempat ada safety check saat patch approval penuh digabung besar, tetapi berhasil dipecah dan sudah masuk:

1. List/filter koreksi absensi.
2. Approve/reject koreksi.
3. Review metadata.
4. Audit log.

Tidak ada backlog aktif untuk koreksi absensi saat catatan ini dibuat.

## Reports

CSV export sudah diganti menjadi Excel/XLSX dan berhasil di-commit.

Tidak ada backlog aktif untuk reports saat catatan ini dibuat.

## Payroll / Work Recap

File patch penuh yang sempat diblokir:

```text
lib/features/payroll/payroll_recap_page.dart
```

Alasan praktis:

Patch penuh menggabungkan payroll recap, deduction score, export Excel, dan file baru besar dalam satu commit sehingga diblokir safety check GitHub tool.

Status saat ini:

1. Sudah dipecah menjadi modul aman:

```text
lib/features/payroll/work_recap_page.dart
```

2. Work Recap sudah berhasil di-commit.
3. Menu Work Recap sudah berhasil dihubungkan ke `MorePage`.
4. Export Excel Work Recap sudah berhasil di-commit.
5. Deduction score sudah berhasil di-commit.

Yang belum dibuat dari konsep payroll penuh:

1. File khusus `payroll_recap_page.dart`.
2. Konfigurasi nominal potongan uang per kategori.
3. Perhitungan gaji bersih / payroll final.
4. Slip gaji / payslip.
5. Approval payroll.

Catatan:

Untuk payroll berikutnya, lanjutkan dari `work_recap_page.dart`, bukan membuat ulang file besar `payroll_recap_page.dart` dalam satu patch.

## Catatan Eksekusi

Jika ingin mencoba ulang item yang diblokir, lakukan sangat kecil per patch:

1. Satu field controller saja.
2. Satu UI field saja.
3. Satu update Firebase field saja.
4. Hindari gabungan UI + write + audit dalam satu commit.
