const { onRequest } = require("firebase-functions/v2/https");
const { setGlobalOptions } = require("firebase-functions/v2");
const admin = require("firebase-admin");
const cors = require("cors")({ origin: true });

setGlobalOptions({ region: "africa-south1" });

if (!admin.apps.length) {
    admin.initializeApp();
}

let ttsClient = null;
let textToSpeech = null;
let cachedVoices = null;
let cachedVoicesAtMs = 0;

const VOICE_CACHE_TTL_MS = 10 * 60 * 1000;

function getTtsClient() {
    if (!ttsClient) {
        if (!textToSpeech) {
            textToSpeech = require("@google-cloud/text-to-speech");
        }
        ttsClient = new textToSpeech.TextToSpeechClient();
    }
    return ttsClient;
}

async function getCachedVoices() {
    const now = Date.now();
    if (cachedVoices && (now - cachedVoicesAtMs) < VOICE_CACHE_TTL_MS) {
        return cachedVoices;
    }

    const [voicesResponse] = await getTtsClient().listVoices({});
    cachedVoices = voicesResponse?.voices || [];
    cachedVoicesAtMs = now;
    return cachedVoices;
}

function voiceQualityScore(voiceName) {
    const name = String(voiceName || "").toLowerCase();
    if (!name) return 0;
    if (name.includes("studio")) return 100;
    if (name.includes("chirp")) return 95;
    if (name.includes("neural2")) return 90;
    if (name.includes("wavenet")) return 80;
    if (name.includes("news")) return 70;
    if (name.includes("standard")) return 40;
    return 50;
}

function sortVoicesByQuality(voices) {
    return [...voices].sort((a, b) => {
        const scoreDiff = voiceQualityScore(b?.name) - voiceQualityScore(a?.name);
        if (scoreDiff !== 0) return scoreDiff;
        return String(a?.name || "").localeCompare(String(b?.name || ""));
    });
}

function buildGenderAttempts(requestedGender) {
    const attempts = [requestedGender, "NEUTRAL", "FEMALE", "MALE"];
    return attempts.filter((v, i, arr) => typeof v === "string" && arr.indexOf(v) === i);
}

// Geographic fallback for languages unsupported by Google Cloud TTS.
// Prefer South African English over generic Anglo voices; never fall back to en-US/en-GB.
const ZA_FALLBACK_CODE = "en-ZA";

async function synthesizeBestSpeech({ text, requestedCode, requestedGender }) {
    const voices = await getCachedVoices();
    // Try native language first; fall back to South African English if unavailable.
    const fallbackCodes = [requestedCode, ZA_FALLBACK_CODE]
        .filter((v, i, arr) => arr.indexOf(v) === i);
    const genderAttempts = buildGenderAttempts(requestedGender);

    for (const code of fallbackCodes) {
        const matchingVoices = sortVoicesByQuality(
            voices.filter((v) => {
                const hasCode = (v.languageCodes || []).includes(code);
                // Keep voice output native to the selected language only.
                // Quality sorting still prefers premium voices first.
                return hasCode;
            }),
        );

        // Try top voices first for faster, more natural synthesis.
        for (const voice of matchingVoices.slice(0, 8)) {
            for (const gender of genderAttempts) {
                try {
                    const [ttsResponse] = await getTtsClient().synthesizeSpeech({
                        input: { text },
                        voice: {
                            languageCode: code,
                            name: voice.name,
                            ssmlGender: gender,
                        },
                        audioConfig: {
                            audioEncoding: "MP3",
                            speakingRate: 0.95,
                        },
                    });

                    if (ttsResponse?.audioContent) {
                        return {
                            audioContent: ttsResponse.audioContent.toString("base64"),
                            voiceLanguageUsed: code,
                            voiceGenderUsed: gender,
                            voiceNameUsed: voice.name,
                        };
                    }
                } catch (ttsError) {
                    console.warn(`TTS synthesis warning (${code}, ${voice?.name}, ${gender}):`, ttsError.message);
                }
            }
        }

        // Some locales may not appear in listVoices reliably across projects.
        // Try direct language synthesis without a named voice as final native fallback.
        for (const gender of genderAttempts) {
            try {
                const [ttsResponse] = await getTtsClient().synthesizeSpeech({
                    input: { text },
                    voice: {
                        languageCode: code,
                        ssmlGender: gender,
                    },
                    audioConfig: {
                        audioEncoding: "MP3",
                        speakingRate: 0.95,
                    },
                });

                if (ttsResponse?.audioContent) {
                    return {
                        audioContent: ttsResponse.audioContent.toString("base64"),
                        voiceLanguageUsed: code,
                        voiceGenderUsed: gender,
                        voiceNameUsed: "AUTO",
                    };
                }
            } catch (ttsError) {
                console.warn(`TTS direct-language fallback warning (${code}, ${gender}):`, ttsError.message);
            }
        }
    }

    return {
        audioContent: null,
        voiceLanguageUsed: requestedCode,
        voiceGenderUsed: requestedGender,
        voiceNameUsed: null,
    };
}

function mapLanguageCode(targetLanguage) {
    const map = {
        English: "en-ZA",
        isiZulu: "zu-ZA",
        Sepedi: "nso-ZA",
        Xitsonga: "ts-ZA",
        Tshivenda: "ve-ZA",
        Afrikaans: "af-ZA",
        Sesotho: "st-ZA",
        Setswana: "tn-ZA",
        Yoruba: "yo-NG",
        Hausa: "ha-NE",
        "Akan (Ghana)": "ak-GH",
        "Wolof (Senegal)": "wo-SN",
        "Kiswahili (Kenya/Tanzania)": "sw-KE",
        Amharic: "am-ET",
        "Afaan Oromoo": "om-ET",
        Somali: "so-SO",
        "Kinyarwanda (Rwanda)": "rw-RW",
    };
    return map[targetLanguage] || "en-ZA";
}

function mapGender(isMale) {
    return isMale ? "MALE" : "FEMALE";
}

function appCheckEnforced() {
    return String(process.env.ENFORCE_APP_CHECK || "false").toLowerCase() === "true";
}

async function verifyAppCheck(req) {
    const token = String(req.headers["x-firebase-appcheck"] || "").trim();
    if (!token) {
        if (appCheckEnforced()) {
            return { ok: false, reason: "Missing X-Firebase-AppCheck token." };
        }
        return { ok: true, skipped: true };
    }

    try {
        await admin.appCheck().verifyToken(token);
        return { ok: true, skipped: false };
    } catch (error) {
        if (appCheckEnforced()) {
            return { ok: false, reason: "Invalid App Check token." };
        }
        console.warn("App Check token invalid but enforcement is off:", error?.message || error);
        return { ok: true, skipped: true };
    }
}

function extractTextFromGeminiStreamPayload(payload) {
    const lines = payload.split(/\r?\n/);
    const chunks = [];

    for (const line of lines) {
        const trimmed = line.trim();
        if (!trimmed.startsWith("data:")) {
            continue;
        }

        const jsonPart = trimmed.slice(5).trim();
        if (!jsonPart || jsonPart === "[DONE]") {
            continue;
        }

        try {
            const parsed = JSON.parse(jsonPart);
            const candidates = parsed.candidates || [];
            for (const candidate of candidates) {
                const parts = candidate?.content?.parts || [];
                for (const part of parts) {
                    if (typeof part?.text === "string" && part.text.trim()) {
                        chunks.push(part.text);
                    }
                }
            }
        } catch {
            // Ignore non-JSON heartbeat/control lines.
        }
    }

    if (chunks.length > 0) {
        return chunks.join("").trim();
    }

    // Some responses may still come back as plain JSON.
    try {
        const parsed = JSON.parse(payload);
        const parts = parsed?.candidates?.[0]?.content?.parts || [];
        const text = parts
            .map((p) => (typeof p?.text === "string" ? p.text : ""))
            .join("")
            .trim();
        return text || null;
    } catch {
        return null;
    }
}

async function translateWithGemini(text, targetLanguage, isRespectMode, preferredModel) {
    const apiKey = process.env.GEMINI_API_KEY;
    if (!apiKey) {
        throw new Error("Missing GEMINI_API_KEY secret in function runtime.");
    }

    const prompt = `You are an expert translator for South African languages.
Translate the following text into ${targetLanguage || "isiZulu"}.
${isRespectMode ? "IMPORTANT: Use the most formal, respectful version." : "Use casual language."}
Text: "${text}"
Return ONLY the translated string.`;

    const modelCandidates = [
        preferredModel,
        process.env.GEMINI_MODEL,
        "gemini-2.0-flash-live-001",
        "gemini-2.5-flash",
    ].filter((v, i, arr) => typeof v === "string" && v.trim() && arr.indexOf(v) === i);

    let lastError = null;

    for (const model of modelCandidates) {
        const url = `https://generativelanguage.googleapis.com/v1beta/models/${encodeURIComponent(model)}:streamGenerateContent?alt=sse&key=${encodeURIComponent(apiKey)}`;
        const response = await fetch(url, {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({
                contents: [{ parts: [{ text: prompt }] }],
                generationConfig: {
                    temperature: 0.2,
                },
            }),
        });

        const bodyText = await response.text();
        if (!response.ok) {
            lastError = new Error(`Gemini model ${model} failed: [${response.status}] ${bodyText}`);
            continue;
        }

        const translated = extractTextFromGeminiStreamPayload(bodyText);
        if (translated) {
            return { translatedText: translated, modelUsed: model };
        }

        lastError = new Error(`Gemini model ${model} returned no text content.`);
    }

    throw lastError || new Error("All Gemini models failed.");
}

exports.processSpeech = onRequest({ secrets: ["GEMINI_API_KEY"] }, (req, res) => {
    cors(req, res, async () => {
        try {
            const appCheckResult = await verifyAppCheck(req);
            if (!appCheckResult.ok) {
                return res.status(401).send({ error: appCheckResult.reason });
            }

            const authHeader = String(req.headers.authorization || "");
            if (!authHeader.startsWith("Bearer ")) {
                return res.status(401).send({ error: "Missing Authorization bearer token." });
            }

            const idToken = authHeader.slice("Bearer ".length).trim();
            if (!idToken) {
                return res.status(401).send({ error: "Empty Authorization bearer token." });
            }

            try {
                await admin.auth().verifyIdToken(idToken);
            } catch {
                return res.status(401).send({ error: "Unauthorized" });
            }

            const {
                text,
                targetLanguage,
                isRespectMode,
                isMale,
                model,
            } = req.body;

            if (!text) {
                return res.status(400).send({ error: "No text provided" });
            }

            const { translatedText, modelUsed } = await translateWithGemini(
                text,
                targetLanguage,
                isRespectMode,
                model,
            );

            const requestedCode = mapLanguageCode(targetLanguage);
            const requestedGender = mapGender(isMale !== false);
            const ttsResult = await synthesizeBestSpeech({
                text: translatedText,
                requestedCode,
                requestedGender,
            });

            res.status(200).send({
                translation: translatedText,
                audioContent: ttsResult.audioContent,
                voiceLanguageUsed: ttsResult.voiceLanguageUsed,
                voiceGenderUsed: ttsResult.voiceGenderUsed,
                voiceNameUsed: ttsResult.voiceNameUsed,
                modelUsed,
                status: "success",
            });
        } catch (error) {
            console.error("Translation Error:", error);
            const details = String(error?.message || "Unknown error");
            const isInvalidApiKey = details.includes("API_KEY_INVALID") || details.toLowerCase().includes("api key expired");
            res.status(500).send({
                error: "Translation Failed",
                details,
                hint: isInvalidApiKey ? "GEMINI_API_KEY is invalid/expired. Rotate the secret and redeploy processSpeech." : undefined,
            });
        }
    });
});

exports.liveHealthCheck = onRequest({ secrets: ["GEMINI_API_KEY"] }, (req, res) => {
    cors(req, res, async () => {
        try {
            const appCheckResult = await verifyAppCheck(req);
            if (!appCheckResult.ok) {
                return res.status(401).send({ error: appCheckResult.reason });
            }

            const authHeader = String(req.headers.authorization || "");
            if (!authHeader.startsWith("Bearer ")) {
                return res.status(401).send({ error: "Missing Authorization bearer token." });
            }

            const idToken = authHeader.slice("Bearer ".length).trim();
            if (!idToken) {
                return res.status(401).send({ error: "Empty Authorization bearer token." });
            }

            try {
                await admin.auth().verifyIdToken(idToken);
            } catch {
                return res.status(401).send({ error: "Unauthorized" });
            }

            const requestedModel = String(req.body?.model || "").trim();
            const model = requestedModel || process.env.GEMINI_LIVE_MODEL || "gemini-2.0-flash-live-001";
            const apiKey = process.env.GEMINI_API_KEY;
            if (!apiKey) {
                return res.status(500).send({ error: "Missing GEMINI_API_KEY secret in function runtime." });
            }

            const listUrl = `https://generativelanguage.googleapis.com/v1beta/models?key=${encodeURIComponent(apiKey)}`;
            const response = await fetch(listUrl, { method: "GET" });
            const bodyText = await response.text();
            if (!response.ok) {
                return res.status(502).send({
                    error: "Live model health check failed",
                    model,
                    details: bodyText,
                });
            }

            let payload;
            try {
                payload = JSON.parse(bodyText);
            } catch {
                return res.status(502).send({
                    error: "Live model health check failed",
                    model,
                    details: "Unable to parse model list response.",
                });
            }

            const models = Array.isArray(payload?.models) ? payload.models : [];
            const liveModels = models
                .filter((m) => Array.isArray(m?.supportedGenerationMethods) && m.supportedGenerationMethods.includes("bidiGenerateContent"));
            const requestedName = model.startsWith("models/") ? model : `models/${model}`;
            let requestedEntry = models.find((m) => String(m?.name || "") === requestedName);

            if (!requestedEntry) {
                requestedEntry = liveModels[0] || null;
            }

            if (!requestedEntry) {
                return res.status(404).send({
                    error: "No Gemini Live-capable models found in ListModels",
                    model,
                    availableLiveModels: [],
                });
            }

            const methods = Array.isArray(requestedEntry.supportedGenerationMethods)
                ? requestedEntry.supportedGenerationMethods
                : [];
            const supportsLive = methods.includes("bidiGenerateContent");

            if (!supportsLive) {
                return res.status(422).send({
                    error: "Requested model does not support Gemini Live bidiGenerateContent",
                    model: requestedEntry.name,
                    supportedGenerationMethods: methods,
                });
            }

            return res.status(200).send({
                status: "ok",
                mode: "live-health",
                model: requestedEntry.name,
                autoSelectedModel: requestedEntry.name !== requestedName,
                supportsBidiGenerateContent: true,
                supportedGenerationMethods: methods,
                availableLiveModels: liveModels.map((m) => m.name),
            });
        } catch (error) {
            console.error("Live health check error:", error);
            return res.status(500).send({
                error: "Live health check failed",
                details: String(error?.message || "Unknown error"),
            });
        }
    });
});