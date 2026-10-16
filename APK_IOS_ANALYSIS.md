# Togg Garajım 1.0.13 — APK / iOS Proje Analizi

Tarih: 2026-10-16  
APK: `/Users/ergunural/Downloads/Togg-Garajim-1.0.13.apk`  
Android paket adı: `com.ibrahim.togggaraj`  
APK sürümü: `1.0.13` (`versionCode 113`)  
Analiz yöntemi: APK manifesti, kaynak arşivi, JADX decompile çıktısı ve WebView/native bridge incelemesi; iOS tarafında Xcode proje dosyaları ve Swift modelleri.

## Sonuç

Mevcut iOS uygulaması canlı Togg hesabı, araç telemetrisi, konum, sürüş/şarj geçmişi ve sunucu analizleri bakımından APK ile önemli ölçüde örtüşüyor. Ancak APK’nın 1.0.13 sürümündeki ayırt edici genişleme, salt-okunur araç ekranından gerçek araç erişim katmanına geçmesi:

- Bluetooth LE araç bağlantısı ve sürekli bağlantı servisi
- Dijital anahtar kurulumu, sertifika/provisioning ve anahtar tanılama
- Sürüş yetkilendirme
- BLE üzerinden kapı, bagaj ve klima komutları
- Kullanıcı onaylı klima komutu ve durum polling’i
- Android ana ekran widget’ı

Bu işlevlerin hiçbiri mevcut iOS projesinde gerçek olarak uygulanmış değil. iOS’taki dijital anahtar ekranı örnek veri gösteriyor; klima kontrolleri de açıkça örnek modla sınırlı.

## Özellik karşılaştırması

| APK özelliği | APK kanıtı | Mevcut iOS durumu | Değerlendirme |
|---|---|---|---|
| Togg ID girişi | `MainActivity`, PKCE auth callback, `toggid.togg.cloud` | `VehicleStore.swift`, `GarageStore.signIn` | Mevcut |
| Araç listesi / çoklu araç | `vehicles`, `vehicleSelect`, VIN tabanlı seçim | `VehicleSummary`, `vehicles`, `selectVehicle` | Mevcut |
| Batarya / menzil / kilometre | `VehicleWidget`, `VehicleSnapshot`, Web UI | `VehicleState`, `VehicleSnapshot`, `HomeView` | Mevcut |
| İç/dış sıcaklık | Telemetri normalizasyonu | `VehicleState.inside/outside` | Mevcut |
| Lastik basıncı | `VehicleSnapshot`, `tirePressure` | `VehicleState` lastik PSI alanları | Mevcut |
| Lastik sıcaklığı / uyarılar | Web UI `tireDetails`, telemetri alanları | `tireTemperatures`, `brakeWarning`, `engineWarning` | Mevcut / kısmi görünüm |
| Sürüş özeti | `tripGrid`, `lastTripInfo` | `currentTrip`, `sinceCharge`, `TripDerivation` | Mevcut |
| Sunucu sürüş/şarj geçmişi | `logbook`, `journeysOverview`, `chargingOverview` | `ServerAnalyticsView`, `ServerAnalytics` | Mevcut |
| Haftalık/aylık/yıllık analiz | `logPeriod`, özet ve kayıt ekranları | `AnalyticsPeriod`, sunucu analiz ekranı | Mevcut |
| Araç konumu / harita | `map`, `vehicleAddress`, `journeyAddress` | `LocationView`, MapKit ve Apple Maps | Mevcut; harita sağlayıcısı farklı |
| Araç renkleri ve görseller | `vehicle-colors`, `vehicle-spin`, `setVehicleColor`, `viewAngle` | PNG araç görselleri, `VehicleColor`, sınırlı 360° destek | Kısmi; APK’da T10F ve daha geniş Web UI kapsamı var |
| Yardımcı akü | `auxHistory`, widget yardımcı akü alanları | `auxBattery` modeli var | Veri modeli mevcut, ayrı geçmiş/ekran eksik |
| İnternet kotası | `dataVolume`, `dataUsage`, kota progress alanları | `internetUsedGB`, `internetQuotaGB` örnek değerleri | Kısmi; canlı veri kaynağı bağlı değil |
| Ana ekran widget’ı | `VehicleWidget`, `vehicle_widget.xml`, manifest receiver | WidgetKit extension yok | Eksik |
| Canlı BLE telemetrisi | `BleClient`, `BleConnectionService`, BLE izinleri | `CoreBluetooth` veya BLE servisi yok | Eksik |
| Dijital anahtar | `blePrepare`, `bleLearnVehicleKey`, `bleAcceptInvitation`, `bleSaveCarKey` | `DigitalKeyView` yalnızca örnek veri | Eksik / yüksek risk |
| Sertifika işlemleri | `CreateCertificate`, `GetCertificate`, `CertificateInspection` | Sertifika modeli/akışı yok | Eksik / yüksek risk |
| Anahtar tanılama | `KeyDiagnostics`, `bleDiagnostics`, adım ve aday şeması | Yalnızca genel uygulama günlüğü var | Eksik |
| Sürüş yetkilendirme | `bleDriveAuthorization`, `DriveGrant`, countdown ve grant akışı | Yok | Eksik / çok yüksek risk |
| Kapı ve bagaj komutları | `bleQuickToggle`, `bleLock`, `bleUnlock`, `bleTrunkOpen/Close` | `toggleLock/toggleTrunk` yalnızca local örnek state değiştiriyor | Eksik; mevcut kontrol araçta çalışmaz |
| Gerçek klima komutu | `climateCommand`, `climate`, `climateTarget` | `ClimateView` demo state değiştiriyor | Eksik; APK kullanıcı onayı ve polling yapıyor |
| Klima hedef sıcaklık kalıcılığı | `climateTarget` ve araç bazlı hedef | `UserDefaults` ile yerel varsayılan sıcaklık | Kısmi |
| Bildirimler | APK native `POST_NOTIFICATIONS`, Web UI bildirim/notice alanları | Örnek bildirim listesi var | Canlı bildirim entegrasyonu eksik |
| Servis / abonelik verileri | `serviceNotes`, `account`, `subscriptionCard` | Örnek servis ve abonelik ekranları; DEBUG probe mevcut | Kısmi; canlı UI eksik |
| Siri / App Intent | — | `VehicleStatusIntent` | iOS APK’dan farklı bir entegrasyon sunuyor |

## APK mimarisi ve önemli teknik bulgular

### WebView + native bridge

APK arayüzü büyük ölçüde `assets/index.html` içinde çalışıyor. Native Android katmanına `GarajNative.call(...)` üzerinden bağlanıyor. Tespit edilen bridge işlemleri:

`account`, `addWidget`, `auxHistory`, `bleDriveAuthorization`, `bleQuickToggle`, `bleSettings`, `bleState`, `cachedVehicle`, `climate`, `climateCommand`, `climateTarget`, `experience`, `journeyAddress`, `login`, `logout`, `map`, `serviceNotes`, `session`, `setTheme`, `setVehicleColor`, `setVehicleView`, `setWidgetTheme`, `theme`, `trumore`, `vehicle`, `vehicleAddress`, `vehicleAppearance`, `vehicles`, `viewAngle`.

Bu liste, APK’nın iOS projesinden farkını yalnızca ekran düzeyinde değil, native yetenek düzeyinde de gösteriyor.

### BLE ve araç erişimi

Manifestte şu izin ve bileşenler bulunuyor:

- `BLUETOOTH_SCAN`
- `BLUETOOTH_CONNECT`
- `FOREGROUND_SERVICE_CONNECTED_DEVICE`
- `POST_NOTIFICATIONS`
- `BleConnectionService` foreground service
- `VehicleWidget` app widget receiver

`BleClient` içinde taranan cihazların tutulması, GATT bağlantısı, characteristic yazma/okuma, frame exchange, sertifika seçimi, araç anahtarı ve sürüş yetkisiyle ilişkili akışlar bulunuyor. `BleProtocol`, sertifika tarihi ve protokol frame üretimi gibi düşük seviye işlemler içeriyor.

Bu alan Android kodundan Swift’e doğrudan taşınmamalı. Önce gerçek Togg BLE protokolünün yetkili ve güvenli biçimde doğrulanması, iOS arka plan kısıtları ve anahtar saklama modeli tasarlanmalı.

### Klima komutunun güvenlik modeli

APK’da klima komutu tek adımlı bir local state değişimi değil:

1. Mevcut klima durumu okunuyor.
2. Kullanıcı komutu başlatıyor.
3. Native katman kullanıcı onayı istiyor.
4. Komut servis üzerinden gönderiliyor.
5. Sonuç `FAILED`, `REJECTED`, `ERROR` veya `CANCELLED` olarak ele alınıyor.
6. Başarılı kabulden sonra araç durumu yaklaşık 15 saniyelik polling ile izleniyor.
7. Beklenen durum 240 saniye içinde oluşmazsa işlem belirsiz/başarısız kabul ediliyor.

Mevcut iOS `GarageStore.toggleClimate()` bu davranışı uygulamıyor; yalnızca `snapshot.climateOn` değerini değiştiriyor ve canlı modda klima sekmesi gizleniyor.

### Widget

APK widget’ı şunları gösterebiliyor:

- Ana batarya yüzdesi ve menzil
- Yardımcı akü yüzdesi
- İnternet kullanımı/kotası
- Araç görseli ve rengi
- Son araç güncelleme zamanı
- Şarj modu bilgisi
- Yenileme ve uygulamayı açma aksiyonları
- Açık/koyu widget teması

Mevcut iOS uygulamasında WidgetKit target, App Group cache’i ve widget veri sağlayıcısı bulunmuyor.

## iOS için önerilen uygulama sırası

### Faz 1 — Güvenli salt-okunur kapsam

- Canlı yardımcı akü ve internet kotası alanlarını `VehicleState`/`VehicleSnapshot` içine tamamlamak.
- Yardımcı akü geçmişi için mevcut `HistoryStore` ile uyumlu veri modeli oluşturmak.
- Araç renk/görsel eşlemesini APK’daki `vehicleAppearance` ve `viewAngle` davranışına yaklaştırmak.
- Canlı lastik sıcaklığı, fren/sistem uyarıları ve yazılım sürümünü görünür hale getirmek.
- Servis, abonelik ve bildirim uç noktalarını mevcut DEBUG probe’dan üretim ekranlarına taşımadan önce yanıt şemalarını doğrulamak.

### Faz 2 — WidgetKit

- Ayrı WidgetKit extension ve uygun App Group kurulumu.
- Keychain token paylaşmak yerine güvenli, sınırlı bir cache veri sözleşmesi kullanmak.
- Widget refresh policy, eski veri etiketi, oturum yok ve araç seçimi değişti senaryolarını uygulamak.
- Widget için App Intent tabanlı yenileme ve uygulamaya deep link eklemek.

### Faz 3 — Salt-okunur BLE

- CoreBluetooth bağlantı katmanı.
- BLE izinleri, cihaz keşfi, bağlantı/yeniden bağlanma ve telemetri durum makinesi.
- Araç verisini mevcut `VehicleState` içine dönüştüren ayrı adapter.
- BLE tanılama loglarının VIN, token, sertifika ve konum sızdırmaması.
- Gerçek araç ve fiziksel test cihazı olmadan üretim protokolü varsayımı yapılmaması.

### Faz 4 — Araç komutları ve dijital anahtar

Bu faz ayrı güvenlik incelemesi gerektirir:

- Kullanıcı onayı ve biyometrik doğrulama.
- Sertifika/key material için Secure Enclave/Keychain tasarımı.
- Dijital anahtar provisioning, davet kabulü ve sahiplik doğrulaması.
- Kapı, bagaj, klima ve sürüş yetkisi için açık durum makinesi.
- Timeout, iptal, bağlantı kopması ve belirsiz sonuçta tekrar göndermeme.
- Audit log ve güvenli hata mesajları.

## Doğrulama planı

- Model testleri: batarya, yardımcı akü, kota, lastik, şarj modu ve sürüş özeti normalizasyonu.
- Widget testleri: canlı veri, cache, eski veri, oturum kapalı ve eksik alanlar.
- BLE testleri: izin reddi, cihaz yok, bağlantı kopması, tekrar bağlanma ve arka plana geçiş.
- Komut testleri: kullanıcı iptali, servis reddi, timeout, beklenen durumun oluşmaması ve duplicate command engeli.
- Güvenlik testleri: log redaction, Keychain erişimi, App Group cache içeriği ve deep-link doğrulaması.
- Xcode `BuildProject`, `XcodeRefreshCodeIssuesInFile` ve uygun unit/UI testleriyle derleme doğrulaması.

## Son karar

İlk uygulanacak özellik grubu: **WidgetKit + canlı yardımcı akü/kota + eksik salt-okunur telemetri**.  
Dijital anahtar, BLE sürüş yetkilendirme ve araç komutları bu kapsamın dışında tutulmalı; bunlar ancak protokol, güvenlik ve gerçek araç testleri tamamlandıktan sonra ayrı bir geliştirme fazı olarak ele alınmalı.
