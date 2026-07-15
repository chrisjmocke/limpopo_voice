const { onRequest } = require("firebase-functions/v2/https");
const { setGlobalOptions } = require("firebase-functions/v2");
const admin = require("firebase-admin");

setGlobalOptions({ region: "africa-south1" });

if (!admin.apps.length) {
    admin.initializeApp();
}

// Lazy-loaded main logic for processSpeech to avoid deployment timeouts
exports.processSpeech = onRequest({
    secrets: ["GEMINI_API_KEY", "NARAKEET_API_KEY"],
    minInstances: Number(process.env.PROCESS_SPEECH_MIN_INSTANCES || 1),
    maxInstances: Number(process.env.PROCESS_SPEECH_MAX_INSTANCES || 20),
    timeoutSeconds: 120,
}, (req, res) => {
    return require("./speech_processor").handleProcessSpeech(req, res);
});

exports.liveHealthCheck = onRequest({ secrets: ["GEMINI_API_KEY"] }, (req, res) => {
    return require("./speech_processor").handleLiveHealthCheck(req, res);
});

exports.ttsProviderReadiness = onRequest((req, res) => {
    return require("./speech_processor").handleTtsProviderReadiness(req, res);
});

// Paystack & PayPal functions
const paystack = require("./paystack");
const paypal = require("./paypal");

exports.createPaystackTransaction = paystack.createPaystackTransaction;
exports.createPaystackTransactionHttp = paystack.createPaystackTransactionHttp;
exports.paystackWebhook = paystack.paystackWebhook;

exports.createPayPalOrderHttp = paypal.createPayPalOrderHttp;
exports.capturePayPalOrderHttp = paypal.capturePayPalOrderHttp;
