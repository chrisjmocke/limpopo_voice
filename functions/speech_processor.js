const { HttpsError } = require("firebase-functions/v2/https");
const admin = require("firebase-admin");
const crypto = require("crypto");
const cors = require("cors")({ origin: true });

// Configuration and Constants
const API_COST_PER_UNIT = 0.0029;
const VOICE_CACHE_TTL_MS = 10 * 60 * 1000;
const MAX_TEXT_LENGTH = Number(process.env.MAX_TEXT_LENGTH || 600);
const MAX_CONTENT_LENGTH_BYTES = Number(process.env.MAX_CONTENT_LENGTH_BYTES || 32 * 1024);
const AUDIO_MEMORY_CACHE_LIMIT = Number(process.env.AUDIO_MEMORY_CACHE_LIMIT || 400);
const AUDIO_CACHE_MAX_TEXT_LENGTH = Number(process.env.AUDIO_CACHE_MAX_TEXT_LENGTH || 180);
const AUDIO_CACHE_SIGNED_URL_TTL_HOURS = Number(process.env.AUDIO_CACHE_SIGNED_URL_TTL_HOURS || 24);
const AUDIO_CACHE_OBJECT_PREFIX = String(process.env.AUDIO_CACHE_OBJECT_PREFIX || "tts-cache").trim();

const KNOWN_TTS_PROVIDERS = ["narakeet"];
const NARAKEET_VOICE_ALTERNATIVES = {
    'Afrikaans': ['Rolanda', 'Aletta'],
    'English': ['Aletta', 'Rolanda'],
    'isiNdebele': ['Dumisani', 'Nandi'],
    'isiXhosa': ['Lindiwe', 'Nandi'],
    'isiZulu': ['Nandi', 'Lindiwe'],
    'Sepedi': ['Mpho', 'Palesa'],
    'Sesotho': ['Palesa', 'Mpho'],
    'Setswana': ['Bokang', 'Mpho'],
    'siSwati': ['Nomcebo', 'Nandi'],
    'Tshivenda': ['Mulalo', 'Dumisani'],
    'Xitsonga': ['Basetsana', 'Lindiwe'],
};

// State
const audioBase64MemoryCache = new Map();

// Helper Functions

function buildGenderAttempts(requestedGender) {
    const attempts = [requestedGender, "NEUTRAL", "FEMALE", "MALE"];
    return attempts.filter((v, i, arr) => typeof v === "string" && arr.indexOf(v) === i);
}

function buildTtsProviderChain(requestedProvider, targetLanguage) {
    return ["narakeet"];
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

async function attemptNarakeetSynthesis({ text, voice, narakeetApiKey }) {
    const submitUrl = `https://api.narakeet.com/text-to-speech/mp3?voice=${encodeURIComponent(voice)}`;
    const submitResp = await fetch(submitUrl, {
        method: "POST",
        headers: { "x-api-key": narakeetApiKey, "Content-Type": "text/plain", "Accept": "application/json, audio/mpeg, audio/*" },
        body: text,
    });
    if (!submitResp.ok) {
        const errorBody = await submitResp.text().catch(() => "Could not read error body");
        console.error(`Narakeet initial request failed for voice ${voice}: ${submitResp.status} ${submitResp.statusText}. Body: ${errorBody}`);
        return null;
    }
    const submitContentType = String(submitResp.headers.get("content-type") || "").toLowerCase();
    if (submitContentType.includes("audio/")) {
        const submitAudioBuffer = Buffer.from(await submitResp.arrayBuffer());
        if (submitAudioBuffer.length) {
            return { audioContent: submitAudioBuffer.toString("base64"), voiceLanguageUsed: null, voiceGenderUsed: null, voiceNameUsed: voice, ttsProviderUsed: "narakeet" };
        }
        console.error("Narakeet initial audio response was empty.");
        return null;
    }
    let submitJson = await submitResp.json().catch((e) => {
        console.error(`Narakeet initial JSON parse failed: ${e}`);
        return null;
    });
    const statusUrl = String(submitJson?.statusUrl || "").trim();
    if (!statusUrl) {
        console.error("Narakeet initial response missing statusUrl.", submitJson);
        return null;
    }
    for (let attempt = 0; attempt < 40; attempt++) {
        await sleep(attempt < 8 ? 250 : 500);
        const pollResp = await fetch(statusUrl, { method: "GET", headers: { "x-api-key": narakeetApiKey, "Accept": "application/json, audio/mpeg, audio/*" } });
        if (!pollResp.ok) {
            console.warn(`Narakeet poll attempt ${attempt} failed for voice ${voice}: ${pollResp.status} ${pollResp.statusText}`);
            continue;
        }
        const pollContentType = String(pollResp.headers.get("content-type") || "").toLowerCase();
        if (pollContentType.includes("audio/")) {
            const directAudioBuffer = Buffer.from(await pollResp.arrayBuffer());
            if (directAudioBuffer.length) {
                return { audioContent: directAudioBuffer.toString("base64"), voiceLanguageUsed: null, voiceGenderUsed: null, voiceNameUsed: voice, ttsProviderUsed: "narakeet" };
            }
            console.error("Narakeet direct audio poll response was empty.");
            break;
        }
        let pollJson = await pollResp.json().catch((e) => {
            console.error(`Narakeet poll JSON parse failed: ${e}`);
            return null;
        });
        if (pollJson?.finished === true && pollJson?.succeeded === true) {
            const resultUrl = String(pollJson?.result || "").trim();
            if (!resultUrl) {
                console.error("Narakeet poll result missing resultUrl.", pollJson);
                break;
            }
            const audioResp = await fetch(resultUrl, { method: "GET", headers: { "x-api-key": narakeetApiKey, "Accept": "audio/mpeg, audio/*" } });
            if (!audioResp.ok) {
                console.error(`Narakeet final audio fetch failed: ${audioResp.status} ${audioResp.statusText}`);
                break;
            }
            const audioBuffer = Buffer.from(await audioResp.arrayBuffer());
            if (!audioBuffer.length) {
                console.error("Narakeet final audio response was empty.");
                break;
            }
            return { audioContent: audioBuffer.toString("base64"), voiceLanguageUsed: null, voiceGenderUsed: null, voiceNameUsed: voice, ttsProviderUsed: "narakeet" };
        }
        if (pollJson?.finished === true && !pollJson?.succeeded) {
            console.error(`Narakeet synthesis failed for voice ${voice} according to poll response.`, pollJson);
            break;
        }
    }
    return null;
}

async function synthesizeWithNarakeetConcurrent({ text, targetLanguage, narakeetApiKey }) {
    const voices = NARAKEET_VOICE_ALTERNATIVES[targetLanguage] || ['Aletta'];
    const promises = voices.map(async (voice) => {
        const result = await attemptNarakeetSynthesis({ text, voice, narakeetApiKey });
        if (!result) throw new Error(`Failed for ${voice}`);
        return result;
    });
    
    try {
        return await Promise.any(promises);
    } catch (e) {
        console.error("All Narakeet synthesis attempts failed", e);
        return null;
    }
}

async function synthesizeWithNarakeet({ text, requestedVoiceName, targetLanguage }) {
    const narakeetApiKey = String(process.env.NARAKEET_API_KEY || "").trim();
    const failedResult = { audioContent: null, voiceLanguageUsed: null, voiceGenderUsed: null, voiceNameUsed: requestedVoiceName || 'Default', ttsProviderUsed: "narakeet" };
    
    if (!narakeetApiKey) return failedResult;
    
    // If a specific voice is requested, try that one first.
    if (requestedVoiceName) {
        const result = await attemptNarakeetSynthesis({ text, voice: requestedVoiceName, narakeetApiKey });
        if (result) return result;
    }
    
    // Otherwise or if the specific voice failed, try all concurrently
    const result = await synthesizeWithNarakeetConcurrent({ text, targetLanguage, narakeetApiKey });
    if (result) return result;
    
    console.error(`Narakeet synthesis failed for all tried voices for ${targetLanguage}`);
    return failedResult;
}

const ZA_FALLBACK_CODE = "en-ZA";

async function synthesizeWithProviderChain({ text, targetLanguage, requestedVoiceName }) {
    const providerChain = ["narakeet"];
    const narakeetResult = await synthesizeWithNarakeet({ text, requestedVoiceName, targetLanguage });
    const decorated = { ...narakeetResult, ttsProviderChain: providerChain, cacheHit: false, cacheLayer: null, cacheKey: null, audioUrl: null };
    if (decorated.audioContent) {
        const stored = await putCachedNarakeetAudio({ text, targetLanguage, requestedVoiceName, audioContent: decorated.audioContent });
        decorated.cacheKey = stored.cacheKey; decorated.audioUrl = stored.audioUrl;
    }
    return decorated;
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
        console.log("handleProcessSpeech invoked.");
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
            const ttsResult = await synthesizeWithProviderChain({ text: translatedText, targetLanguage, requestedVoiceName: voiceName });
            if (!ttsResult?.audioContent) {
                console.error("Speech synthesis unavailable: Narakeet returned no audioContent.");
                return res.status(503).send({
                    error: "Speech synthesis unavailable",
                    details: "Narakeet is unavailable or not configured. Check the function secret and deployment.",
                    provider: "narakeet",
                    status: "error",
                    translation: translatedText,
                    modelUsed: modelUsed || null,
                    skipTranslation: shouldSkipTranslation,
                });
            }
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
