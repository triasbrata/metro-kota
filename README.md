# Metro Kota

Game transportasi kota bergaya Mini Metro dengan lapisan ekonomi, untuk tujuh kota
Indonesia. Flutter + Flame; semua UI digambar di kanvas game. Daftar fitur yang sudah
dibuat ada di [FITUR.md](FITUR.md), dan isi halaman itch.io di
[store/ITCH_PAGE.md](store/ITCH_PAGE.md).

## Pengembangan

```sh
flutter test                 # semua test
./scripts/dev-linux.sh       # Linux (WSLg) dengan hot reload
./scripts/dev-windows.sh     # Windows dengan hot reload, dijalankan dari WSL
./scripts/build-windows.sh   # build release Windows ke C:\src\metro-kota-windows\
```

## Rilis ke itch.io

Setiap push ke `main` menjalankan [.github/workflows/itch.yml](.github/workflows/itch.yml):

1. menjalankan analyze dan test;
2. membangun Linux, Windows, macOS, dan Android secara paralel;
3. mengunggah tiap build dengan [butler](https://itch.io/docs/butler/) ke channel
   `linux`, `windows`, `mac`, dan `android` dengan versi `X.Y.Z.<nomor run>` (X.Y.Z dari
   `pubspec.yaml`).

Bisa juga dijalankan manual dari tab Actions (**Run workflow**). Push yang lebih baru
membatalkan run lama yang masih berjalan, jadi itch tidak pernah menerima build yang
urutannya terbalik.

### Pengaturan sekali di GitHub

Di repo: **Settings → Secrets and variables → Actions**.

| Jenis | Nama | Isi |
|---|---|---|
| Variable | `ITCH_GAME` | `user/nama-game` dari URL itch, mis. `triasbrata/metro-kota` |
| Secret | `BUTLER_API_KEY` | API key dari https://itch.io/user/settings/api-keys |
| Secret (opsional) | `ANDROID_KEYSTORE_BASE64` | keystore rilis, `base64 -w0 release.jks` |
| Secret (opsional) | `ANDROID_STORE_PASSWORD` | password keystore |
| Secret (opsional) | `ANDROID_KEY_ALIAS` | alias key |
| Secret (opsional) | `ANDROID_KEY_PASSWORD` | password key |

Game-nya harus sudah dibuat dulu di itch.io (**Upload new project**, jenis
*Downloadable*); butler hanya mengisi file-nya.

Tanpa secret Android, APK ditandatangani debug key milik runner, yang berbeda setiap run,
sehingga APK baru tidak bisa meng-update APK lama. Buat keystore sekali dan simpan baik-baik:

```sh
keytool -genkey -v -keystore release.jks -keyalg RSA -keysize 2048 -validity 10000 -alias metro-kota
base64 -w0 release.jks   # isi untuk ANDROID_KEYSTORE_BASE64
```

Untuk build lokal, taruh `android/key.properties` (diabaikan git) berisi `storeFile`,
`storePassword`, `keyAlias`, dan `keyPassword`.

Build macOS belum ditandatangani Apple, jadi pemain membukanya pertama kali dengan klik
kanan → Open. Petunjuknya ada di halaman itch.
