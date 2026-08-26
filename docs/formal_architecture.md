# Formal Architectural Overview - Limpopo Voice

## 1. System Component Diagram

```mermaid
componentDiagram
    component [Flutter App] as App
    component [Firebase Auth] as Auth
    component [Cloud Firestore] as DB
    component [Cloud Functions] as Backend
    component [Gemini API] as AI
    component [Google/Narakeet TTS] as TTS

    App --> Auth : Authenticates
    App --> DB : Reads/Writes Data
    App --> Backend : Calls APIs
    Backend --> AI : Requests Translation
    Backend --> TTS : Requests Speech
    Backend --> DB : Updates Credits
```

## 2. Component Detailed Description

### 2.1 Frontend (Flutter App)
- **Directory**: `lib/`
- **Responsibility**: Provides the user interface, handles user authentication (via Firebase Auth), manages local state (e.g., `_isListening`, `_credits`), handles speech-to-text input, renders translation results, and facilitates payment flows (Paystack).

### 2.2 Backend (Cloud Functions)
- **Directory**: `functions/`
- **Responsibility**: Hosted on Google Cloud (region: `africa-south1`). Handles secure API calls to external services (Gemini, Narakeet, Paystack) to protect API keys. Manages credit deduction logic and transaction verification.

### 2.3 Services & Infrastructure
- **Firebase Auth**: Manages anonymous and authenticated user sessions.
- **Cloud Firestore**: Stores user profiles, credit balances, transaction history, and organization data.
- **Gemini API**: Generative AI service for high-quality language translation.
- **TTS Services (Google Neural2/Narakeet)**: Text-to-speech engine for generating audio from translated text.

## 3. Data Flow Analysis

### 3.1 Translation and Audio Generation Flow
1.  **Request Initiation**: The user interacts with the Flutter app to record speech or enter text.
2.  **Authentication**: The app ensures the user is authenticated (or anonymous) and gets a valid Firebase ID Token.
3.  **Backend Call**: The app calls the `processSpeech` Cloud Function (`functions/speech_processor.js`) via HTTP POST, passing the text, target language, and ID token in the Authorization header.
4.  **Backend Processing**:
    *   The function verifies the ID token.
    *   It calls the **Gemini API** for translation.
    *   It determines the appropriate TTS provider (Google or Narakeet) and calls the respective API.
5.  **Response**: The function returns a JSON payload to the app containing the translated text and the base64-encoded audio content.
6.  **Client Handling**: The app decodes the audio, caches it locally for performance, and plays the audio using `audioplayers`.

## 4. Security and Authentication Review

### 4.1 Authentication
- The app uses **Firebase Authentication** to manage user identities, supporting anonymous guest sessions and authenticated users (Google, Email/Password).
- Secure API interactions are enforced by requiring a valid Firebase ID Token in the `Authorization` header of all Cloud Function requests.

### 4.2 Security Rules (Firestore)
- **Data Isolation**: Firestore rules (`firestore.rules`) enforce strict data isolation using the `isSelf(userId)` function, ensuring users can only read/write their own profile documents.
- **Organization Security**: Organization data is protected with ownership checks (`isOrgOwner`) and strict constraints on credit spending for members (`memberSpendingExactlyOneCredit`).

### 4.3 Sensitive Data Handling
- API keys (Gemini, Narakeet, Paystack) are stored securely in **Firebase Secrets Manager** and are never exposed in the client-side code.
- Cloud Functions access these secrets at runtime, ensuring they are not leaked in source code or deployment logs.
