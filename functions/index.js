const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { setGlobalOptions } = require("firebase-functions/v2");
const admin = require("firebase-admin");
const { SpeechClient } = require("@google-cloud/speech");

admin.initializeApp();
const db = admin.firestore();
const speechClient = new SpeechClient();

// ✅ Set region globally (v2 way)
setGlobalOptions({ region: "africa-south1" });

exports.processSpeech = onCall(async (request) => {
  try {
    // 🔐 AUTH CHECK
    if (!request.auth) {
      throw new HttpsError(
        "unauthenticated",
        "User must be authenticated."
      );
    }

    const uid = request.auth.uid;
    const userRef = db.collection("users").doc(uid);
    const userSnap = await userRef.get();

    if (!userSnap.exists) {
      throw new HttpsError("not-found", "User not found.");
    }

    const userData = userSnap.data();
    const credits = userData.credits || 0;

    // ❌ BLOCK IF NO CREDITS
    if (credits <= 0) {
      throw new HttpsError(
        "failed-precondition",
        "No credits remaining."
      );
    }

    const audioBase64 = request.data.audio;

    if (!audioBase64) {
      throw new HttpsError(
        "invalid-argument",
        "No audio provided."
      );
    }

    // 🎙 Google Speech-to-Text
    const [response] = await speechClient.recognize({
      audio: { content: audioBase64 },
      config: {
        encoding: "LINEAR16",
        sampleRateHertz: 16000,
        languageCode: "en-US",
      },
    });

    const transcription =
      response.results
        ?.map((r) => r.alternatives[0].transcript)
        .join(" ") || "";

    if (!transcription) {
      throw new HttpsError(
        "invalid-argument",
        "No speech detected."
      );
    }

    // 🔥 ATOMIC CREDIT DEDUCTION
    await userRef.update({
      credits: admin.firestore.FieldValue.increment(-1),
      lastUsed: admin.firestore.FieldValue.serverTimestamp(),
    });

    return {
      originalText: transcription,
      translatedText: transcription,
      remainingCredits: credits - 1,
    };

  } catch (error) {
    console.error("Error:", error);

    if (error instanceof HttpsError) {
      throw error;
    }

    throw new HttpsError("internal", "Processing failed.");
  }
});
