const { onRequest } = require("firebase-functions/v2/https");
const { setGlobalOptions } = require("firebase-functions/v2");
const { GoogleGenerativeAI } = require("@google/generative-ai");
const cors = require("cors")({ origin: true });

setGlobalOptions({ region: "africa-south1" });

exports.processSpeech = onRequest({ secrets: ["GEMINI_API_KEY"] }, (req, res) => {
    // 1. Handle CORS so Flutter can talk to it
    cors(req, res, async () => {
        try {
            // 2. Security Check (The Password)
            const providedPassword = req.headers['x-app-password'];
            if (providedPassword !== "MySecureSouthAfricaApp2026") {
                return res.status(401).send({ error: "Unauthorized" });
            }

            // 3. Get Data (Standard JSON format)
            const { text, targetLanguage, isRespectMode } = req.body;

            if (!text) {
                return res.status(400).send({ error: "No text provided" });
            }

            // 4. Gemini Setup
            const apiKey = process.env.GEMINI_API_KEY;
            const genAI = new GoogleGenerativeAI(apiKey);
            const model = genAI.getGenerativeModel({ model: "gemini-2.5-flash" });

            const prompt = `You are an expert translator for South African languages. 
            Translate the following text into ${targetLanguage || 'isiZulu'}. 
            ${isRespectMode ? "IMPORTANT: Use the most formal, respectful version." : "Use casual language."}
            Text: "${text}"
            Return ONLY the translated string.`;

            // 5. Generate and Send
            const result = await model.generateContent(prompt);
            const response = await result.response;
            const translatedText = response.text().trim();

            // Sending back as "translation" to match your Flutter code
            res.status(200).send({ 
                translation: translatedText,
                status: "success" 
            });

        } catch (error) {
            console.error("Gemini Error:", error);
            res.status(500).send({ error: "Translation Failed", details: error.message });
        }
    });
});