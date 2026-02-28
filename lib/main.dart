import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:share_plus/share_plus.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'firebase_options.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await dotenv.load(fileName: ".env");
  } catch (e) {
    debugPrint("Dotenv load failed: $e");
  }
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const LimpopoVoiceApp());
}

class LimpopoVoiceApp extends StatelessWidget {
  const LimpopoVoiceApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF008080),
        brightness: Brightness.light,
      ),
      home: FirebaseAuth.instance.currentUser == null ? const LoginScreen() : const LimpopoHome(),
    );
  }
}

// --- LOGIN SCREEN ---
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _phoneController = TextEditingController();

  void _verifyPhone() async {
    await FirebaseAuth.instance.verifyPhoneNumber(
      phoneNumber: _phoneController.text.trim(),
      verificationCompleted: (cred) async => await FirebaseAuth.instance.signInWithCredential(cred),
      verificationFailed: (e) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Auth Error: ${e.message}"))),
      codeSent: (id, token) => _showOTPDialog(id),
      codeAutoRetrievalTimeout: (id) {},
    );
  }

  void _showOTPDialog(String vId) {
    final otpController = TextEditingController();
    showDialog(context: context, builder: (context) => AlertDialog(
      title: const Text("Verify Phone"),
      content: TextField(controller: otpController, keyboardType: TextInputType.number, decoration: const InputDecoration(hintText: "Enter SMS code")),
      actions: [TextButton(onPressed: () async {
        try {
          final cred = PhoneAuthProvider.credential(verificationId: vId, smsCode: otpController.text.trim());
          await FirebaseAuth.instance.signInWithCredential(cred);
          if (!mounted) return;
          Navigator.pop(context);
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const LimpopoHome()));
        } catch (e) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Invalid Code")));
        }
      }, child: const Text("Verify"))],
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(30),
          child: Column(children: [
            const Icon(Icons.record_voice_over, size: 100, color: Color(0xFF008080)),
            const SizedBox(height: 10),
            const Text("Limpopo Voice", style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
            const SizedBox(height: 40),
            TextField(controller: _phoneController, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: "Phone Number (+27...)", border: OutlineInputBorder())),
            const SizedBox(height: 20),
            SizedBox(width: double.infinity, height: 50, child: ElevatedButton(onPressed: _verifyPhone, child: const Text("Send Code"))),
          ]),
        ),
      ),
    );
  }
}

// --- HOME SCREEN ---
class LimpopoHome extends StatefulWidget {
  const LimpopoHome({super.key});
  @override
  State<LimpopoHome> createState() => _LimpopoHomeState();
}

class _LimpopoHomeState extends State<LimpopoHome> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final FlutterTts _tts = FlutterTts();
  final stt.SpeechToText _speech = stt.SpeechToText();
  
  bool _isListening = false;
  bool _isLoading = false;
  bool _isRespectMode = false;
  bool _isFastMode = false; // Fast Mode Toggle
  
  String _text = "Hold mic to speak";
  String _translatedResult = "";
  String _inputLang = "English";
  String _targetLang = "Sepedi";
  int _userCredits = 0;
  
  final List<String> _languages = ["English", "Sepedi", "Xitsonga", "Tshivenda", "Afrikaans"];
  final List<Map<String, String>> _history = [];

  // Local Dictionary for Fast Mode (Credits: 0)
  final Map<String, Map<String, String>> _localDict = {
    "hello": {"Sepedi": "Dumela", "Xitsonga": "Avuxeni", "Tshivenda": "Nndaa", "Afrikaans": "Hallo"},
    "how are you": {"Sepedi": "O kae?", "Xitsonga": "Ku njhani?", "Tshivenda": "Vhu masiari?", "Afrikaans": "Hoe gaan dit?"},
    "thank you": {"Sepedi": "Ke a leboga", "Xitsonga": "Inkomu", "Tshivenda": "Ro livhuwa", "Afrikaans": "Dankie"},
  };

  late final GenerativeModel _model;

  @override
  void initState() {
    super.initState();
    _model = GenerativeModel(
      model: 'gemini-2.5-flash', 
      apiKey: dotenv.env['GEMINI_KEY'] ?? "",
      safetySettings: [
        SafetySetting(HarmCategory.hateSpeech, HarmBlockThreshold.high),
        SafetySetting(HarmCategory.harassment, HarmBlockThreshold.high),
      ],
    );
    _syncCredits();
    _initTts();
  }

  void _initTts() async {
    await _tts.setSpeechRate(0.45);
    await _tts.setVolume(1.0);
  }

  void _syncCredits() {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    FirebaseFirestore.instance.collection('users').doc(uid).snapshots().listen((doc) {
      if (doc.exists && mounted) setState(() => _userCredits = doc.data()?['credits'] ?? 0);
    });
  }

  Future<void> _updateCredits(int amount) async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    await FirebaseFirestore.instance.collection('users').doc(uid).update({'credits': FieldValue.increment(amount)});
  }

  void _listen() async {
    if (_isLoading) return;
    if (!_isListening) {
      bool avail = await _speech.initialize();
      if (avail) {
        setState(() => _isListening = true);
        _speech.listen(onResult: (val) => setState(() => _text = val.recognizedWords));
      }
    } else {
      setState(() => _isListening = false);
      await _speech.stop();
      _translate();
    }
  }

  Future<void> _translate() async {
    String cleanInput = _text.trim().toLowerCase();

    // 1. FAST MODE CHECK (No Credits)
    if (_isFastMode && _localDict.containsKey(cleanInput)) {
      String? fastResult = _localDict[cleanInput]![_targetLang];
      if (fastResult != null) {
        setState(() { _translatedResult = fastResult; _isLoading = false; });
        _speakResult();
        return;
      }
    }

    // 2. AI TRANSLATION (Strict Prompt)
    if (_userCredits <= 0) { _showTopUp(); return; }
    setState(() { _isLoading = true; _translatedResult = "Translating..."; });

    try {
      final prompt = """
        Translate '$_text' to $_targetLang.
        Style: ${_isRespectMode ? "Formal/Respectful" : "Normal"}.
        Constraint: Provide ONLY the translation. NO introductions. NO explanations. NO seminar.
      """;
      
      final content = [Content.text(prompt)];
      final response = await _model.generateContent(content).timeout(const Duration(seconds: 15));
      
      if (mounted) {
        setState(() {
          _translatedResult = response.text?.trim() ?? "Error";
          _history.insert(0, {"q": _text, "a": _translatedResult});
          _isLoading = false;
        });
        _updateCredits(-1);
        _speakResult();
      }
    } catch (e) {
      setState(() { _isLoading = false; _translatedResult = "Connection Error."; });
    }
  }

  Future<void> _speakResult() async {
    if (_translatedResult.isNotEmpty && !_translatedResult.contains("Error")) {
      await _tts.speak(_translatedResult);
    }
  }

  void _reportTranslation() {
    FirebaseFirestore.instance.collection('reports').add({
      'user': FirebaseAuth.instance.currentUser!.uid,
      'input': _text,
      'translation': _translatedResult,
      'timestamp': FieldValue.serverTimestamp(),
    });
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Reported.")));
  }

  void _showTopUp() {
    showModalBottomSheet(context: context, builder: (context) => Column(mainAxisSize: MainAxisSize.min, children: [
      ListTile(title: const Text("35 Credits - R10"), onTap: () { _updateCredits(35); Navigator.pop(context); }),
      ListTile(title: const Text("200 Credits - R60"), onTap: () { _updateCredits(200); Navigator.pop(context); }),
    ]));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(title: const Text("Limpopo Voice"), actions: [
        IconButton(icon: const Icon(Icons.history), onPressed: () => _scaffoldKey.currentState!.openEndDrawer())
      ]),
      endDrawer: Drawer(child: ListView(children: _history.map((e) => ListTile(title: Text(e['a']!), subtitle: Text(e['q']!))).toList())),
      body: Column(children: [
        ActionChip(label: Text("Credits: $_userCredits"), onPressed: _showTopUp),
        const SizedBox(height: 10),
        Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
          _langDrop(_inputLang, (v) => setState(() => _inputLang = v!)),
          const Icon(Icons.swap_horiz),
          _langDrop(_targetLang, (v) => setState(() => _targetLang = v!)),
        ]),
        SwitchListTile(title: const Text("Fast Mode (Dictionary)"), value: _isFastMode, onChanged: (v) => setState(() => _isFastMode = v)),
        SwitchListTile(title: const Text("Respect Mode"), value: _isRespectMode, onChanged: (v) => setState(() => _isRespectMode = v)),
        const Spacer(),
        Padding(padding: const EdgeInsets.all(20), child: Text(_text, style: const TextStyle(fontSize: 18, color: Colors.grey))),
        Padding(padding: const EdgeInsets.all(20), child: Text(_translatedResult, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Color(0xFF008080)), textAlign: TextAlign.center)),
        const Spacer(),
        if (_translatedResult.isNotEmpty && !_isLoading)
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            IconButton(icon: const Icon(Icons.volume_up), onPressed: _speakResult),
            IconButton(icon: const Icon(Icons.flag), onPressed: _reportTranslation),
            IconButton(icon: const Icon(Icons.share), onPressed: () => Share.share(_translatedResult)),
          ]),
        const SizedBox(height: 20),
        GestureDetector(
          onLongPress: _listen,
          onLongPressUp: _listen,
          child: CircleAvatar(radius: 40, backgroundColor: _isListening ? Colors.red : const Color(0xFF008080), child: Icon(_isListening ? Icons.stop : Icons.mic, color: Colors.white)),
        ),
        const SizedBox(height: 40),
      ]),
    );
  }

  Widget _langDrop(String val, Function(String?) onChg) => DropdownButton<String>(value: val, items: _languages.map((l) => DropdownMenuItem(value: l, child: Text(l))).toList(), onChanged: onChg);
}