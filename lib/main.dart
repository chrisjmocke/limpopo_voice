// LIMPOPO VOICE - RESTORED FULL VERSION

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:permission_handler/permission_handler.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const LimpopoVoiceApp());
}

class LimpopoVoiceApp extends StatelessWidget {
  const LimpopoVoiceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: LimpopoHome(),
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
  final FlutterSoundRecorder _recorder = FlutterSoundRecorder();
  final TextEditingController _textController = TextEditingController();

  StreamController<Uint8List>? _controller;
  final List<int> _pcmBuffer = [];

  int _credits = 0;
  bool _recording = false;
  bool _processing = false;

  String _sourceLanguage = "English";
  String _targetLanguage = "Sepedi";

  String _originalText = "";
  String _translatedText = "";

  static const int sampleRate = 16000;

  final Map<String, String> _languageCodes = {
    "English": "en",
    "Sepedi": "nso",
    "Xitsonga": "ts",
    "Tshivenda": "ve",
    "Afrikaans": "af",
  };

  final Color africanGreen = const Color(0xFF0B6E4F);
  final Color africanRed = const Color(0xFFC1121F);
  final Color africanGold = const Color(0xFFF4A261);

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await FirebaseAuth.instance.signInAnonymously();
    await Permission.microphone.request();
    await _recorder.openRecorder();
    await _loadCredits();
  }

  Future<void> _loadCredits() async {
    final callable =
        FirebaseFunctions.instanceFor(region: 'africa-south1')
            .httpsCallable('initializeUser');

    final res = await callable.call();
    setState(() => _credits = res.data['credits']);
  }

  void _openHistory() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const HistoryScreen()),
    );
  }

  void _openTopUp() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PurchaseScreen(onPurchase: (credits) async {
          final callable =
              FirebaseFunctions.instanceFor(region: 'africa-south1')
                  .httpsCallable('addCredits');
          final res = await callable.call({"amount": credits});
          setState(() => _credits = res.data['credits']);
        }),
      ),
    );
  }

  Future<void> _startRecording() async {
    if (_credits <= 0) return;

    setState(() => _recording = true);

    _pcmBuffer.clear();
    _controller = StreamController<Uint8List>();
    _controller!.stream.listen((data) {
      _pcmBuffer.addAll(data);
    });

    await _recorder.startRecorder(
      codec: Codec.pcm16,
      sampleRate: sampleRate,
      numChannels: 1,
      toStream: _controller!.sink,
    );
  }

  Future<void> _stopRecording() async {
    if (!_recorder.isRecording) return;

    setState(() => _recording = false);

    await _recorder.stopRecorder();
    await _controller?.close();

    final wavBytes = _buildWav(Uint8List.fromList(_pcmBuffer));
    await _processTranslation(audio: wavBytes);
  }

  Future<void> _translateText() async {
    if (_textController.text.trim().isEmpty) return;
    await _processTranslation(text: _textController.text.trim());
    _textController.clear();
  }

  Future<void> _processTranslation({Uint8List? audio, String? text}) async {
    setState(() => _processing = true);

    final callable =
        FirebaseFunctions.instanceFor(region: 'africa-south1')
            .httpsCallable('processSpeech');

    final res = await callable.call({
      if (audio != null) "audio": base64Encode(audio),
      if (text != null) "text": text,
      "sourceLanguage": _languageCodes[_sourceLanguage],
      "targetLanguage": _languageCodes[_targetLanguage],
    });

    setState(() {
      _credits = res.data['remainingCredits'];
      _originalText = res.data['originalText'] ?? text ?? "";
      _translatedText = res.data['translatedText'] ?? "";
      _processing = false;
    });

    await _tts.setLanguage(_languageCodes[_targetLanguage]!);
    await _tts.speak(_translatedText);
  }

  Uint8List _buildWav(Uint8List pcm) {
    final builder = BytesBuilder();
    final byteRate = sampleRate * 2;

    builder.add(ascii.encode('RIFF'));
    builder.add(_intToBytes(36 + pcm.length, 4));
    builder.add(ascii.encode('WAVEfmt '));
    builder.add(_intToBytes(16, 4));
    builder.add(_intToBytes(1, 2));
    builder.add(_intToBytes(1, 2));
    builder.add(_intToBytes(sampleRate, 4));
    builder.add(_intToBytes(byteRate, 4));
    builder.add(_intToBytes(2, 2));
    builder.add(_intToBytes(16, 2));
    builder.add(ascii.encode('data'));
    builder.add(_intToBytes(pcm.length, 4));
    builder.add(pcm);

    return builder.toBytes();
  }

  Uint8List _intToBytes(int val, int bytes) {
    final data = ByteData(bytes);
    if (bytes == 2) {
      data.setUint16(0, val, Endian.little);
    } else {
      data.setUint32(0, val, Endian.little);
    }
    return data.buffer.asUint8List();
  }

  Widget _languageRow(bool isSource) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _languageCodes.keys.map((lang) {
        final selected =
            isSource ? _sourceLanguage == lang : _targetLanguage == lang;

        return GestureDetector(
          onTap: () {
            setState(() {
              if (isSource) {
                _sourceLanguage = lang;
              } else {
                _targetLanguage = lang;
              }
            });
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: selected ? africanRed : africanGold,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              lang,
              style: const TextStyle(color: Colors.white),
            ),
          ),
        );
      }).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              'assets/limpopo_voice.png',
              fit: BoxFit.cover,
            ),
          ),
          SafeArea(
            child: SingleChildScrollView(
              child: Column(
                children: [

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      GestureDetector(
                        onTap: _openTopUp,
                        child: Container(
                          margin: const EdgeInsets.all(12),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: africanGold,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            "Credits: $_credits",
                            style: const TextStyle(
                                fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: _openHistory,
                        icon: const Icon(Icons.history),
                        label: const Text("History"),
                      )
                    ],
                  ),

                  const SizedBox(height: 10),
                  const Text("Input Language",
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  _languageRow(true),

                  const SizedBox(height: 20),
                  const Text("Output Language",
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  _languageRow(false),

                  const SizedBox(height: 30),

                  GestureDetector(
                    onLongPressStart: (_) => _startRecording(),
                    onLongPressEnd: (_) => _stopRecording(),
                    child: Container(
                      width: 160,
                      height: 160,
                      decoration: BoxDecoration(
                        color: _recording ? africanRed : africanGreen,
                        shape: BoxShape.circle,
                      ),
                      child: const Center(
                        child: Text(
                          "Hold to Talk",
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  if (_originalText.isNotEmpty)
                    Text("You said: $_originalText",
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold)),

                  if (_translatedText.isNotEmpty)
                    Text("Translation: $_translatedText",
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),

                  const SizedBox(height: 20),

                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: TextField(
                      controller: _textController,
                      decoration: const InputDecoration(
                        hintText: "Type text to translate",
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),

                  const SizedBox(height: 10),

                  ElevatedButton(
                    onPressed: _processing ? null : _translateText,
                    child: const Text("Translate Text"),
                  ),

                  const SizedBox(height: 40),
                ],
              ),
            ),
          )
        ],
      ),
    );
  }
}

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Translation History")),
      body: StreamBuilder(
        stream: FirebaseFirestore.instance
            .collection('history')
            .orderBy('timestamp', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final docs = snapshot.data!.docs;

          return ListView.builder(
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final data = docs[index].data();
              return ListTile(
                title: Text(data['translatedText'] ?? ""),
                subtitle: Text(data['originalText'] ?? ""),
              );
            },
          );
        },
      ),
    );
  }
}

class PurchaseScreen extends StatelessWidget {
  final Function(int) onPurchase;
  const PurchaseScreen({super.key, required this.onPurchase});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Top Up")),
      body: Column(
        children: [
          _pack(context, "Starter", "R10", 20),
          _pack(context, "Pro", "R25", 60),
          _pack(context, "Max", "R50", 150),
        ],
      ),
    );
  }

  Widget _pack(BuildContext context, String name, String price, int credits) {
    return GestureDetector(
      onTap: () {
        onPurchase(credits);
        Navigator.pop(context);
      },
      child: Container(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFFC1121F),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          children: [
            Text(name,
                style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white)),
            Text(price, style: const TextStyle(color: Colors.white)),
            Text("$credits Credits",
                style: const TextStyle(color: Colors.white)),
          ],
        ),
      ),
    );
  }
}