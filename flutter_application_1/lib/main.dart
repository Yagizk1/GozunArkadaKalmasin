import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner:
          false, // Sağ üstteki "Debug" yazısını kaldırır
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
  bool korumaAcikmi = false;
  bool gizliModAktif = false; // 4. maddedeki "WOW" özelliği için hazırlık

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Gözüm Arkada Kalmasın"), centerTitle: true),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // KORUMA BUTONU
            GestureDetector(
              onTap: () {
                setState(() {
                  korumaAcikmi = !korumaAcikmi;
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

            // GİZLİ MOD AYARI (WOW ÖZELLİĞİ HAZIRLIĞI)
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

            SizedBox(height: 20),

            // REHBER BUTONU (GÜNCELLENDİ: İZİNLER EKLENDİ)
            ElevatedButton.icon(
              onPressed: () async {
                // Çoklu izin isteme penceresi tetikleniyor
                Map<Permission, PermissionStatus> statuses = await [
                  Permission.microphone,
                  Permission.location,
                  Permission.sms,
                  Permission.contacts,
                ].request();

                // İzinlerin verilip verilmediğini kontrol edelim
                if (statuses[Permission.microphone]!.isGranted &&
                    statuses[Permission.location]!.isGranted) {
                  print("Harika! Mikrofon ve Konum izni alındı.");
                  // Birazdan buraya rehberi açma kodunu ekleyeceğiz
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
