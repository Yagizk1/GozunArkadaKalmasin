import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'services/wake_word_service.dart'; // WAKE WORD SERVİSİ İÇE AKTARILDI
import 'dart:async'; // ZAMANLAYICI İÇİN EKLENDİ
import 'package:geolocator/geolocator.dart';
import 'package:direct_sms/direct_sms.dart';



void main() {
  runApp(MyApp());
}

// 1. UYGULAMANIN ANA İSKELETİ (Sadece tema ayarlarını tutar)
class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Gözüm Arkada Kalmasın',
      theme: ThemeData(
        primarySwatch: Colors.red,
        scaffoldBackgroundColor: Colors.grey[100],
      ),
      home: AnaSayfa(),
    );
  }
}

class AnaSayfa extends StatefulWidget {
  @override
  _AnaSayfaState createState() => _AnaSayfaState();
}

class _AnaSayfaState extends State<AnaSayfa> {
  
  // Değişkenler
  List<Map<String, String>> secilenKisiler = [];
  bool korumaAcikmi = false;
  bool gizliModAktif = false;
  SesDinlemeServisi? _sesDinlemeServisi;
  final DirectSms directSms = DirectSms();

  @override
  void initState() {
    super.initState();
    
    // 2. DÜZELTME: Sınıfı yeni adıyla başlatıyoruz
    _sesDinlemeServisi = SesDinlemeServisi(
      onWakeWordDetected: () {
        // SES DUYULDUĞUNDA ARTIK GERİ SAYIMI BAŞLATIYORUZ
        acilDurumBaslat(); 
      },
    );
  }

  @override
  void dispose() {
    // 3. DÜZELTME: Kapatırken de yeni isimle durduruyoruz
    _sesDinlemeServisi?.stopListening();
    super.dispose();
  }

  // --- FONKSİYONLAR ---

  

  // ACİL DURUM FONKSİYONU ARTIK DOĞRU YERDE!
  void acilDurumBaslat() {
    int sayac = 10; // 10 saniyelik iptal süresi
    Timer? zamanlayici;

    showDialog(
      context: context,
      barrierDismissible: false, 
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            
            zamanlayici ??= Timer.periodic(Duration(seconds: 1), (timer) {
              if (sayac > 0) {
                setDialogState(() {
                  sayac--;
                });
              } else {
                timer.cancel();
                Navigator.pop(context); 
                gercekAcilDurumTetikte(); 
              }
            });

            return AlertDialog(
              backgroundColor: Colors.red[900],
              title: Text("ACİL DURUM TETİKLENDİ!", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              content: Text(
                "Konumunuz ve yardım talebiniz\n$sayac saniye içinde seçilen kişilere gönderilecek.\n\nYanlış alarm ise hemen iptal edin.",
                style: TextStyle(color: Colors.white, fontSize: 18),
                textAlign: TextAlign.center,
              ),
              actionsAlignment: MainAxisAlignment.center,
              actions: [
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.white),
                    onPressed: () {
                      zamanlayici?.cancel(); 
                      Navigator.pop(context); 
                      print("Acil durum kullanıcı tarafından iptal edildi.");
                    },
                    child: Text("YANLIŞ ALARM - İPTAL ET", style: TextStyle(color: Colors.red[900], fontSize: 18, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // --- GÜNCELLENEN REHBER FONKSİYONU ---
  void rehberiAcVeKisiSec() async {
  if (await Permission.contacts.isGranted) {
    await Future.delayed(Duration(milliseconds: 300));
    final contact = await FlutterContacts.openExternalPick();

    if (contact != null) {
      // Sadece adını değil, tüm detaylarını çekiyoruz
      final tamKisi = await FlutterContacts.getContact(contact.id);

      if (tamKisi != null && tamKisi.phones.isNotEmpty) {
        String yeniAd = tamKisi.displayName;
        String yeniNumara = tamKisi.phones.first.number;

        setState(() {
          // Aynı numara listede zaten var mı diye kontrol ediyoruz
          bool zatenVarMi = secilenKisiler.any((kisi) => kisi['numara'] == yeniNumara);
          if (!zatenVarMi) {
            secilenKisiler.add({'ad': yeniAd, 'numara': yeniNumara});
            print("Eklendi: $yeniAd - $yeniNumara");
          } else {
            print("Bu kişi zaten ekli!");
          }
        });
      } else {
        print("Seçilen kişinin numarası bulunamadı.");
      }
    }
  } else {  
    print("Kullanıcı rehber izni vermedi!");
  }
}

  void gercekAcilDurumTetikte() async {
  print("🚨 ACİL DURUM TETİKLENDİ 🚨");

  // 1. Liste boş mu kontrolü
  if (secilenKisiler.isEmpty) {
    print("❌ HATA: Gönderilecek acil durum kişisi seçilmemiş.");
    return;
  }

  try {
    // 2. Güncel Konumu Al
    Position konum = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high
    );

    // 3. Google Maps Linkini ve Mesajı Hazırla (URL formatı düzeltildi)
    String haritaLinki = "https://maps.google.com/?q=${konum.latitude},${konum.longitude}";
    String acilMesaj = "IMDAT! Tehlikedeyim. Konumum: $haritaLinki";

    // 4. Listedeki herkese sırayla SMS Gönder
    for (var kisi in secilenKisiler) {
      String numara = kisi['numara']!;
      directSms.sendSms(
        message: acilMesaj, 
        phone: numara 
      );
      print("✅ BAŞARILI: SMS '${kisi['ad']}' kişisine gönderildi.");
    }

  } catch (e) {
    print("❌ KRİTİK HATA: $e");
  }
}

  // --- ARAYÜZ (UI) ---

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Gözüm Arkada Kalmasın"), centerTitle: true),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            GestureDetector(
              onTap: () {
                setState(() {
                  // 1. Mevcut işlev: Görsel durumu (kırmızı/yeşil) değiştiriyoruz
                  korumaAcikmi = !korumaAcikmi;

                  // 2. Yeni İşlev: Duruma göre mikrofonu yönetiyoruz
                  if (korumaAcikmi) {
                    // Buton yeşil olduğunda dinlemeyi başlat
                    _sesDinlemeServisi?.startListening();
                    print("KORUMA AKTİF: Dinleme başladı.");
                  } else {
                    // Buton kırmızı olduğunda dinlemeyi durdur
                    _sesDinlemeServisi?.stopListening();
                    print("KORUMA KAPALI: Dinleme durduruldu.");
                  }
                });
              },
              child: AnimatedContainer(
                duration: Duration(milliseconds: 300),
                width: 220,
                height: 220,
                decoration: BoxDecoration(
                  color: korumaAcikmi ? Colors.green : Colors.red,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: korumaAcikmi
                          ? Colors.green.withOpacity(0.4)
                          : Colors.red.withOpacity(0.4),
                      blurRadius: 20,
                      spreadRadius: 5,
                    ),
                  ],
                ),
                child: Icon(
                  korumaAcikmi ? Icons.security : Icons.security_update_warning,
                  size: 100,
                  color: Colors.white,
                ),
              ),
            ),
            SizedBox(height: 30),
            Text(
              korumaAcikmi ? "DİNLEME AKTİF" : "KORUMA KAPALI",
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.bold,
                color: korumaAcikmi ? Colors.green : Colors.red,
              ),
            ),
            SizedBox(height: 40),

            Card(
              elevation: 4,
              child: SwitchListTile(
                title: Text("Gizli Kayıt Modu"),
                subtitle: Text("Tetikteyken ekran kararır."),
                value: gizliModAktif,
                onChanged: (bool value) {
                  setState(() {
                    gizliModAktif = value;
                  });
                },
                secondary: Icon(Icons.visibility_off, color: Colors.blueGrey),
              ),
            ),

            Column(
            children: [
              Text(
                "Acil Durum Kişileri:",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blueGrey),
              ),
              SizedBox(height: 10),
              secilenKisiler.isEmpty 
                ? Text("Henüz kişi seçilmedi", style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic))
                : Wrap(
                    spacing: 8.0, 
                    runSpacing: 4.0, 
                    alignment: WrapAlignment.center,
                    children: secilenKisiler.map((kisi) {
                      return Chip(
                        label: Text(kisi['ad']!),
                        backgroundColor: Colors.red[100],
                        deleteIcon: Icon(Icons.cancel, size: 20, color: Colors.red[900]),
                        onDeleted: () {
                          setState(() {
                            secilenKisiler.remove(kisi);
                          });
                        },
                      );
                    }).toList(),
                  ),
            ],
          ),
            
            SizedBox(height: 15),

            ElevatedButton.icon(
              onPressed: () async {
                Map<Permission, PermissionStatus> statuses = await [
                  Permission.microphone,
                  Permission.location,
                  Permission.sms,
                  Permission.contacts,
                ].request();

                if (statuses[Permission.microphone]!.isGranted &&
                    statuses[Permission.location]!.isGranted) {
                  print("Harika! Mikrofon ve Konum izni alındı.");
                  rehberiAcVeKisiSec(); 
                } else {
                  print("Uygulamanın çalışması için izin vermeniz gerekiyor!");
                }
              },
              style: ElevatedButton.styleFrom(
                padding: EdgeInsets.symmetric(horizontal: 30, vertical: 15),
              ),
              icon: Icon(Icons.people),
              label: Text("Acil Durum Kişilerini Seç"),
            ),
          ],
        ),
      ),
    );
  }
}