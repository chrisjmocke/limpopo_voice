const { onRequest } = require("firebase-functions/v2/https");
const { setGlobalOptions } = require("firebase-functions/v2");
const admin = require("firebase-admin");
const { verifyTokenAndGetUserId, handleInitialTranslationWithAudio } = require("./speech_processor");

const firebaseConfig = (() => {
  try {
    return process.env.FIREBASE_CONFIG ? JSON.parse(process.env.FIREBASE_CONFIG) : {};
  } catch {
    return {};
  }
})();

const projectId = process.env.GCLOUD_PROJECT || firebaseConfig.projectId || "limpopo-voice-prod";

setGlobalOptions({ region: "africa-south1" });

if (!admin.apps.length) {
  admin.initializeApp({
    projectId,
    ...(firebaseConfig.databaseURL ? { databaseURL: firebaseConfig.databaseURL } : {}),
  });
}

exports.healthCheck = onRequest({ region: "africa-south1" }, (req, res) => {
  res.status(200).send({ ok: true, service: "limpopo-voice-payments" });
});

exports.createPaystackTransaction = onRequest({
  region: "africa-south1",
  secrets: ["PAYSTACK_SECRET_KEY"],
}, (req, res) => {
  return require("./paystack").createPaystackTransaction(req, res);
});

exports.createPaystackTransactionHttp = onRequest({
  region: "africa-south1",
  secrets: ["PAYSTACK_SECRET_KEY"],
}, (req, res) => {
  return require("./paystack").createPaystackTransactionHttp(req, res);
});

exports.cancelPaystackSubscriptionHttp = onRequest({
  region: "africa-south1",
  secrets: ["PAYSTACK_SECRET_KEY"],
}, (req, res) => {
  return require("./paystack").cancelPaystackSubscriptionHttp(req, res);
});

exports.paystackWebhook = onRequest({
  region: "africa-south1",
  secrets: ["PAYSTACK_SECRET_KEY"],
}, (req, res) => {
  return require("./paystack").paystackWebhook(req, res);
});

exports.processSpeech = onRequest({
  region: "africa-south1",
  secrets: ["GEMINI_API_KEY", "NARAKEET_API_KEY"],
}, (req, res) => {
  return require("./speech_processor").handleProcessSpeech(req, res);
});

exports.liveHealthCheck = onRequest({
  region: "africa-south1",
  secrets: ["GEMINI_API_KEY"],
}, (req, res) => {
  return require("./speech_processor").handleLiveHealthCheck(req, res);
});

exports.ttsProviderReadiness = onRequest({
  region: "africa-south1",
}, (req, res) => {
  return require("./speech_processor").handleTtsProviderReadiness(req, res);
});

exports.translateAndSynthesize = onRequest(async (req, res) => {
  try {
    const authHeader = req.headers.authorization;
    if (!authHeader) {
      return res.status(401).json({ error: "Unauthorized: Missing authorization header." });
    }

    const userId = await verifyTokenAndGetUserId(authHeader);
    const { text, targetLanguage, ttsProvider } = req.body || {};

    if (!text || !targetLanguage) {
      return res.status(400).json({ error: "Bad Request: Missing text or targetLanguage." });
    }

    const audioUrl = await handleInitialTranslationWithAudio(userId, text, targetLanguage, ttsProvider);
    return res.status(200).json({ success: true, audioUrl });
  } catch (error) {
    console.error("translateAndSynthesize error:", error);
    return res.status(500).json({ error: error.message || "Internal Server Error" });
  }
});
