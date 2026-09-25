# Metro Kota: daftar fitur yang diminta

Checklist untuk diperiksa ulang. Tiap poin: permintaanmu, lalu cara kerjanya di game, lalu cara mengeceknya.
Angka-angka balancing ada di `lib/cities.dart` (per kota) dan konstanta `Game` di `lib/game.dart`.

## Dasar game

- [ ] **1. Game ala Mini Metro di Flutter: urus transportasi umum kota besar, cari uang untuk membuka jalur baru.**
  - Stasiun (lingkaran, segitiga, kotak, bintang, belah ketupat) muncul bertahap. Penumpang ingin pergi ke stasiun berbentuk tertentu.
  - Tarik jari dari stasiun ke stasiun untuk membuka jalur. Jalur pertama gratis; jalur berikutnya **Rp5.000, Rp10.000, Rp15.000**, dst. (diturunkan dari kelipatan Rp10.000).
  - Tiap penumpang yang sampai membayar tarif. Uang dipakai untuk rel (**Rp500 per segmen**, turun dari Rp800), jalur, dan kereta (Rp6.000).
  - **Menambah kereta dengan drag and drop:** seret tombol "🚆 Kereta Rp6.000" di bawah ke rel jalur mana pun. Kereta bayangan menempel di rel, dengan panah arah jalannya. **Geser jari searah rel** untuk memilih arah (misalnya ke kiri berarti menuju stasiun di kiri, a → b atau b → a). Lepas jari untuk menaruh kereta di titik itu. Tidak bisa ditaruh di terowongan yang belum selesai.
  - **Tombol mati kalau uang kurang:** tombol Kereta (dan Gerbong) jadi abu-abu dan tidak bisa diseret selama uang di bawah harganya. Begitu uang pas atau lebih, tombol langsung hidup lagi. Mengetuk tombol yang mati menampilkan harganya.
  - **Gerbong (Rp1.200 = 1/5 harga kereta):** seret tombol "Gerbong" ke kereta mana pun (kereta sasaran diberi lingkaran). **Bisa juga dilepas langsung di rel:** gerbong otomatis dipasang ke kereta jalur itu yang gerbongnya **paling sedikit** (kalau sama banyak, kereta yang paling dekat). Kereta yang akan dapat gerbong sudah diberi lingkaran selama diseret. Kalau semua kereta di jalur itu sudah penuh (3 gerbong), muncul pesan dan uang tidak dipotong. Tiap gerbong menambah 6 kursi, maksimal 3 gerbong per kereta (total 24 penumpang). Gerbong digambar di belakang lokomotif, lengkap dengan penumpangnya, dan **selalu menempel di rel**: mengikuti belokan, melewati stasiun ke segmen sebelumnya, memutar di loop, dan ikut berbalik di stasiun ujung (diperbaiki, dulu gerbong keluar jalur di tikungan).
- [ ] **Mengubah bentuk rel.** Pegang rel, tarik ke tanah kosong (bukan ke stasiun), lalu lepas: segmen itu dibangun ulang mengikuti **rencana yang ditampilkan** (stasiun → titik jari → stasiun, tetap bergaya peta metro). Label harganya "↝ Rp500" (1 segmen), ditambah biaya jembatan hanya kalau bentuk baru menyeberang air jauh dari jembatan lama (aturan pakai ulang jembatan tetap berlaku). Kereta di segmen itu ikut pindah ke rel baru. Tarik lalu lepas lagi di dekat jalur lurus aslinya untuk meluruskan rel. Lepas di rel itu sendiri: tidak ada perubahan.
  - Biaya operasional bulanan: **Rp500 per kereta + Rp250 per jalur** (turun dari Rp800 + Rp400). Utang lewat Rp20.000 berarti bangkrut.
  - **Rincian operasional di HUD:** "• N kereta × Rp500 = …" dan "• M jalur × Rp250 = …", di bawah total "Operasional …/bulan".
  - **Stasiun baru muncul tiap 22 detik** (diperlambat dari 14 detik).
  - **Waktu dalam bulan dan tahun**, bukan hari: 1 bulan = 30 detik main, dan HUD menampilkan misalnya "Mar · Tahun 1".
  - Cek: buka jalur, lihat uang bertambah setiap penumpang sampai.
- [ ] **2. (Diubah) Memakai game engine Flame.**
  - Flame menjalankan game loop dan menggambar peta setiap frame. HUD (uang, capaian, tombol) tetap widget Flutter di atasnya dan hanya di-refresh sekitar 10× per detik, tidak setiap frame. Dulu justru HUD yang paling berat.
  - Latar (daratan, grid heksagon, sungai/laut, kawasan izin) direkam sekali dan diputar ulang, lalu digambar ulang hanya saat kamera bergerak atau kawasan berubah.
  - **Hasil ukur** (Jakarta ramai: 6 jalur, 24 stasiun, kecepatan 3×): Windows tetap 60 fps dengan waktu build per frame turun dari 1,6 ms ke 0,9 ms. Mode debug Linux (`dev-linux.sh`) naik dari 39 ke ±48 fps.
  - **Catatan FPS:** angka di bawah 30 fps yang terlihat sebelumnya berasal dari **mode debug** (FPS meter hanya tampil otomatis di debug/profile). Mode debug memang jauh lebih lambat daripada aplikasi jadi. Build release dan profile di Windows stabil 60 fps.
  - Alat ukur: `flutter drive --profile --driver=test_driver/perf_driver.dart --target=integration_test/perf_test.dart -d windows` (atau `-d <id HP>`) mencetak rata-rata waktu build dan raster serta jumlah frame yang telat.
- [ ] **2c. Musik latar gaya SNES yang cozy.** Lagu loop 44 detik (F mayor, ±88 BPM): melodi pulse-wave dengan vibrato, akor e-piano jazzy (Fmaj7–Dm7–Gm7–C7…), bass segitiga, shaker, dan kick lembut, dengan efek gema khas SNES. Diputar pelan (35%) terus-menerus dan menyambung tanpa jeda. Tombol 🎵 di kanan atas (atau **N**) mematikan/menyalakan musik saja. Lagunya dibuat dengan `tool/gen_music.py`, jadi nada, akor, dan tempo bisa diubah di situ.
- [ ] **2b. Efek suara.**
  - Ada suara saat: penumpang sampai (koin, pelan dan tidak terlalu rapat), rel dibangun, kereta ditaruh, stasiun baru muncul, penumpang pergi, acara 🎉, kecelakaan 🚨, kawasan izin 🚧, jembatan selesai, capaian tercapai, uang kurang, kota tamat, dan kalah.
  - Tombol 🔊 di kanan atas (atau tombol **M**) untuk mematikan/menyalakan suara.
  - Suara dibuat dengan `tool/gen_sfx.py` (bisa diubah lalu dijalankan ulang) dan diputar lewat SoLoud (latensi rendah, banyak suara sekaligus). Di mesin tanpa perangkat audio (misalnya WSL) game tetap jalan tanpa suara.

## Perbaikan yang kamu laporkan

- [ ] **3. Kereta keluar jalur.** Rute rel sekarang sama persis di kedua arah, jadi kereta selalu menempel di garis. Cek: buat jalur yang berbelok, lihat kereta bolak-balik.
- [ ] **3b. Rel dibangun saat jari/klik dilepas; selama ditarik masih perencanaan.**
  - Aturan event saat jari/klik ditekan: **in** = masuk area stasiun, **out** = keluar area stasiun, **done** = jari/klik diangkat.
  - **In** ke stasiun baru: stasiun itu tersambung ke rencana. Rencana tampil sebagai garis bayangan, dengan label biaya di dekat jari (merah kalau uang tidak cukup). Kawasan berizin yang belum dibayar ditolak sejak rencana.
  - **Out lalu in lagi** ke stasiun yang sudah ada di rencana, lalu diam **500 ms**: lingkar terisi, lalu stasiun itu langsung lepas dari rencana (stasiun sebelum dan sesudahnya tersambung). Untuk menambahkannya lagi: out lalu in lagi.
  - Diam di stasiun yang baru pertama kali dimasuki tidak menghapus apa pun.
  - Saat dilepas, seluruh rencana dibangun sekaligus. Kalau uang tidak cukup, tidak ada yang dibangun. Menempelkan jari kedua (zoom) membatalkan rencana.
  - Swipe cepat dari stasiun tetap terbaca mulai dari stasiun itu.
- [ ] **4. Tidak bisa menambah rel dengan men-drag garis ke titik baru.**
  - Drag dari tengah garis ke stasiun lain untuk menyisipkan stasiun di antara dua stasiun.
  - Drag dari ujung "T" untuk memperpanjang jalur. Area sentuh ujung T sudah diperbesar.
  - Cek: tarik bagian tengah rel ke stasiun di sampingnya.

## Stage kota

- [ ] **4c. Jalur melingkar (loop).**
  - Buat rencana dengan 3 stasiun atau lebih, lalu lepas jari **di stasiun awal**: jalur tertutup jadi loop. Label biaya diberi tanda ⟳ dan sudah termasuk segmen penutupnya.
  - Bisa juga dari jalur yang sudah ada: tarik dari ujungnya, lalu lepas di stasiun ujung satunya (total minimal 3 stasiun).
  - Kereta di loop berputar terus searah, tidak bolak-balik. Penumpang memilih arah yang terdekat.
  - Loop tidak punya ujung "T", jadi tidak bisa diperpanjang. Menyisipkan stasiun di rel mana pun tetap bisa.
  - Melepas stasiun dari loop (termasuk stasiun awalnya) tetap membuat loop, minimal 3 stasiun.
- [ ] **4b. Melepas stasiun dari jalur (seperti Mini Metro).**
  - Cara 1: pegang bagian rel, **in** ke salah satu stasiun di ujung segmen itu, lalu diam 500 ms.
  - Cara 2 (stasiun ujung): mulai dari stasiun ujung atau ujung "T", **out** dari stasiun itu, lalu **in lagi** ke stasiun yang sama dan diam 500 ms.
  - Muncul pesan "Diam sebentar untuk melepas stasiun dari jalur". Lingkar di stasiun terisi lalu berubah merah dengan tulisan "Lepas", dan stasiun dilepas saat **done** (jari diangkat). Out sebelum done membatalkannya.
  - Stasiun di tengah: kedua tetangganya disambung langsung. Jembatan lama dipakai ulang kalau sambungan baru melintas di atas lantai jembatan yang sama; jembatan di tempat baru dibayar dan dibangun. Stasiun di ujung: jalur memendek.
  - Kereta di rel yang terlepas pindah ke stasiun tetangga, dan penumpangnya tetap di dalam. Jalur minimal 2 stasiun; untuk menghapusnya pakai "Tutup jalur".
- [ ] **5. Stage memakai kota-kota besar Indonesia.** Urutannya Medan → Semarang → Bandung → Makassar → Surabaya → Palembang → Jakarta.
  - Peta bergaya sesuai ciri kota: sungai, laut, kanal.
  - Tiap kota punya modal, harga terowongan, dan keramaian yang berbeda.
- [ ] **6. Kota yang sudah dilewati tidak bisa dimainkan lagi.**
  - Kota tamat ditandai ✓ dan terkunci, lalu kota berikutnya terbuka. Progres tersimpan di HP.
  - Setelah semua tamat muncul tombol "Ulang dari awal".
- [ ] **7–8. Tujuan kota berupa capaian, tanpa batas waktu.** (Menggantikan milestone bertenggat.)
  - Tiga capaian: **uang** (total pendapatan tarif di kota itu, tidak berkurang saat belanja), **stasiun terhubung** (stasiun yang ada di minimal satu jalur aktif), dan **penumpang diantar**.
  - Kota tamat begitu ketiganya terpenuhi bersamaan. Tidak ada tenggat, jadi kalah hanya karena bangkrut atau **terlalu banyak warga marah**.
  - **Meter warga marah (😠, kiri atas):** setiap penumpang yang pergi karena tidak dijemput menambah +1, walaupun datangnya beruntun (misalnya selang 100 ms). Kalau 5 detik tidak ada yang pergi, meter turun pelan-pelan (1 per detik) sampai 0, dan naik lagi begitu ada yang pergi. Penuh (15) = game over "Terlalu banyak warga marah dan pergi!". Aturan lama "stasiun penuh sesak" (cincin merah di stasiun) dihapus.
  - HUD menampilkan tiga bar progres, dengan tanda ✓ hijau untuk capaian yang sudah terpenuhi. Setiap capaian yang terpenuhi memunculkan pesan "… tercapai! 🎯".
- [ ] **9. Target tiap kota jangan terlalu sedikit, makin berat ke Jakarta.**
  - Medan Rp180.000 · 10 stasiun · 500 penumpang; Semarang Rp185.000 · 11 · 600; Bandung Rp240.000 · 12 · 700; Makassar Rp231.000 · 13 · 750; Surabaya Rp343.000 · 14 · 850; Palembang Rp283.000 · 15 · 950; Jakarta Rp536.000 · 18 · 1.100.
- [ ] **10. Daya bayar penumpang berbeda per kota.**
  - Tiap kota punya "tarif wajar": Jakarta Rp500, Surabaya Rp400, Medan/Bandung Rp350, Semarang/Makassar/Palembang Rp300.
  - **(Diubah)** Tarif **tidak** lagi mengurangi jumlah penumpang. Tarif mengatur **kesabaran**: bayar mahal berarti harus cepat dijemput.
  - Lingkar kuning terisi lebih cepat sebanding tarif ÷ tarif wajar. Di Medan (wajar Rp350): Rp175 → sabar 30 detik, Rp350 → 15 detik, Rp700 → 7,5 detik. Rp500 biasa di Jakarta, tapi di Medan membuat penumpang cepat tidak sabar.
  - Tarif diatur dengan tombol −/+ (langkah Rp50). Tarif wajar dan batas sabar ("sabar X dtk") ditampilkan di sebelahnya.

## Penumpang dan stasiun

- [ ] **11. Makin lama waktu tunggu di stasiun, makin jarang penumpang muncul di sana; muncul lagi setelah waktu tunggu turun di bawah batas.**
  - Lingkar kuning di stasiun menunjukkan lamanya waktu tunggu.
  - Saat lingkar penuh (15 detik), stasiun berhenti memunculkan penumpang. Begitu kereta menjemput, lingkar kembali kosong.
- [ ] **12. Kalau lingkar kuning penuh, penumpang hilang satu per satu.** Tiap 2 detik satu penumpang yang paling lama menunggu pergi. HUD: "X kecewa pergi".
- [ ] **13. Reputasi stasiun.**
  - Makin sering penumpang hilang, lingkar kuning terisi makin cepat dan penumpang makin jarang muncul.
  - Makin sering penumpang dijemput, penumpang makin sering muncul.
  - Tiap stasiun punya reputasi 0,3–2: −0,15 per penumpang pergi, +0,03 per penumpang naik.

## Pembangunan

- [ ] **14. Terowongan butuh waktu tambahan untuk dibangun.**
  - Rel yang menyeberangi sungai atau laut butuh 10 detik untuk dibangun (sudah diturunkan 50% dari 20 detik).
  - Selama dibangun, relnya pudar dan **lantai jembatan itu sendiri menjadi bar progres**: bagian di atas air (di antara pagar hitam) terisi warna jalur sedikit demi sedikit, searah dengan relnya. Kereta putar balik di depannya, dan penumpang belum dirutekan lewat sana.
  - Bagian rel di atas sungai/laut diberi **garis hitam di sisi kanan dan kirinya** (pagar jembatan), baik saat dibangun maupun sesudah jadi.
  - **Jembatan dipakai ulang (diperbaiki):** kalau segmen yang sudah punya jembatan diubah (disisipi satu atau beberapa stasiun, atau stasiun tengahnya dilepas), jembatan lama **ikut pindah** ke penyeberangan baru di **sungai yang sama** asalkan masih **dekat** (maks. 160 px peta, ±2 sel heksagon). Tidak bayar biaya jembatan dan tidak dibangun ulang, dan kalau jembatan lama belum selesai, sisa waktunya ikut.
    - Contoh (Medan): rel barat → timur memakai 2 jembatan (Babura dan Deli). Membelokkan rel lewat stasiun di pulau di antara kedua sungai memakai ulang **kedua** jembatannya, jadi hanya bayar relnya.
    - **Menyeberangi sungai yang sama jauh dari jembatan lama**, atau **menyeberanginya lebih sering** dari sebelumnya, dihitung jembatan baru: dibayar dan dibangun.
    - Menyisipkan beberapa stasiun sekaligus dihitung sebagai satu perubahan, jadi label harga rencana selalu sama dengan yang ditagih. (Dulu tiap stasiun dihitung satu per satu, dan itu bisa menagih jembatan untuk rel yang tidak pernah dibangun.)
    - Angka 160 bisa diubah di `Game.bridgeReach`.
- [ ] **15. Event daerah: harus bayar izin dulu sebelum rel boleh lewat.**
  - Peta punya **grid heksagon tipis** di seluruh daratan. Kawasan berizin selalu muncul tepat di sel-sel grid itu (3–4 sel yang bersebelahan, di daratan), jadi tidak ada kotak yang tiba-tiba muncul.
  - Tiap 3 bulan muncul kawasan (Cagar Budaya, Lahan Sengketa, Kompleks Militer, dll.) dengan harga izin, diwarnai oranye di sel-selnya. Dua kawasan tidak pernah berdempetan.
  - **Lahan yang sudah dibebaskan tidak akan kena event izin lagi:** kawasan baru tidak pernah menimpa atau menempel pada kawasan yang sudah dibayar. Nama kawasan juga tidak pernah dipakai dua kali di satu kota (sekarang ada 14 nama), jadi kawasan yang sudah bebas tidak terlihat "muncul lagi". Kalau semua nama sudah terpakai, tidak ada event kawasan lagi.
  - Rel yang lewat kawasan itu ditolak. Ketuk kawasannya, lalu bayar, supaya rel boleh lewat.
  - Kawasan baru tidak pernah muncul di atas rel yang sudah ada.

## Event acak

- [ ] **16. Event acara di suatu daerah: semua orang menuju satu stasiun unik, dengan warna stasiun dan penumpang yang berbeda.**
  - Contoh acara: Konser Musik, Pertandingan Sepak Bola, Festival Kuliner, dll.
  - Acara terjadi di **stasiun yang sudah ada** (dipilih acak). Stasiun itu diisi warna ungu selama acara.
  - Hanya satu acara dalam satu waktu.
  - **Terasa chaos:** begitu acara mulai, setiap stasiun lain **langsung** kedatangan 2 penumpang ungu. Selama acara, penumpang di semua stasiun **bertambah 5×**: laju penumpang biasa tetap sama, dan tambahannya (~80% dari semua penumpang baru) **menuju stasiun acara saja**. Mereka digambar dengan **bentuk yang sama dengan stasiun acara, berwarna ungu** (ungu muda saat di dalam kereta).
  - Penumpang ungu hanya turun di stasiun acara, bukan di stasiun lain yang bentuknya sama.
  - **Waktu selesai dan waktu hilang:**
    - **Waktu selesai** (setelah 1 bulan): acara **tutup**, jadi tidak ada lagi penumpang baru yang menuju ke sana dan lonjakan penumpang berhenti. Muncul pesan "… sudah tutup".
    - **Waktu hilang:** stasiun tetap ungu dan tetap jadi tujuan sampai **semua penumpang yang menuju ke sana sudah sampai atau pergi** karena tidak dijemput. Setelah itu acara hilang ("… selesai: semua pengunjung sudah pulang"). Jadi tidak pernah ada penumpang yang masih menuju acara yang sudah hilang.
    - Pengaman: kalau ada penumpang ungu yang tersangkut lebih dari 1 bulan setelah acara tutup, acara tetap dihilangkan dan penumpang itu jadi penumpang biasa ke bentuk stasiun tersebut.
  - HUD menampilkan nama acara dan sisa waktunya. Setelah tutup, HUD menampilkan "tutup · N pengunjung masih menuju ke sana".
- [ ] **17. Event kecelakaan: harus bayar ganti rugi.**
  - Satu kereta acak berhenti 10 detik dengan lingkar merah berkedip, dan tanda ❗ merah muncul di atas lokasi kecelakaan.
  - **Jalur di titik itu tertutup:** kereta lain di jalur yang sama, dari arah mana pun, tertahan sebelum lokasi kecelakaan. Kalau lokasinya dekat stasiun, kereta menunggu di stasiun. Setelah 10 detik semua kereta lanjut.
  - Ganti rugi Rp3.000 + Rp300 × bulan dipotong walaupun uang kurang, jadi bisa berutang.
- Pemicunya: di tiap pergantian bulan mulai bulan ke-3, peluang 35% salah satu dari dua event di atas terjadi. Bulan kelipatan 3 dipakai untuk event kawasan berizin (poin 15).

- [ ] **18. Pemberitahuan event dengan popup.**
  - Tiap event (acara 🎉, kecelakaan 🚨, kawasan berizin 🚧) muncul sebagai popup berikon dengan penjelasan singkat.
  - Game dijeda selama popup terbuka dan lanjut lagi setelah "Oke". Beberapa event sekaligus ditampilkan bergantian.

- [ ] **19. Hukuman penumpang pergi: penumpang lain jadi lebih cepat ikut pergi.**
  - **(Diubah) Kekesalan dihitung per stasiun, bukan per kota.** Tiap penumpang yang pergi menaikkan kekesalan **stasiun itu saja** (+0,4, maks 4). Stasiun yang sepi bisa kesal sementara stasiun lain yang ramai tetap tenang.
  - Jeda antar penumpang pergi di stasiun itu = 2 detik ÷ (1 + kekesalannya).
  - Kekesalan mereda 0,1 per detik. Stasiun yang kesal diberi tanda 😠 (makin besar makin kesal), dan HUD menampilkan "Warga kesal di N stasiun".

- [ ] **22. Jalur yang sedang dipakai tidak langsung terhapus (rute sementara).**
  - Tekan lama warna jalur, lalu pilih "Tutup jalur". Jalur jadi pudar, dan di palet tertulis ⏳ dengan jumlah kereta yang masih jalan.
  - Selama ditutup: tidak ada penumpang baru yang naik, dan penumpang lain tidak dirutekan lewat jalur ini. Jalur tidak bisa diperpanjang, disisipi stasiun, atau ditambah kereta.
  - Penumpang di dalam kereta tetap diantar kalau tujuannya masih ada di depan. Kalau tidak, mereka turun di stasiun berikutnya untuk pindah jalur.
  - Kereta yang kosong ditarik saat sampai di stasiun. Setelah semua kereta ditarik, jalur hilang dan warnanya bisa dipakai lagi.

## Tampilan

- [ ] **28. Layar pembuka (welcome screen).** Aplikasi dibuka dengan judul Metro Kota di atas peta samar kota berikutnya, dan tiga tombol:
  - **▶ Lanjutkan**, dengan keterangan kota, bulan, dan uangnya: melanjutkan kota yang terakhir dimainkan persis seperti saat ditinggal (stasiun dan antrean, jalur, rel yang dibentuk ulang, loop, kereta dan gerbong, jembatan yang sedang dibangun, kawasan izin, acara, uang, dan waktu). Tombol ini hanya muncul kalau ada permainan yang tersimpan.
  - **Pilih kota** (atau **Main** kalau belum ada simpanan): daftar kota seperti biasa. Kalau kota itu sedang dimainkan, kamu ditanya mau lanjut atau mulai ulang.
  - **Pengaturan**: musik latar (nyala/mati dan volume), efek suara (nyala/mati dan volume), tampilkan FPS, dan **Hapus progres** (dengan konfirmasi) untuk mulai lagi dari Medan. Semua pengaturan disimpan di perangkat. Tombol 🎵/🔊 saat bermain memakai pengaturan yang sama.
  - **Simpan otomatis:** permainan disimpan saat keluar dari kota, saat aplikasi ditinggal ke background, saat jendela ditutup (tombol X di Windows/Linux), dan **setiap minggu** di dalam game (±7,5 detik). Jadi bisa dilanjutkan kapan saja. Kota yang kalah atau tamat menghapus simpanannya.
  - Layar **Pilih kota** punya tombol **←** di kiri atas untuk kembali ke layar pembuka.
  - **Musik menu dan musik bermain dibedakan, tapi lagunya sama, dan tidak lagi seperti lagu tidur:** di layar pembuka, pilih kota, dan pengaturan dimainkan versi 96 BPM dengan kotak musik satu oktaf lebih tinggi, akor yang dipetik, bass berjalan, serta kick dan shaker ringan. Saat masuk kota, musik pindah ke versi bermain (108 BPM, lead pulse, e-piano, bass memantul, kick-snare-shaker) dengan crossfade, lalu kembali saat keluar.
  - **Demo di layar pembuka:** di belakang panel judul, sebuah kota bermain sendiri tanpa UI. Bot terus menghubungkan stasiun ke stasiun dan menambah kereta, penumpang muncul lalu diantar, dan tidak ada warga yang marah. Demo mulai ulang setelah ±1,5 tahun.
- [ ] **29. Tombol Kereta dan Gerbong** ada di kiri, bertumpuk vertikal mulai dari tengah layar ke bawah (mencerminkan daftar jalur di kanan). Tombolnya **hanya ikon** supaya tidak menutupi peta. Arahkan mouse atau **ketuk** untuk melihat **harganya saja** di sebelah kanan tombol (hilang saat mouse keluar atau ada sentuhan lain), lalu **seret** untuk membeli.
- [ ] **31. Angkat kereta untuk membalik arah atau memindahkannya (gratis).** Tekan kereta di rel lalu seret: kereta terangkat dari rel. Geser searah rel untuk memilih arahnya (A→B atau B→A), lalu lepas. Bisa juga dipindah ke bagian rel lain atau ke jalur lain. Penumpang dan gerbongnya ikut. Kalau dilepas di luar rel, kereta kembali ke tempatnya. Kereta yang sedang tertahan kecelakaan tidak bisa diangkat.
- [ ] **32. Jarak antar kereta.** Kereta baru (atau yang dipindah) harus berjarak minimal ±40 px dari kereta lain di jalur yang sama, termasuk dari **buntut/gerbong** kereta lain. Kalau terlalu dekat, pratinjau berwarna merah dengan tulisan "Terlalu dekat", dan saat dilepas muncul pesan **"Gagal menambahkan kereta: terlalu dekat dengan kereta lain"** tanpa memotong uang.
- [ ] **37. Modal event dengan gaya game sendiri, lengkap dengan gambar.** Popup event (acara, kawasan izin, kecelakaan) tampil sebagai modal di atas peta: kartu krem dengan garis tepi tebal, gambar event 16:9 di atas, judul, teks, dan tombol **Oke** hitam. Game berhenti selama modal terbuka. Gambar diambil dari `assets/events/<nama>.png`. Daftar nama file dan mood tiap gambar ada di `assets/events/README.md`. Selama gambarnya belum ada, yang tampil emoji eventnya.
- [ ] **35. Kota yang sudah selesai bisa dimainkan lagi.** Di layar Pilih kota, kota yang selesai ditandai ✓ hijau dan bisa diketuk (kota terkunci ditandai 🔒, tanpa tulisan lain). Kartu kota menampilkan **★ skor** permainan terakhir di kota itu, dicatat saat game over atau saat keluar dari kota yang sudah selesai (lanjut ke kota berikutnya atau keluar dari mode main terus).
  - **Skor** = stasiun terhubung ×100 + pendapatan ÷100 + penumpang diantar ×10 − penumpang pergi ×20 − stasiun tidak terhubung ×50 (minimal 0). Bobotnya tebakan awal.
  - Semua kartu punya susunan yang sama (judul, 2 baris keterangan, baris skor, baris target, baris info kota) sehingga barisnya sejajar. Target dan info kota hanya ikon + angka K/M: 💰 uang, stasiun, penumpang; modal, tarif wajar, terowongan, dan ramai ×N.
- [ ] **36. Rel yang dibentuk ulang tidak terlipat lagi.** Rel yang dibelokkan lewat satu titik tidak lagi jadi "lurus – geser sedikit – lurus" (terlipat). Bagian miringnya ditaruh di awal/akhir, sehingga rel paling sedikit berbelok.
- [ ] **34. Setelah kota selesai: main terus atau lanjut.** Saat semua target tercapai, kotak "Kota terhubung! 🎉" menawarkan dua pilihan:
  - **∞ Main terus di <kota>:** kota tetap berjalan tanpa batas (stasiun terus muncul, uang terus berjalan). **Tidak ada akhirnya, termasuk game over:** utang boleh lewat batas dan meter warga marah tidak berlaku (penumpang tetap bisa pergi dan membuat warga kesal). Di kiri atas tertulis "∞ Main terus", dan permainan ini disimpan otomatis seperti biasa sehingga bisa dilanjutkan dari **▶ Lanjutkan**. Kota tetap dihitung sudah selesai.
  - **Lanjut ke <kota berikutnya>:** langsung membuka kota berikutnya (di kota terakhir tombolnya **Selesai**).
- [ ] **33. HUD ringkas supaya peta tidak tertutup.**
  - **Target kota:** di kiri atas hanya tampil uang, bulan, dan tiga bar kecil (💰 uang, stasiun, penumpang). Ketuk untuk membuka rinciannya (angka target, penumpang kecewa, pemasukan/pengeluaran bulan lalu, rincian operasional). Ketuk lagi untuk menutup.
  - **Tarif:** hanya menampilkan angka tarif. Ketuk untuk membuka tombol − / + dan keterangan tarif wajar serta kesabaran. Menutup sendiri saat mouse keluar atau ada sentuhan/klik di tempat lain (atau tekan ✕).
  - **Jumlah kereta** tampil di dalam lingkaran warna masing-masing jalur di kanan (🚆 2), jadi tidak perlu lagi kotak "1 kereta" di bawah.
- [ ] **30. Tombol "+" di daftar jalur langsung masuk mode rencana jalur baru.** Muncul pita di atas: "Ketuk stasiun awal jalur baru". Stasiun pertama yang diketuk menjadi titik mulai. Ketuk stasiun lain untuk menambahkannya ke rencana, ketuk stasiun yang sudah direncanakan untuk menghapusnya, dan ketuk stasiun awal lagi (minimal 3 stasiun) untuk membuat loop. Pita menampilkan jumlah stasiun dan harganya (merah kalau uang kurang), lalu tekan **Bangun**, atau **Batal**/Esc. Menyeret juga bisa, dan di mode ini selalu membuat jalur baru, tidak pernah memperpanjang jalur lama.

- [ ] **27. Rel yang dipakai beberapa jalur tidak saling menumpuk.** Di bagian rel yang dilewati 2 jalur atau lebih, tiap jalur punya lajur sendiri **berdampingan**, bersentuhan tapi tidak ditumpuk. **Lebarnya sama dengan jalur biasa**, tidak mengecil. Di luar bagian bersama, jalur kembali ke tengah. **Sambungannya mulus:** jalur tidak lagi patah atau melompat ke samping di awal/akhir bagian bersama. Jalur bergeser pelan ke lajurnya (±12 px), dan belokan lajur dibuat membulat. **Urutan lajur tetap sama melewati tikungan**: jalur yang berdampingan tidak lagi bertukar sisi atau bersilangan di sudut, dan sudut lajur dibelokkan sekali dengan bersih. Kereta dan gerbong mengikuti lajur yang sama persis. **Semua belokan rel** (bukan hanya yang dipakai bersama) digambar sebagai lengkungan halus seperti Mini Metro. Rel digambar dengan geometri pasti (garis lurus antar titik belok, lalu lengkungan Bézier di tiap sudut), tidak lagi dari potongan kecil tiap 3 px. Kereta berjalan di lajur jalurnya masing-masing, dan pagar jembatan yang dipakai bersama mengapit semua lajur.
- [ ] **39. Kota baru menunggu rel pertama.** Saat kota baru dibuka, belum ada penumpang yang muncul dan waktu belum berjalan (tidak ada stasiun baru, tidak ada biaya bulanan) sampai kamu membuat rel pertama.
- [ ] **40. Tombol kembali (←) satu komponen untuk semua layar.** Lingkaran putih dengan panah yang sama di Pilih kota, Pengaturan, dan di dalam kota. Judul layar di sebelahnya sejajar tepat dengan tengah tombol.
- [ ] **38. Semua UI digambar oleh game engine, bukan widget.** Layar pembuka, pilih kota, pengaturan, HUD di kota, modal event, kotak konfirmasi, dan toast semuanya digambar langsung di kanvas Flame. Rincian target memakai ikon saja dengan angka ribuan dibulatkan (10,8K, 1,2M). Tidak ada teks penjelasan di UI kecuali diminta.

- [ ] **20. Zoom.**
  - Cubit dengan dua jari untuk zoom (1×–3×) dan geser dengan dua jari untuk memindah peta.
  - Satu jari tetap untuk menarik rel. Peta tidak bisa digeser keluar layar.
  - Tombol ⤢ (muncul saat zoom) mengembalikan ke tampilan seluruh kota.

- [ ] **21. Versi desktop (Linux).**
  - Build: `flutter build linux --release`, hasilnya di `build/linux/x64/release/bundle/metro_kota`. Bisa dijalankan di WSL lewat WSLg.
  - Kontrol mouse: **drag klik kiri** untuk menarik rel, **scroll** untuk zoom di posisi kursor, **drag klik kanan/tengah** untuk geser peta.
  - Keyboard: **Space** untuk pause, lalu lanjut lagi dengan kecepatan sebelumnya (1× atau 2×).
  - **Versi Windows:** jalankan `./scripts/build-windows.sh` dari WSL. Skrip ini menyalin proyek ke `C:\src\metro-kota-build`, build dengan Flutter Windows (`C:\src\flutter`), lalu menaruh hasilnya (tanpa zip) di folder **`C:\src\metro-kota-windows\`**. Jalankan `metro_kota.exe` di dalamnya, dan biarkan file lain di folder itu karena dibutuhkan exe.
- [ ] **24. Tombol pause / jalan / cepat 2× tersusun vertikal** (cepat sekarang 2×, bukan 3×) di kanan atas. Tombol yang sedang aktif (tidak bisa diklik) dibuat semi-transparan.
- [ ] **26. Daftar jalur (palet warna) di kanan, mulai dari tengah layar dan bertambah ke bawah.**
  - Urutannya: jalur yang sudah ada sesuai urutan dibuka, lalu tombol "+" beserta harganya, lalu titik kecil untuk warna yang belum dibuka. Jalur baru selalu muncul di bawah. Di layar pendek, daftar mengecil supaya muat.
  - Tidak ada lagi pita abu-abu di belakang daftar/tombol. Daratan peta mengisi seluruh layar, dan sungai/laut yang menyentuh tepi peta bersambung sampai tepi layar.
- [ ] **25. FPS meter untuk developer.**
  - Pojok kanan bawah menampilkan "60 fps · 16,7 ms" (diperhalus). Warnanya merah kalau di bawah 50 fps.
  - Otomatis tampil di mode debug/profile (termasuk `./scripts/dev-linux.sh`), tersembunyi di build release. Bisa dinyalakan di **Pengaturan → Tampilkan FPS**, dan tombol **F** menyalakan/mematikannya saat bermain.
- [ ] **23. Mode pengembangan Linux dengan hot reload.**
  - Jalankan `./scripts/dev-linux.sh` dari folder proyek.
  - Setiap file `.dart` di `lib/` yang disimpan langsung di-hot-reload (dicek tiap 1 detik).
  - Di terminal: `r` = reload, `R` = restart, `q` = keluar.
  - **Windows dengan hot reload:** jalankan `./scripts/dev-windows.sh` dari WSL. Aplikasi terbuka di Windows (mode debug). Setiap file di `lib/` atau `assets/` yang disimpan disalin ke `C:\src\metro-kota-build` dan langsung di-hot-reload. Ctrl+C untuk berhenti (jendela ikut tertutup). Mode debug lebih lambat dari build release.

## Belum dibuat (bisa diminta)

- Upgrade kecepatan kereta.
- Balancing: angka target dan harga masih tebakan awal dan perlu dicoba dulu.
