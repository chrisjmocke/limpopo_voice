import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:http/http.dart' as http; 
import 'dart:convert';               
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:permission_handler/permission_handler.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    ).timeout(const Duration(seconds: 5));
  } catch (e) {
    debugPrint("Firebase init timeout: $e");
  }
  runApp(const LimpopoVoiceApp());
}

class LimpopoVoiceApp extends StatelessWidget {
  const LimpopoVoiceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Limpopo Voice',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF008080)),
      ),
      home: const LimpopoHome(),
    );
  }
}

class LimpopoHome extends StatefulWidget {
  const LimpopoHome({super.key});

  @override
  State<LimpopoHome> createState() => _LimpopoHomeState();
}

class _LimpopoHomeState extends State<LimpopoHome> {
  final FlutterTts _tts = FlutterTts();
  final stt.SpeechToText _speech = stt.SpeechToText();

  bool _isListening = false;
  bool _isRespectMode = false;
  String _text = "Hold the button to speak";
  String _translatedResult = "";
  String _targetLanguage = "Sepedi";
  
  int _userCredits = 6; 
  final Color _appColor = const Color(0xFF008080); 

  final Map<String, String> _languages = {
    "English": "en",
    "Afrikaans": "af",
    "Sepedi": "nso",
    "Xitsonga": "ts",
    "Tshivenda": "ve",
  };

  @override
  void initState() {
    super.initState();
    _initApp();
  }

  Future<void> _initApp() async {
    await Permission.microphone.request();
    await _tts.setLanguage("en-US");
  }

  // --- LOGIC: THE VERIFIED HTTPS TRANSLATION ---
  Future<void> _sendToTranslation(String input) async {
    if (input.trim().isEmpty) return;

    if (_userCredits <= 0) {
      _showPurchasePopup();
      return;
    }

    // UPDATED: This is the URL we verified in PowerShell
    const String firebaseUrl = "https://africa-south1-limpopo-voice-prod.cloudfunctions.net/processSpeech";

    try {
      setState(() => _translatedResult = "Thinking...");

      final response = await http.post(
        Uri.parse(firebaseUrl),
        headers: {
          "Content-Type": "application/json",
          "x-app-password": "MySecureSouthAfricaApp2026", // Verified Password
        },
        body: jsonEncode({
          "text": input,
          "targetLanguage": _targetLanguage,
          "isRespectMode": _isRespectMode,
        }),
      ).timeout(const Duration(seconds: 15)); // 15-second timeout for spotty 3G

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          // 'translation' matches the key returned by your index.js
          _translatedResult = data['translation'] ?? "No translation returned";
          _userCredits--;
        });

        // Speak the result
        if (_translatedResult.isNotEmpty) {
          await _tts.speak(_translatedResult);
        }
      } else {
        setState(() => _translatedResult = "Server Error: ${response.statusCode}");
        debugPrint("Server Response: ${response.body}");
      }
    } catch (e) {
      setState(() => _translatedResult = "Connection Error. Check Internet.");
      debugPrint("Error detail: $e");
    }
  }

  // Helper for Speech to Text
  void _listen() async {
    if (!_isListening) {
      bool available = await _speech.initialize();
      if (available) {
        setState(() => _isListening = true);
        _speech.listen(onResult: (val) {
          setState(() {
            _text = val.recognizedWords;
          });
          if (val.finalResult) {
            setState(() => _isListening = false);
            _sendToTranslation(_text);
          }
        });
      }
    } else {
      setState(() => _isListening = false);
      _speech.stop();
    }
  }

  void _showPurchasePopup() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Out of Credits"),
        content: const Text("Please top up to continue translating."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("OK")),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Limpopo Voice"),
        backgroundColor: _appColor,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            Text("Credits: $_userCredits", style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            DropdownButton<String>(
              value: _targetLanguage,
              items: _languages.keys.map((String lang) {
                return DropdownMenuItem(value: lang, child: Text(lang));
              }).toList(),
              onChanged: (val) => setState(() => _targetLanguage = val!),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text("Respect Mode"),
                Switch(
                  value: _isRespectMode,
                  onChanged: (val) => setState(() => _isRespectMode = val),
                ),
              ],
            ),
            const Expanded(
              child: Center(child: Icon(Icons.mic, size: 100, color: Colors.grey)),
            ),
            Container(
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(_text, style: const TextStyle(fontSize: 18)),
            ),
            const SizedBox(height: 10),
            Text(
              _translatedResult,
              style: TextStyle(fontSize: 22, color: _appColor, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            GestureDetector(
              onLongPress: _listen,
              onLongPressUp: () {
                setState(() => _isListening = false);
                _speech.stop();
              },
              child: FloatingActionButton.large(
                onPressed: () {}, // Handled by LongPress
                backgroundColor: _isListening ? Colors.red : _appColor,
                child: Icon(_isListening ? Icons.stop : Icons.mic, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
}