const { onRequest } = require("firebase-functions/v2/https");
const { setGlobalOptions } = require("firebase-functions/v2");
const admin = require("firebase-admin");

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
