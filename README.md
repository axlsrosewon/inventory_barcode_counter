# 재고 실사 바코드 카운터

Local-first barcode inventory counting app for Android.

## Release Values

- App name: `재고 실사 바코드 카운터`
- English listing name: `Inventory Barcode Counter`
- Package: `com.nst.inventorybarcodecounter`
- Version: `1.0.0+1`
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

- The current release AAB was built with Google test ad IDs because AdMob UI automation was unavailable in this session.
- For the production AAB, set real IDs before building:

```powershell
$env:ADMOB_APP_ID='ca-app-pub-...~...'
flutter build appbundle --release `
  --dart-define=ADMOB_BANNER_AD_UNIT_ID='ca-app-pub-.../...' `
  --dart-define=ADMOB_INTERSTITIAL_AD_UNIT_ID='ca-app-pub-.../...'
```

- Firebase Analytics requires a Firebase Android app config for `com.nst.inventorybarcodecounter`. Add `android/app/google-services.json` and the matching FlutterFire options when Firebase Console access is available.
