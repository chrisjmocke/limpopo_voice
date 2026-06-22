const { onCall, HttpsError, onRequest } = require("firebase-functions/v2/https");
const admin = require("firebase-admin");
const crypto = require("crypto");

if (!admin.apps.length) {
  admin.initializeApp();
}

function getPaystackSecret() {
  const secret = String(process.env.PAYSTACK_SECRET_KEY || "").trim();
  if (!secret) {
    throw new Error("PAYSTACK_SECRET_KEY secret not configured in function runtime.");
  }
  return secret;
}

function buildFallbackEmail(uid) {
  const safe = String(uid || "anon").replace(/[^a-zA-Z0-9]/g, "").toLowerCase();
  return `${safe || "anon"}@letstalk.local`;
}

const createPaystackTransaction = onCall(
  {
    region: "africa-south1",
    secrets: ["PAYSTACK_SECRET_KEY"],
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "User must be signed in");
    }

    const { amountCents, email, orgId } = request.data || {};
    if (typeof amountCents !== "number" || amountCents <= 0) {
      throw new HttpsError("invalid-argument", "Invalid amount");
    }

    const payerEmail =
      typeof email === "string" && email.includes("@")
        ? email
        : buildFallbackEmail(request.auth.uid);

    const secretKey = getPaystackSecret();
    const reference = `limpopo_${Date.now()}_${Math.random().toString(36).slice(2, 7)}`;

    const payload = {
      email: payerEmail,
      amount: Math.trunc(amountCents),
      reference,
      metadata: {
        userId: request.auth.uid,
        orgId: typeof orgId === "string" && orgId.trim() ? orgId.trim() : null,
      },
    };

    const response = await fetch("https://api.paystack.co/transaction/initialize", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${secretKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(payload),
    });

    const result = await response.json();
    if (!response.ok || !result?.status) {
      console.error("Paystack init failed", result);
      throw new HttpsError("internal", "Paystack transaction creation failed");
    }

    return {
      authorization_url: result.data?.authorization_url || null,
      access_code: result.data?.access_code || null,
      reference,
    };
  },
);

const createPaystackTransactionHttp = onRequest(
  {
    region: "africa-south1",
    secrets: ["PAYSTACK_SECRET_KEY"],
  },
  async (req, res) => {
    if (req.method !== "POST") {
      return res.status(405).send({ error: "Method Not Allowed" });
    }

    const authHeader = String(req.headers.authorization || "");
    if (!authHeader.startsWith("Bearer ")) {
      return res.status(401).send({ error: "Missing Authorization bearer token." });
    }

    const idToken = authHeader.slice("Bearer ".length).trim();
    if (!idToken) {
      return res.status(401).send({ error: "Empty Authorization bearer token." });
    }

    let decodedToken;
    try {
      decodedToken = await admin.auth().verifyIdToken(idToken);
    } catch {
      return res.status(401).send({ error: "Unauthorized" });
    }

    const { amountCents, email, orgId } = req.body || {};
    if (typeof amountCents !== "number" || amountCents <= 0) {
      return res.status(400).send({ error: "Invalid amount" });
    }

    const payerEmail =
      typeof email === "string" && email.includes("@")
        ? email
        : buildFallbackEmail(decodedToken.uid);

    try {
      const secretKey = getPaystackSecret();
      const reference = `limpopo_${Date.now()}_${Math.random().toString(36).slice(2, 7)}`;

      const response = await fetch("https://api.paystack.co/transaction/initialize", {
        method: "POST",
        headers: {
          Authorization: `Bearer ${secretKey}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          email: payerEmail,
          amount: Math.trunc(amountCents),
          reference,
          metadata: {
            userId: decodedToken.uid,
            orgId: typeof orgId === "string" && orgId.trim() ? orgId.trim() : null,
          },
        }),
      });

      const result = await response.json();
      if (!response.ok || !result?.status) {
        console.error("Paystack init failed", result);
        return res.status(502).send({ error: "Paystack transaction creation failed" });
      }

      return res.status(200).send({
        authorization_url: result.data?.authorization_url || null,
        access_code: result.data?.access_code || null,
        reference,
      });
    } catch (error) {
      console.error("Paystack HTTP init failed", error);
      return res.status(500).send({
        error: "Paystack transaction creation failed",
        details: String(error?.message || error),
      });
    }
  },
);

const paystackWebhook = onRequest(
  {
    region: "africa-south1",
    secrets: ["PAYSTACK_SECRET_KEY"],
  },
  async (req, res) => {
    if (req.method !== "POST") {
      return res.status(405).send("Method Not Allowed");
    }

    const signature = String(req.headers["x-paystack-signature"] || "");
    if (!signature) {
      return res.status(400).send("Missing signature");
    }

    const secretKey = getPaystackSecret();
    const rawBody = req.rawBody || Buffer.from(JSON.stringify(req.body || {}));
    const hash = crypto.createHmac("sha512", secretKey).update(rawBody).digest("hex");

    if (hash !== signature) {
      console.warn("Invalid Paystack webhook signature");
      return res.status(400).send("Invalid signature");
    }

    const event = req.body || {};
    if (event.event !== "charge.success") {
      return res.status(200).send("Ignored");
    }

    const data = event.data || {};
    const metadata = data.metadata || {};
    const userId = metadata.userId;
    const orgId = metadata.orgId;

    if (!userId) {
      console.error("Missing userId in webhook metadata");
      return res.status(400).send("Missing metadata");
    }

    const amount = Number(data.amount || 0);
    const creditsToAdd = Math.floor(amount / 100);

    const db = admin.firestore();
    const batch = db.batch();

    const userRef = db.collection("users").doc(String(userId));
    batch.set(
      userRef,
      {
        credits: admin.firestore.FieldValue.increment(creditsToAdd),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true },
    );

    if (typeof orgId === "string" && orgId.trim()) {
      const orgRef = db.collection("organizations").doc(orgId.trim());
      batch.set(
        orgRef,
        {
          sharedCredits: admin.firestore.FieldValue.increment(creditsToAdd),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
    }

    await batch.commit();
    console.log(`Added ${creditsToAdd} credits to user ${userId}${orgId ? ` and org ${orgId}` : ""}`);
    return res.status(200).send("OK");
  },
);

module.exports = {
  createPaystackTransaction,
  createPaystackTransactionHttp,
  paystackWebhook,
};
