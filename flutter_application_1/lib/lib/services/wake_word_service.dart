import 'package:speech_to_text/speech_to_text.dart' as stt;

class SesDinlemeServisi {
  final Function onWakeWordDetected;
  final stt.SpeechToText _speech = stt.SpeechToText();
  
  bool _isListening = false;
  bool _hasInitialized = false; 
  List<String> _aktifKelimeler = [];

  SesDinlemeServisi({required this.onWakeWordDetected});

  Future<void> _initEgerGerekliyse() async {
    if (_hasInitialized) return; 
    
    _hasInitialized = await _speech.initialize(
      onStatus: (status) {
        print("Mikrofon Durumu: $status");
        if ((status == 'done' || status == 'notListening') && _isListening) {
          Future.delayed(const Duration(milliseconds: 500), () {
            if (_isListening) _startDinlemeIcGorev();
          });
        }
      },
      onError: (error) {
        print("Dinleme Hatası: $error");
        if (_isListening) {
          Future.delayed(const Duration(milliseconds: 500), () {
            if (_isListening) _startDinlemeIcGorev();
          });
        }
      },
    );
  }

  void startListening(List<String> tetikleyiciKelimeler) async {
    if (_isListening) return;
    _isListening = true;
    _aktifKelimeler = tetikleyiciKelimeler;

    await _initEgerGerekliyse();

    if (_hasInitialized) {
      if (_speech.isListening) {
        await _speech.cancel();
        await Future.delayed(const Duration(milliseconds: 300));
      }
      _startDinlemeIcGorev();
    } else {
      print("Kullanıcı mikrofona izin vermedi.");
    }
  }

  void _startDinlemeIcGorev() {
    if (!_isListening) return; 

    _speech.listen(
      localeId: "tr_TR",
      cancelOnError: false,
      partialResults: true,
      listenFor: const Duration(minutes: 30),
      pauseFor: const Duration(minutes: 5),
      // DESİBEL VE FREKANS KISIMLARI TAMAMEN SİLİNDİ!
      onResult: (result) {
        String duyulanMetin = result.recognizedWords.toLowerCase();
        for (String kelime in _aktifKelimeler) {
          if (duyulanMetin.contains(kelime.toLowerCase())) {
            print("🚨 ÖZEL KELİME DUYULDU: $kelime 🚨");
            _tetiklenmeyiBaslat();
            return;
          }
        }
      },
    );
  }

  void _tetiklenmeyiBaslat() {
    if (!_isListening) return; 
    stopListening(); 
    onWakeWordDetected(); 
  }

  void stopListening() async {
    _isListening = false;
    if (_hasInitialized) {
      await _speech.cancel(); 
    }
    print("Dinleme servisi kapatıldı.");
  }
}