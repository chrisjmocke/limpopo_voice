import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:share_plus/share_plus.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'firebase_options.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

// LL language controller for Pan-African expansion.
enum LLRegion { SouthAfrica, WestAfrica, EastAfrica, CentralAfrica }

class LLLanguageController {
  static List<String> getLanguagesForRegion(LLRegion region) {
    switch (region) {
      case LLRegion.SouthAfrica:
        return [
          'English',
          'isiZulu',
          'Afrikaans',
          'Sesotho',
          'Setswana',
        ];
      case LLRegion.WestAfrica:
        return [
          'English',
          'Yoruba',
          'Hausa',
          'Akan (Ghana)',
          'Wolof (Senegal)',
        ];
      case LLRegion.EastAfrica:
        return [
          'English',
          'Kiswahili (Kenya/Tanzania)',
          'Amharic',
          'Afaan Oromoo',
          'Somali',
        ];
      case LLRegion.CentralAfrica:
        return [
          'English',
          'Kinyarwanda (Rwanda)',
        ];
    }
  }

  static String _normalizeLanguageKey(String language) {
    return language
        .trim()
        .toLowerCase()
        .replaceAll('ù', 'u')
        .replaceAll('á', 'a')
        .replaceAll('’', "'");
  }

  static String getGeminiCode(String language) {
    final key = _normalizeLanguageKey(language);
    switch (key) {
      case 'isizulu':
      case 'zulu':
        return 'zu-ZA';
      case 'yoruba':
      case 'yoruba (nigeria)':
      case 'yoruba (nigerian)':
      case 'yoruba (yoruba)':
      case 'yoruba (yoruba language)':
      case "yoru'ba":
        return 'yo-NG';
      case 'kiswahili (kenya/tanzania)':
      case 'kiswahili':
      case 'swahili':
        return 'sw-KE';
      case 'hausa':
        return 'ha-NE';
      case 'afrikaans':
        return 'af-ZA';
      case 'sesotho':
        return 'st-ZA';
      case 'setswana':
      case 'tswana':
        return 'tn-ZA';
      case 'akan (ghana)':
      case 'akan':
        return 'ak-GH';
      case 'wolof (senegal)':
      case 'wolof':
        return 'wo-SN';
      case 'amharic':
        return 'am-ET';
      case 'afaan oromoo':
      case 'oromo':
        return 'om-ET';
      case 'somali':
        return 'so-SO';
      case 'kinyarwanda (rwanda)':
      case 'kinyarwanda':
        return 'rw-RW';
      case 'english':
      default:
        return 'en-US';
    }
  }

  static String regionLabel(LLRegion region) {
    switch (region) {
      case LLRegion.SouthAfrica:
        return 'South Africa';
      case LLRegion.WestAfrica:
        return 'West Africa';
      case LLRegion.EastAfrica:
        return 'East Africa';
      case LLRegion.CentralAfrica:
        return 'Central Africa';
    }
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    await FirebaseAppCheck.instance.activate(
      androidProvider:
          kDebugMode ? AndroidProvider.debug : AndroidProvider.playIntegrity,
    );
    await dotenv.load(fileName: ".env");
  } catch (e) {
    debugPrint("Firebase/Env Error: $e");
  }
  runApp(const LingoLangaApp());
}

class LingoLangaApp extends StatefulWidget {
  const LingoLangaApp({super.key});

  @override
  State<LingoLangaApp> createState() => _LingoLangaAppState();
}

class _LingoLangaAppState extends State<LingoLangaApp> {
  ThemeMode _themeMode = ThemeMode.light;
  MaterialColor _primaryColor = Colors.blue;
  bool _isMale = true; // gender toggle

  void toggleTheme() {
    setState(() {
      _themeMode =
          _themeMode == ThemeMode.light ? ThemeMode.dark : ThemeMode.light;
    });
  }

  void toggleGender() {
    setState(() {
      _isMale = !_isMale;
      _primaryColor = _isMale ? Colors.blue : Colors.indigo;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      themeMode: _themeMode,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: _primaryColor),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: _primaryColor,
          brightness: Brightness.dark,
        ),
      ),
      home: AuthWrapper(
          toggleTheme: toggleTheme,
          toggleGender: toggleGender,
          isMale: _isMale),
    );
  }
}

class AuthWrapper extends StatelessWidget {
  final VoidCallback toggleTheme;
  final VoidCallback toggleGender;
  final bool isMale;
  const AuthWrapper(
      {super.key,
      required this.toggleTheme,
      required this.toggleGender,
      required this.isMale});
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          return LingoLangaHome(
              toggleTheme: toggleTheme,
              toggleGender: toggleGender,
              isMale: isMale);
        }
        return LingoLangaLogin(
            toggleTheme: toggleTheme,
            toggleGender: toggleGender,
            isMale: isMale);
      },
    );
  }
}

class LingoLangaHome extends StatefulWidget {
  final VoidCallback toggleTheme;
  final VoidCallback toggleGender;
  final bool isMale;
  const LingoLangaHome(
      {super.key,
      required this.toggleTheme,
      required this.toggleGender,
      required this.isMale});
  @override
  State<LingoLangaHome> createState() => _LingoLangaHomeState();
}

class _LingoLangaHomeState extends State<LingoLangaHome> {
  final stt.SpeechToText _speech = stt.SpeechToText();
  final FlutterTts _tts = FlutterTts();
  final AudioPlayer _audioPlayer = AudioPlayer();

  bool _isListening = false;
  bool _isLoading = false;
  bool _useLiveMode = false;
  String _liveModel = 'gemini-2.5-flash';
  String _text = "Hold mic to speak";
  String _result = "";

  // Credit Tiers: Free (10), Pro (100), Enterprise (Unlimited/999)
  int _credits = 0;
  String _tier = "Free";

  final List<Map<String, String>> _history = []; // translation history

  LLRegion _selectedRegion = LLRegion.SouthAfrica;
  String _fromLang = "English";
  String _toLang = "isiZulu";
  List<String> get _langs =>
      LLLanguageController.getLanguagesForRegion(_selectedRegion);

  DateTime? _speechStart;
  Duration _lastDuration = Duration.zero;

  @override
  void initState() {
    super.initState();
    _syncCreditsAndTier();
    _tts.setLanguage(LLLanguageController.getGeminiCode(_toLang));
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    _tts.stop();
    super.dispose();
  }

  InputDecoration _modernDropdownDecoration({
    required bool isDark,
    required Color accent,
    required Color surface,
  }) {
    return InputDecoration(
      isDense: true,
      filled: true,
      fillColor: surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: accent.withValues(alpha: 0.22)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: accent, width: 1.4),
      ),
    );
  }

  Widget _elevatedField({
    required Widget child,
    required Color shadowColor,
  }) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: shadowColor.withValues(alpha: 0.16),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: child,
    );
  }

  Future<void> _playAiAudio(String audioBase64) async {
    try {
      debugPrint(
          '🔊 Attempting to play AI audio, base64 length: ${audioBase64.length}');
      final bytes = base64Decode(audioBase64);
      debugPrint('✅ Decoded ${bytes.length} bytes of audio data');

      // Write to temporary file for proper MP3 playback
      final tempDir = await getTemporaryDirectory();
      final tempFile = File('${tempDir.path}/google_tts_audio.mp3');
      await tempFile.writeAsBytes(bytes);
      debugPrint('💾 Audio file created: ${tempFile.path}');

      await _audioPlayer.stop();
      await _audioPlayer.play(DeviceFileSource(tempFile.path));
      debugPrint('🎵 AI audio playback started (Google TTS voice)');
    } catch (e) {
      debugPrint('❌ AI audio playback failed: $e');
      debugPrint('⚠️  Generic local TTS fallback disabled by design.');
    }
  }

  // REMEMBER: Credits are managed in Firestore users/{uid}
  void _syncCreditsAndTier() {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .snapshots()
          .listen((doc) {
        if (doc.exists && mounted) {
          setState(() {
            _credits = doc.data()?['credits'] ?? 0;
            _tier = doc.data()?['tier'] ?? "Free";
          });
        }
      });
    }
  }

  void _swap() => setState(() {
        final t = _fromLang;
        _fromLang = _toLang;
        _toLang = t;
      });

  void _onRegionChanged(LLRegion? region) {
    if (region == null) return;
    setState(() {
      _selectedRegion = region;
      final langs = _langs;
      if (!langs.contains(_fromLang)) {
        _fromLang = langs.first;
      }
      if (!langs.contains(_toLang)) {
        _toLang = langs.length > 1 ? langs[1] : langs.first;
      }
    });
  }

  Future<void> _translate() async {
    int creditsNeeded = (_lastDuration.inSeconds / 10).ceil();
    if (_credits < creditsNeeded && _tier != "Enterprise") {
      _showTopUp();
      return;
    }

    setState(() => _isLoading = true);
    final functionUrl = dotenv.env['TRANSLATE_FUNCTION_URL'];
    final user = FirebaseAuth.instance.currentUser;

    if (functionUrl == null || functionUrl.isEmpty) {
      setState(() {
        _result = 'TRANSLATE_FUNCTION_URL not found in .env';
        _isLoading = false;
      });
      return;
    }

    if (user == null) {
      setState(() {
        _result = 'Please sign in again.';
        _isLoading = false;
      });
      return;
    }

    final idToken = await user.getIdToken();
    if (idToken == null || idToken.isEmpty) {
      setState(() {
        _result = 'Unable to authenticate request.';
        _isLoading = false;
      });
      return;
    }

    final url = Uri.parse(functionUrl);
    debugPrint('Function URL: $url');
    final requestBody = jsonEncode({
      "text": _text,
      "sourceLanguage": _fromLang,
      "targetLanguage": _toLang,
      "sourceLanguageCode": LLLanguageController.getGeminiCode(_fromLang),
      "targetLanguageCode": LLLanguageController.getGeminiCode(_toLang),
      "isRespectMode": false,
      "isMale": widget.isMale,
      if (_useLiveMode) "model": _liveModel,
    });
    debugPrint('Request body: $requestBody');

    String? appCheckToken;
    try {
      appCheckToken = await FirebaseAppCheck.instance.getToken();
    } catch (e) {
      // In debug or rollout mode, proceed without App Check header.
      // Backend enforcement should remain off until debug tokens are enrolled.
      debugPrint('App Check token unavailable: $e');
      appCheckToken = null;
    }
    final response = await http.post(
      url,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $idToken',
        if (appCheckToken != null && appCheckToken.isNotEmpty)
          'X-Firebase-AppCheck': appCheckToken,
      },
      body: requestBody,
    );
    debugPrint('API response code: ${response.statusCode}');
    debugPrint('API response body: ${response.body}');

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      setState(() {
        if (data['translation'] != null &&
            data['translation'].toString().isNotEmpty) {
          _result = data['translation'];
        } else {
          _result = 'No translation returned';
        }
        _isLoading = false;

        // Update Firestore credits
        FirebaseFirestore.instance
            .collection('users')
            .doc(FirebaseAuth.instance.currentUser?.uid)
            .update({
          'credits': FieldValue.increment(-creditsNeeded),
          'last_translation': DateTime.now(),
        });
      });
      // Add to history
      setState(() {
        _history.insert(0, {
          'q': _text,
          'a': _result,
          'from': _fromLang,
          'to': _toLang,
        });
      });

      // Save to Firestore history
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('translation_history')
            .add({
          'text': _text,
          'translation': _result,
          'from': _fromLang,
          'to': _toLang,
          'timestamp': DateTime.now(),
        });
      }

      if (data['audioContent'] != null &&
          data['audioContent'].toString().isNotEmpty) {
        debugPrint(
            '📥 audioContent received from backend, playing AI audio...');
        await _playAiAudio(data['audioContent']);
      } else {
        debugPrint(
            '⚠️  No native high-quality audio available for this language/voice.');
      }
    } else {
      debugPrint('API call failed with status ${response.statusCode}');
      setState(() {
        _result = 'Error: ${response.statusCode} - ${response.body}';
        _isLoading = false;
      });
    }
  }

  Future<void> _checkLiveHealth() async {
    final functionUrl = dotenv.env['TRANSLATE_FUNCTION_URL'];
    final user = FirebaseAuth.instance.currentUser;

    if (functionUrl == null || functionUrl.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('TRANSLATE_FUNCTION_URL not found in .env')),
      );
      return;
    }

    if (user == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please sign in first.')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final idToken = await user.getIdToken();
      if (idToken == null || idToken.isEmpty) {
        setState(() => _isLoading = false);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unable to get Firebase ID token.')),
        );
        return;
      }

      String? appCheckToken;
      try {
        appCheckToken = await FirebaseAppCheck.instance.getToken();
      } catch (e) {
        debugPrint('Live health App Check token unavailable: $e');
      }

      final healthUrl = functionUrl.replaceAll('/processSpeech', '/liveHealthCheck');
      final response = await http.post(
        Uri.parse(healthUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $idToken',
          if (appCheckToken != null && appCheckToken.isNotEmpty)
            'X-Firebase-AppCheck': appCheckToken,
        },
        body: jsonEncode({}),
      );

      setState(() => _isLoading = false);
      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final model = data['model']?.toString() ?? 'unknown';
        setState(() {
          _liveModel = model;
          _useLiveMode = true;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Live check OK: $model (Live Mode ON)')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Live check failed: ${response.statusCode}'),
            duration: const Duration(seconds: 4),
          ),
        );
        debugPrint('Live check body: ${response.body}');
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Live check error: $e')),
      );
    }
  }

  void _showTopUp() {
    showDialog(
        context: context,
        builder: (c) => AlertDialog(
              title: const Text("Top Up Credits"),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text("Choose a credit package:"),
                  const SizedBox(height: 10),
                  ElevatedButton(
                    onPressed: () {
                      FirebaseFirestore.instance
                          .collection('users')
                          .doc(FirebaseAuth.instance.currentUser?.uid)
                          .update({
                        'credits': FieldValue.increment(35),
                      });
                      Navigator.pop(context);
                    },
                    child: const Text("R10 - 35 Credits"),
                  ),
                  const SizedBox(height: 5),
                  ElevatedButton(
                    onPressed: () {
                      FirebaseFirestore.instance
                          .collection('users')
                          .doc(FirebaseAuth.instance.currentUser?.uid)
                          .update({
                        'credits': FieldValue.increment(200),
                      });
                      Navigator.pop(context);
                    },
                    child: const Text("R60 - 200 Credits"),
                  ),
                  const SizedBox(height: 5),
                  ElevatedButton(
                    onPressed: () {
                      FirebaseFirestore.instance
                          .collection('users')
                          .doc(FirebaseAuth.instance.currentUser?.uid)
                          .update({
                        'credits': FieldValue.increment(1000),
                      });
                      Navigator.pop(context);
                    },
                    child: const Text("R200 - 1000 Credits"),
                  ),
                ],
              ),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text("CLOSE")),
              ],
            ));
  }

  Future<String> getImageUrl() async {
    try {
      return await FirebaseStorage.instance
          .ref('limpopo_voice.png')
          .getDownloadURL();
    } catch (e) {
      debugPrint('Error loading image: $e');
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent =
        widget.isMale ? Colors.blue.shade500 : Colors.indigo.shade400;
    final accentDeep =
        widget.isMale ? Colors.blue.shade800 : Colors.indigo.shade700;
    final surface = isDark ? const Color(0xFF1B2331) : Colors.white;
    final pageStart =
        isDark ? const Color(0xFF0A1220) : const Color(0xFFF4F8FF);
    final pageEnd = isDark ? const Color(0xFF0F1A2E) : const Color(0xFFEAF1FF);

    return Scaffold(
      backgroundColor: pageStart,
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.transparent,
        actions: [
          IconButton(
            icon: const Icon(Icons.brightness_6),
            onPressed: widget.toggleTheme,
          ),
          Row(
            children: [
              const Text('Male', style: TextStyle(fontSize: 12)),
              Switch(
                value: widget.isMale,
                activeThumbColor: Colors.blue,
                inactiveThumbColor: Colors.indigo,
                onChanged: (_) => widget.toggleGender(),
              ),
              const Text('Female', style: TextStyle(fontSize: 12)),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.credit_card),
            tooltip: 'Top up credits',
            onPressed: _showTopUp,
          ),
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: Tooltip(
              message: '1 credit = 10 seconds of speech',
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(_tier,
                      style: const TextStyle(
                          fontSize: 10, fontWeight: FontWeight.bold)),
                  Text("$_credits",
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.bold)),
                  const Text('(1=10s)',
                      style: TextStyle(fontSize: 9, color: Colors.grey)),
                ],
              ),
            ),
          )
        ],
      ),
      bottomNavigationBar: null,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [pageStart, pageEnd],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: DefaultTabController(
            length: 2,
            child: Column(
              children: [
                Container(
                  margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  height: 118,
                  width: double.infinity,
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [
                        BoxShadow(
                          color: accent.withValues(alpha: 0.24),
                          blurRadius: 18,
                          offset: const Offset(0, 8),
                        ),
                      ],
                      gradient: LinearGradient(
                        colors: [accentDeep, accent],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'LingoLanga',
                            style: TextStyle(
                              fontSize: 30,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Your Africa Voice Translation Studio',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.white.withValues(alpha: 0.9),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Container(
                    height: 48,
                    decoration: BoxDecoration(
                      color: surface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: accent.withValues(alpha: 0.25)),
                    ),
                    child: TabBar(
                      indicatorSize: TabBarIndicatorSize.tab,
                      indicator: BoxDecoration(
                        borderRadius: BorderRadius.all(Radius.circular(12)),
                        color: accent,
                      ),
                      labelColor: Colors.white,
                      unselectedLabelColor: accent,
                      dividerColor: Colors.transparent,
                      tabs: const [
                        Tab(text: 'Translate'),
                        Tab(text: 'History'),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: TabBarView(
                    children: [
                      SingleChildScrollView(
                        child: Column(
                          children: [
                            const SizedBox(height: 10),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(22, 12, 22, 8),
                              child: _isLoading
                                  ? const CircularProgressIndicator()
                                  : Column(
                                      children: [
                                        if (_result.isNotEmpty) ...
                                        [
                                          Container(
                                            width: double.infinity,
                                            padding: const EdgeInsets.all(14),
                                            decoration: BoxDecoration(
                                              color: surface,
                                              borderRadius: BorderRadius.circular(14),
                                              border: Border.all(
                                                  color: accent.withValues(alpha: 0.25)),
                                              boxShadow: [
                                                BoxShadow(
                                                  color: accent.withValues(alpha: 0.10),
                                                  blurRadius: 10,
                                                  offset: const Offset(0, 4),
                                                ),
                                              ],
                                            ),
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text('Translation',
                                                    style: TextStyle(
                                                        fontSize: 11,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                        color: accent,
                                                        letterSpacing: 0.8)),
                                                const SizedBox(height: 6),
                                                Text(_result,
                                                    style: TextStyle(
                                                        fontSize: 26,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        color: accentDeep),
                                                    textAlign:
                                                        TextAlign.start),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(height: 10),
                                        ],
                                        Wrap(
                                          alignment: WrapAlignment.center,
                                          children: [
                                            FilterChip(
                                              label: Text(_useLiveMode
                                                  ? 'Live: ON'
                                                  : 'Live: OFF'),
                                              selected: _useLiveMode,
                                              onSelected: (v) {
                                                setState(() => _useLiveMode = v);
                                              },
                                            ),
                                            const SizedBox(width: 6),
                                            IconButton(
                                              icon: const Icon(Icons.wifi_tethering),
                                              tooltip: 'Live API check',
                                              onPressed: _checkLiveHealth,
                                            ),
                                            IconButton(
                                              icon: const Icon(Icons.share),
                                              onPressed: () async {
                                                if (_result.isNotEmpty) {
                                                  await SharePlus.instance
                                                      .share(
                                                    ShareParams(text: _result),
                                                  );
                                                }
                                              },
                                            ),
                                            IconButton(
                                              icon: const Icon(Icons.replay),
                                              onPressed: () {
                                                if (_text.length > 2 &&
                                                    _text !=
                                                        "Hold mic to speak") {
                                                  _translate();
                                                }
                                              },
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                            ),
                            const SizedBox(height: 20),
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 16),
                              child: Row(
                                children: [
                                  const Text('Region',
                                      style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          color: Colors.blue)),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: _elevatedField(
                                      shadowColor: accent,
                                      child: DropdownButtonFormField<LLRegion>(
                                        decoration: _modernDropdownDecoration(
                                          isDark: isDark,
                                          accent: accent,
                                          surface: surface,
                                        ),
                                        isExpanded: true,
                                        initialValue: _selectedRegion,
                                        items: LLRegion.values
                                            .map((region) => DropdownMenuItem(
                                                  value: region,
                                                  child: Text(
                                                      LLLanguageController
                                                          .regionLabel(region),
                                                      overflow: TextOverflow
                                                          .ellipsis),
                                                ))
                                            .toList(),
                                        onChanged: _onRegionChanged,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 16),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: _elevatedField(
                                      shadowColor: accent,
                                      child: DropdownButtonFormField<String>(
                                          decoration: _modernDropdownDecoration(
                                            isDark: isDark,
                                            accent: accent,
                                            surface: surface,
                                          ),
                                          isExpanded: true,
                                          initialValue: _fromLang,
                                          items: _langs
                                              .map((l) => DropdownMenuItem(
                                                  value: l,
                                                  child: Text(l,
                                                      overflow: TextOverflow
                                                          .ellipsis)))
                                              .toList(),
                                          onChanged: (v) =>
                                              setState(() => _fromLang = v!)),
                                    ),
                                  ),
                                  IconButton(
                                      icon:
                                          Icon(Icons.swap_horiz, color: accent),
                                      onPressed: _swap),
                                  Expanded(
                                    child: _elevatedField(
                                      shadowColor: accent,
                                      child: DropdownButtonFormField<String>(
                                          decoration: _modernDropdownDecoration(
                                            isDark: isDark,
                                            accent: accent,
                                            surface: surface,
                                          ),
                                          isExpanded: true,
                                          initialValue: _toLang,
                                          items: _langs
                                              .map((l) => DropdownMenuItem(
                                                  value: l,
                                                  child: Text(l,
                                                      overflow: TextOverflow
                                                          .ellipsis)))
                                              .toList(),
                                          onChanged: (v) =>
                                              setState(() => _toLang = v!)),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 0),
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 12),
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? const Color(0xFF1B2331)
                                      : Colors.grey.shade100,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                      color: accent.withValues(alpha: 0.18)),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('You said',
                                        style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                            color: isDark
                                                ? Colors.white38
                                                : Colors.blueGrey.shade400,
                                            letterSpacing: 0.8)),
                                    const SizedBox(height: 4),
                                    Text(_text,
                                        style: TextStyle(
                                            fontSize: 16,
                                            color: isDark
                                                ? Colors.white70
                                                : Colors.blueGrey.shade700)),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            GestureDetector(
                              onLongPressStart: (_) async {
                                _speechStart = DateTime.now();
                                bool available = await _speech.initialize();
                                if (available) {
                                  setState(() => _isListening = true);
                                  _speech.listen(
                                      onResult: (v) => setState(
                                          () => _text = v.recognizedWords));
                                }
                              },
                              onLongPressEnd: (_) {
                                if (_speechStart != null) {
                                  _lastDuration =
                                      DateTime.now().difference(_speechStart!);
                                }
                                _speech.stop();
                                setState(() => _isListening = false);
                                if (_text.length > 2 &&
                                    _text != "Hold mic to speak") {
                                  _translate();
                                }
                              },
                              child: CircleAvatar(
                                  radius: 40,
                                  backgroundColor:
                                      _isListening ? Colors.red : accent,
                                  child: const Icon(Icons.mic,
                                      color: Colors.white, size: 35)),
                            ),
                            const SizedBox(height: 18),
                          ],
                        ),
                      ),
                      // history page
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            if (_history.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: ElevatedButton.icon(
                                  icon: const Icon(Icons.delete),
                                  label: const Text('Delete All History'),
                                  style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.red),
                                  onPressed: () {
                                    showDialog(
                                      context: context,
                                      builder: (c) => AlertDialog(
                                        title: const Text('Delete History?'),
                                        content: const Text(
                                            'This will permanently delete all translation history.'),
                                        actions: [
                                          TextButton(
                                              onPressed: () =>
                                                  Navigator.pop(context),
                                              child: const Text('CANCEL')),
                                          TextButton(
                                            onPressed: () {
                                              setState(() => _history.clear());
                                              final user = FirebaseAuth
                                                  .instance.currentUser;
                                              if (user != null) {
                                                FirebaseFirestore.instance
                                                    .collection('users')
                                                    .doc(user.uid)
                                                    .collection(
                                                        'translation_history')
                                                    .get()
                                                    .then((snapshot) {
                                                  for (var doc
                                                      in snapshot.docs) {
                                                    doc.reference.delete();
                                                  }
                                                });
                                              }
                                              Navigator.pop(context);
                                            },
                                            child: const Text('DELETE',
                                                style: TextStyle(
                                                    color: Colors.red)),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                              ),
                            Expanded(
                              child: _history.isEmpty
                                  ? const Center(child: Text('No history yet'))
                                  : ListView.builder(
                                      itemCount: _history.length,
                                      itemBuilder: (c, i) {
                                        final e = _history[i];
                                        return ListTile(
                                          title: Text(e['a']!),
                                          subtitle: Text(
                                              '${e['q']} (${e['from']} → ${e['to']})'),
                                          trailing: IconButton(
                                            icon: const Icon(Icons.replay),
                                            onPressed: () {
                                              setState(() {
                                                _text = e['q']!;
                                                _fromLang = e['from']!;
                                                _toLang = e['to']!;
                                              });
                                              _translate();
                                            },
                                          ),
                                        );
                                      },
                                    ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class LingoLangaLogin extends StatefulWidget {
  final VoidCallback toggleTheme;
  final VoidCallback toggleGender;
  final bool isMale;
  const LingoLangaLogin(
      {super.key,
      required this.toggleTheme,
      required this.toggleGender,
      required this.isMale});

  @override
  State<LingoLangaLogin> createState() => _LingoLangaLoginState();
}

class _LingoLangaLoginState extends State<LingoLangaLogin> {
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _codeController = TextEditingController();
  String _verificationId = '';
  bool _codeSent = false;
  bool _isLoading = false;

  @override
  void dispose() {
    _phoneController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    String phone = _phoneController.text.trim();
    if (phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enter your phone number')));
      return;
    }

    // Ensure phone starts with country code
    if (!phone.startsWith('+')) {
      phone = '+27$phone'; // Default to South Africa
    }

    setState(() => _isLoading = true);

    await FirebaseAuth.instance.verifyPhoneNumber(
      phoneNumber: phone,
      verificationCompleted: (PhoneAuthCredential credential) async {
        await FirebaseAuth.instance.signInWithCredential(credential);
        await _createUserDocument();
      },
      verificationFailed: (FirebaseAuthException e) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: ${e.message}')));
      },
      codeSent: (String verificationId, int? resendToken) {
        setState(() {
          _verificationId = verificationId;
          _codeSent = true;
          _isLoading = false;
        });
      },
      codeAutoRetrievalTimeout: (String verificationId) {
        setState(() => _verificationId = verificationId);
      },
    );
  }

  Future<void> _verifyCode() async {
    String code = _codeController.text.trim();
    if (code.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enter the verification code')));
      return;
    }

    setState(() => _isLoading = true);

    try {
      PhoneAuthCredential credential = PhoneAuthProvider.credential(
        verificationId: _verificationId,
        smsCode: code,
      );
      await FirebaseAuth.instance.signInWithCredential(credential);
      await _createUserDocument();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Invalid code: $e')));
    }
  }

  Future<void> _createUserDocument() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final doc = FirebaseFirestore.instance.collection('users').doc(user.uid);
      final snapshot = await doc.get();
      if (!snapshot.exists) {
        await doc.set({
          'phone': user.phoneNumber,
          'credits': 10, // Free tier starts with 10 credits
          'tier': 'Free',
          'created': DateTime.now(),
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? const Color(0xFF1B2331) : Colors.blue.shade50;
    final textColor = isDark ? Colors.blue.shade200 : Colors.blue.shade700;

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                height: 120,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(14),
                ),
                alignment: Alignment.center,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'LingoLanga',
                      style: TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w800,
                        color: textColor,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Your Africa Voice',
                      style: TextStyle(
                        fontSize: 15,
                        color: textColor,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Text("LingoLanga Pty Ltd",
                  style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: textColor)),
              const SizedBox(height: 50),
              if (!_codeSent) ...[
                TextField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Phone Number',
                    hintText: '0821234567',
                    prefixText: '+27 ',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 20),
                _isLoading
                    ? const CircularProgressIndicator()
                    : ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          foregroundColor: Colors.white,
                          minimumSize: const Size(200, 50),
                        ),
                        onPressed: _sendCode,
                        child: const Text("SEND CODE"),
                      ),
              ] else ...[
                const Text('Enter the verification code sent to your phone:',
                    textAlign: TextAlign.center),
                const SizedBox(height: 20),
                TextField(
                  controller: _codeController,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  decoration: const InputDecoration(
                    labelText: 'Verification Code',
                    hintText: '123456',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 20),
                _isLoading
                    ? const CircularProgressIndicator()
                    : ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          foregroundColor: Colors.white,
                          minimumSize: const Size(200, 50),
                        ),
                        onPressed: _verifyCode,
                        child: const Text("VERIFY"),
                      ),
                const SizedBox(height: 10),
                TextButton(
                  onPressed: () {
                    setState(() {
                      _codeSent = false;
                      _codeController.clear();
                    });
                  },
                  child: const Text('Change Phone Number'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
