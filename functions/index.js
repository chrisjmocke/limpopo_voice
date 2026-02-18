const { onCall, HttpsError } = require("firebase-functions/v2/https");
const admin = require("firebase-admin");

admin.initializeApp();

exports.processSpeech = onCall(
  {
    region: "africa-south1",
    timeoutSeconds: 60,
  },
  async (request) => {
    try {
      const audioBase64 = request.data?.audio;
      const targetLanguage = request.data?.targetLang || "en";

      if (!audioBase64) {
        throw new HttpsError("invalid-argument", "No audio provided.");
      }

      const speech = require("@google-cloud/speech");
      const { Translate } = require("@google-cloud/translate").v2;

      const speechClient = new speech.SpeechClient();
      const translateClient = new Translate();

      const audioBytes = Buffer.from(audioBase64, "base64");

      console.log("Decoded audio size:", audioBytes.length);

      if (audioBytes.length < 4000) {
        throw new HttpsError("failed-precondition", "Audio too small.");
      }

      const speechRequest = {
        audio: { content: audioBytes },
        config: {
          encoding: "LINEAR16", // 🔥 MATCHES WAV
          sampleRateHertz: 16000,
          languageCode: "en-US",
          enableAutomaticPunctuation: true,
        },
      };

      const [response] = await speechClient.recognize(speechRequest);

      const transcript =
        response.results
          ?.map(r => r.alternatives[0].transcript)
          .join(" ") || "";

      if (!transcript) {
        throw new HttpsError("failed-precondition", "No speech detected.");
      }

      const [translation] = await translateClient.translate(
        transcript,
        targetLanguage
      );

      return {
        originalText: transcript,
        translatedText: translation,
      };

    } catch (error) {
      console.error("🔥 Speech Error:", error);

      throw new HttpsError(
        "internal",
        error.message || "Speech processing failed."
      );
    }
  }
);

exports.activate24h = onCall(
  { region: "africa-south1" },
  async (request) => {
    const uid = request.auth?.uid;

    if (!uid) {
      throw new HttpsError("unauthenticated", "User must be authenticated.");
    }

    const expiry = new Date();
    expiry.setHours(expiry.getHours() + 24);

    await admin.firestore().collection("users").doc(uid).set(
      {
        subscriptionType: "24h",
        subscriptionExpiry: expiry,
      },
      { merge: true }
    );

    return { success: true };
  }
);
