import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:share_plus/share_plus.dart';
import 'package:http/http.dart' as http;
import 'package:audioplayers/audioplayers.dart';
import 'package:vibration/vibration.dart'; 
import 'firebase_options.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await dotenv.load(fileName: ".env");
  } catch (e) {
    debugPrint("Dotenv error: $e");
  }
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const LingoLangaApp());
}

class LingoLangaApp extends StatefulWidget {
  const LingoLangaApp({super.key});
  @override
  State<LingoLangaApp> createState() => _LingoLangaAppState();
}

class _LingoLangaAppState extends State<LingoLangaApp> {
  bool _isDarkMode = true;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      themeMode: _isDarkMode ? ThemeMode.dark : ThemeMode.light,
      darkTheme: ThemeData(
          brightness: Brightness.dark,
          useMaterial3: true,
          colorSchemeSeed: const Color(0xFF008080)),
      theme: ThemeData(
          brightness: Brightness.light,
          useMaterial3: true,
          colorSchemeSeed: const Color(0xFF008080)),
      home: FirebaseAuth.instance.currentUser == null
          ? const LoginScreen()
          : LingoLangaHome(
              isDark: _isDarkMode,
              onThemeChanged: (val) => setState(() => _isDarkMode = val),
            ),
    );
  }
}

class LingoLangaHome extends StatefulWidget {
  final bool isDark;
  final ValueChanged<bool> onThemeChanged;
  const LingoLangaHome({super.key, required this.isDark, required this.onThemeChanged});

  @override
  State<LingoLangaHome> createState() => _LingoLangaHomeState();
}

class _LingoLangaHomeState extends State<LingoLangaHome> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _audio = AudioPlayer();
  final _speech = stt.SpeechToText();

  bool _isListening = false;
  bool _isLoading = false;
  bool _isMale = true;
  int _credits = 0;

  String _text = "Hold mic to speak";
  String _result = "";
  String _inputLang = "Auto Detect";
  String _targetLang = "Sepedi";

  final _limpopoLangs = ["Sepedi", "Xitsonga", "Tshivenda", "Afrikaans", "English"];
  final List<Map<String, String>> _history = [];

  @override
  void initState() {
    super.initState();
    _syncCredits();
  }

  void _syncCredits() {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    FirebaseFirestore.instance.collection('users').doc(uid).snapshots().listen((doc) {
      if (doc.exists && mounted) {
        setState(() => _credits = doc.data()?['credits'] ?? 0);
      }
    });
  }

  Future<void> _speak(String txt) async {
    final key = dotenv.env['GEMINI_KEY'] ?? "";
    String voiceName = _isMale ? "en-ZA-Wavenet-B" : "en-ZA-Wavenet-A";
    String langCode = "en-ZA";

    if (_targetLang == "Afrikaans") {
      voiceName = "af-ZA-Standard-A";
      langCode = "af-ZA";
    }

    try {
      final res = await http.post(
        Uri.parse("https://texttospeech.googleapis.com/v1/text:synthesize?key=$key"),
        headers: {"Content-Type": "application/json", "X-Goog-Api-Key": key},
        body: jsonEncode({
          "input": {"text": txt},
          "voice": {"languageCode": langCode, "name": voiceName},
          "audioConfig": {"audioEncoding": "MP3", "pitch": 0, "speakingRate": 1.0}
        }),
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        await _audio.play(BytesSource(base64Decode(data['audioContent'])));
      }
    } catch (e) {
      debugPrint("TTS Error: $e");
    }
  }

  void _listen() async {
    if (!_isListening) {
      if (await _speech.initialize()) {
        if (await Vibration.hasVibrator() ?? false) Vibration.vibrate(duration: 50);
        setState(() => _isListening = true);
        
        // 🔥 10-Second Hard Limit applied here
        _speech.listen(
          onResult: (v) => setState(() => _text = v.recognizedWords),
          listenFor: const Duration(seconds: 10),
          pauseFor: const Duration(seconds: 3),
        );

        // Auto-stop toggle after 10 seconds
        Future.delayed(const Duration(seconds: 10), () {
          if (_isListening) _listen();
        });
      }
    } else {
      if (await Vibration.hasVibrator() ?? false) Vibration.vibrate(duration: 30);
      setState(() => _isListening = false);
      await _speech.stop();
      if (_credits > 0) {
        _translate();
      } else {
        _showTopUp();
      }
    }
  }

  void _translate() async {
    if (_text.isEmpty || _text == "Hold mic to speak") return;
    setState(() { _isLoading = true; _result = "Translating..."; });

    try {
      final apiKey = dotenv.env['GEMINI_KEY'] ?? "";
      final url = "https://generativelanguage.googleapis.com/v1/models/gemini-1.5-flash:generateContent?key=$apiKey";

      final response = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          "contents": [{
            "parts": [{
              "text": "Translate the following text from $_inputLang to $_targetLang. Provide ONLY the translated text: '$_text'"
            }]
          }]
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final String output = data['candidates'][0]['content']['parts'][0]['text'];
        
        setState(() {
          _result = output.trim();
          _history.insert(0, {"q": _text, "a": _result});
          _isLoading = false;
        });

        // 1 Translation = 1 Credit
        FirebaseFirestore.instance.collection('users').doc(FirebaseAuth.instance.currentUser!.uid).update({'credits': FieldValue.increment(-1)});
        _speak(_result);
      } else {
        setState(() { _isLoading = false; _result = "API Error"; });
      }
    } catch (e) {
      setState(() { _isLoading = false; _result = "Connection Error"; });
    }
  }

  void _showTopUp() {
    showModalBottomSheet(context: context, builder: (c) => Column(mainAxisSize: MainAxisSize.min, children: [
      const Padding(padding: EdgeInsets.all(15), child: Text("Top-Up Credits", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18))),
      ListTile(leading: const Icon(Icons.flash_on, color: Colors.teal), title: const Text("35 Credits - R10"), onTap: () => _buy(35)),
      ListTile(leading: const Icon(Icons.auto_awesome, color: Colors.blue), title: const Text("200 Credits - R60"), onTap: () => _buy(200)),
      ListTile(leading: const Icon(Icons.workspace_premium, color: Colors.amber), title: const Text("750 Credits - R200"), onTap: () => _buy(750)),
      const SizedBox(height: 20),
    ]));
  }

  void _buy(int amt) {
    FirebaseFirestore.instance.collection('users').doc(FirebaseAuth.instance.currentUser!.uid).update({'credits': FieldValue.increment(amt)});
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    bool isLowCredit = _credits < 2;

    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        leading: IconButton(icon: Icon(widget.isDark ? Icons.light_mode : Icons.dark_mode), onPressed: () => widget.onThemeChanged(!widget.isDark)),
        actions: [
          // 🔥 Share App Button
          IconButton(
            icon: const Icon(Icons.share_outlined), 
            onPressed: () => Share.share("Download LingoLanga and translate instantly!"),
          ),
          IconButton(icon: const Icon(Icons.history), onPressed: () => _scaffoldKey.currentState!.openEndDrawer())
        ],
      ),
      endDrawer: Drawer(
        child: Column(children: [
          DrawerHeader(
            decoration: const BoxDecoration(color: Color(0xFF008080)),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text("History", style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  ElevatedButton.icon(
                    onPressed: () => setState(() => _history.clear()), 
                    icon: const Icon(Icons.delete_sweep, size: 18), 
                    label: const Text("Clear History"),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade400, foregroundColor: Colors.white),
                  )
                ],
              ),
            ),
          ),
          Expanded(child: ListView(children: _history.map((e) => ListTile(title: Text(e['a']!), subtitle: Text(e['q']!))).toList())),
        ]),
      ),
      body: Column(children: [
        SizedBox(height: 100, width: double.infinity, child: Image.asset('assets/images/limpopo_voice.png', fit: BoxFit.cover, errorBuilder: (c, e, s) => Container(color: Colors.teal, child: const Center(child: Text("LingoLanga"))))),
        Expanded(child: ListView(padding: const EdgeInsets.symmetric(horizontal: 20), children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            // 🔥 Red Credit Chip Logic
            ActionChip(
              backgroundColor: isLowCredit ? Colors.red : null,
              avatar: Icon(Icons.stars, size: 16, color: isLowCredit ? Colors.white : Colors.amber),
              label: Text("Credits: $_credits", style: TextStyle(color: isLowCredit ? Colors.white : null, fontWeight: FontWeight.bold)), 
              onPressed: _showTopUp
            ),
            Switch(value: _isMale, onChanged: (v) => setState(() => _isMale = v), activeColor: Colors.blue),
          ]),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), color: Colors.teal.withOpacity(0.1)),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text("From: $_inputLang"),
              const Icon(Icons.arrow_forward),
              DropdownButton<String>(
                value: _targetLang, 
                items: _limpopoLangs.map((l) => DropdownMenuItem(value: l, child: Text(l))).toList(), 
                onChanged: (v) => setState(() => _targetLang = v!)
              ),
            ]),
          ),
          const Divider(height: 40),
          Text(_text, textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey)),
          const SizedBox(height: 20),
          _isLoading 
            ? const Center(child: CircularProgressIndicator()) 
            : Text(_result, textAlign: TextAlign.center, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Color(0xFF008080))),
          if (_result.isNotEmpty && !_isLoading) 
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              IconButton(icon: const Icon(Icons.volume_up, size: 30), onPressed: () => _speak(_result)),
              IconButton(icon: const Icon(Icons.copy), onPressed: () => Clipboard.setData(ClipboardData(text: _result))),
              IconButton(icon: const Icon(Icons.share), onPressed: () => Share.share(_result)),
            ]),
        ])),
        Padding(padding: const EdgeInsets.only(bottom: 40), child: GestureDetector(
          onLongPress: _listen, onLongPressUp: _listen,
          child: CircleAvatar(radius: 40, backgroundColor: _isListening ? Colors.red : const Color(0xFF008080), child: Icon(_isListening ? Icons.stop : Icons.mic, color: Colors.white, size: 35)),
        )),
      ]),
    );
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _phone = TextEditingController();
  bool _isLoading = false;

  void _login() async {
    setState(() => _isLoading = true);
    await FirebaseAuth.instance.verifyPhoneNumber(
      phoneNumber: _phone.text.trim(),
      verificationCompleted: (c) async {
        await FirebaseAuth.instance.signInWithCredential(c);
        _handleNewUserAndNavigate();
      },
      verificationFailed: (e) {
        setState(() => _isLoading = false);
        debugPrint(e.message);
      },
      codeSent: (id, _) => _showOtp(id),
      codeAutoRetrievalTimeout: (_) {},
    );
  }

  void _handleNewUserAndNavigate() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      if (!userDoc.exists) {
        await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
          'credits': 6,
          'phone': user.phoneNumber,
          'createdAt': FieldValue.serverTimestamp(),
        });
        if (mounted) _showWelcomeMessage();
      } else {
        _goToHome();
      }
    }
  }

  void _showWelcomeMessage() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (c) => AlertDialog(
        title: const Text("Dumela / Welcome!"),
        content: const Text("You have received 6 FREE credits to start your journey with LingoLanga."),
        actions: [TextButton(onPressed: () => _goToHome(), child: const Text("Let's Start"))],
      ),
    );
  }

  void _goToHome() {
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (c) => const LingoLangaApp()));
  }

  void _showOtp(String id) {
    final otp = TextEditingController();
    showDialog(context: context, builder: (c) => AlertDialog(
      title: const Text("OTP"),
      content: TextField(controller: otp, keyboardType: TextInputType.number),
      actions: [TextButton(onPressed: () async {
        final cred = PhoneAuthProvider.credential(verificationId: id, smsCode: otp.text.trim());
        await FirebaseAuth.instance.signInWithCredential(cred);
        _handleNewUserAndNavigate();
      }, child: const Text("Verify"))],
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(body: Center(child: Padding(padding: const EdgeInsets.all(30), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      const Icon(Icons.record_voice_over, size: 80, color: Color(0xFF008080)),
      const SizedBox(height: 20),
      TextField(controller: _phone, decoration: const InputDecoration(labelText: "Phone (+27...)", border: OutlineInputBorder())),
      const SizedBox(height: 20),
      SizedBox(width: double.infinity, height: 50, child: ElevatedButton(onPressed: _isLoading ? null : _login, child: _isLoading ? const CircularProgressIndicator() : const Text("Enter App"))),
    ]))));
  }
}
