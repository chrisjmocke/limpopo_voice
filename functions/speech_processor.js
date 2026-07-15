const { HttpsError } = require("firebase-functions/v2/https");
const admin = require("firebase-admin");
const crypto = require("crypto");
const cors = require("cors")({ origin: true });

// Configuration and Constants
const VOICE_CACHE_TTL_MS = 10 * 60 * 1000;
const MAX_TEXT_LENGTH = Number(process.env.MAX_TEXT_LENGTH || 600);
const MAX_CONTENT_LENGTH_BYTES = Number(process.env.MAX_CONTENT_LENGTH_BYTES || 32 * 1024);
const AUDIO_MEMORY_CACHE_LIMIT = Number(process.env.AUDIO_MEMORY_CACHE_LIMIT || 400);
const AUDIO_CACHE_MAX_TEXT_LENGTH = Number(process.env.AUDIO_CACHE_MAX_TEXT_LENGTH || 180);
const AUDIO_CACHE_SIGNED_URL_TTL_HOURS = Number(process.env.AUDIO_CACHE_SIGNED_URL_TTL_HOURS || 24);
const AUDIO_CACHE_OBJECT_PREFIX = String(process.env.AUDIO_CACHE_OBJECT_PREFIX || "tts-cache").trim();

const KNOWN_TTS_PROVIDERS = ["narakeet", "google", "azure", "elevenlabs"];
const GOOGLE_NEURAL2_ROUTE_LANGUAGES = new Set([
    "english", "dutch", "french", "german", "mandarin", "hindi", "urdu", "portuguese"
]);

// State
let ttsClient = null;
let textToSpeech = null;
let cachedVoices = null;
let cachedVoicesAtMs = 0;
const audioBase64MemoryCache = new Map();

// Helper Functions
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

function shouldRouteToGoogleNeural2(targetLanguage) {
    return GOOGLE_NEURAL2_ROUTE_LANGUAGES.has(String(targetLanguage || "").toLowerCase().trim());
}

function mapGoogleNeural2LanguageCode(targetLanguage) {
    const map = {
        English: "en-GB", French: "fr-FR", German: "de-DE", Mandarin: "cmn-CN",
        Hindi: "hi-IN", Urdu: "ur-IN", Portuguese: "pt-PT"
    };
    return map[targetLanguage] || mapLanguageCode(targetLanguage);
}

function buildTtsProviderChain(requestedProvider, targetLanguage) {
    const preferred = String(requestedProvider || process.env.TTS_PROVIDER || "narakeet").toLowerCase().trim();
    if (shouldRouteToGoogleNeural2(targetLanguage)) {
        return ["google", "narakeet"];
    }
    if (preferred === "narakeet") {
        return ["narakeet"];
    }
    return [preferred, "google"].filter((v, i, arr) => KNOWN_TTS_PROVIDERS.includes(v) && arr.indexOf(v) === i);
}

function normalizeCacheText(text) {
    return String(text || "").toLowerCase().replace(/\s+/g, " ").trim();
}

function shouldCacheAudioText(text) {
    const normalized = normalizeCacheText(text);
    if (!normalized) return false;
    if (normalized.length > AUDIO_CACHE_MAX_TEXT_LENGTH) return false;
    const tokenCount = normalized.split(" ").filter(Boolean).length;
    return tokenCount <= 40;
}

function buildAudioCacheKey({ text, targetLanguage, requestedVoiceName, provider }) {
    const normalizedText = normalizeCacheText(text);
    const voice = String(requestedVoiceName || "").trim();
    const lang = String(targetLanguage || "").trim();
    const prov = String(provider || "").trim();
    const digest = crypto.createHash("sha256")
        .update([normalizedText, lang, voice, prov].join("|"))
        .digest("hex");
    const ext = "mp3";
    const objectPath = `${AUDIO_CACHE_OBJECT_PREFIX}/${prov}/${lang}/${voice}/${digest}.${ext}`;
    return { digest, objectPath };
}

function setMemoryCachedAudio(cacheKey, audioContent) {
    if (!cacheKey || !audioContent) return;
    audioBase64MemoryCache.delete(cacheKey);
    audioBase64MemoryCache.set(cacheKey, { audioContent, cachedAtMs: Date.now() });
    while (audioBase64MemoryCache.size > AUDIO_MEMORY_CACHE_LIMIT) {
        const oldestKey = audioBase64MemoryCache.keys().next().value;
        if (!oldestKey) break;
        audioBase64MemoryCache.delete(oldestKey);
    }
}

function getMemoryCachedAudio(cacheKey) {
    if (!cacheKey) return null;
    const hit = audioBase64MemoryCache.get(cacheKey);
    if (!hit) return null;
    audioBase64MemoryCache.delete(cacheKey);
    audioBase64MemoryCache.set(cacheKey, hit);
    return hit;
}

async function createSignedReadUrl(file) {
    try {
        const [url] = await file.getSignedUrl({
            version: "v4", action: "read",
            expires: Date.now() + (AUDIO_CACHE_SIGNED_URL_TTL_HOURS * 60 * 60 * 1000),
        });
        return url;
    } catch { return null; }
}

async function getCachedNarakeetAudio({ text, targetLanguage, requestedVoiceName }) {
    if (!shouldCacheAudioText(text)) return null;
    const { digest, objectPath } = buildAudioCacheKey({ text, targetLanguage, requestedVoiceName, provider: "narakeet" });
    const memoryHit = getMemoryCachedAudio(digest);
    if (memoryHit?.audioContent) {
        return { audioContent: memoryHit.audioContent, cacheHit: true, cacheLayer: "memory", cacheKey: digest, audioUrl: null };
    }
    try {
        const bucket = admin.storage().bucket();
        const file = bucket.file(objectPath);
        const [exists] = await file.exists();
        if (!exists) return null;
        const [bytes] = await file.download();
        if (!bytes?.length) return null;
        const audioContent = Buffer.from(bytes).toString("base64");
        setMemoryCachedAudio(digest, audioContent);
        return { audioContent, cacheHit: true, cacheLayer: "storage", cacheKey: digest, audioUrl: await createSignedReadUrl(file) };
    } catch (error) { return null; }
}

async function putCachedNarakeetAudio({ text, targetLanguage, requestedVoiceName, audioContent }) {
    if (!audioContent || !shouldCacheAudioText(text)) return { cacheKey: null, audioUrl: null };
    const { digest, objectPath } = buildAudioCacheKey({ text, targetLanguage, requestedVoiceName, provider: "narakeet" });
    setMemoryCachedAudio(digest, audioContent);
    try {
        const bucket = admin.storage().bucket();
        const file = bucket.file(objectPath);
        const [exists] = await file.exists();
        if (!exists) {
            const bytes = Buffer.from(audioContent, "base64");
            await file.save(bytes, {
                resumable: false,
                metadata: {
                    contentType: "audio/mpeg",
                    cacheControl: "public,max-age=2592000",
                    metadata: { cacheVersion: "v1" },
                },
            });
        }
        return { cacheKey: digest, audioUrl: await createSignedReadUrl(file) };
    } catch (error) { return { cacheKey: digest, audioUrl: null }; }
}

function sleep(ms) { return new Promise((resolve) => setTimeout(resolve, ms)); }

async function synthesizeWithNarakeet({ text, requestedVoiceName }) {
    const narakeetApiKey = String(process.env.NARAKEET_API_KEY || "").trim();
    const voice = String(requestedVoiceName || "Aletta").trim();
    const failedResult = { audioContent: null, voiceLanguageUsed: null, voiceGenderUsed: null, voiceNameUsed: voice, ttsProviderUsed: "narakeet" };
    if (!narakeetApiKey) return failedResult;
    const submitUrl = `https://api.narakeet.com/text-to-speech/mp3?voice=${encodeURIComponent(voice)}`;
    const submitResp = await fetch(submitUrl, {
        method: "POST",
        headers: { "x-api-key": narakeetApiKey, "Content-Type": "text/plain", "Accept": "application/json, audio/mpeg, audio/*" },
        body: text,
    });
    if (!submitResp.ok) return failedResult;
    const submitContentType = String(submitResp.headers.get("content-type") || "").toLowerCase();
    if (submitContentType.includes("audio/")) {
        const submitAudioBuffer = Buffer.from(await submitResp.arrayBuffer());
        if (submitAudioBuffer.length) {
            return { audioContent: submitAudioBuffer.toString("base64"), voiceLanguageUsed: null, voiceGenderUsed: null, voiceNameUsed: voice, ttsProviderUsed: "narakeet" };
        }
        return failedResult;
    }
    let submitJson = await submitResp.json().catch(() => null);
    const statusUrl = String(submitJson?.statusUrl || "").trim();
    if (!statusUrl) return failedResult;
    for (let attempt = 0; attempt < 40; attempt++) {
        await sleep(attempt < 8 ? 250 : 500);
        const pollResp = await fetch(statusUrl, { method: "GET", headers: { "x-api-key": narakeetApiKey, "Accept": "application/json, audio/mpeg, audio/*" } });
        if (!pollResp.ok) continue;
        const pollContentType = String(pollResp.headers.get("content-type") || "").toLowerCase();
        if (pollContentType.includes("audio/")) {
            const directAudioBuffer = Buffer.from(await pollResp.arrayBuffer());
            if (directAudioBuffer.length) {
                return { audioContent: directAudioBuffer.toString("base64"), voiceLanguageUsed: null, voiceGenderUsed: null, voiceNameUsed: voice, ttsProviderUsed: "narakeet" };
            }
            break;
        }
        let pollJson = await pollResp.json().catch(() => null);
        if (pollJson?.finished === true && pollJson?.succeeded === true) {
            const resultUrl = String(pollJson?.result || "").trim();
            if (!resultUrl) break;
            const audioResp = await fetch(resultUrl, { method: "GET", headers: { "x-api-key": narakeetApiKey, "Accept": "audio/mpeg, audio/*" } });
            if (!audioResp.ok) break;
            const audioBuffer = Buffer.from(await audioResp.arrayBuffer());
            if (!audioBuffer.length) break;
            return { audioContent: audioBuffer.toString("base64"), voiceLanguageUsed: null, voiceGenderUsed: null, voiceNameUsed: voice, ttsProviderUsed: "narakeet" };
        }
        if (pollJson?.finished === true && !pollJson?.succeeded) break;
    }
    return failedResult;
}

const ZA_FALLBACK_CODE = "en-ZA";

async function synthesizeBestSpeech({ text, requestedCode, requestedGender }) {
    const voices = await getCachedVoices();
    const fallbackCodes = [requestedCode, ZA_FALLBACK_CODE].filter((v, i, arr) => arr.indexOf(v) === i);
    const genderAttempts = buildGenderAttempts(requestedGender);
    for (const code of fallbackCodes) {
        const matchingVoices = sortVoicesByQuality(voices.filter((v) => (v.languageCodes || []).includes(code)));
        for (const voice of matchingVoices.slice(0, 8)) {
            for (const gender of genderAttempts) {
                try {
                    const [ttsResponse] = await getTtsClient().synthesizeSpeech({
                        input: { text }, voice: { languageCode: code, name: voice.name, ssmlGender: gender },
                        audioConfig: { audioEncoding: "MP3", speakingRate: 0.95 },
                    });
                    if (ttsResponse?.audioContent) {
                        return { audioContent: ttsResponse.audioContent.toString("base64"), voiceLanguageUsed: code, voiceGenderUsed: gender, voiceNameUsed: voice.name };
                    }
                } catch (e) {}
            }
        }
        for (const gender of genderAttempts) {
            try {
                const [ttsResponse] = await getTtsClient().synthesizeSpeech({
                    input: { text }, voice: { languageCode: code, ssmlGender: gender },
                    audioConfig: { audioEncoding: "MP3", speakingRate: 0.95 },
                });
                if (ttsResponse?.audioContent) {
                    return { audioContent: ttsResponse.audioContent.toString("base64"), voiceLanguageUsed: code, voiceGenderUsed: gender, voiceNameUsed: "AUTO" };
                }
            } catch (e) {}
        }
    }
    return { audioContent: null, voiceLanguageUsed: requestedCode, voiceGenderUsed: requestedGender, voiceNameUsed: null };
}

async function synthesizeNeural2Speech({ text, requestedCode, requestedGender }) {
    const voices = await getCachedVoices();
    const genderAttempts = buildGenderAttempts(requestedGender);
    const neural2Voices = sortVoicesByQuality(voices.filter((v) => (v.languageCodes || []).includes(requestedCode) && String(v?.name || "").toLowerCase().includes("neural2")));
    for (const voice of neural2Voices.slice(0, 8)) {
        for (const gender of genderAttempts) {
            try {
                const [ttsResponse] = await getTtsClient().synthesizeSpeech({
                    input: { text }, voice: { languageCode: requestedCode, name: voice.name, ssmlGender: gender },
                    audioConfig: { audioEncoding: "MP3", speakingRate: 0.95 },
                });
                if (ttsResponse?.audioContent) {
                    return { audioContent: ttsResponse.audioContent.toString("base64"), voiceLanguageUsed: requestedCode, voiceGenderUsed: gender, voiceNameUsed: voice.name };
                }
            } catch (e) {}
        }
    }
    return { audioContent: null, voiceLanguageUsed: requestedCode, voiceGenderUsed: requestedGender, voiceNameUsed: null };
}

async function synthesizeWithProviderChain({ text, targetLanguage, requestedCode, requestedGender, requestedProvider, requestedVoiceName }) {
    const providerChain = buildTtsProviderChain(requestedProvider, targetLanguage);
    const googleNeural2Route = shouldRouteToGoogleNeural2(targetLanguage);
    const googleRequestedCode = googleNeural2Route ? mapGoogleNeural2LanguageCode(targetLanguage) : requestedCode;
    let lastResult = null;
    for (const provider of providerChain) {
        if (provider === "narakeet") {
            const cached = await getCachedNarakeetAudio({ text, targetLanguage, requestedVoiceName });
            if (cached?.audioContent) {
                return { audioContent: cached.audioContent, voiceLanguageUsed: null, voiceGenderUsed: null, voiceNameUsed: String(requestedVoiceName || "Aletta").trim(), ttsProviderUsed: "narakeet", ttsProviderChain: providerChain, cacheHit: true, cacheLayer: cached.cacheLayer, cacheKey: cached.cacheKey, audioUrl: cached.audioUrl };
            }
            const narakeetResult = await synthesizeWithNarakeet({ text, requestedVoiceName });
            const decorated = { ...narakeetResult, ttsProviderUsed: "narakeet", ttsProviderChain: providerChain, cacheHit: false, cacheLayer: null, cacheKey: null, audioUrl: null };
            if (decorated.audioContent) {
                const stored = await putCachedNarakeetAudio({ text, targetLanguage, requestedVoiceName, audioContent: decorated.audioContent });
                decorated.cacheKey = stored.cacheKey; decorated.audioUrl = stored.audioUrl;
                return decorated;
            }
            lastResult = decorated; continue;
        }
        if (provider === "google") {
            const googleResult = googleNeural2Route ? await synthesizeNeural2Speech({ text, requestedCode: googleRequestedCode, requestedGender }) : await synthesizeBestSpeech({ text, requestedCode, requestedGender });
            const decorated = { ...googleResult, ttsProviderUsed: "google", ttsProviderChain: providerChain, cacheHit: false, cacheLayer: null, cacheKey: null, audioUrl: null };
            if (decorated.audioContent) return decorated;
            lastResult = decorated; continue;
        }
    }
    return lastResult || { audioContent: null, voiceLanguageUsed: requestedCode, voiceGenderUsed: requestedGender, voiceNameUsed: null, ttsProviderUsed: "google", ttsProviderChain: ["google"] };
}

function mapLanguageCode(targetLanguage) {
    const map = { English: "en-ZA", Dutch: "nl-NL", isiZulu: "zu-ZA", Sepedi: "nso-ZA", Xitsonga: "ts-ZA", Tshivenda: "ve-ZA", Afrikaans: "af-ZA", Sesotho: "st-ZA", Setswana: "tn-ZA", Yoruba: "yo-NG", Hausa: "ha-NE", "Akan (Ghana)": "ak-GH", "Wolof (Senegal)": "wo-SN", "Kiswahili (Kenya/Tanzania)": "sw-KE", Amharic: "am-ET", "Afaan Oromoo": "om-ET", Somali: "so-SO", "Kinyarwanda (Rwanda)": "rw-RW" };
    return map[targetLanguage] || "en-ZA";
}

function mapGender(isMale) { return isMale ? "MALE" : "FEMALE"; }

function extractTextFromGeminiStreamPayload(payload) {
    const lines = payload.split(/\r?\n/);
    const chunks = [];
    for (const line of lines) {
        const trimmed = line.trim();
        if (!trimmed.startsWith("data:")) continue;
        const jsonPart = trimmed.slice(5).trim();
        if (!jsonPart || jsonPart === "[DONE]") continue;
        try {
            const parsed = JSON.parse(jsonPart);
            const candidates = parsed.candidates || [];
            for (const candidate of candidates) {
                const parts = candidate?.content?.parts || [];
                for (const part of parts) if (typeof part?.text === "string" && part.text.trim()) chunks.push(part.text);
            }
        } catch {}
    }
    if (chunks.length > 0) return chunks.join("").trim();
    try {
        const parsed = JSON.parse(payload);
        const parts = parsed?.candidates?.[0]?.content?.parts || [];
        const text = parts.map((p) => (typeof p?.text === "string" ? p.text : "")).join("").trim();
        return text || null;
    } catch { return null; }
}

async function translateWithGemini(text, targetLanguage, isRespectMode, preferredModel) {
    const apiKey = process.env.GEMINI_API_KEY;
    if (!apiKey) throw new Error("Missing GEMINI_API_KEY secret in function runtime.");
    const prompt = `You are an expert translator for South African languages. Translate the following text into ${targetLanguage || "isiZulu"}. ${isRespectMode ? "IMPORTANT: Use the most formal, respectful version." : "Use casual language."} Text: "${text}" Return ONLY the translated string.`;
    const modelCandidates = [preferredModel, process.env.GEMINI_MODEL, "gemini-2.0-flash-live-001", "gemini-2.5-flash"].filter((v, i, arr) => typeof v === "string" && v.trim() && arr.indexOf(v) === i);
    let lastError = null;
    for (const model of modelCandidates) {
        const url = `https://generativelanguage.googleapis.com/v1beta/models/${encodeURIComponent(model)}:streamGenerateContent?alt=sse&key=${encodeURIComponent(apiKey)}`;
        const response = await fetch(url, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ contents: [{ parts: [{ text: prompt }] }], generationConfig: { temperature: 0.2 } }) });
        const bodyText = await response.text();
        if (!response.ok) { lastError = new Error(`Gemini model ${model} failed: [${response.status}] ${bodyText}`); continue; }
        const translated = extractTextFromGeminiStreamPayload(bodyText);
        if (translated) return { translatedText: translated, modelUsed: model };
        lastError = new Error(`Gemini model ${model} returned no text content.`);
    }
    throw lastError || new Error("All Gemini models failed.");
}

function getAllowedOrigins() {
    const raw = String(process.env.ALLOWED_ORIGINS || "").trim();
    return raw ? raw.split(",").map((o) => o.trim()).filter(Boolean) : [];
}

function isOriginAllowed(origin) {
    const allowed = getAllowedOrigins();
    return allowed.length === 0 || !origin || allowed.includes(origin);
}

function enforceRequestGuardrails(req, res) {
    if (req.method !== "POST") { res.status(405).send({ error: "Method Not Allowed. Use POST." }); return false; }
    const origin = String(req.headers.origin || "").trim();
    if (!isOriginAllowed(origin)) { res.status(403).send({ error: "Origin not allowed.", details: "Set ALLOWED_ORIGINS to a comma-separated allowlist for web clients." }); return false; }
    const declaredLength = Number(req.headers["content-length"] || 0);
    if (Number.isFinite(declaredLength) && declaredLength > MAX_CONTENT_LENGTH_BYTES) { res.status(413).send({ error: "Payload too large.", maxBytes: MAX_CONTENT_LENGTH_BYTES }); return false; }
    return true;
}

// Handlers
exports.handleProcessSpeech = (req, res) => {
    cors(req, res, async () => {
        try {
            if (!enforceRequestGuardrails(req, res)) return;
            const authHeader = String(req.headers.authorization || "");
            if (!authHeader.startsWith("Bearer ")) return res.status(401).send({ error: "Missing Authorization bearer token." });
            const idToken = authHeader.slice("Bearer ".length).trim();
            if (!idToken) return res.status(401).send({ error: "Empty Authorization bearer token." });
            try { await admin.auth().verifyIdToken(idToken); } catch { return res.status(401).send({ error: "Unauthorized" }); }
            const { text, targetLanguage, isRespectMode, isMale, model, ttsProvider, skipTranslation, voiceName } = req.body;
            const inputText = String(text || "").trim();
            if (!inputText) return res.status(400).send({ error: "No text provided" });
            if (inputText.length > MAX_TEXT_LENGTH) return res.status(413).send({ error: "Input text too long", maxCharacters: MAX_TEXT_LENGTH });
            const shouldSkipTranslation = skipTranslation === true;
            let translatedText = inputText; let modelUsed = null;
            if (!shouldSkipTranslation) {
                const translationResult = await translateWithGemini(inputText, targetLanguage, isRespectMode, model);
                translatedText = translationResult.translatedText; modelUsed = translationResult.modelUsed;
            }
            const requestedCode = mapLanguageCode(targetLanguage);
            const requestedGender = mapGender(isMale !== false);
            const ttsResult = await synthesizeWithProviderChain({ text: translatedText, targetLanguage, requestedCode, requestedGender, requestedProvider: ttsProvider, requestedVoiceName: voiceName });
            res.status(200).send({ translation: translatedText, audioContent: ttsResult.audioContent, voiceLanguageUsed: ttsResult.voiceLanguageUsed, voiceGenderUsed: ttsResult.voiceGenderUsed, voiceNameUsed: ttsResult.voiceNameUsed, ttsProviderUsed: ttsResult.ttsProviderUsed, ttsProviderChain: ttsResult.ttsProviderChain, cacheHit: ttsResult.cacheHit === true, cacheLayer: ttsResult.cacheLayer || null, cacheKey: ttsResult.cacheKey || null, audioUrl: ttsResult.audioUrl || null, modelUsed, skipTranslation: shouldSkipTranslation, status: "success" });
        } catch (error) {
            console.error("Translation Error:", error);
            const details = String(error?.message || "Unknown error");
            res.status(500).send({ error: "Translation Failed", details, hint: details.includes("API_KEY_INVALID") ? "GEMINI_API_KEY is invalid/expired." : undefined });
        }
    });
};

exports.handleLiveHealthCheck = (req, res) => {
    cors(req, res, async () => {
        try {
            if (!enforceRequestGuardrails(req, res)) return;
            const authHeader = String(req.headers.authorization || "");
            if (!authHeader.startsWith("Bearer ")) return res.status(401).send({ error: "Missing Authorization bearer token." });
            const idToken = authHeader.slice("Bearer ".length).trim();
            if (!idToken) return res.status(401).send({ error: "Empty Authorization bearer token." });
            try { await admin.auth().verifyIdToken(idToken); } catch { return res.status(401).send({ error: "Unauthorized" }); }
            const apiKey = process.env.GEMINI_API_KEY;
            if (!apiKey) return res.status(500).send({ error: "Missing GEMINI_API_KEY secret." });
            const listUrl = `https://generativelanguage.googleapis.com/v1beta/models?key=${encodeURIComponent(apiKey)}`;
            const response = await fetch(listUrl);
            const bodyText = await response.text();
            if (!response.ok) return res.status(502).send({ error: "Live model health check failed", details: bodyText });
            const payload = JSON.parse(bodyText);
            const models = payload?.models || [];
            const liveModels = models.filter((m) => m?.supportedGenerationMethods?.includes("bidiGenerateContent"));
            res.status(200).send({ status: "ok", mode: "live-health", availableLiveModels: liveModels.map((m) => m.name) });
        } catch (error) { res.status(500).send({ error: "Live health check failed", details: String(error?.message || error) }); }
    });
};

exports.handleTtsProviderReadiness = (req, res) => {
    cors(req, res, async () => {
        if (req.method !== "GET") return res.status(405).send({ error: "Method Not Allowed." });
        if (!isOriginAllowed(String(req.headers.origin || "").trim())) return res.status(403).send({ error: "Origin not allowed." });
        res.status(200).send({ status: "ok", providers: { google: { configured: true }, narakeet: { configured: Boolean(process.env.NARAKEET_API_KEY) } } });
    });
};
