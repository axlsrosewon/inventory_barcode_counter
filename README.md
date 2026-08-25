# 재고 실사 바코드 카운터

Local-first barcode inventory counting app for Android.

## Release Values

- App name: `재고 실사 바코드 카운터`
- English listing name: `Inventory Barcode Counter`
- Package: `com.nst.inventorybarcodecounter`
- Version: `1.0.2+3`
- AdMob app ID: `ca-app-pub-3569416988400580~2299372578`
- AdMob banner unit ID: `ca-app-pub-3569416988400580/2112308347`
- AdMob interstitial unit ID: `ca-app-pub-3569416988400580/4329659601`
- Contact website: `http://nst21c.com`
- Privacy policy: `https://axlsrosewon.github.io/inventory-barcode-counter-privacy/`
- Release AAB: `build/app/outputs/bundle/release/app-release.aab`

## Implemented MVP

- Inventory sessions
- Camera barcode and QR scanning
- Duplicate scan merge with quantity +1
- Manual code entry
- Optional item name or memo
- Quantity edit with + / - and direct edit dialog
- Last scan undo
- Search and sort by recent, code, or quantity
- CSV export and Android share sheet
- Local SQLite storage with no server
- AdMob banner/interstitial integration
- Firebase Analytics event wrapper

## Verification

```powershell
flutter analyze
flutter test
flutter build apk --debug
flutter build appbundle --release
```

## Production Notes

- The 2026-08-16 update build uses the real AdMob app, banner, and interstitial IDs by default.
- Firebase Analytics requires a Firebase Android app config for `com.nst.inventorybarcodecounter`. Add `android/app/google-services.json` and the matching FlutterFire options when Firebase Console access is available.
