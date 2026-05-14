import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'services/wake_word_service.dart';
import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:telephony/telephony.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;

void main() async {

  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Gözün Arkada Kalmasın',
      theme: ThemeData(
        primarySwatch: Colors.red,
        scaffoldBackgroundColor: Colors.grey[100],
      ),
      home: AnaSayfa(),
    );
  }
}

class AnaSayfa extends StatefulWidget {
  const AnaSayfa({super.key});

  @override
  State<AnaSayfa> createState() => _AnaSayfaState();
}

class _AnaSayfaState extends State<AnaSayfa> {
  // Değişkenler
  List<Map<String, String>> secilenKisiler = [];
  List<String> tetikleyiciKelimeler = ["imdat", "yardım"];
  TextEditingController kelimeController = TextEditingController();
  bool korumaAcikmi = false;
  SesDinlemeServisi? _sesDinlemeServisi;
  final Telephony telephony = Telephony.instance;

  @override
  void initState() {
    super.initState();

    _sesDinlemeServisi = SesDinlemeServisi(
      onWakeWordDetected: () {
        acilDurumBaslat();
      },
    );
  }

  @override
  void dispose() {
    _sesDinlemeServisi?.stopListening();
    record.dispose();
    super.dispose();
  }

  // --- FONKSİYONLAR ---

  void acilDurumBaslat() {
    int sayac = 10;
    Timer? zamanlayici;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (BuildContext statefulContext, StateSetter setDialogState) {
            zamanlayici ??= Timer.periodic(Duration(seconds: 1), (timer) {
              if (sayac > 0) {
                setDialogState(() {
                  sayac--;
                });
              } else {
                timer.cancel();
                if (mounted) Navigator.pop(dialogContext);
                gercekAcilDurumTetikte();

                // 1. GÜNCELLEME: Mikrofon çakışmasını önlemek için,
                // 30 saniyelik ses kaydı BİTTİKTEN SONRA dinlemeyi başlatıyoruz (32 sn bekleme).
                if (korumaAcikmi) {
                  Future.delayed(Duration(seconds: 32), () {
                    _sesDinlemeServisi?.startListening(tetikleyiciKelimeler);
                    print("Koruma modu açık: 30sn kayıt bitti, dinleme yeniden başlatıldı.");
                  });
                }
              }
            });

            return AlertDialog(
              backgroundColor: Colors.red[900],
              title: Text(
                "ACİL DURUM TETİKLENDİ!",
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
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
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                    ),
                    onPressed: () {
                      zamanlayici?.cancel();
                      if (mounted) Navigator.pop(dialogContext);
                      print("Acil durum kullanıcı tarafından iptal edildi.");

                      // 2. GÜNCELLEME: Yanlış alarm diyip iptal edildiğinde
                      // koruma hala açıksa sistemi hemen dinlemeye al.
                      if (korumaAcikmi) {
                        Future.delayed(Duration(milliseconds: 500), () {
                          _sesDinlemeServisi?.startListening(
                            tetikleyiciKelimeler,
                          );
                          print(
                            "İptal edildi. Koruma modu açık: Dinleme yeniden başlatıldı.",
                          );
                        });
                      }
                    },
                    child: Text(
                      "YANLIŞ ALARM - İPTAL ET",
                      style: TextStyle(
                        color: Colors.red[900],
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void rehberiAcVeKisiSec() async {
    // Sadece izni kontrol etme, yoksa izin iste.
    PermissionStatus rehberIzin = await Permission.contacts.request();
    if (rehberIzin.isGranted) {
      await Future.delayed(Duration(milliseconds: 300));
      final contact = await FlutterContacts.openExternalPick();

      if (contact != null) {
        final tamKisi = await FlutterContacts.getContact(contact.id);

        if (tamKisi != null && tamKisi.phones.isNotEmpty) {
          String yeniAd = tamKisi.displayName;
          String yeniNumara = tamKisi.phones.first.number;

          if (!mounted) {
            return; // Asenkron işlem sonrası sayfa kapandıysa çökmesin
          }

          setState(() {
            bool zatenVarMi = secilenKisiler.any(
              (kisi) => kisi['numara'] == yeniNumara,
            );
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

    if (secilenKisiler.isEmpty) {
      print("❌ HATA: Gönderilecek acil durum kişisi seçilmemiş.");
      return;
    }

    // 1. DÜZELTME: Mikrofon çakışmasını önlemek için arka plan dinlemesini kesin olarak durduruyoruz!
    _sesDinlemeServisi?.stopListening();

    try {
      // 2. DÜZELTME: İzinleri kayıt BAŞLAMADAN ÖNCE alıyoruz. (Sistem pop-up çıkarırsa kaydı kesmesin diye)
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          print("❌ HATA: Konum izni verilmedi.");
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        print("❌ HATA: Konum izinleri kalıcı olarak reddedildi.");
        return;
      }

      PermissionStatus smsIzin = await Permission.sms.request();
      if (!smsIzin.isGranted) {
        print("❌ HATA: SMS gönderme izni reddedildi.");
        return;
      }

      // --- İZİNLER TAMAM, ŞİMDİ SES KAYDINI ARKA PLANDA BAŞLAT ---
      acilDurumKaydiniBaslat().then((dosyaYolu) async {
        if (dosyaYolu != null) {
          print("📁 30 Saniyelik Ses dosyası hazır: $dosyaYolu");
          
          String? sesLinki = await sesiUcretsizBulutaYukle(dosyaYolu);

          if (sesLinki != null) {
            String ikinciMesaj = "Ses kaydım tamamlandı. O anki durumu dinlemek için tıklayın: $sesLinki";
            
            for (var kisi in secilenKisiler) {
              String numara = kisi['numara']!;
              telephony.sendSms(
                to: numara, 
                message: ikinciMesaj,
                isMultipart: true 
              );
              print("✅ BAŞARILI: İkinci SMS (Ses Linki) '${kisi['ad']}' kişisine gönderildi.");
            }
          } else {
            print("❌ Buluta yükleme başarısız olduğu için 2. SMS atılamadı.");
          }
        }
      });

      // --- AYNI ANDA KONUMU AL VE İLK MESAJI GÖNDER ---
      Position konum = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      String haritaLinki =
          "https://maps.google.com/?q=${konum.latitude},${konum.longitude}";
      
      String acilMesaj = "IMDAT! Tehlikedeyim. Konumum: $haritaLinki\n(30 saniye içinde ses kaydım da iletilecek)";

      for (var kisi in secilenKisiler) {
        String numara = kisi['numara']!;
        telephony.sendSms(
          to: numara, 
          message: acilMesaj,
          isMultipart: true
        );
        print("✅ BAŞARILI: İlk SMS (Konum) '${kisi['ad']}' kişisine gönderildi.");
      }
    } catch (e) {
      print("❌ KRİTİK HATA: $e");
    }
  }

  // Ses kayıt cihazımızı ve durumunu tanımlıyoruz
  final record = AudioRecorder();
  bool isRecording = false;

  // 30 saniyelik acil durum kayıt fonksiyonu
  Future<String?> acilDurumKaydiniBaslat() async {
    try {
      if (await record.hasPermission()) {
        setState(() {
          isRecording = true;
        });

        final directory = await getApplicationDocumentsDirectory();
        // Her kaydın üzerine yazmaması için isme tarih damgası ekliyoruz
        final String dosyaAdi = "kayit_${DateTime.now().millisecondsSinceEpoch}.m4a";
        final sesDosyasiYolu = '${directory.path}/$dosyaAdi';
        
        await record.start(const RecordConfig(), path: sesDosyasiYolu);
        print("🎙️ Acil durum kaydı başladı (30 Sn)...");

        // 30 saniye bekle
        await Future.delayed(const Duration(seconds: 30));
        
        if (await record.isRecording()) {
          final String? dosyaYolu = await record.stop();
          if (mounted) {
            setState(() {
              isRecording = false;
            });
          }
          print("✅ 30 saniyelik kayıt tamamlandı: $dosyaYolu");
          return dosyaYolu; // Dosya yolunu dışarı aktarıyoruz ki SMS atabilelim
        }
      } else {
        print("❌ Mikrofon izni verilmedi!");
      }
    } catch (e) {
      print("❌ Kayıt başlatılırken hata oluştu: $e");
    }
    return null;
  }

  // --- SES DOSYASINI ÜCRETSİZ VE ANONİM SUNUCUYA YÜKLEME ---
  Future<String?> sesiUcretsizBulutaYukle(String dosyaYolu) async {
    try {
      print("☁️ Dosya ücretsiz sunucuya yükleniyor...");
      
      var request = http.MultipartRequest(
        'POST', 
        Uri.parse('https://catbox.moe/user/api.php')
      );
      
      request.fields['reqtype'] = 'fileupload';
      request.files.add(await http.MultipartFile.fromPath('fileToUpload', dosyaYolu));

      var response = await request.send();
      
      if (response.statusCode == 200) {
        String indirmeLinki = await response.stream.bytesToString();
        print("✅ Ücretsiz Yükleme Başarılı! Link: $indirmeLinki");
        return indirmeLinki;
      } else {
        print("❌ Sunucu hatası: ${response.statusCode}");
      }
    } catch (e) {
      print("❌ Yükleme hatası: $e");
    }
    return null;
  }
  
  // --- ARAYÜZ (UI) ---

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: Text(
          "Gözün Arkada Kalmasın",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.pink[800],
        centerTitle: true,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [

              // --- KAYIT DURUMU GÖSTERGESİ (Sadece kayıt varken görünür) ---
              if (isRecording)
                Container(
                  margin: EdgeInsets.only(bottom: 20),
                  padding: EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                  decoration: BoxDecoration(
                    color: Colors.red[50],
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(color: Colors.red, width: 2),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Yanıp sönen efekti andırması için kırmızı mikrofon
                      Icon(Icons.fiber_manual_record, color: Colors.red, size: 24),
                      SizedBox(width: 10),
                      Text(
                        "Acil Durum Sesi Kaydediliyor...",
                        style: TextStyle(
                          color: Colors.red[900],
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              // 1. BÖLÜM: DEV PANİK BUTONU
              SizedBox(height: 20),
              Center(
                child: Container(
                  width: 220,
                  height: 220,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.redAccent.withOpacity(0.4),
                        spreadRadius: 15,
                        blurRadius: 30,
                        offset: Offset(0, 5),
                      ),
                    ],
                  ),
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red[700],
                      shape: CircleBorder(),
                      padding: EdgeInsets.all(40),
                      elevation: 10,
                    ),
                    onPressed: () {
                      print("🚨 MANUEL SOS BUTONUNA BASILDI! 🚨");
                      acilDurumBaslat(); // BUTON ARTIK DOĞRUDAN TETİKLİYOR
                    },
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.touch_app, size: 60, color: Colors.white),
                        SizedBox(height: 10),
                        Text(
                          "YARDIM\nİSTE",
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            height: 1.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              SizedBox(height: 30),

              // 2. BÖLÜM: DİNLEME (KORUMA) MODU ANAHTARI
              Card(
                elevation: 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
                child: SwitchListTile(
                  title: Text(
                    "Sesli Koruma Modu",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    korumaAcikmi
                        ? "Arka planda tetikleyici kelimeler dinleniyor."
                        : "Dinleme kapalı.",
                  ),
                  secondary: Icon(
                    korumaAcikmi ? Icons.mic : Icons.mic_off,
                    color: korumaAcikmi ? Colors.green : Colors.grey,
                    size: 32,
                  ),
                  value: korumaAcikmi,
                  activeColor: Colors.green,
                  onChanged: (bool deger) {
                    setState(() {
                      korumaAcikmi = deger;
                      if (korumaAcikmi) {
                        _sesDinlemeServisi?.startListening(
                          tetikleyiciKelimeler,
                        );
                      } else {
                        _sesDinlemeServisi?.stopListening();
                      }
                    });
                  },
                ),
              ),
              SizedBox(height: 20),

              // 3. BÖLÜM: TETİKLEYİCİ KELİMELER KARTI
              Card(
                elevation: 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.record_voice_over,
                            color: Colors.pink[800],
                          ),
                          SizedBox(width: 10),
                          Text(
                            "Tetikleyici Kelimeler",
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      Divider(height: 20, thickness: 1),

                      Wrap(
                        spacing: 8.0,
                        runSpacing: 4.0,
                        children: tetikleyiciKelimeler.map((kelime) {
                          return Chip(
                            label: Text(kelime),
                            backgroundColor: Colors.pink[50],
                            deleteIcon: tetikleyiciKelimeler.length > 1
                                ? Icon(
                                    Icons.cancel,
                                    size: 20,
                                    color: Colors.pink[900],
                                  )
                                : null,
                            onDeleted: tetikleyiciKelimeler.length > 1
                                ? () {
                                    setState(() {
                                      tetikleyiciKelimeler.remove(kelime);
                                    });
                                  }
                                : null,
                          );
                        }).toList(),
                      ),
                      SizedBox(height: 15),

                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: kelimeController,
                              decoration: InputDecoration(
                                hintText: "Yeni kelime ekle...",
                                prefixIcon: Icon(
                                  Icons.add_comment,
                                  color: Colors.grey,
                                ),
                                filled: true,
                                fillColor: Colors.grey[200],
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide.none,
                                ),
                                contentPadding: EdgeInsets.symmetric(
                                  vertical: 0,
                                ),
                              ),
                            ),
                          ),
                          SizedBox(width: 10),
                          ElevatedButton(
                            onPressed: () {
                              String yeniKelime = kelimeController.text
                                  .trim()
                                  .toLowerCase();
                              if (yeniKelime.isNotEmpty &&
                                  !tetikleyiciKelimeler.contains(yeniKelime)) {
                                setState(() {
                                  tetikleyiciKelimeler.add(yeniKelime);
                                  kelimeController.clear();
                                });
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.pink[800],
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              padding: EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 14,
                              ),
                            ),
                            child: Text(
                              "Ekle",
                              style: TextStyle(color: Colors.white),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(height: 20),

              // 4. BÖLÜM: ACİL DURUM KİŞİLERİ KARTI
              Card(
                elevation: 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.contact_phone, color: Colors.pink[800]),
                          SizedBox(width: 10),
                          Text(
                            "Acil Durum Kişileri",
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      Divider(height: 20, thickness: 1),

                      // Kişi Ekleme Butonu
                      Center(
                        child: ElevatedButton.icon(
                          onPressed: rehberiAcVeKisiSec,
                          icon: Icon(Icons.person_add, color: Colors.white),
                          label: Text(
                            "Rehberden Kişi Ekle",
                            style: TextStyle(color: Colors.white),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.pink[800],
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            padding: EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 12,
                            ),
                          ),
                        ),
                      ),
                      SizedBox(height: 15),

                      // Eklenen Kişilerin Listesi
                      secilenKisiler.isEmpty
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(8.0),
                                child: Text(
                                  "Henüz acil durum kişisi eklenmedi.",
                                  style: TextStyle(color: Colors.grey),
                                ),
                              ),
                            )
                          : ListView.builder(
                              shrinkWrap: true,
                              physics: NeverScrollableScrollPhysics(),
                              itemCount: secilenKisiler.length,
                              itemBuilder: (context, index) {
                                var kisi = secilenKisiler[index];
                                return Card(
                                  color: Colors.pink[50],
                                  elevation: 0,
                                  margin: EdgeInsets.symmetric(vertical: 4),
                                  child: ListTile(
                                    leading: CircleAvatar(
                                      backgroundColor: Colors.pink[200],
                                      child: Icon(
                                        Icons.person,
                                        color: Colors.white,
                                      ),
                                    ),
                                    title: Text(
                                      kisi['ad']!,
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    subtitle: Text(kisi['numara']!),
                                    trailing: IconButton(
                                      icon: Icon(
                                        Icons.delete,
                                        color: Colors.red[400],
                                      ),
                                      onPressed: () {
                                        setState(() {
                                          secilenKisiler.removeAt(index);
                                        });
                                      },
                                    ),
                                  ),
                                );
                              },
                            ),
                    ],
                  ),
                ),
              ),
              SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }
}