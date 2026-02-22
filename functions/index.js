const { onCall } = require("firebase-functions/v2/https");
const { setGlobalOptions } = require("firebase-functions/v2");
const admin = require("firebase-admin");
const { SpeechClient } = require("@google-cloud/speech");
const { Translate } = require("@google-cloud/translate").v2;

admin.initializeApp();

setGlobalOptions({
  region: "africa-south1",
  memory: "512MiB",
  timeoutSeconds: 60,
});

const db = admin.firestore();
const speechClient = new SpeechClient();
const translate = new Translate();

//////////////////////////////////////////////////////////
// INITIALIZE USER
//////////////////////////////////////////////////////////

exports.initializeUser = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new Error("Unauthorized");

  const userRef = db.collection("users").doc(uid);
  const doc = await userRef.get();

  if (!doc.exists) {
    await userRef.set({
      credits: 6,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return { credits: 6 };
  }

  return { credits: doc.data().credits || 0 };
});

//////////////////////////////////////////////////////////
// ADD CREDITS (SIMULATED PAYMENT)
//////////////////////////////////////////////////////////

exports.addCredits = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new Error("Unauthorized");

  const amount = request.data.amount;

  const userRef = db.collection("users").doc(uid);
  const userDoc = await userRef.get();

  const current = userDoc.data().credits || 0;
  const updated = current + amount;

  await userRef.update({
    credits: updated,
  });

  return { credits: updated };
});

//////////////////////////////////////////////////////////
// PROCESS SPEECH OR TEXT
//////////////////////////////////////////////////////////

exports.processSpeech = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new Error("Unauthorized");

  const { audio, text, sourceLanguage, targetLanguage } = request.data;

  const userRef = db.collection("users").doc(uid);
  const userDoc = await userRef.get();

  if (!userDoc.exists || userDoc.data().credits <= 0)
    throw new Error("No credits remaining");

  let transcript = text || "";

  if (audio) {
    const audioBytes = Buffer.from(audio, "base64");

    const [sttResponse] = await speechClient.recognize({
      audio: { content: audioBytes },
      config: {
        encoding: "LINEAR16",
        sampleRateHertz: 16000,
        languageCode: sourceLanguage,
      },
    });

    transcript =
      sttResponse.results
        ?.map((r) => r.alternatives[0].transcript)
        .join(" ") || "";
  }

  if (!transcript)
    return {
      translatedText: "No speech detected.",
      remainingCredits: userDoc.data().credits,
    };

  const [translation] = await translate.translate(
    transcript,
    targetLanguage
  );

  const newCredits = userDoc.data().credits - 1;

  await userRef.update({ credits: newCredits });

  await db
    .collection("users")
    .doc(uid)
    .collection("history")
    .add({
      originalText: transcript,
      translatedText: translation,
      sourceLanguage,
      targetLanguage,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

  return {
    translatedText: translation,
    remainingCredits: newCredits,
  };
});