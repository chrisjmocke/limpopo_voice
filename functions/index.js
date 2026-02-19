const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { setGlobalOptions } = require("firebase-functions/v2");
const admin = require("firebase-admin");

admin.initializeApp();
const db = admin.firestore();

setGlobalOptions({
  region: "africa-south1",
});

// 🔹 Create user with starter credits (call once on app start)
exports.initializeUser = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError(
      "unauthenticated",
      "User must be authenticated"
    );
  }

  const uid = request.auth.uid;
  const userRef = db.collection("users").doc(uid);

  const userDoc = await userRef.get();

  if (!userDoc.exists) {
    await userRef.set({
      credits: 5,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    return { credits: 5 };
  }

  return { credits: userDoc.data().credits || 0 };
});

// 🔹 Speech processing (ONLY decrements credits)
exports.processSpeech = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError(
      "unauthenticated",
      "User must be authenticated"
    );
  }

  const uid = request.auth.uid;
  const userRef = db.collection("users").doc(uid);

  let remainingCredits = 0;

  await db.runTransaction(async (transaction) => {
    const userDoc = await transaction.get(userRef);

    if (!userDoc.exists) {
      throw new HttpsError(
        "failed-precondition",
        "User not initialized"
      );
    }

    const credits = userDoc.data().credits || 0;

    if (credits <= 0) {
      throw new HttpsError(
        "failed-precondition",
        "No credits remaining"
      );
    }

    remainingCredits = credits - 1;

    transaction.update(userRef, {
      credits: remainingCredits,
      lastUsed: admin.firestore.FieldValue.serverTimestamp(),
    });
  });

  return {
    translatedText: "Speech processed successfully",
    remainingCredits,
  };
});
