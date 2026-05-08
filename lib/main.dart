import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:http/http.dart' as http;
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:audioplayers/audioplayers.dart';
import 'translation_service.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    await FirebaseAppCheck.instance.activate(
      androidProvider: kDebugMode ? AndroidProvider.debug : AndroidProvider.playIntegrity,
    );
    await dotenv.load(fileName: ".env");
  } catch (e) { debugPrint("Firebase/Env Error: $e"); }
  runApp(const LimpopoVoiceApp());
}

class LimpopoVoiceApp extends StatefulWidget {
  const LimpopoVoiceApp({super.key});
  @override State<LimpopoVoiceApp> createState() => _LimpopoVoiceAppState();
}

class _LimpopoVoiceAppState extends State<LimpopoVoiceApp> {
  ThemeMode _themeMode = ThemeMode.dark;
  void _toggleTheme() => setState(() =>
      _themeMode = _themeMode == ThemeMode.light ? ThemeMode.dark : ThemeMode.light);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Limpopo Voice',
      debugShowCheckedModeBanner: false,
      themeMode: _themeMode,
      theme: ThemeData(
        brightness: Brightness.light,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1E3C72),
          primary: const Color(0xFF1E3C72), secondary: const Color(0xFF2A5298)),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1E3C72),
          primary: const Color(0xFF3B6FD4), secondary: const Color(0xFF5B8FEE),
          brightness: Brightness.dark),
        useMaterial3: true,
      ),
      home: HomeScreen(onToggleTheme: _toggleTheme),
    );
  }
}

class _CreditTier { final String name; final int secs; final String price;
  const _CreditTier(this.name, this.secs, this.price); }

const _tiers = [_CreditTier('Standard', 180, 'R40.00'),
                _CreditTier('Premium', 600, 'R120.00'),
                _CreditTier('Enterprise', 1500, 'R300.00')];
const int _usageCostSecs = 5;

class HistoryItem {
  final String inputLang, outputLang, original, translated;
  final String? phonetic;
  final DateTime time;
  HistoryItem(this.inputLang, this.outputLang, this.original, this.translated, this.time, {this.phonetic});
}

class HomeScreen extends StatefulWidget {
  final VoidCallback onToggleTheme;
  const HomeScreen({super.key, required this.onToggleTheme});
  @override State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _activeTab = 'translate';
  final stt.SpeechToText _speech = stt.SpeechToText();
  late final TranslationService _translationService;
  late final AudioPlayer _audioPlayer;
  bool _speechAvailable = false;
  bool _isTalking = false;
  bool _isTranslating = false;
  bool _isPlayingAudio = false;
  String _selectedInputLang = 'English';
  String _selectedOutputLang = 'Sepedi';
  // Input: English, Afrikaans, Limpopo 3, Secondary African, International
  final _inputLangs = ['English', 'Afrikaans', 'Sepedi', 'Xitsonga', 'Tshivenda', 'Shona',
    'Sesotho', 'isiNdebele', 'Portuguese', 'Mandarin', 'Hindi', 'Urdu', 'German', 'French'];
  // Output: Limpopo 3, Secondary African, Afrikaans, English, International
  final _outputLangs = ['Sepedi', 'Xitsonga', 'Tshivenda', 'Shona', 'Sesotho', 'isiNdebele',
    'Afrikaans', 'English', 'Portuguese', 'Mandarin', 'Hindi', 'Urdu', 'German', 'French'];
  final _locales = {'English': 'en-ZA', 'Sesotho': 'st-ZA', 'Sepedi': 'nso-ZA', 'Tshivenda': 've-ZA',
    'Shona': 'sn-ZW', 'Xitsonga': 'ts-ZA', 'Afrikaans': 'af-ZA', 'isiNdebele': 'nr-ZA',
    'Portuguese': 'pt-PT', 'Mandarin': 'zh-CN', 'Hindi': 'hi-IN', 'Urdu': 'ur-PK', 'German': 'de-DE', 'French': 'fr-FR'};
  final _translateCodes = {
    'English': 'en',
    'Sesotho': 'st',
    'Sepedi': 'nso',
    'Tshivenda': 've',
    'Shona': 'sn',
    'Xitsonga': 'ts',
    'Afrikaans': 'af',
    'isiNdebele': 'nr',
    'Portuguese': 'pt',
    'Mandarin': 'zh-CN',
    'Hindi': 'hi',
    'Urdu': 'ur',
    'German': 'de',
    'French': 'fr',
  };
  static const _voiceNames = {
    'Sesotho':   'Palesa',
    'Sepedi':    'Mpho',
    'Tshivenda': 'Mulalo',
    'Xitsonga':  'Basetsana',
    'Shona':     'Nandi',
    'Afrikaans': 'Rolanda',
    'isiNdebele': 'Dumisani',
    'Portuguese': 'Lurdes',
    'Mandarin': 'Yifei',
    'Hindi': 'Aditi',
    'Urdu': 'Mawra',
    'German': 'Martina',
    'French': 'Marion',
    'English':   'Aletta',
  };
  String _spokenText = '';
  String _translatedText = '';
  String _phoneticText = '';
  String _spokenLang = '';
  String _translatedLang = '';
  final TextEditingController _tttController = TextEditingController();
  int _credits = 0;
  int _freeTryTokens = 2;
  final List<HistoryItem> _history = [];
  String _selectedLearnLang = 'Sepedi';
  bool _exportingHistory = false;
  Timer? _autocorrectTimer;

  static const Map<String, List<Map<String, String>>> _learnPhrasesByLang = {
    'English': [
      {'text': 'Hello, how are you?', 'en': 'Hello, how are you?'},
      {'text': 'Thank you very much.', 'en': 'Thank you very much.'},
      {'text': 'Please help me.', 'en': 'Please help me.'},
      {'text': 'Goodbye, see you later.', 'en': 'Goodbye, see you later.'},
    ],
    'Sepedi': [
      {'text': 'Dumela, o kae?', 'en': 'Hello, how are you?'},
      {'text': 'Ke a leboga kudu.', 'en': 'Thank you very much.'},
      {'text': 'Hle nthuise.', 'en': 'Please help me.'},
      {'text': 'Sala gabotse.', 'en': 'Goodbye.'},
    ],
    'Xitsonga': [
      {'text': 'Avuxeni, u njhani?', 'en': 'Hello, how are you?'},
      {'text': 'Ndza nkhensa swinene.', 'en': 'Thank you very much.'},
      {'text': 'Ndzi kombela mpfuno.', 'en': 'Please help me.'},
      {'text': 'A hi tlhelela.', 'en': 'Goodbye.'},
    ],
    'Tshivenda': [
      {'text': 'Ndaa, ni hone?', 'en': 'Hello, how are you?'},
      {'text': 'Ndo livhuwa vhukuma.', 'en': 'Thank you very much.'},
      {'text': 'Ndichelphe, ndi khou humbela.', 'en': 'Please help me.'},
      {'text': 'Ndo livhuwa, tshee.', 'en': 'Goodbye.'},
    ],
    'Shona': [
      {'text': 'Mhoro, makadii?', 'en': 'Hello, how are you?'},
      {'text': 'Ndatenda zvikuru.', 'en': 'Thank you very much.'},
      {'text': 'Ndapota ndibatsireiwo.', 'en': 'Please help me.'},
      {'text': 'Chisarai zvakanaka.', 'en': 'Goodbye.'},
    ],
    'Sesotho': [
      {'text': 'Dumela, o phela jwang?', 'en': 'Hello, how are you?'},
      {'text': 'Ke a leboha haholo.', 'en': 'Thank you very much.'},
      {'text': 'Ka kopo nthuse.', 'en': 'Please help me.'},
      {'text': 'Sala hantle.', 'en': 'Goodbye.'},
    ],
    'isiNdebele': [
      {'text': 'Lotjhani, unjani?', 'en': 'Hello, how are you?'},
      {'text': 'Ngiyathokoza khulu.', 'en': 'Thank you very much.'},
      {'text': 'Ngicela ungisize.', 'en': 'Please help me.'},
      {'text': 'Sala kahle.', 'en': 'Goodbye.'},
    ],
    'Afrikaans': [
      {'text': 'Hallo, hoe gaan dit?', 'en': 'Hello, how are you?'},
      {'text': 'Baie dankie.', 'en': 'Thank you very much.'},
      {'text': 'Help my asseblief.', 'en': 'Please help me.'},
      {'text': 'Totsiens.', 'en': 'Goodbye.'},
    ],
    'Portuguese': [
      {'text': 'Ola, como esta?', 'en': 'Hello, how are you?'},
      {'text': 'Muito obrigado.', 'en': 'Thank you very much.'},
      {'text': 'Por favor, ajude-me.', 'en': 'Please help me.'},
      {'text': 'Ate logo.', 'en': 'Goodbye.'},
    ],
    'Mandarin': [
      {'text': '你好，你怎么样？', 'en': 'Hello, how are you?', 'phonetic': 'Nǐ hǎo, nǐ zěnme yàng?'},
      {'text': '非常感谢。', 'en': 'Thank you very much.', 'phonetic': 'Fēicháng gǎnxiè.'},
      {'text': '请帮帮我。', 'en': 'Please help me.', 'phonetic': 'Qǐng bāng bāng wǒ.'},
      {'text': '再见。', 'en': 'Goodbye.', 'phonetic': 'Zàijiàn.'},
    ],
    'Hindi': [
      {'text': 'नमस्ते, आप कैसे हैं?', 'en': 'Hello, how are you?', 'phonetic': 'Namaste, aap kaise hain?'},
      {'text': 'बहुत धन्यवाद।', 'en': 'Thank you very much.', 'phonetic': 'Bahut dhanyavaad.'},
      {'text': 'कृपया मेरी मदद कीजिए।', 'en': 'Please help me.', 'phonetic': 'Kripya meri madad kijiye.'},
      {'text': 'अलविदा।', 'en': 'Goodbye.', 'phonetic': 'Alvida.'},
    ],
    'Urdu': [
      {'text': 'السلام علیکم، آپ کیسے ہیں؟', 'en': 'Hello, how are you?', 'phonetic': 'As-salaam-alaikum, aap kaise hain?'},
      {'text': 'بہت شکریہ۔', 'en': 'Thank you very much.', 'phonetic': 'Bohat shukriya.'},
      {'text': 'مہربانی کرکے میری مدد کریں۔', 'en': 'Please help me.', 'phonetic': 'Meherbani karke meri madad karein.'},
      {'text': 'خدا حافظ۔', 'en': 'Goodbye.', 'phonetic': 'Khuda hafiz.'},
    ],
    'German': [
      {'text': 'Hallo, wie geht es dir?', 'en': 'Hello, how are you?'},
      {'text': 'Vielen Dank.', 'en': 'Thank you very much.'},
      {'text': 'Bitte hilf mir.', 'en': 'Please help me.'},
      {'text': 'Tschuss, bis spater.', 'en': 'Goodbye, see you later.'},
    ],
    'French': [
      {'text': 'Bonjour, comment ca va?', 'en': 'Hello, how are you?'},
      {'text': 'Merci beaucoup.', 'en': 'Thank you very much.'},
      {'text': 'S il vous plait, aidez-moi.', 'en': 'Please help me.'},
      {'text': 'Au revoir, a bientot.', 'en': 'Goodbye, see you soon.'},
    ],
  };

  @override
  void initState() {
    super.initState();
    _audioPlayer = AudioPlayer();
    final apiKey = dotenv.env['NARAKEET_API_KEY'] ?? '';
    _translationService = TranslationService(apiKey: apiKey);
    _initSpeech();
    _tttController.addListener(_onInputChanged);
  }

  void _onInputChanged() {
    _autocorrectTimer?.cancel();
    if (_tttController.text.trim().length < 4) return;
    _autocorrectTimer = Timer(const Duration(milliseconds: 700), _runAutocorrect);
  }

  Future<void> _runAutocorrect() async {
    final text = _tttController.text;
    if (text.trim().length < 4) return;
    final source = _translateCodes[_selectedInputLang] ?? 'auto';
    final uri = Uri.parse(
      'https://translate.googleapis.com/translate_a/single?client=gtx&sl=$source&tl=en&dt=t&dt=ss&q=${Uri.encodeQueryComponent(text)}',
    );
    try {
      final response = await http.get(uri);
      if (response.statusCode != 200) return;
      final decoded = jsonDecode(response.body) as List?;
      if (decoded == null || decoded.length <= 7) return;
      final ssArr = decoded[7];
      if (ssArr is! List || ssArr.isEmpty) return;
      final corrected = ssArr[0];
      if (corrected is! String || corrected.isEmpty || corrected == text) return;
      _tttController.removeListener(_onInputChanged);
      _tttController.value = TextEditingValue(
        text: corrected,
        selection: TextSelection.collapsed(offset: corrected.length),
      );
      _tttController.addListener(_onInputChanged);
    } catch (_) {}
  }

  Future<void> _initSpeech() async {
    final ok = await _speech.initialize(onError: (e) => debugPrint('STT: $e'));
    setState(() => _speechAvailable = ok);
  }

  void _startListening() async {
    if (!_speechAvailable) { _showSnack('Microphone not available'); return; }
    setState(() { _isTalking = true; _spokenText = ''; _translatedText = ''; _phoneticText = ''; _spokenLang = ''; _translatedLang = ''; });
    await _speech.listen(
      onResult: (r) {
        setState(() { _spokenText = r.recognizedWords; _spokenLang = _selectedInputLang; });
        if (r.finalResult && _spokenText.isNotEmpty) {
          _doTranslate(_spokenText);
        }
      },
      localeId: _locales[_selectedInputLang] ?? 'en-ZA',
      listenFor: const Duration(seconds: 30),
      pauseFor: const Duration(seconds: 3),
    );
  }

  void _stopListening() async {
    await _speech.stop();
    setState(() => _isTalking = false);
  }

  bool _consumeUsageAllowance() {
    if (_credits >= _usageCostSecs) {
      setState(() => _credits -= _usageCostSecs);
      return true;
    }
    if (_freeTryTokens > 0) {
      setState(() => _freeTryTokens -= 1);
      _showSnack('Used 1 free try token (${_freeTryTokens} left).');
      return true;
    }
    _showSnack('No balance left. Please top up to continue.');
    return false;
  }

  Future<void> _doTranslate(String input) async {
    if (!_consumeUsageAllowance()) {
      return;
    }
    setState(() => _isTranslating = true);
    final result = await _translateText(input);
    if (!mounted) {
      return;
    }

    setState(() {
      _translatedText = result;
      _translatedLang = _selectedOutputLang;
      _isTranslating = false;
      // _phoneticText is set as a side-effect inside _translateText; include it here so the UI rebuilds with it
    });

    _history.insert(0, HistoryItem(_selectedInputLang, _selectedOutputLang,
        input, result, DateTime.now(), phonetic: _phoneticText));
    await _speakTranslatedText(result);
  }

  Future<String> _translateText(String input) async {
    final source = _translateCodes[_selectedInputLang] ?? 'auto';
    final target = _translateCodes[_selectedOutputLang] ?? 'en';
    final needsPhonetics = _selectedOutputLang == 'Hindi' || _selectedOutputLang == 'Urdu' || _selectedOutputLang == 'Mandarin';
    final uri = Uri.parse(
      'https://translate.googleapis.com/translate_a/single?client=gtx&sl=$source&tl=$target&dt=t${needsPhonetics ? '&dt=rm' : ''}&q=${Uri.encodeQueryComponent(input)}',
    );

    try {
      final response = await http.get(uri);
      if (response.statusCode != 200) {
        _phoneticText = '';
        return input;
      }
      final decoded = jsonDecode(response.body);
      if (decoded is List && decoded.isNotEmpty && decoded[0] is List) {
        final pieces = decoded[0] as List;
        final translated = pieces
            .whereType<List>()
            .map((segment) => segment.isNotEmpty ? segment.first.toString() : '')
            .join();

        if (needsPhonetics) {
          // dt=rm: romanization of each translated segment is at index [2] of each piece
          final phonetic = pieces
              .whereType<List>()
              .map((s) => s.length > 2 && s[2] != null ? s[2].toString().trim() : '')
              .where((s) => s.isNotEmpty)
              .join(' ')
              .trim();
          // Fallback: check top-level decoded[1] (some API variants put it there)
          final fallback = (phonetic.isEmpty && decoded.length > 1 && decoded[1] is String)
              ? (decoded[1] as String).trim()
              : '';
          _phoneticText = phonetic.isNotEmpty ? phonetic : fallback;
          debugPrint('Phonetics found: "$_phoneticText"');
        } else {
          _phoneticText = '';
        }

        return translated.trim().isEmpty ? input : translated.trim();
      }
      _phoneticText = '';
      return input;
    } catch (_) {
      _phoneticText = '';
      return input;
    }
  }

  Future<void> _speakText(String text, String language) async {
    if (text.trim().isEmpty) return;
    try {
      final voiceName = _voiceNames[language] ?? 'Aletta';
      final audioData = await _translationService.generateTranslation(text, voiceName);
      if (audioData != null && audioData.isNotEmpty) {
        await _audioPlayer.play(BytesSource(audioData));
      }
    } catch (e) {
      debugPrint('Audio playback error: $e');
    }
  }

  Future<void> _speakTranslatedText(String text) async {
    if (text.trim().isEmpty) {
      return;
    }
    
    try {
      setState(() => _isPlayingAudio = true);
      
      final voiceName = _voiceNames[_selectedOutputLang] ?? 'Aletta';
      debugPrint('Requesting audio for: $text (voice: $voiceName)');
      final audioData = await _translationService.generateTranslation(text, voiceName);
      
      debugPrint('Audio data received - size: ${audioData?.length ?? 0} bytes');
      
      if (audioData != null && audioData.isNotEmpty) {
        // Play directly from memory to reduce startup latency.
        await _audioPlayer.play(BytesSource(audioData));
        debugPrint('Audio playback started');
      } else {
        debugPrint('No audio data returned from API');
        _showSnack('Failed to generate audio');
      }
    } catch (e) {
      debugPrint('Audio playback error: $e');
      _showSnack('Error: Unable to play audio');
    } finally {
      setState(() => _isPlayingAudio = false);
    }
  }

  void _submitTTT() {
    final t = _tttController.text.trim();
    if (t.isEmpty) return;
    setState(() { _spokenText = t; _spokenLang = _selectedInputLang; _translatedText = ''; _phoneticText = ''; _translatedLang = ''; });
    _doTranslate(t);
    _tttController.clear();
    FocusScope.of(context).unfocus();
  }

  void _resetOutput() => setState(() { _spokenText = ''; _translatedText = ''; _phoneticText = ''; _spokenLang = ''; _translatedLang = ''; });

  void _showSnack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  void _showQrShare() {
    const appUrl = 'https://play.google.com/store/apps/details?id=com.limpopovoice.translate';
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Scan Here',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const Text('to share',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 20),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 8, offset: const Offset(0, 2))],
                ),
                padding: const EdgeInsets.all(12),
                child: QrImageView(
                  data: appUrl,
                  version: QrVersions.auto,
                  size: 200,
                  backgroundColor: Colors.white,
                  eyeStyle: const QrEyeStyle(
                    eyeShape: QrEyeShape.square,
                    color: Color(0xFF1E3C72),
                  ),
                  dataModuleStyle: const QrDataModuleStyle(
                    dataModuleShape: QrDataModuleShape.square,
                    color: Color(0xFF1E3C72),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text('Limpopo Voice',
                  style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white70 : const Color(0xFF1E3C72))),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showCreditTiers() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.account_balance_wallet, color: Color(0xFF2A5298)),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Credit Packages',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: Chip(label: Text('Balance: $_credits secs | Free tries: $_freeTryTokens')),
            ),
            const SizedBox(height: 16),
            ..._tiers.map((tier) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1E3C72),
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 52),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () {
                  Navigator.pop(ctx);
                  setState(() => _credits += tier.secs);
                  _showSnack('Topped up ${tier.secs} secs (${tier.price})');
                },
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        tier.name,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text('${tier.secs} secs'),
                    const SizedBox(width: 8),
                    Text(tier.price, style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            )),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          // Top bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(children: [
              IconButton(
                icon: Icon(isDark ? Icons.light_mode : Icons.dark_mode),
                onPressed: widget.onToggleTheme),
              IconButton(
                icon: const Icon(Icons.qr_code_2),
                tooltip: 'Share App',
                onPressed: _showQrShare,
              ),
              const Spacer(),
              OutlinedButton.icon(
                icon: Icon(Icons.account_balance_wallet, size: 16,
                    color: isDark ? Colors.white : const Color(0xFF1E3C72)),
                label: Text('$_credits s | $_freeTryTokens tries',
                    style: TextStyle(
                        color: isDark ? Colors.white : const Color(0xFF1E3C72),
                        fontWeight: FontWeight.bold)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: isDark ? Colors.white : const Color(0xFF1E3C72),
                  side: BorderSide(color: isDark ? Colors.white60 : const Color(0xFF1E3C72)),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                ),
                onPressed: _showCreditTiers,
              ),
            ]),
          ),
          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Container(
                width: double.infinity,
                height: 112,
                color: Colors.transparent,
                alignment: Alignment.center,
                child: Image.asset(
                  isDark ? 'assets/lv2.png' : 'assets/lv.png',
                  width: double.infinity,
                  height: 112,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.high,
                  errorBuilder: (_, __, ___) => Container(
                    width: double.infinity,
                    height: 112,
                    alignment: Alignment.center,
                    child: const Icon(Icons.image_not_supported, color: Colors.white),
                  ),
                ),
              ),
            ),
          ),
          // Tab switcher
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Container(
              decoration: BoxDecoration(
                color: isDark ? Colors.white12 : const Color(0xFF1E3C72).withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: ['translate', 'history', 'learn'].map((tab) {
                  final active = _activeTab == tab;
                  final label = tab == 'translate'
                      ? 'Translate'
                      : (tab == 'history' ? 'History' : 'Learn');
                  return Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _activeTab = tab),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.all(4),
                        padding: const EdgeInsets.symmetric(vertical: 11),
                        decoration: BoxDecoration(
                          color: active ? const Color(0xFF1E3C72) : Colors.transparent,
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: Center(child: Text(
                          label,
                          style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 15,
                            color: active ? Colors.white
                                : (isDark ? Colors.white60 : const Color(0xFF1E3C72)),
                          ),
                        )),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          // Content
          Expanded(
            child: _activeTab == 'translate'
                ? _buildTranslateTab(isDark)
                : (_activeTab == 'history'
                    ? _buildHistoryTab(isDark)
                    : _buildLearnTab(isDark)),
          ),
        ]),
      ),
    );
  }

  Widget _buildLearnTab(bool isDark) {
    final phrases = _learnPhrasesByLang[_selectedLearnLang] ?? _learnPhrasesByLang['English']!;
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Learn Everyday Phrases',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white : const Color(0xFF1E3C72),
            ),
          ),
          const SizedBox(height: 10),
          _langDrop(
            _selectedLearnLang,
            _outputLangs,
            (v) => setState(() => _selectedLearnLang = v!),
            isDark,
          ),
          const SizedBox(height: 14),
          ...phrases.map((phrase) => Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: isDark ? Colors.white10 : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: isDark ? Colors.white24 : Colors.grey.shade300),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        phrase['text'] ?? '',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                      if ((phrase['phonetic'] ?? '').isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          phrase['phonetic']!,
                          style: TextStyle(
                            fontSize: 12,
                            fontStyle: FontStyle.italic,
                            color: isDark ? Colors.orange.shade300 : Colors.orange.shade800,
                          ),
                        ),
                      ],
                      const SizedBox(height: 3),
                      Text(
                        phrase['en'] ?? '',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.white60 : Colors.grey.shade700,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.volume_up),
                  tooltip: 'Listen',
                  onPressed: () => _speakText(phrase['text'] ?? '', _selectedLearnLang),
                ),
              ],
            ),
          )),
        ],
      ),
    );
  }

  Widget _buildTranslateTab(bool isDark) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Language dropdowns
        Row(children: [
          Expanded(child: _langDrop(_selectedInputLang, _inputLangs, (v) => setState(() => _selectedInputLang = v!), isDark)),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 4),
              child: IconButton(
                icon: Icon(Icons.swap_horiz, color: isDark ? Colors.white70 : Colors.grey),
                onPressed: () => setState(() {
                  final tmp = _selectedInputLang;
                  _selectedInputLang = _selectedOutputLang;
                  _selectedOutputLang = tmp;
                }),
                tooltip: 'Swap languages',
              )),
          Expanded(child: _langDrop(_selectedOutputLang, _outputLangs, (v) => setState(() => _selectedOutputLang = v!), isDark)),
        ]),
        const SizedBox(height: 14),
        // TTT row
        Row(children: [
          Expanded(child: TextField(
            controller: _tttController,
            decoration: InputDecoration(
              hintText: 'Type text to translate...',
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              filled: true, fillColor: isDark ? Colors.white10 : Colors.grey.shade50,
            ),
            onSubmitted: (_) => _submitTTT(),
            textInputAction: TextInputAction.send,
          )),
          const SizedBox(width: 8),
          IconButton.filled(
            onPressed: _submitTTT,
            icon: const Icon(Icons.send),
            style: IconButton.styleFrom(
                backgroundColor: const Color(0xFF1E3C72),
                foregroundColor: Colors.white,
                minimumSize: const Size(48, 48)),
          ),
        ]),
        const SizedBox(height: 8),
        Row(mainAxisAlignment: MainAxisAlignment.start, children: [
          TextButton.icon(onPressed: _spokenText.isNotEmpty ? () => Share.share(_spokenText) : null,
              icon: const Icon(Icons.share, size: 18), label: const Text('Share')),
          const Spacer(),
          TextButton.icon(onPressed: _spokenText.isNotEmpty ? _resetOutput : null,
              icon: const Icon(Icons.refresh, size: 18), label: const Text('Reset')),
        ]),
        if (_spokenText.isNotEmpty) ...[
          Row(children: [
            Expanded(child: _outBox('You said $_spokenLang:', _spokenText, Colors.blue, isDark)),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.repeat),
              onPressed: () => _speakText(_spokenText, _selectedInputLang),
              tooltip: 'Repeat',
            ),
          ]),
          const SizedBox(height: 10),
        ],
        if (_isTranslating)
          const Padding(
            padding: EdgeInsets.only(bottom: 10),
            child: LinearProgressIndicator(),
          ),
        if (_translatedText.isNotEmpty) ...[
          Row(children: [
            Expanded(child: _outBox('Translation $_translatedLang:', _translatedText, Colors.green, isDark)),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.repeat),
              onPressed: () => _speakTranslatedText(_translatedText),
              tooltip: 'Repeat',
            ),
          ]),
          if (_phoneticText.isNotEmpty) ...[
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(isDark ? 0.12 : 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.orange.withOpacity(0.4)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Phonetics (how to say it):',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold,
                          color: isDark ? Colors.orange.shade300 : Colors.orange.shade800)),
                  const SizedBox(height: 3),
                  Text(_phoneticText,
                      style: TextStyle(fontSize: 14,
                          color: isDark ? Colors.white : Colors.black87,
                          fontStyle: FontStyle.italic)),
                ],
              ),
            ),
          ],
          const SizedBox(height: 10),
        ],
        if (_spokenText.isEmpty && _translatedText.isEmpty)
          Container(
            width: double.infinity, padding: const EdgeInsets.all(20),
            margin: const EdgeInsets.only(top: 8),
            decoration: BoxDecoration(
              color: isDark ? Colors.white10 : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: isDark ? Colors.white24 : Colors.grey.shade300),
            ),
            child: Text('Hold TALK to speak, or type above to translate.',
                textAlign: TextAlign.center,
                style: TextStyle(color: isDark ? Colors.white60 : Colors.grey.shade600)),
          ),
        const SizedBox(height: 32),
        // Talk button
        Center(child: GestureDetector(
          onTapDown: (_) => _startListening(),
          onTapUp: (_) => _stopListening(),
          onTapCancel: _stopListening,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: _isTalking ? 130 : 120, height: _isTalking ? 130 : 120,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _isTalking ? Colors.red : const Color(0xFF1E3C72),
              boxShadow: [BoxShadow(
                color: (_isTalking ? Colors.red : const Color(0xFF1E3C72)).withOpacity(0.4),
                blurRadius: _isTalking ? 20 : 10, spreadRadius: _isTalking ? 4 : 2,
              )],
            ),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(_isTalking ? Icons.mic : Icons.mic_none, color: Colors.white, size: 40),
              const SizedBox(height: 4),
              Text(_isTalking ? 'LISTENING' : 'HOLD TO TALK',
                  style: const TextStyle(color: Colors.white, fontSize: 10,
                      fontWeight: FontWeight.bold, letterSpacing: 0.5)),
            ]),
          ),
        )),
        const SizedBox(height: 24),
      ]),
    );
  }

  Widget _langDrop(String value, List<String> langs, ValueChanged<String?> onChanged, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      decoration: BoxDecoration(
        border: Border.all(color: isDark ? Colors.white38 : const Color(0xFF1E3C72)),
        borderRadius: BorderRadius.circular(10),
        color: isDark ? Colors.white10 : Colors.white,
      ),
      child: DropdownButtonHideUnderline(child: DropdownButton<String>(
        isExpanded: true, value: value,
        dropdownColor: isDark ? const Color(0xFF1B263B) : Colors.white,
        style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontWeight: FontWeight.w600),
        items: langs.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
        onChanged: onChanged,
      )),
    );
  }

  Widget _outBox(String label, String text, Color color, bool isDark) {
    return Container(
      width: double.infinity, padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(isDark ? 0.12 : 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 12)),
        const SizedBox(height: 6),
        Text(text, style: TextStyle(fontSize: 16, color: isDark ? Colors.white : Colors.black87)),
      ]),
    );
  }

  Future<void> _exportHistory() async {
    if (_history.isEmpty) return;
    setState(() => _exportingHistory = true);
    try {
      final dir = await getTemporaryDirectory();
      final files = <XFile>[];

      // Build text summary file
      final buf = StringBuffer();
      buf.writeln('Limpopo Voice — Translation History');
      buf.writeln('Exported: ${DateTime.now().toString().substring(0, 16)}');
      buf.writeln();
      for (int i = 0; i < _history.length; i++) {
        final item = _history[i];
        buf.writeln('[${i + 1}] ${item.inputLang} -> ${item.outputLang}  '
            '${item.time.hour.toString().padLeft(2,"0")}:${item.time.minute.toString().padLeft(2,"0")}');
        buf.writeln('Original:    ${item.original}');
        buf.writeln('Translation: ${item.translated}');
        buf.writeln();
      }
      final txtFile = File('${dir.path}/limpopo_voice_history.txt');
      await txtFile.writeAsString(buf.toString());
      files.add(XFile(txtFile.path, mimeType: 'text/plain'));

      // Generate audio files
      for (int i = 0; i < _history.length; i++) {
        final item = _history[i];
        try {
          final inVoice = _voiceNames[item.inputLang] ?? 'Aletta';
          final inAudio = await _translationService.generateTranslation(item.original, inVoice);
          if (inAudio != null && inAudio.isNotEmpty) {
            final mp3 = File('${dir.path}/entry_${i+1}_${item.inputLang}_original.mp3');
            await mp3.writeAsBytes(inAudio);
            files.add(XFile(mp3.path, mimeType: 'audio/mpeg'));
          }
        } catch (_) {}
        try {
          final outVoice = _voiceNames[item.outputLang] ?? 'Aletta';
          final outAudio = await _translationService.generateTranslation(item.translated, outVoice);
          if (outAudio != null && outAudio.isNotEmpty) {
            final mp3 = File('${dir.path}/entry_${i+1}_${item.outputLang}_translation.mp3');
            await mp3.writeAsBytes(outAudio);
            files.add(XFile(mp3.path, mimeType: 'audio/mpeg'));
          }
        } catch (_) {}
      }

      if (files.isNotEmpty) {
        await Share.shareXFiles(files, subject: 'Limpopo Voice — Translation History');
      }
    } catch (e) {
      debugPrint('Export error: $e');
      _showSnack('Export failed');
    } finally {
      setState(() => _exportingHistory = false);
    }
  }

  Widget _buildHistoryTab(bool isDark) {
    if (_history.isEmpty) return Center(child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.history, size: 64, color: isDark ? Colors.white30 : Colors.grey.shade300),
        const SizedBox(height: 12),
        Text('No translations yet', style: TextStyle(
            color: isDark ? Colors.white38 : Colors.grey.shade500, fontSize: 16)),
      ],
    ));
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (_exportingHistory)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: Row(children: [
                    SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                    SizedBox(width: 8),
                    Text('Preparing...', style: TextStyle(fontSize: 13, color: Colors.grey)),
                  ]),
                )
              else
                TextButton.icon(
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Preparing audio & history...'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                    _exportHistory();
                  },
                  icon: const Icon(Icons.email_outlined, size: 18),
                  label: const Text('Download All'),
                  style: TextButton.styleFrom(foregroundColor: const Color(0xFF2A5298)),
                ),
              TextButton.icon(
                onPressed: () => setState(() => _history.clear()),
                icon: const Icon(Icons.delete_sweep, size: 18),
                label: const Text('Clear History'),
                style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            itemCount: _history.length,
            itemBuilder: (context, i) {
              final item = _history[i];
              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Text('${item.inputLang} -> ${item.outputLang}',
                            style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF2A5298))),
                        const Spacer(),
                        Text('${item.time.hour.toString().padLeft(2, "0")}:${item.time.minute.toString().padLeft(2, "0")}',
                            style: TextStyle(fontSize: 12, color: isDark ? Colors.white38 : Colors.grey.shade500)),
                      ]),
                      const SizedBox(height: 6),
                      Row(children: [
                        Expanded(child: Text(item.original, style: const TextStyle(fontWeight: FontWeight.w500))),
                        IconButton(
                          icon: const Icon(Icons.repeat, size: 20),
                          onPressed: () => _speakText(item.original, item.inputLang),
                          tooltip: 'Repeat',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                        ),
                      ]),
                      const SizedBox(height: 4),
                      Row(children: [
                        Expanded(child: Text(item.translated, style: TextStyle(
                            color: isDark ? Colors.white60 : Colors.grey.shade600,
                            fontStyle: FontStyle.italic))),
                        IconButton(
                          icon: const Icon(Icons.repeat, size: 20),
                          onPressed: () => _speakText(item.translated, item.outputLang),
                          tooltip: 'Repeat',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                        ),
                      ]),
                      if ((item.phonetic ?? '').isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.orange.withOpacity(isDark ? 0.12 : 0.08),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.orange.withOpacity(0.4)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Phonetics:',
                                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold,
                                      color: isDark ? Colors.orange.shade300 : Colors.orange.shade800)),
                              const SizedBox(height: 2),
                              Text(item.phonetic ?? '',
                                  style: TextStyle(fontSize: 13, fontStyle: FontStyle.italic,
                                      color: isDark ? Colors.white70 : Colors.black87)),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _speech.stop();
    _audioPlayer.release();
    _autocorrectTimer?.cancel();
    _tttController.dispose();
    super.dispose();
  }
}
