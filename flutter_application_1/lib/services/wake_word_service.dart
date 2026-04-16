import 'package:speech_to_text/speech_to_text.dart' as stt;

class SesDinlemeServisi {
  final stt.SpeechToText _speechToText = stt.SpeechToText();
  final Function() onWakeWordDetected;
  bool _dinliyorMu = false;

  SesDinlemeServisi({required this.onWakeWordDetected});

  // Dinlemeyi Başlat
  Future<void> startListening() async {
    // Önce mikrofonu kullanmaya hazır mıyız diye telefonu kontrol ediyoruz
    bool isAvailable = await _speechToText.initialize(
      onStatus: (status) => print('Ses Durumu: $status'),
      onError: (errorNotification) => print('Ses Hatası: $errorNotification'),
    );

    if (isAvailable) {
      _dinliyorMu = true;
      _speechToText.listen(
        localeId: 'tr_TR', // Doğrudan Türkçe dinliyoruz!
        onResult: (sonuc) {
          // Telefonun duyduğu kelimeleri alıp küçük harfe çeviriyoruz
          String duyulanCumle = sonuc.recognizedWords.toLowerCase();
          print("Duyulan kelimeler: $duyulanCumle");

          // ŞİFRELERİMİZ BURADA: Bu kelimelerden biri geçerse tetikle!
          if (duyulanCumle.contains('imdat') || 
              duyulanCumle.contains('yardım') || 
              duyulanCumle.contains('polisi arayın')) {
            
            print("🚨 ŞİFRE KELİME DUYULDU! 🚨");
            stopListening(); // Tetiklendiğinde dinlemeyi durdur
            onWakeWordDetected(); // AnaSayfa'daki geri sayımı başlat
          }
        },
      );
      print("Sistem Türkçe dinlemeye başladı. 'İmdat' veya 'Yardım' demeyi deneyin.");
    } else {
      print("Kullanıcının telefonu ses tanıma özelliğini desteklemiyor veya izin verilmedi.");
    }
  }

  // Dinlemeyi Durdur
  void stopListening() {
    if (_dinliyorMu) {
      _speechToText.stop();
      _dinliyorMu = false;
      print("Dinleme durduruldu.");
    }
  }
}