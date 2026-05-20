import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'package:payfast/payfast.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'translation_service.dart';
import 'firebase_options.dart';

// Removed duplicate _sendToLearnMultipleLangs. Only defined inside _HomeScreenState.

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform);
  } catch (e) {
    debugPrint("Firebase init error: $e");
  }

  // Always load env vars even if Firebase/App Check fails.
  try {
    await dotenv.load(fileName: ".env");
  } catch (e) {
    debugPrint("Env load error: $e");
  }
  runApp(const LimpopoVoiceApp());
}

class LimpopoVoiceApp extends StatefulWidget {
  const LimpopoVoiceApp({super.key});
  @override
  State<LimpopoVoiceApp> createState() => _LimpopoVoiceAppState();
}

class _LimpopoVoiceAppState extends State<LimpopoVoiceApp> {
  ThemeMode _themeMode = ThemeMode.dark;
  void _toggleTheme() => setState(() => _themeMode =
      _themeMode == ThemeMode.light ? ThemeMode.dark : ThemeMode.light);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Let\'s Talk',
      debugShowCheckedModeBanner: false,
      themeMode: _themeMode,
      theme: ThemeData(
        brightness: Brightness.light,
        fontFamily: 'monospace',
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF000000),
          primary: const Color(0xFF000000),
          secondary: const Color(0xFF000000),
          brightness: Brightness.light,
          background: const Color(0xFFFFFFFF),
          surface: const Color(0xFFFFFFFF),
        ),
        scaffoldBackgroundColor: const Color(0xFFFFFFFF),
        canvasColor: const Color(0xFFFFFFFF),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        fontFamily: 'monospace',
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF000000),
          primary: const Color(0xFF000000),
          secondary: const Color(0xFF000000),
          brightness: Brightness.dark,
          background: const Color(0xFF000000),
          surface: const Color(0xFF000000),
        ),
        scaffoldBackgroundColor: const Color(0xFF000000),
        canvasColor: const Color(0xFF000000),
        useMaterial3: true,
      ),
      builder: (context, child) {
        final media = MediaQuery.of(context);
        return MediaQuery(
          data: media.copyWith(textScaler: const TextScaler.linear(1.0)),
          child: DefaultTextStyle.merge(
            style: const TextStyle(
              fontFamily: 'monospace',
              fontWeight: FontWeight.w900,
              fontSize: 18,
              shadows: [
                Shadow(
                  color: Color(0x66000000),
                  blurRadius: 0,
                  offset: Offset(1.5, 0),
                ),
                Shadow(
                  color: Color(0x66000000),
                  blurRadius: 0,
                  offset: Offset(-1.5, 0),
                ),
                Shadow(
                  color: Color(0x66000000),
                  blurRadius: 0,
                  offset: Offset(0, 1.5),
                ),
                Shadow(
                  color: Color(0x4D000000),
                  blurRadius: 0,
                  offset: Offset(0, -1),
                ),
                Shadow(
                  color: Color(0x55000000),
                  blurRadius: 0,
                  offset: Offset(1, 1),
                ),
                Shadow(
                  color: Color(0x55000000),
                  blurRadius: 0,
                  offset: Offset(-1, 1),
                ),
                Shadow(
                  color: Color(0x66000000),
                  blurRadius: 2,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: child ?? const SizedBox.shrink(),
          ),
        );
      },
      home: HomeScreen(onToggleTheme: _toggleTheme),
    );
  }
}

class _CreditTier {
  final String name;
  final int secs;
  final String price;
  const _CreditTier(this.name, this.secs, this.price);
}

const _tiers = [
  _CreditTier('Micro', 30, 'R9.99'),
  _CreditTier('Basic', 180, 'R49.99'),
  _CreditTier('Pro', 600, 'R169.99'),
  _CreditTier('Enterprise', 1500, 'R419.99')
];
const int _usageCostSecs = 5;
const bool _enableClientFirestoreCache = false;
const String _payFastMerchantId = '10004002';
const String _payFastMerchantKey = 'q1cd2rdny4a53';
const String _payFastPassPhrase = 'payfast';
const String _payFastSandboxScriptUrl =
  'https://youngcet.github.io/sandbox_payfast_onsite_payments/';

class HistoryItem {
  final String inputLang, outputLang, original, translated;
  final String? phonetic;
  final DateTime time;
  HistoryItem(this.inputLang, this.outputLang, this.original, this.translated,
      this.time,
      {this.phonetic});
}

class HomeScreen extends StatefulWidget {
  final VoidCallback onToggleTheme;
  const HomeScreen({super.key, required this.onToggleTheme});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
          final FocusNode _inputFocusNode = FocusNode();
        // Track selection state for history items
        final Set<int> _selectedHistoryIndexes = {};
        final bool _showClearAll = false;
      // --- Helper for deleting user phrase in Learn tab ---
      Future<void> _deleteUserPhrase(int idx) async {
        final sure = await _confirmDeleteLearnPhrase();
        if (sure) {
          setState(() {
            final lang = _selectedLearnLang;
            final list = _userLearnPhrasesByLang[lang];
            if (list != null && idx < list.length) {
              list.removeAt(idx);
              _userLearnPhrasesByLang[lang] = List.from(list);
            }
          });
        }
      }

      Future<bool> _confirmDeleteLearnPhrase() async {
        final result = await showDialog<bool>(
          context: context,
          builder: (ctx) {
            final isDark = Theme.of(ctx).brightness == Brightness.dark;
            return AlertDialog(
              title: const Text('Are you sure?'),
              content: const Text('Delete this phrase from Learn?'),
              backgroundColor: isDark ? const Color(0xFF000000) : const Color(0xFFFFFFFF),
              surfaceTintColor: isDark ? const Color(0xFF000000) : const Color(0xFFFFFFFF),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: Text('Cancel', style: TextStyle(color: isDark ? Colors.white : Color(0xFF000000))),
                ),
                TextButton(
                  style: TextButton.styleFrom(
                    backgroundColor: const Color(0xFF000000),
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: const Text('Clear', style: TextStyle(color: Colors.white)),
                ),
              ],
            );
          },
        );
        return result == true;
      }
    // User-added phrases for Learn tab (mutable)
    final Map<String, List<Map<String, String>>> _userLearnPhrasesByLang = {};

    void _sendToLearnMultipleLangs({
      required String translated,
      required String original,
      required String phonetic,
      required List<String> langs,
    }) {
      setState(() {
        for (final lang in langs) {
          final key = lang;
          final phraseList = (_userLearnPhrasesByLang[key] ?? []).toList();
          phraseList.insert(0, {
            'text': translated,
            'en': original,
            if (phonetic.isNotEmpty) 'phonetic': phonetic,
          });
          while (phraseList.length > 5) {
            phraseList.removeLast();
          }
          _userLearnPhrasesByLang[key] = phraseList;
          _learnFocusTextByLang[lang] = translated;
          _learnFocusMeaningByLang[lang] = original;
          _learnFocusPhoneticByLang[lang] = phonetic.isEmpty ? null : phonetic;
        }
        if (langs.isNotEmpty) {
          _selectedLearnLang = langs.first;
          _activeTab = 'learn';
        }
      });
      _showSnack('Sentence sent to selected languages (max 5 per language)');
    }
  static const List<String> _offensiveWords = [
    // English profanity/slurs/blasphemy
    'fuck',
    'fucking',
    'fucker',
    'shit',
    'bullshit',
    'shitty',
    'bitch',
    'bitches',
    'biatch',
    'bastard',
    'asshole',
    'ass',
    'arse',
    'arsehole',
    'damn',
    'goddamn',
    'hell',
    'bloody',
    'crap',
    'dick',
    'dildo',
    'wanker',
    'jerkoff',
    'cunt',
    'piss',
    'pissed',
    'cock',
    'penis',
    'vagina',
    'motherfucker',
    'mf',
    'nigger',
    'nigga',
    'slut',
    'whore',
    'hoe',
    'idiot',
    'moron',
    'stupid',
    'retard',
    // SA/Afrikaans slang profanity
    'kak',
    'k@k',
    'poes',
    'p0es',
    'naai',
    'naaier',
    'bliksem',
    'fok',
    'fokken',
    'domkop',
    // Mild blasphemy variants
    'jesus christ',
    'god damn',
  ];

  static const int _firstSpeechChunkMaxChars = 42;
  static const int _speechChunkMaxChars = 90;
  static const Duration _firstChunkFetchTimeout = Duration(seconds: 55);
  static const Duration _nextChunkFetchTimeout = Duration(seconds: 55);

  static final RegExp _offensiveWordRegex = RegExp(
    '\\b(${_offensiveWords.map(RegExp.escape).join('|')})\\b',
    caseSensitive: false,
  );

  static final RegExp _maskedProfanityRegex = RegExp(
    r'([a-zA-Z]\*{2,}|@[*$]+)',
    caseSensitive: false,
  );

  static final List<RegExp> _offensiveFlexibleRegexes = _offensiveWords
      .map(_buildFlexibleOffensiveRegex)
      .toList(growable: false);

  static RegExp _buildFlexibleOffensiveRegex(String word) {
    final compact = word.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    if (compact.isEmpty) {
      return RegExp(r'$.');
    }

    final chars = compact.split('').map(RegExp.escape).join(r'[\W_]*');
    return RegExp(
      '(?<![A-Za-z0-9])$chars(?![A-Za-z0-9])',
      caseSensitive: false,
    );
  }

  static const String _disclaimerText =
    "'Let's Talk' uses advanced AI to provide translations. However, automated translation is not perfect. 'Let's Talk' is not responsible for any inaccurate, misleading, or offensive translations generated by the system. By using this app, you agree to use these translations at your own risk.";

  Future<void> _showDisclaimerInfo() async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Disclaimer'),
        content: const SingleChildScrollView(
          child: Text(_disclaimerText),
        ),
        actions: [
          TextButton(
            style: TextButton.styleFrom(
              backgroundColor: const Color(0xFF000000),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  String _activeTab = 'translate';
  Future<void>? _startupInitFuture;
  final stt.SpeechToText _speech = stt.SpeechToText();
  late final TranslationService _translationService;
  late final AudioPlayer _audioPlayer;
  bool _speechAvailable = false;
  bool _isTalking = false;
  bool _isTranslating = false;
  bool _isPlayingAudio = false;
  String _selectedInputLang = 'English';
  String _selectedOutputLang = 'Sepedi';
  // Full South African language set
  final _inputLangs = [
    'English',
    'Afrikaans',
    'isiNdebele',
    'isiXhosa',
    'isiZulu',
    'Sepedi',
    'Sesotho',
    'Setswana',
    'siSwati',
    'Tshivenda',
    'Xitsonga',
  ];
  // Full South African language set
  final _outputLangs = [
    'isiNdebele',
    'isiXhosa',
    'isiZulu',
    'Sepedi',
    'Sesotho',
    'Setswana',
    'siSwati',
    'Tshivenda',
    'Xitsonga',
    'English',
    'Afrikaans',
  ];
  final _locales = {
    'Afrikaans': 'af-ZA',
    'English': 'en-ZA',
    'isiNdebele': 'nr-ZA',
    'isiXhosa': 'xh-ZA',
    'isiZulu': 'zu-ZA',
    'Sepedi': 'nso-ZA',
    'Sesotho': 'st-ZA',
    'Setswana': 'tn-ZA',
    'siSwati': 'ss-ZA',
    'Tshivenda': 've-ZA',
    'Xitsonga': 'ts-ZA',
  };
  final _translateCodes = {
    'Afrikaans': 'af',
    'English': 'en',
    'isiNdebele': 'nr',
    'isiXhosa': 'xh',
    'isiZulu': 'zu',
    'Sepedi': 'nso',
    'Sesotho': 'st',
    'Setswana': 'tn',
    'siSwati': 'ss',
    'Tshivenda': 've',
    'Xitsonga': 'ts',
  };
  static const _voiceNames = {
    'Afrikaans': 'Rolanda',
    'English': 'Aletta',
    'isiNdebele': 'Dumisani',
    'isiXhosa': 'Lindiwe',
    'isiZulu': 'Nandi',
    'Sepedi': 'Mpho',
    'Sesotho': 'Palesa',
    'Setswana': 'Basetsana',
    'siSwati': 'Nomcebo',
    'Tshivenda': 'Mulalo',
    'Xitsonga': 'Basetsana',
  };
  static const Set<String> _southAfricanLanguages = {
    'Afrikaans',
    'English',
    'isiNdebele',
    'isiXhosa',
    'isiZulu',
    'Sepedi',
    'Sesotho',
    'Setswana',
    'siSwati',
    'Tshivenda',
    'Xitsonga',
  };
  String _spokenText = '';
  String _translatedText = '';
  String _spokenRawText = '';
  String _translatedRawText = '';
  String _phoneticText = '';
  String _spokenLang = '';
  String _translatedLang = '';
  final TextEditingController _tttController = TextEditingController();
  int _credits = 30;
  final List<HistoryItem> _history = [];
  String _selectedLearnLang = 'Sepedi';
  final Map<String, String> _learnFocusTextByLang = {};
  final Map<String, String> _learnFocusMeaningByLang = {};
  final Map<String, String?> _learnFocusPhoneticByLang = {};
  bool _exportingHistory = false;
  bool _sharingCurrentTranslation = false;
  Timer? _autocorrectTimer;

  static const Map<String, List<Map<String, String>>> _learnPhrasesByLang = {
    'English': [
      {'text': 'Hello, how are you?', 'en': 'Hello, how are you?'},
      {'text': 'Thank you very much.', 'en': 'Thank you very much.'},
      {'text': 'Please help me.', 'en': 'Please help me.'},
      {'text': 'Goodbye, see you later.', 'en': 'Goodbye, see you later.'},
    ],
    'Sepedi': [
      {'text': 'Dumela, o phela bjang?', 'en': 'Hello, how are you?'},
      {'text': 'Ke a leboga kudu.', 'en': 'Thank you very much.'},
      {'text': 'Hle, nthuše.', 'en': 'Please help me.'},
      {'text': 'Sala gabotse.', 'en': 'Goodbye.'},
    ],
    'Xitsonga': [
      {'text': 'Avuxeni, u njhani?', 'en': 'Hello, how are you?'},
      {'text': 'Ndza nkhensa swinene.', 'en': 'Thank you very much.'},
      {'text': 'Ndzi kombela mpfuno.', 'en': 'Please help me.'},
      {'text': 'Endla kahle.', 'en': 'Goodbye.'},
    ],
    'Tshivenda': [
      {'text': 'Ndaa, ni hone?', 'en': 'Hello, how are you?'},
      {'text': 'Ndo livhuwa vhukuma.', 'en': 'Thank you very much.'},
      {'text': 'Ndi humbela thuso.', 'en': 'Please help me.'},
      {'text': 'Salani zwavhudi.', 'en': 'Goodbye.'},
    ],
    'Setswana': [
      {'text': 'Dumela, o tsogile jang?', 'en': 'Hello, how are you?'},
      {'text': 'Ke a go leboga thata.', 'en': 'Thank you very much.'},
      {'text': 'Tsweetswee nthuse.', 'en': 'Please help me.'},
      {'text': 'Tsamaya sentle.', 'en': 'Goodbye.'},
    ],
    'isiXhosa': [
      {'text': 'Molo, unjani?', 'en': 'Hello, how are you?'},
      {'text': 'Enkosi kakhulu.', 'en': 'Thank you very much.'},
      {'text': 'Nceda undincede.', 'en': 'Please help me.'},
      {'text': 'Hamba kakuhle.', 'en': 'Goodbye.'},
    ],
    'isiZulu': [
      {'text': 'Sawubona, unjani?', 'en': 'Hello, how are you?'},
      {'text': 'Ngiyabonga kakhulu.', 'en': 'Thank you very much.'},
      {'text': 'Ngicela ungisize.', 'en': 'Please help me.'},
      {'text': 'Hamba kahle.', 'en': 'Goodbye.'},
    ],
    'siSwati': [
      {'text': 'Sawubona, wentani?', 'en': 'Hello, how are you?'},
      {'text': 'Ngiyabonga kakhulu.', 'en': 'Thank you very much.'},
      {'text': 'Ngicela ungisize.', 'en': 'Please help me.'},
      {'text': 'Sala kahle.', 'en': 'Goodbye.'},
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
    'Dutch': [
      {'text': 'Hallo, hoe gaat het?', 'en': 'Hello, how are you?'},
      {'text': 'Heel erg bedankt.', 'en': 'Thank you very much.'},
      {'text': 'Help me alsjeblieft.', 'en': 'Please help me.'},
      {'text': 'Tot ziens.', 'en': 'Goodbye.'},
    ],
    'Portuguese': [
      {'text': 'Ola, como esta?', 'en': 'Hello, how are you?'},
      {'text': 'Muito obrigado.', 'en': 'Thank you very much.'},
      {'text': 'Por favor, ajude-me.', 'en': 'Please help me.'},
      {'text': 'Ate logo.', 'en': 'Goodbye.'},
    ],
    'Mandarin': [
      {
        'text': '你好，你怎么样？',
        'en': 'Hello, how are you?',
        'phonetic': 'Nǐ hǎo, nǐ zěnme yàng?'
      },
      {
        'text': '非常感谢。',
        'en': 'Thank you very much.',
        'phonetic': 'Fēicháng gǎnxiè.'
      },
      {
        'text': '请帮帮我。',
        'en': 'Please help me.',
        'phonetic': 'Qǐng bāng bāng wǒ.'
      },
      {'text': '再见。', 'en': 'Goodbye.', 'phonetic': 'Zàijiàn.'},
    ],
    'Hindi': [
      {
        'text': 'नमस्ते, आप कैसे हैं?',
        'en': 'Hello, how are you?',
        'phonetic': 'Namaste, aap kaise hain?'
      },
      {
        'text': 'बहुत धन्यवाद।',
        'en': 'Thank you very much.',
        'phonetic': 'Bahut dhanyavaad.'
      },
      {
        'text': 'कृपया मेरी मदद कीजिए।',
        'en': 'Please help me.',
        'phonetic': 'Kripya meri madad kijiye.'
      },
      {'text': 'अलविदा।', 'en': 'Goodbye.', 'phonetic': 'Alvida.'},
    ],
    'Urdu': [
      {
        'text': 'السلام علیکم، آپ کیسے ہیں؟',
        'en': 'Hello, how are you?',
        'phonetic': 'As-salaam-alaikum, aap kaise hain?'
      },
      {
        'text': 'بہت شکریہ۔',
        'en': 'Thank you very much.',
        'phonetic': 'Bohat shukriya.'
      },
      {
        'text': 'مہربانی کرکے میری مدد کریں۔',
        'en': 'Please help me.',
        'phonetic': 'Meherbani karke meri madad karein.'
      },
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

  String _normalizeLanguageLabel(String language) {
    final cleaned = language
        .replaceAll('(', '')
        .replaceAll(')', '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (cleaned == 'English South African Accent') return 'English';
    if (cleaned == 'Sepedi Northern Sotho') return 'Sepedi';
    if (cleaned == 'Sesotho Southern Sotho') return 'Sesotho';
    return cleaned;
  }

  String _ttsProviderForLanguage(String language) {
    final normalized = _normalizeLanguageLabel(language);
    return _southAfricanLanguages.contains(normalized) ? 'narakeet' : 'google';
  }

  String? _voiceNameForLanguage(String language) {
    final normalized = _normalizeLanguageLabel(language);
    final provider = _ttsProviderForLanguage(normalized);
    if (provider == 'narakeet') {
      return _voiceNames[normalized] ?? 'Aletta';
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _selectedInputLang = _normalizeLanguageLabel(_selectedInputLang);
    _selectedOutputLang = _normalizeLanguageLabel(_selectedOutputLang);
    _selectedLearnLang = _normalizeLanguageLabel(_selectedLearnLang);
    if (!_inputLangs.contains(_selectedInputLang)) {
      _selectedInputLang = _inputLangs.first;
    }
    if (!_outputLangs.contains(_selectedOutputLang)) {
      _selectedOutputLang = _outputLangs.first;
    }
    if (!_outputLangs.contains(_selectedLearnLang)) {
      _selectedLearnLang = _outputLangs.first;
    }
    _audioPlayer = AudioPlayer();
    final functionUrl = dotenv.env['TRANSLATE_FUNCTION_URL'] ?? '';
    _translationService = TranslationService(functionUrl: functionUrl);
    _translationService.primeSession();
    _configureAudioPlayback();
    _initSpeech();
    _tttController.addListener(_onInputChanged);
    _startupInitFuture = _checkInstallIdAndFreeTrial();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showDisclaimerIfFirstInstall();
    });
  }

  String _generateUUID() {
    const chars = 'abcdef0123456789';
    final random = Random();
    return List.generate(32, (_) => chars[random.nextInt(chars.length)]).join();
  }

  Future<void> _checkInstallIdAndFreeTrial() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      const installIdKey = 'limpopo_install_id_v1';
      
      String? installId = prefs.getString(installIdKey);
      if (installId == null) {
        installId = _generateUUID();
        await prefs.setString(installIdKey, installId);
        debugPrint('Generated new install ID: $installId');
      } else {
        debugPrint('Retrieved existing install ID: $installId');
      }

      // Check Firebase if this device has already used free trial
      final db = FirebaseFirestore.instance;
      final docRef = db.collection('device_installs').doc(installId);
      final docSnapshot = await docRef.get();
      
      if (docSnapshot.exists && docSnapshot.data()?['used_free_trial'] == true) {
        debugPrint('Install ID $installId already used free trial');
      } else {
        // First time - mark for future reinstalls
        await docRef.set({
          'used_free_trial': true,
          'first_seen': FieldValue.serverTimestamp(),
          'last_seen': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true)).catchError((e) {
          debugPrint('Failed to record device install: $e');
        });
        debugPrint('Install ID $installId registered for first free trial use');
      }
    } catch (e) {
      debugPrint('Error checking install ID: $e');
      // On error, allow free trial to proceed (don't block user)
    }
  }

  String _getCacheKey(String text, String language, String voice) {
    final normalized = text.toLowerCase().trim();
    return '${normalized}_${language}_$voice';
  }

  bool _isFirestorePermissionDenied(Object error) {
    final msg = error.toString().toLowerCase();
    return msg.contains('permission-denied') ||
        msg.contains('missing or insufficient permissions');
  }

  Future<String?> _getCachedTranslation(String text, String language) async {
    if (!_enableClientFirestoreCache) return null;
    try {
      final db = FirebaseFirestore.instance;
      final cacheKey = _getCacheKey(text, language, '');
      final docSnapshot = await db
          .collection('cache_translations')
          .doc(cacheKey)
          .get();
      
      if (docSnapshot.exists) {
        final translation = docSnapshot.data()?['translation'] as String?;
        debugPrint('Cache HIT for translation: "$text" -> "$translation"');
        return translation;
      }
      return null;
    } catch (e) {
      if (!_isFirestorePermissionDenied(e)) {
        debugPrint('Error fetching cached translation: $e');
      }
      return null;
    }
  }

  Future<void> _saveCacheTranslation(String text, String language, String translation) async {
    if (!_enableClientFirestoreCache) return;
    try {
      final db = FirebaseFirestore.instance;
      final cacheKey = _getCacheKey(text, language, '');
      await db.collection('cache_translations').doc(cacheKey).set({
        'original_text': text,
        'language': language,
        'translation': translation,
        'cached_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true)).catchError((e) {
        if (!_isFirestorePermissionDenied(e)) {
          debugPrint('Failed to cache translation: $e');
        }
      });
    } catch (e) {
      if (!_isFirestorePermissionDenied(e)) {
        debugPrint('Error saving cached translation: $e');
      }
    }
  }

  Future<String?> _getCachedAudio(String text, String language, String voice) async {
    if (!_enableClientFirestoreCache) return null;
    try {
      final db = FirebaseFirestore.instance;
      final cacheKey = _getCacheKey(text, language, voice);
      final docSnapshot = await db
          .collection('cache_audio')
          .doc(cacheKey)
          .get();
      
      if (docSnapshot.exists) {
        final audioBase64 = docSnapshot.data()?['audio_base64'] as String?;
        if (audioBase64 != null && audioBase64.isNotEmpty) {
          debugPrint('Cache HIT for audio: "$text" (language=$language, voice=$voice)');
          return audioBase64;
        }
      }
      return null;
    } catch (e) {
      if (!_isFirestorePermissionDenied(e)) {
        debugPrint('Error fetching cached audio: $e');
      }
      return null;
    }
  }

  Future<void> _saveCacheAudio(String text, String language, String voice, String audioBase64) async {
    if (!_enableClientFirestoreCache) return;
    try {
      final db = FirebaseFirestore.instance;
      final cacheKey = _getCacheKey(text, language, voice);
      await db.collection('cache_audio').doc(cacheKey).set({
        'original_text': text,
        'language': language,
        'voice': voice,
        'audio_base64': audioBase64,
        'cached_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true)).catchError((e) {
        if (!_isFirestorePermissionDenied(e)) {
          debugPrint('Failed to cache audio: $e');
        }
      });
    } catch (e) {
      if (!_isFirestorePermissionDenied(e)) {
        debugPrint('Error saving cached audio: $e');
      }
    }
  }

  Future<void> _configureAudioPlayback() async {
    try {
      await _audioPlayer.setAudioContext(
        AudioContext(
          android: const AudioContextAndroid(
            isSpeakerphoneOn: true,
            stayAwake: false,
            contentType: AndroidContentType.speech,
            usageType: AndroidUsageType.media,
            audioFocus: AndroidAudioFocus.gain,
          ),
        ),
      );
    } catch (e) {
      debugPrint('Audio context setup failed: $e');
    }

    try {
      await _audioPlayer.setReleaseMode(ReleaseMode.stop);
      await _audioPlayer.setVolume(1.0);
    } catch (e) {
      debugPrint('Audio release mode setup failed: $e');
    }

  }

  Future<void> _showDisclaimerIfFirstInstall() async {
    final prefs = await SharedPreferences.getInstance();
    const key = 'disclaimerAcceptedV5';
    final accepted = prefs.getBool(key) ?? false;
    if (accepted || !mounted) return;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFFFFFFFF),
        surfaceTintColor: const Color(0xFFFFFFFF),
        title: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final wordmarkWidth = (constraints.maxWidth * 0.9).clamp(220.0, 320.0);
                return Center(
                  child: SizedBox(
                    width: wordmarkWidth,
                    child: _buildHeaderWordmark(true),
                  ),
                );
              },
            ),
            const SizedBox(height: 8),
            const Text(
              'Disclaimer',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFF000000)),
            ),
          ],
        ),
        content: const SingleChildScrollView(
          child: Text(
            _disclaimerText,
            style: TextStyle(color: Color(0xFF000000)),
          ),
        ),
        actionsAlignment: MainAxisAlignment.end,
        actions: [
          Builder(
            builder: (ctx2) {
              return TextButton(
                style: TextButton.styleFrom(
                  backgroundColor: Colors.black,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                ),
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Accept and Close', style: TextStyle(color: Colors.white)),
              );
            },
          ),
        ],
      ),
    );
  }

  Future<void> _showFirstInstallIntroSplash() async {
    if (!mounted) return;

    bool introVisible = false;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        introVisible = true;
        return AlertDialog(
          backgroundColor: const Color(0xFF000000),
          surfaceTintColor: const Color(0xFF000000),
          content: LayoutBuilder(
            builder: (context, constraints) {
              final wordmarkWidth = (constraints.maxWidth * 0.95).clamp(260.0, 360.0);
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: wordmarkWidth,
                    child: _buildHeaderWordmark(true),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Preparing LetsTalk...',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );

    // Let the intro render, then keep it until startup initialization is done.
    await Future<void>.delayed(const Duration(milliseconds: 1));
    try {
      await (_startupInitFuture ?? Future<void>.value());
    } catch (_) {
      // Keep flow resilient if startup telemetry/checks fail.
    }

    if (mounted && introVisible && Navigator.of(context, rootNavigator: true).canPop()) {
      Navigator.of(context, rootNavigator: true).pop();
    }
  }

  void _onInputChanged() {
    _autocorrectTimer?.cancel();
    if (_tttController.text.trim().length < 4) return;
    _autocorrectTimer =
        Timer(const Duration(milliseconds: 700), _runAutocorrect);
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
      if (corrected is! String || corrected.isEmpty || corrected == text) {
        return;
      }
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
    if (!_speechAvailable) {
      _showSnack('Microphone not available');
      return;
    }
    setState(() {
      _isTalking = true;
      _spokenText = '';
      _translatedText = '';
      _phoneticText = '';
      _spokenLang = '';
      _translatedLang = '';
    });
    await _speech.listen(
      onResult: (r) {
        setState(() {
          _spokenRawText = r.recognizedWords;
          _spokenText = _maskProfanityForDisplay(_spokenRawText);
          _spokenLang = _selectedInputLang;
        });
        if (r.finalResult && _spokenRawText.isNotEmpty) {
          _doTranslate(_spokenRawText);
        }
      },
      localeId: _locales[_selectedInputLang] ?? 'en-ZA',
      // Keep capture active while user is holding the Talk button.
      listenFor: const Duration(seconds: 60),
      pauseFor: const Duration(seconds: 20),
    );
  }

  void _stopListening() async {
    await _speech.stop();
    setState(() => _isTalking = false);
  }

  bool _consumeUsageAllowance() {
    if (_credits >= _usageCostSecs) {
      setState(() => _credits -= _usageCostSecs);
      _showSnack('Used $_usageCostSecs sec | Balance: $_credits sec remaining');
      return true;
    }
    _showCreditTiers();
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
      _translatedRawText = result;
      _translatedText = _maskProfanityForDisplay(result);
      _translatedLang = _selectedOutputLang;
      _isTranslating = false;
      // _phoneticText is set as a side-effect inside _translateText; include it here so the UI rebuilds with it
    });

    _history.insert(
        0,
        HistoryItem(
            _selectedInputLang,
            _selectedOutputLang,
            _maskProfanityForDisplay(input),
            _maskProfanityForDisplay(result),
            DateTime.now(),
            phonetic: _phoneticText));
    await _speakTranslatedText(result);
  }

  String _maskProfanityForDisplay(String text) {
    if (text.trim().isEmpty) return text;
    String masked = text.replaceAllMapped(_offensiveWordRegex, (_) => '@#\$');
    masked = masked.replaceAllMapped(_maskedProfanityRegex, (_) => '@#\$');
    for (final pattern in _offensiveFlexibleRegexes) {
      masked = masked.replaceAllMapped(pattern, (_) => '@#\$');
    }
    return masked;
  }

  String _silenceProfanityForSpeech(String text) {
    if (text.trim().isEmpty) return text;
    String silenced = text.replaceAllMapped(_offensiveWordRegex, (_) => '');
    silenced = silenced.replaceAllMapped(_maskedProfanityRegex, (_) => '');
    for (final pattern in _offensiveFlexibleRegexes) {
      silenced = silenced.replaceAllMapped(pattern, (_) => '');
    }
    return silenced.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  bool _containsProfanity(String text) {
    if (text.trim().isEmpty) return false;
    if (_offensiveWordRegex.hasMatch(text)) return true;
    if (_maskedProfanityRegex.hasMatch(text)) return true;
    return _offensiveFlexibleRegexes.any((pattern) => pattern.hasMatch(text));
  }

  Future<String> _translateText(String input) async {
    final source = _translateCodes[_selectedInputLang] ?? 'auto';
    final target = _translateCodes[_selectedOutputLang] ?? 'en';
    final needsPhonetics = _selectedOutputLang == 'Hindi' ||
        _selectedOutputLang == 'Urdu' ||
        _selectedOutputLang == 'Mandarin';

    // Check cache first
    final cached = await _getCachedTranslation(input, _selectedOutputLang);
    if (cached != null && cached.isNotEmpty) {
      _phoneticText = '';
      return cached;
    }

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
            .map(
                (segment) => segment.isNotEmpty ? segment.first.toString() : '')
            .join();

        if (needsPhonetics) {
          // dt=rm: romanization of each translated segment is at index [2] of each piece
          final phonetic = pieces
              .whereType<List>()
              .map((s) =>
                  s.length > 2 && s[2] != null ? s[2].toString().trim() : '')
              .where((s) => s.isNotEmpty)
              .join(' ')
              .trim();
          // Fallback: check top-level decoded[1] (some API variants put it there)
          final fallback =
              (phonetic.isEmpty && decoded.length > 1 && decoded[1] is String)
                  ? (decoded[1] as String).trim()
                  : '';
          _phoneticText = phonetic.isNotEmpty ? phonetic : fallback;
          debugPrint('Phonetics found: "$_phoneticText"');
        } else {
          _phoneticText = '';
        }

        final result = translated.trim().isEmpty ? input : translated.trim();
        await _saveCacheTranslation(input, _selectedOutputLang, result);
        return result;
      }
      _phoneticText = '';
      return input;
    } catch (_) {
      _phoneticText = '';
      return input;
    }
  }

  Future<void> _speakText(String text, String language) async {
    if (_containsProfanity(text)) {
      return;
    }

    final safeForSpeech = _silenceProfanityForSpeech(text);
    if (safeForSpeech.trim().isEmpty) return;
    try {
      final provider = _ttsProviderForLanguage(language);
      final voiceName = _voiceNameForLanguage(language);
      debugPrint('Requesting audio: text="$safeForSpeech", language=$language, provider=$provider, voice=${voiceName ?? 'auto'}');
      final audioData = await _generateAudioWithCache(
        safeForSpeech,
        language,
        voiceName,
        provider: provider,
      );
      if (audioData != null && audioData.isNotEmpty) {
        debugPrint('Audio received: ${audioData.length} bytes, playing...');
        await _audioPlayer.play(BytesSource(audioData));
      } else {
        debugPrint('Narakeet returned no audio data (null or empty)');
        _showSnack(_narakeetUnavailableMessage());
      }
    } catch (e) {
      debugPrint('Audio playback error: $e');
      _showSnack('Audio error: $e');
    }
  }

  Future<Uint8List?> _generateAudioWithCache(
      String text, String language, String? voice,
      {required String provider}) async {
    final cacheVoiceKey = '$provider|${voice ?? ''}';
    // Check cache first
    final cachedBase64 = await _getCachedAudio(text, language, cacheVoiceKey);
    if (cachedBase64 != null) {
      return base64Decode(cachedBase64);
    }

    // Not in cache, generate new audio
    final audioData = await _translationService.generateTranslation(
      text,
      language,
      voiceName: voice,
      ttsProvider: provider,
    );

    // Save to cache if successful
    if (audioData != null && audioData.isNotEmpty) {
      final audioBase64 = base64Encode(audioData);
      await _saveCacheAudio(text, language, cacheVoiceKey, audioBase64);
    }

    return audioData;
  }

  Future<void> _speakTranslatedText(String text) async {
    if (_containsProfanity(text)) {
      return;
    }

    final safeForSpeech = _silenceProfanityForSpeech(text);
    if (safeForSpeech.trim().isEmpty) {
      return;
    }

    try {
      setState(() => _isPlayingAudio = true);

      final provider = _ttsProviderForLanguage(_selectedOutputLang);
      final voiceName = _voiceNameForLanguage(_selectedOutputLang);
      final chunks = _buildRealtimeSpeechChunks(safeForSpeech);
      if (chunks.isEmpty) {
        debugPrint('No audio data returned from API');
        _showSnack(_narakeetUnavailableMessage());
        return;
      }

      debugPrint(
          'Requesting chunked audio (${chunks.length} chunks) for language: $_selectedOutputLang, provider: $provider, voice: ${voiceName ?? 'auto'}');
      for (int i = 0; i < chunks.length; i++) {
        debugPrint('  Chunk ${i + 1}: "${chunks[i]}"');
      }

      // Kick off all chunk requests immediately so later chunks are ready sooner.
      final chunkRequests = chunks
          .map((chunk) {
            debugPrint('Calling Narakeet for chunk: "$chunk"');
            return _generateAudioWithCache(
              chunk,
              _selectedOutputLang,
              voiceName,
              provider: provider,
            );
          })
          .toList(growable: false);

      bool playedAny = false;
      await _audioPlayer.stop();

      for (int i = 0; i < chunkRequests.length; i++) {
        final audioData = await chunkRequests[i].timeout(
          i == 0 ? _firstChunkFetchTimeout : _nextChunkFetchTimeout,
          onTimeout: () {
            debugPrint('Chunk ${i + 1} request timed out');
            return null;
          },
        );
        if (audioData == null || audioData.isEmpty) {
          debugPrint(
              'Chunk ${i + 1}/${chunkRequests.length} returned no audio (null/empty)');
          continue;
        }

        debugPrint(
            'Chunk ${i + 1}/${chunkRequests.length} audio size: ${audioData.length} bytes');
        await _audioPlayer.play(BytesSource(audioData));
        playedAny = true;

        // Wait for completion before the next chunk to preserve natural flow.
        try {
          await _audioPlayer.onPlayerComplete.first
              .timeout(const Duration(seconds: 45));
        } catch (_) {
          // Continue even if completion signal times out.
        }
      }

      if (!playedAny) {
        debugPrint('ERROR: No chunks were successfully converted to audio. Check Narakeet API key and network.');
        _showSnack(_narakeetUnavailableMessage());
      }
    } catch (e) {
      debugPrint('Audio playback error: $e');
      _showSnack('Narakeet audio error. Please try again.');
    } finally {
      setState(() => _isPlayingAudio = false);
    }
  }

  List<String> _buildRealtimeSpeechChunks(String text) {
    final normalized = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.isEmpty) return const [];

    // Split on sentence punctuation first, then keep each chunk short.
    final sentences = normalized
        .split(RegExp(r'(?<=[.!?])\s+'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    final chunks = <String>[];
    var maxChars = _firstSpeechChunkMaxChars;

    for (final sentence in sentences) {
      if (sentence.length <= maxChars) {
        chunks.add(sentence);
        maxChars = _speechChunkMaxChars;
        continue;
      }

      // For long sentences, split by words without breaking words.
      final words = sentence.split(' ');
      var buffer = StringBuffer();

      for (final word in words) {
        final candidate = buffer.isEmpty ? word : '${buffer.toString()} $word';
        if (candidate.length > maxChars && buffer.isNotEmpty) {
          chunks.add(buffer.toString());
          maxChars = _speechChunkMaxChars;
          buffer = StringBuffer(word);
        } else {
          buffer = StringBuffer(candidate);
        }
      }

      if (buffer.isNotEmpty) {
        chunks.add(buffer.toString());
        maxChars = _speechChunkMaxChars;
      }
    }

    return chunks;
  }

  void _submitTTT() {
    final t = _tttController.text.trim();
    if (t.isEmpty) return;
    setState(() {
      _spokenRawText = t;
      _spokenText = _maskProfanityForDisplay(t);
      _spokenLang = _selectedInputLang;
      _translatedRawText = '';
      _translatedText = '';
      _phoneticText = '';
      _translatedLang = '';
    });
    _doTranslate(t);
    _tttController.clear();
    FocusScope.of(context).unfocus();
  }

  void _resetOutput() => setState(() {
        _spokenText = '';
      _spokenRawText = '';
        _translatedText = '';
      _translatedRawText = '';
        _phoneticText = '';
        _spokenLang = '';
        _translatedLang = '';
      });

  Future<void> _shareCurrentTranslationPackage() async {
    final inputDisplay = _spokenText.trim();
    final outputDisplay = _translatedText.trim();
    if (inputDisplay.isEmpty || outputDisplay.isEmpty) {
      _showSnack('Translate first so input and output can be shared.');
      return;
    }

    if (_sharingCurrentTranslation) return;
    setState(() => _sharingCurrentTranslation = true);

    try {
      final inputRaw = _spokenRawText.trim().isNotEmpty ? _spokenRawText.trim() : inputDisplay;
      final outputRaw =
          _translatedRawText.trim().isNotEmpty ? _translatedRawText.trim() : outputDisplay;
      final inputLang = _spokenLang.isNotEmpty ? _spokenLang : _selectedInputLang;
      final outputLang = _translatedLang.isNotEmpty ? _translatedLang : _selectedOutputLang;
      final dir = await getTemporaryDirectory();
      final nowSuffix = DateTime.now().millisecondsSinceEpoch;

      final payload = StringBuffer()
        ..writeln('Let\'s Talk Translation')
        ..writeln()
        ..writeln('Input ($inputLang):')
        ..writeln(inputDisplay)
        ..writeln()
        ..writeln('Output ($outputLang):')
        ..writeln(outputDisplay);

      if (_phoneticText.trim().isNotEmpty) {
        payload
          ..writeln()
          ..writeln('Phonetics:')
          ..writeln(_phoneticText.trim());
      }

      final files = <XFile>[];

      final inputProvider = _ttsProviderForLanguage(inputLang);
      final inputVoice = _voiceNameForLanguage(inputLang);
      final safeInputForSpeech = _silenceProfanityForSpeech(inputRaw);
      final inputSpeechText =
          safeInputForSpeech.isNotEmpty ? safeInputForSpeech : inputRaw;
      var hasInputMp3 = false;
      if (inputSpeechText.isNotEmpty) {
        var inputAudio = await _generateAudioWithCache(
          inputSpeechText,
          inputLang,
          inputVoice,
          provider: inputProvider,
        );
        inputAudio ??= await _translationService.generateTranslation(
          inputSpeechText,
          inputLang,
          voiceName: inputVoice,
          ttsProvider: inputProvider,
        );
        if (inputAudio != null && inputAudio.isNotEmpty) {
          final inFile = File('${dir.path}/limpopo_input_$nowSuffix.mp3');
          await inFile.writeAsBytes(inputAudio, flush: true);
          files.add(XFile(inFile.path, mimeType: 'audio/mpeg'));
          hasInputMp3 = true;
        }
      }

      final outputProvider = _ttsProviderForLanguage(outputLang);
      final outputVoice = _voiceNameForLanguage(outputLang);
      final safeOutputForSpeech = _silenceProfanityForSpeech(outputRaw);
      final outputSpeechText =
          safeOutputForSpeech.isNotEmpty ? safeOutputForSpeech : outputRaw;
      var hasOutputMp3 = false;
      if (outputSpeechText.isNotEmpty) {
        var outputAudio = await _generateAudioWithCache(
          outputSpeechText,
          outputLang,
          outputVoice,
          provider: outputProvider,
        );
        outputAudio ??= await _translationService.generateTranslation(
          outputSpeechText,
          outputLang,
          voiceName: outputVoice,
          ttsProvider: outputProvider,
        );
        if (outputAudio != null && outputAudio.isNotEmpty) {
          final outFile = File('${dir.path}/limpopo_output_$nowSuffix.mp3');
          await outFile.writeAsBytes(outputAudio, flush: true);
          files.add(XFile(outFile.path, mimeType: 'audio/mpeg'));
          hasOutputMp3 = true;
        }
      }

      if (!hasInputMp3 || !hasOutputMp3) {
        _showSnack('Could not generate both input and output MP3 files. Please try again.');
        return;
      }

      // Add text files after audio files so share targets prioritise media attachments.
      final inputTextFile = File('${dir.path}/limpopo_input_$nowSuffix.txt');
      await inputTextFile.writeAsString(
        'Input Language: $inputLang\n\n$inputDisplay\n',
        flush: true,
      );
      files.add(XFile(inputTextFile.path, mimeType: 'text/plain'));

      final outputTextFile = File('${dir.path}/limpopo_output_$nowSuffix.txt');
      await outputTextFile.writeAsString(
        'Output Language: $outputLang\n\n$outputDisplay\n',
        flush: true,
      );
      files.add(XFile(outputTextFile.path, mimeType: 'text/plain'));

      await Share.shareXFiles(
        files,
        subject: 'Let\'s Talk Translation',
        text: payload.toString(),
      );
    } catch (e) {
      debugPrint('Share translation package error: $e');
      _showSnack('Could not prepare share package. Try again.');
    } finally {
      if (mounted) {
        setState(() => _sharingCurrentTranslation = false);
      }
    }
  }

  void _showSnack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  void _sendHistoryToLearn(HistoryItem item) {
    final phonetic = (item.phonetic ?? '').trim();
    final normalizedOutputLang = _normalizeLanguageLabel(item.outputLang);
    setState(() {
      _selectedLearnLang = normalizedOutputLang;
      _activeTab = 'learn';
      _learnFocusTextByLang[normalizedOutputLang] = item.translated;
      _learnFocusMeaningByLang[normalizedOutputLang] = item.original;
      _learnFocusPhoneticByLang[normalizedOutputLang] = phonetic.isEmpty ? null : phonetic;
    });
    _showSnack('Sentence sent to Learn');
  }

  String _narakeetUnavailableMessage() =>
      'Narakeet unavailable. Check connection & try again.';

  void _showQrShare() {
    const appUrl =
      'https://dummy.link/limpopovoice';
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor:
            isDark ? const Color(0xFF000000) : const Color(0xFFFFFFFF),
        surfaceTintColor:
            isDark ? const Color(0xFF000000) : const Color(0xFFFFFFFF),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Share App',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 20),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black26,
                        blurRadius: 8,
                        offset: const Offset(0, 2))
                  ],
                ),
                padding: const EdgeInsets.all(12),
                child: QrImageView(
                  data: appUrl,
                  version: QrVersions.auto,
                  size: 200,
                  backgroundColor: Colors.white,
                  eyeStyle: const QrEyeStyle(
                    eyeShape: QrEyeShape.square,
                    color: Color(0xFF000000),
                  ),
                  dataModuleStyle: const QrDataModuleStyle(
                    dataModuleShape: QrDataModuleShape.square,
                    color: Color(0xFF000000),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text('Let\'s Talk',
                  style: TextStyle(
                      fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white70 : const Color(0xFF000000))),
              const SizedBox(height: 16),
              // Play Store link removed as requested
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white,
                  backgroundColor: Colors.black,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                ),
                child: const Text('Close', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showCreditTiers() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? const Color(0xFF000000) : const Color(0xFFFFFFFF),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return Material(
          color: isDark ? const Color(0xFF000000) : const Color(0xFFFFFFFF),
          surfaceTintColor:
              isDark ? const Color(0xFF000000) : const Color(0xFFFFFFFF),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
              Row(
                children: [
                  Icon(Icons.account_balance_wallet,
                      color: isDark ? Colors.white : const Color(0xFF000000)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Credit Packages',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : const Color(0xFF000000),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Translations capped at\n5 seconds',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.white70 : Colors.black54,
                      ),
                    ),
                  ),
                  Chip(
                    label: Text('Balance: $_credits sec',
                      style: TextStyle(
                        color: isDark ? Colors.white : const Color(0xFF000000),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    backgroundColor: isDark ? Colors.black : Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ],
              ),
              const SizedBox(height: 16),
                ..._tiers.map((tier) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isDark ? Colors.white10 : Colors.black,
                        foregroundColor: Colors.white, // Always white text
                        minimumSize: const Size(double.infinity, 52),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () {
                        Navigator.pop(ctx);
                        _startSandboxTierPayment(tier);
                      },
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              tier.name,
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 16,
                                  color: Colors.white),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text('${tier.secs} sec',
                            style: const TextStyle(
                              color: Colors.white70,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(tier.price,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                    )),
              ],
            ),
          ),
        );
      },
    );
  }

  double _tierAmountFromPrice(String price) {
    final cleaned = price.replaceAll(RegExp(r'[^0-9.]'), '');
    return double.tryParse(cleaned) ?? 0;
  }

  Future<void> _startSandboxTierPayment(_CreditTier tier) async {
    final amount = _tierAmountFromPrice(tier.price);
    if (amount <= 0) {
      _showSnack('Invalid tier amount.');
      return;
    }

    final paymentId =
        'LV-${tier.name}-${DateTime.now().millisecondsSinceEpoch}';

    final paid = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (payContext) => Scaffold(
          appBar: AppBar(title: Text('PayFast Sandbox - ${tier.name}')),
          body: SafeArea(
            child: PayFast(
              useSandBox: true,
              passPhrase: _payFastPassPhrase,
              onsiteActivationScriptUrl: _payFastSandboxScriptUrl,
              paymentSummaryBuilder: (context, data, processPayment) {
                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          SizedBox(
                            width: 48,
                            height: 48,
                            child: Center(
                              child: Image.asset(
                                'assets/letstalkmainblack.png',
                                width: 64,
                                height: 64,
                                fit: BoxFit.contain,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Let\'s Talk - ${tier.name}',
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text('${tier.secs} sec top-up'),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text('Amount: R${amount.toStringAsFixed(2)}'),
                      const SizedBox(height: 14),
                      Builder(
                        builder: (context) {
                          final isDark = Theme.of(context).brightness == Brightness.dark;
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              ElevatedButton(
                                onPressed: processPayment,
                                style: ElevatedButton.styleFrom(
                                  foregroundColor: Colors.white, // Always white text
                                  backgroundColor: isDark ? Colors.white10 : Colors.black,
                                ),
                                child: const Text('Pay Now'),
                              ),
                              const SizedBox(height: 8),
                              OutlinedButton(
                                onPressed: () {
                                  if (Navigator.of(payContext).canPop()) {
                                    Navigator.of(payContext).pop(true);
                                  }
                                },
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: isDark ? Colors.white : const Color(0xFF000000),
                                  side: BorderSide(color: isDark ? Colors.white : Colors.black),
                                ),
                                child: const Text('Sandbox: Add Credits Now'),
                              ),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                );
              },
              data: {
                'merchant_id': _payFastMerchantId,
                'merchant_key': _payFastMerchantKey,
                'name_first': 'Limpopo',
                'name_last': 'Voice',
                'email_address': 'sandbox@limpopovoice.app',
                'm_payment_id': paymentId,
                'amount': amount.toStringAsFixed(2),
                'item_name': 'LV Studio: ${tier.name}',
                'return_url': 'https://yoursite.com/success',
                'cancel_url': 'https://yoursite.com/cancel',
                'notify_url': 'https://yoursite.com/notify',
              },
              onPaymentCompleted: (_) {
                if (Navigator.of(payContext).canPop()) {
                  Navigator.of(payContext).pop(true);
                }
              },
              onPaymentCancelled: () {
                if (Navigator.of(payContext).canPop()) {
                  Navigator.of(payContext).pop(false);
                }
              },
              onError: (msg) {
                debugPrint('PayFast error: $msg');
                if (Navigator.of(payContext).canPop()) {
                  Navigator.of(payContext).pop(false);
                }
              },
            ),
          ),
        ),
      ),
    );

    if (!mounted) return;

    if (paid == true) {
      setState(() => _credits += tier.secs);
      _showSnack('Credits added: ${tier.secs} sec (${tier.name}) [Sandbox].');
      try {
        await FirebaseFirestore.instance.collection('payment_events').add({
          'tierName': tier.name,
          'secondsAdded': tier.secs,
          'amountPaid': amount,
          'status': 'completed_sandbox',
          'createdAt': FieldValue.serverTimestamp(),
        });
      } catch (_) {
        // Do not block crediting if telemetry logging fails.
      }
    } else {
      _showSnack('Payment cancelled. No credits added.');
    }
  }
  Widget _buildHeaderWordmark(bool isDark) {
    final titleColor = isDark ? Colors.white : const Color(0xFF1F2D40);
    final subtitleColor = isDark ? Colors.white70 : const Color(0xFF2C3A4B);

    return SizedBox(
      height: 88,
      child: AspectRatio(
        aspectRatio: 616 / 218,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          decoration: isDark
              ? BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xFF0D1A2A),
                      Color(0xFF08111B),
                      Color(0xFF03070D),
                    ],
                  ),
                )
              : null,
          child: FittedBox(
            fit: BoxFit.contain,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'let\'s talk',
                  style: TextStyle(
                    color: titleColor,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w900,
                    fontSize: 120,
                    height: 1.02,
                    letterSpacing: 0.6,
                    shadows: [
                      Shadow(
                        color: Colors.black.withOpacity(isDark ? 0.65 : 0.28),
                        blurRadius: 0,
                        offset: const Offset(1, 0),
                      ),
                      Shadow(
                        color: Colors.black.withOpacity(isDark ? 0.65 : 0.28),
                        blurRadius: 0,
                        offset: const Offset(-1, 0),
                      ),
                      Shadow(
                        color: Colors.black.withOpacity(isDark ? 0.65 : 0.28),
                        blurRadius: 0,
                        offset: const Offset(0, 1),
                      ),
                      Shadow(
                        color: Colors.black.withOpacity(isDark ? 0.65 : 0.28),
                        blurRadius: 0,
                        offset: const Offset(0, -1),
                      ),
                      Shadow(
                        color: Colors.black.withOpacity(isDark ? 0.7 : 0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'SOUTH AFRICA',
                  style: TextStyle(
                    color: subtitleColor,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w800,
                    fontSize: 48,
                    letterSpacing: 3.0,
                    height: 1,
                    shadows: [
                      Shadow(
                        color: Colors.black.withOpacity(isDark ? 0.55 : 0.2),
                        blurRadius: 0,
                        offset: const Offset(1, 0),
                      ),
                      Shadow(
                        color: Colors.black.withOpacity(isDark ? 0.55 : 0.2),
                        blurRadius: 0,
                        offset: const Offset(-1, 0),
                      ),
                      Shadow(
                        color: Colors.black.withOpacity(isDark ? 0.65 : 0.2),
                        blurRadius: 5,
                        offset: const Offset(0, 1),
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final pageName = _activeTab == 'history'
        ? 'History'
        : (_activeTab == 'learn' ? 'Learn' : 'Translate');
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          // Top bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: SizedBox(
              height: 44,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: PopupMenuButton<String>(
                      icon: const Icon(Icons.menu),
                      tooltip: 'Menu',
                      color: Colors.white,
                      surfaceTintColor: Colors.white,
                      itemBuilder: (context) => [
                        PopupMenuItem(
                          value: 'about',
                          child: Row(
                            children: [
                              const Icon(Icons.info_outline, size: 18, color: Colors.black),
                              const SizedBox(width: 12),
                              const Text('About', style: TextStyle(color: Colors.black)),
                            ],
                          ),
                        ),
                        PopupMenuItem(
                          value: 'translate',
                          child: Row(
                            children: [
                              const Icon(Icons.translate, size: 18, color: Colors.black),
                              const SizedBox(width: 12),
                              const Text('Translate', style: TextStyle(color: Colors.black)),
                            ],
                          ),
                        ),
                        PopupMenuItem(
                          value: 'history',
                          child: Row(
                            children: [
                              const Icon(Icons.history, size: 18, color: Colors.black),
                              const SizedBox(width: 12),
                              const Text('History', style: TextStyle(color: Colors.black)),
                            ],
                          ),
                        ),
                        PopupMenuItem(
                          value: 'learn',
                          child: Row(
                            children: [
                              const Icon(Icons.school, size: 18, color: Colors.black),
                              const SizedBox(width: 12),
                              const Text('Learn', style: TextStyle(color: Colors.black)),
                            ],
                          ),
                        ),
                        PopupMenuItem(
                          value: 'theme',
                          child: Row(
                            children: [
                              Icon(
                                isDark ? Icons.light_mode : Icons.dark_mode,
                                size: 18,
                                color: Colors.black,
                              ),
                              const SizedBox(width: 12),
                              Text(
                                isDark ? 'Light Mode' : 'Dark Mode',
                                style: const TextStyle(color: Colors.black),
                              ),
                            ],
                          ),
                        ),
                      ],
                      onSelected: (value) {
                        if (value == 'about') {
                          showDialog(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Text('About'),
                              content: const Text(
                                "'Let's Talk' lets you instantly translate, speak, and learn phrases across all South African languages. It features fast voice/text translation, a learn tab for practice, a history tab for review and deletion, and a clean, modern interface with light/dark modes. Everything is designed for quick, easy, and accessible multilingual communication."
                              ),
                              actions: [
                                Builder(
                                  builder: (ctx2) {
                                    final isDark = Theme.of(ctx2).brightness == Brightness.dark;
                                    return TextButton(
                                      style: TextButton.styleFrom(
                                        backgroundColor: const Color(0xFF000000),
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                      ),
                                      onPressed: () => Navigator.of(ctx).pop(),
                                      child: const Text('Close'),
                                    );
                                  },
                                ),
                              ],
                            ),
                          );
                        } else if (value == 'translate') {
                          setState(() => _activeTab = 'translate');
                        } else if (value == 'history') {
                          setState(() => _activeTab = 'history');
                        } else if (value == 'learn') {
                          setState(() => _activeTab = 'learn');
                        } else if (value == 'theme') {
                          widget.onToggleTheme();
                        }
                      },
                    ),
                  ),
                  Center(
                    child: _buildHeaderWordmark(isDark),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: PopupMenuButton<int>(
                      tooltip: 'User menu',
                      color: isDark ? const Color(0xFF000000) : const Color(0xFFFFFFFF),
                      surfaceTintColor:
                          isDark ? const Color(0xFF000000) : const Color(0xFFFFFFFF),
                      offset: const Offset(0, 40),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      itemBuilder: (context) {
                        final isDark = Theme.of(context).brightness == Brightness.dark;
                        return [
                          PopupMenuItem(
                            value: 1,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 20,
                                      backgroundImage: null,
                                      backgroundColor: isDark ? Colors.grey[400] : Colors.black, // TODO: Replace with user image
                                      child: Icon(Icons.person, size: 24, color: Colors.white),
                                    ),
                                    const SizedBox(width: 12),
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text('User', style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.white : const Color(0xFF000000))),
                                        Text('user@example.com', style: TextStyle(fontSize: 12, color: isDark ? Colors.grey : Colors.black54)), // TODO: Replace with real email/ID
                                      ],
                                    ),
                                  ],
                                ),
                                const Divider(height: 18),
                                ListTile(
                                  leading: Icon(Icons.qr_code_2, color: isDark ? Colors.white : Colors.black),
                                  title: Text('Share App', style: TextStyle(color: isDark ? Colors.white : const Color(0xFF000000))),
                                  onTap: () {
                                    Navigator.pop(context);
                                    _showQrShare();
                                  },
                                ),
                                ListTile(
                                  leading: Icon(Icons.account_balance_wallet, color: isDark ? Colors.white : Colors.black),
                                  title: Text('Credits', style: TextStyle(color: isDark ? Colors.white : const Color(0xFF000000))),
                                  onTap: () {
                                    Navigator.pop(context);
                                    _showCreditTiers();
                                  },
                                ),
                                ListTile(
                                  leading: Icon(Icons.info_outline,
                                      color: isDark ? Colors.white : Colors.black),
                                  title: Text('Disclaimer',
                                      style: TextStyle(
                                          color: isDark
                                              ? Colors.white
                                              : const Color(0xFF000000))),
                                  onTap: () {
                                    Navigator.pop(context);
                                    _showDisclaimerInfo();
                                  },
                                ),
                                // Add more user actions here if needed
                              ],
                            ),
                          ),
                        ];
                      },
                      child: CircleAvatar(
                        radius: 16,
                        backgroundImage: null, // Placeholder icon
                        backgroundColor: isDark ? Colors.grey[400] : Colors.black, // TODO: Replace with NetworkImage or AssetImage for user thumb
                        child: Icon(Icons.person, size: 20, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: isDark ? Colors.black : Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isDark ? Colors.white : Colors.black,
                  width: 1.6,
                ),
              ),
              child: Text(
                pageName,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  color: isDark ? Colors.white : const Color(0xFF000000),
                ),
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

  Future<bool> _confirmClearSentFromHistory() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return AlertDialog(
          title: const Text('sure?'),
          content: const Text(
            'This will delete the phrase sent from History on the Learn page.',
          ),
          backgroundColor:
              isDark ? const Color(0xFF000000) : const Color(0xFFFFFFFF),
          surfaceTintColor:
              isDark ? const Color(0xFF000000) : const Color(0xFFFFFFFF),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text('Cancel', style: TextStyle(color: isDark ? Colors.white : Color(0xFF000000))),
            ),
            TextButton(
              style: TextButton.styleFrom(
                backgroundColor: const Color(0xFF000000),
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Clear', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
    return result == true;
  }

  Widget _buildLearnTab(bool isDark) {
    final learnPhraseKey = _selectedLearnLang;
    final userPhrases = _userLearnPhrasesByLang[learnPhraseKey] ?? [];
    final defaultPhrases = _learnPhrasesByLang[learnPhraseKey] ?? _learnPhrasesByLang['English']!;
    final phrases = [
      ...userPhrases,
      ...defaultPhrases.where((def) => !userPhrases.any((u) => u['text'] == def['text'])),
    ]; // Avoid duplicate default if user added same
    final currentLearnText = _learnFocusTextByLang[_selectedLearnLang] ?? '';
    final hasHistoryFocus = currentLearnText.trim().isNotEmpty;
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
              color: isDark ? Colors.white : const Color(0xFF000000),
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
          ...phrases.asMap().entries.map((entry) {
            final idx = entry.key;
            final phrase = entry.value;
            final isUserPhrase = idx < userPhrases.length;
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: isDark ? Colors.white12 : const Color(0xFFE3F0FF), // soft blue pastel
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isDark ? Colors.white24 : Colors.black26,
                ),
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
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            color: isDark ? Colors.white : const Color(0xFF000000),
                          ),
                        ),
                        if ((phrase['phonetic'] ?? '').isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            phrase['phonetic']!,
                            style: TextStyle(
                              fontSize: 12,
                              fontStyle: FontStyle.italic,
                              color: isDark ? Colors.white70 : const Color(0xFF000000),
                            ),
                          ),
                        ],
                        const SizedBox(height: 3),
                        Text(
                          phrase['en'] ?? '',
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark
                                ? Colors.white60
                                : Colors.grey.shade700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.volume_up),
                    tooltip: 'Listen',
                    onPressed: () =>
                        _speakText(phrase['text'] ?? '', _selectedLearnLang),
                  ),
                  if (isUserPhrase)
                    IconButton(
                      icon: Icon(Icons.close, color: isDark ? Colors.white70 : Colors.black54),
                      tooltip: 'Delete',
                      onPressed: () => _deleteUserPhrase(idx),
                    ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildTranslateTab(bool isDark) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final boxHeight = (constraints.maxHeight - 260) * 0.42;
        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight - 8),
            child: IntrinsicHeight(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Input box
                  GestureDetector(
                    onTap: () {
                      FocusScope.of(context).requestFocus(_inputFocusNode);
                    },
                    child: Container(
                      width: double.infinity,
                      height: boxHeight,
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white12 : const Color(0xFFE0F8D8),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: isDark ? Colors.white24 : Colors.black26),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: _langDrop(
                                  _selectedInputLang,
                                  _inputLangs,
                                  (v) => setState(() => _selectedInputLang = v!),
                                  isDark,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Expanded(
                            child: Stack(
                              children: [
                                if (_spokenText.isNotEmpty && _tttController.text.isEmpty)
                                  Align(
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                      _spokenText,
                                      style: TextStyle(
                                        fontFamily: 'monospace',
                                        fontSize: 14,
                                        color: isDark ? Colors.white : Colors.black,
                                      ),
                                    ),
                                  ),
                                TextField(
                                  controller: _tttController,
                                  focusNode: _inputFocusNode,
                                  autofocus: false,
                                  enableSuggestions: true,
                                  autocorrect: true,
                                  keyboardType: TextInputType.text,
                                  textCapitalization: TextCapitalization.sentences,
                                  cursorColor: isDark ? Colors.white : Colors.black,
                                  style: TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 14,
                                    color: isDark ? Colors.white : Colors.black,
                                  ),
                                  decoration: const InputDecoration(
                                    border: InputBorder.none,
                                    hintText: '',
                                    isDense: true,
                                    contentPadding: EdgeInsets.zero,
                                  ),
                                  minLines: 1,
                                  maxLines: 3,
                                  readOnly: true,
                                  onChanged: (_) => setState(() {}),
                                  onSubmitted: (_) => _submitTTT(),
                                  textInputAction: TextInputAction.send,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // SWAP BUTTON (moved up by 4px)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Center(
                      child: Transform.translate(
                        offset: const Offset(0, -4), // Move up by 4 pixels
                        child: Material(
                          color: isDark ? Colors.black : Colors.white,
                          shape: const CircleBorder(),
                          elevation: 2,
                          child: IconButton(
                            icon: Icon(
                              Icons.swap_vert,
                              size: 36,
                              color: isDark ? Colors.white : Colors.black,
                            ),
                            tooltip: 'Swap languages',
                            onPressed: () => setState(() {
                              final tmp = _selectedInputLang;
                              _selectedInputLang = _selectedOutputLang;
                              _selectedOutputLang = tmp;
                            }),
                          ),
                        ),
                      ),
                    ),
                  ),

                  // Output box
                  Container(
                    width: double.infinity,
                    height: boxHeight,
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white12 : const Color(0xFFFFF3E0),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: isDark ? Colors.white24 : Colors.black26),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: _langDrop(
                                _selectedOutputLang,
                                _outputLangs,
                                (v) => setState(() => _selectedOutputLang = v!),
                                isDark,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Expanded(
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              _translatedText.isNotEmpty ? _translatedText : '',
                              style: TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 14,
                                color: isDark ? Colors.white : Colors.black,
                              ),
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Send to Learn button
                  if (_translatedText.isNotEmpty && !_isTranslating)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8.0),
                      child: Center(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: isDark ? Colors.white12 : const Color(0xFFE3F0FF),
                            foregroundColor: isDark ? Colors.white : Colors.black,
                            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            elevation: 0,
                          ),
                          icon: const Icon(Icons.school, size: 20),
                          label: const Text('Send to Learn', style: TextStyle(fontWeight: FontWeight.bold)),
                          onPressed: () {
                            _sendToLearnMultipleLangs(
                              translated: _translatedText,
                              original: _spokenText.isNotEmpty ? _spokenText : _tttController.text,
                              phonetic: _phoneticText,
                              langs: [_selectedOutputLang],
                            );
                          },
                        ),
                      ),
                    ),
                  if (_isTranslating)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 10),
                      child: LinearProgressIndicator(
                        color: Colors.white,
                        backgroundColor: Colors.transparent,
                      ),
                    ),
                  const Spacer(),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        if (isDark)
                          IconButton(
                            onPressed: (_spokenText.isNotEmpty &&
                                    _translatedText.isNotEmpty &&
                                    !_sharingCurrentTranslation)
                                ? _shareCurrentTranslationPackage
                                : null,
                            icon: Icon(
                              Icons.share,
                              size: 28,
                              color: Colors.white,
                            ),
                            tooltip: 'Share',
                            padding: const EdgeInsets.all(8),
                          )
                        else
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.10),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: IconButton(
                              onPressed: (_spokenText.isNotEmpty &&
                                      _translatedText.isNotEmpty &&
                                      !_sharingCurrentTranslation)
                                  ? _shareCurrentTranslationPackage
                                  : null,
                              icon: const Icon(
                                Icons.share,
                                size: 28,
                                color: Colors.black,
                              ),
                              tooltip: 'Share',
                              padding: const EdgeInsets.all(8),
                            ),
                          ),
                        GestureDetector(
                          onTapDown: (_) => _startListening(),
                          onTapUp: (_) => _stopListening(),
                          onTapCancel: () {},
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            width: _isTalking ? 130 : 120,
                            height: _isTalking ? 130 : 120,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _isTalking ? Colors.red : Colors.green,
                              boxShadow: [
                                BoxShadow(
                                  color: (_isTalking ? Colors.red : Colors.green)
                                      .withOpacity(0.4),
                                  blurRadius: _isTalking ? 20 : 10,
                                  spreadRadius: _isTalking ? 4 : 2,
                                )
                              ],
                            ),
                            child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(_isTalking ? Icons.mic : Icons.mic_none,
                                      color: Colors.white, size: 40),
                                  const SizedBox(height: 4),
                                  Text(
                                    _isTalking ? 'LISTENING' : 'HOLD TO TALK',
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 0.5),
                                  ),
                                ]),
                          ),
                        ),
                        if (isDark)
                          IconButton(
                            onPressed: _spokenText.isNotEmpty ? _resetOutput : null,
                            icon: Icon(
                              Icons.refresh,
                              size: 28,
                              color: Colors.white,
                            ),
                            tooltip: 'New Translation',
                            padding: const EdgeInsets.all(8),
                          )
                        else
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.10),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: IconButton(
                              onPressed: _spokenText.isNotEmpty ? _resetOutput : null,
                              icon: const Icon(
                                Icons.refresh,
                                size: 28,
                                color: Colors.black,
                              ),
                              tooltip: 'New Translation',
                              padding: const EdgeInsets.all(8),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _langDrop(String value, List<String> langs,
      ValueChanged<String?> onChanged, bool isDark) {
    // Detect if this is the main output dropdown by checking langs and value
    final isOutputDropdown =
      langs.length == 12 &&
      (langs.contains('isiZulu') && langs.contains('Afrikaans')) &&
      value == _selectedOutputLang;
    final isInputDropdown =
      langs.length == 11 &&
      (langs.contains('isiZulu') && langs.contains('Afrikaans')) &&
      value == _selectedInputLang;
    final dropdownColor = isDark
      ? const Color(0xFF000000)
      : isOutputDropdown
        ? const Color(0xFFFFF3E0)
        : Colors.white;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: isDark
          ? Colors.transparent
          : isOutputDropdown
            ? const Color(0xFFFFF3E0)
            : isInputDropdown
              ? const Color(0xFFE0F8D8)
              : Colors.transparent,
      ),
      child: Theme(
        data: Theme.of(context).copyWith(
          canvasColor: dropdownColor,
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            isExpanded: true,
            value: value,
            dropdownColor: dropdownColor,
            style: TextStyle(
                color: isDark ? Colors.white : const Color(0xFF000000),
                fontWeight: FontWeight.w600,
                fontFamily: 'monospace',
                fontSize: 16),
            items: langs
                .map((e) => DropdownMenuItem(
                    value: e,
                    child: Text(
                      e,
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 16),
                    )))
                .toList(),
            onChanged: onChanged,
          ),
        ),
      ),
    );
  }

  Widget _outBox(String label, String text, Color color, bool isDark) {
    // Use the passed color for the background in light mode, else white12 in dark mode
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? Colors.white12 : color,
        borderRadius: BorderRadius.circular(12),
        border: isDark ? null : Border.all(
          color: Colors.black26,
        ),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label,
            style: TextStyle(
                fontWeight: FontWeight.bold,
            color: isDark ? Colors.white : const Color(0xFF000000),
                fontSize: 12,
                fontFamily: 'monospace')),
        const SizedBox(height: 6),
        Text(text,
            style: TextStyle(
                fontSize: 16,
                color: isDark ? Colors.white : const Color(0xFF000000),
                fontFamily: 'monospace')),
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
      buf.writeln('Let\'s Talk — Translation History');
      buf.writeln('Exported: ${DateTime.now().toString().substring(0, 16)}');
      buf.writeln();
      for (int i = 0; i < _history.length; i++) {
        final item = _history[i];
        buf.writeln('[${i + 1}] ${item.inputLang} -> ${item.outputLang}  '
            '${item.time.hour.toString().padLeft(2, "0")}:${item.time.minute.toString().padLeft(2, "0")}');
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
          final inProvider = _ttsProviderForLanguage(item.inputLang);
          final inVoice = _voiceNameForLanguage(item.inputLang);
          final inAudio = await _translationService.generateTranslation(
            item.original,
            item.inputLang,
            voiceName: inVoice,
            ttsProvider: inProvider,
          );
          if (inAudio != null && inAudio.isNotEmpty) {
            final mp3 = File(
                '${dir.path}/entry_${i + 1}_${item.inputLang}_original.mp3');
            await mp3.writeAsBytes(inAudio);
            files.add(XFile(mp3.path, mimeType: 'audio/mpeg'));
          }
        } catch (_) {}
        try {
          final outProvider = _ttsProviderForLanguage(item.outputLang);
          final outVoice = _voiceNameForLanguage(item.outputLang);
          final outAudio = await _translationService.generateTranslation(
            item.translated,
            item.outputLang,
            voiceName: outVoice,
            ttsProvider: outProvider,
          );
          if (outAudio != null && outAudio.isNotEmpty) {
            final mp3 = File(
                '${dir.path}/entry_${i + 1}_${item.outputLang}_translation.mp3');
            await mp3.writeAsBytes(outAudio);
            files.add(XFile(mp3.path, mimeType: 'audio/mpeg'));
          }
        } catch (_) {}
      }

      if (files.isNotEmpty) {
        await Share.shareXFiles(files,
            subject: 'Let\'s Talk — Translation History');
      }
    } catch (e) {
      debugPrint('Export error: $e');
      _showSnack('Export failed');
    } finally {
      setState(() => _exportingHistory = false);
    }
  }

  Widget _buildHistoryTab(bool isDark) {
    if (_history.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.history,
                size: 64, color: isDark ? Colors.white30 : Colors.grey.shade300),
            const SizedBox(height: 12),
            Text('No translations yet',
                style: TextStyle(
                    color: isDark ? Colors.white38 : Colors.grey.shade500,
                    fontSize: 16)),
          ],
        ),
      );
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              // Share History Icon Button (far left)
              Material(
                color: Colors.white,
                shape: const CircleBorder(),
                elevation: 2,
                child: IconButton(
                  onPressed: _history.isEmpty ? null : _exportHistory,
                  icon: const Icon(Icons.share, size: 24, color: Colors.black),
                  tooltip: 'Share History',
                  padding: const EdgeInsets.all(12),
                ),
              ),
              const Spacer(),
              // Clear History Icon Button (far right)
              Material(
                color: Colors.white,
                shape: const CircleBorder(),
                elevation: 2,
                child: IconButton(
                  onPressed: () async {
                    final sure = await showDialog<bool>(
                      context: context,
                      builder: (ctx) {
                        final isDark = Theme.of(ctx).brightness == Brightness.dark;
                        return AlertDialog(
                          title: const Text('Are you sure?'),
                          content: const Text('Clear all History?'),
                          backgroundColor: isDark ? const Color(0xFF000000) : const Color(0xFFFFFFFF),
                          surfaceTintColor: isDark ? const Color(0xFF000000) : const Color(0xFFFFFFFF),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.of(ctx).pop(false),
                              child: Text('Cancel', style: TextStyle(color: isDark ? Colors.white : Color(0xFF000000))),
                            ),
                            TextButton(
                              style: TextButton.styleFrom(
                                backgroundColor: const Color(0xFF000000),
                                foregroundColor: Colors.white,
                              ),
                              onPressed: () => Navigator.of(ctx).pop(true),
                              child: const Text('Clear', style: TextStyle(color: Colors.white)),
                            ),
                          ],
                        );
                      },
                    );
                    if (sure == true) {
                      setState(() {
                        _history.clear();
                      });
                    }
                  },
                  icon: const Icon(Icons.delete_sweep, size: 24, color: Colors.black),
                  tooltip: 'Clear History',
                  padding: const EdgeInsets.all(12),
                ),
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
              final selected = _selectedHistoryIndexes.contains(i);
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                color: isDark ? Colors.white12 : const Color(0xFFFFEBEE), // pastel red
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ListTile(
                      title: Text(item.translated,
                          style: TextStyle(
                              color: isDark ? Colors.white : Colors.black,
                              fontWeight: FontWeight.bold)),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('From: ${item.inputLang}'),
                          Text('To: ${item.outputLang}'),
                          if ((item.phonetic ?? '').isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 4.0),
                              child: Text('Phonetics: ${item.phonetic}',
                                  style: TextStyle(
                                      fontStyle: FontStyle.italic,
                                      color: isDark ? Colors.white70 : Colors.black87)),
                            ),
                          Padding(
                            padding: const EdgeInsets.only(top: 4.0),
                            child: Text('Original: ${item.original}'),
                          ),
                        ],
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.volume_up),
                            tooltip: 'Repeat',
                            onPressed: () => _speakText(item.translated, item.outputLang),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isDark ? Colors.white12 : const Color(0xFFE3F0FF),
                          foregroundColor: isDark ? Colors.white : Colors.black,
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          elevation: 0,
                        ),
                        icon: const Icon(Icons.school, size: 20),
                        label: const Text('Send to Learn', style: TextStyle(fontWeight: FontWeight.bold)),
                        onPressed: () {
                          _sendHistoryToLearn(item);
                        },
                      ),
                    ),
                  ],
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
