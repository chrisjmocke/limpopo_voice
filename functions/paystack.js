const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { onRequest } = require("firebase-functions/v2/https");
const admin = require("firebase-admin");
const crypto = require("crypto");
const fs = require("fs");
const path = require("path");

const plansPath = path.join(__dirname, "plans.json");
const plansData = JSON.parse(fs.readFileSync(plansPath, "utf8"));
const plansConfig = plansData;

const firebaseConfig = (() => {
  try {
    return process.env.FIREBASE_CONFIG ? JSON.parse(process.env.FIREBASE_CONFIG) : {};
  } catch {
    return {};
  }
})();

const projectId = process.env.GCLOUD_PROJECT || firebaseConfig.projectId || "limpopo-voice-prod";
const firestoreDatabaseId = String(process.env.FIRESTORE_DATABASE_ID || "(default)").trim() || "(default)";

if (!admin.apps.length) {
  admin.initializeApp({
    projectId,
    ...(firebaseConfig.databaseURL ? { databaseURL: firebaseConfig.databaseURL } : {}),
  });
}

function getFirestoreDb() {
  return firestoreDatabaseId === "(default)"
    ? admin.firestore()
    : admin.firestore(admin.app(), firestoreDatabaseId);
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

function getCreditsForPlanCode(planCode) {
  const normalized = String(planCode || "").trim();
  const plan = (plansConfig.plans || []).find((p) => p.code === normalized);
  return plan ? Number(plan.credits) : null;
}

function getAmountForPlanCode(planCode) {
  const normalized = String(planCode || "").trim();
  const plan = (plansConfig.plans || []).find((p) => p.code === normalized);
  return plan && Number.isFinite(Number(plan.amountCents))
    ? Number(plan.amountCents)
    : null;
}

function resolvePlanCredits(planCode) {
  return getCreditsForPlanCode(planCode);
}

function resolvePlanAmount(planCode) {
  return getAmountForPlanCode(planCode);
}

function extractSubscriptionMetadata(eventData = {}) {
  const direct = eventData || {};
  const metadata = direct.metadata || {};
  const customerMetadata = direct.customer && direct.customer.metadata ? direct.customer.metadata : {};
  const subscriptionCode = String(
    direct.subscription_code ||
    direct.subscription?.subscription_code ||
    direct.subscription?.code ||
    direct.subscription?.id ||
    direct.authorization?.subscription_code ||
    direct.authorization?.code ||
    metadata.subscriptionCode ||
    customerMetadata.subscriptionCode ||
    metadata.subscription_code ||
    "",
  ).trim() || null;

  const subscriptionToken = String(
    direct.authorization?.authorization_code ||
    direct.authorization?.token ||
    direct.subscription?.authorization?.authorization_code ||
    direct.subscription?.authorization?.token ||
    direct.customer?.authorization?.authorization_code ||
    direct.customer?.authorization?.token ||
    direct.subscription?.authorization_code ||
    direct.subscription?.token ||
    direct.token ||
    metadata.subscriptionToken ||
    customerMetadata.subscriptionToken ||
    "",
  ).trim() || null;

  return { subscriptionCode, subscriptionToken };
}

function normalizeUserId(value) {
  const text = String(value ?? "").trim();
  return text || null;
}

async function resolveWebhookUserRef(db, metadata = {}, customerInfo = {}, fallbackEmail = "") {
  const candidateIds = [
    normalizeUserId(metadata.userId),
    normalizeUserId(metadata.uid),
    normalizeUserId(metadata.authUid),
    normalizeUserId(metadata.firebaseUid),
    normalizeUserId(customerInfo.metadata?.userId),
    normalizeUserId(customerInfo.metadata?.uid),
    normalizeUserId(customerInfo.metadata?.authUid),
    normalizeUserId(customerInfo.metadata?.firebaseUid),
  ].filter(Boolean);

  for (const candidate of candidateIds) {
    const userDoc = await db.collection("users").doc(String(candidate)).get();
    if (userDoc.exists) {
      return userDoc.ref;
    }
  }

  const email = String(fallbackEmail || customerInfo.email || metadata.email || "").trim().toLowerCase();
  if (email) {
    const snapshot = await db.collection("users").where("email", "==", email).limit(1).get();
    if (!snapshot.empty) {
      return snapshot.docs[0].ref;
    }
  }

  return null;
}

async function persistSubscriptionMetadata(db, userId, overrides = {}) {
  if (!userId) return null;

  const ref = db.collection("users").doc(String(userId));
  const patch = {
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    ...(overrides.subscriptionCode !== undefined ? { subscriptionCode: overrides.subscriptionCode || null } : {}),
    ...(overrides.subscriptionToken !== undefined ? { subscriptionToken: overrides.subscriptionToken || null } : {}),
    ...(overrides.subscriptionPlanCode !== undefined ? { subscriptionPlanCode: overrides.subscriptionPlanCode || null } : {}),
    ...(overrides.monthlyRenewalActive !== undefined ? { monthlyRenewalActive: Boolean(overrides.monthlyRenewalActive) } : {}),
    ...(overrides.subscriptionStatus !== undefined ? { subscriptionStatus: overrides.subscriptionStatus || null } : {}),
  };

  if (Object.keys(patch).length <= 1) return ref;
  await ref.set(patch, { merge: true });
  return ref;
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

    const { amountCents, email, callback_url, planCode } = request.data || {};
    const normalizedPlanCode = typeof planCode === "string" ? planCode.trim() : "";
    const amountProvided = typeof amountCents === "number" && amountCents > 0;

    if (!amountProvided && !normalizedPlanCode) {
      throw new HttpsError("invalid-argument", "Provide either amountCents or planCode");
    }

    const payerEmail =
      typeof email === "string" && email.includes("@")
        ? email
        : buildFallbackEmail(request.auth.uid);

    const secretKey = getPaystackSecret();
    const reference = `limpopo_${Date.now()}_${Math.random().toString(36).slice(2, 7)}`;

    const paymentType = normalizedPlanCode ? "subscription" : "once_off";
    const payload = {
      email: payerEmail,
      reference,
      callback_url: typeof callback_url === "string" ? callback_url : undefined,
      metadata: {
        userId: request.auth.uid,
        isSubscription: Boolean(normalizedPlanCode),
        payment_type: paymentType,
      },
    };

    if (normalizedPlanCode) {
      payload.plan = normalizedPlanCode;
      payload.channels = ["card"];
    } else {
      payload.amount = Math.trunc(amountCents);
      payload.channels = ["card", "bank", "eft", "capitec_pay", "mobile_money"];
    }

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

    const { amountCents, email, callback_url, planCode, creditsToAdd, purchaseType } = req.body || {};
    const normalizedPlanCode = typeof planCode === "string" ? planCode.trim() : "";
    const amountProvided = typeof amountCents === "number" && amountCents > 0;
    const requestedCredits =
      typeof creditsToAdd === "number" && creditsToAdd > 0
        ? Math.max(0, Math.trunc(creditsToAdd))
        : null;

    if (!amountProvided && !normalizedPlanCode) {
      return res.status(400).send({ error: "Provide either amountCents or planCode." });
    }

    const payerEmail =
      typeof email === "string" && email.includes("@")
        ? email
        : buildFallbackEmail(decodedToken.uid);

    try {
      const secretKey = getPaystackSecret();
      const reference = `limpopo_${Date.now()}_${Math.random().toString(36).slice(2, 7)}`;

      const paymentType = normalizedPlanCode ? "subscription" : "once_off";
      const payload = {
        email: payerEmail,
        reference,
        callback_url: typeof callback_url === "string" ? callback_url : undefined,
        metadata: {
          userId: decodedToken.uid,
          isSubscription: Boolean(normalizedPlanCode),
          payment_type: paymentType,
          creditsToAdd: requestedCredits ?? (normalizedPlanCode ? (resolvePlanCredits(normalizedPlanCode) ?? 0) : 0),
          purchaseType: typeof purchaseType === "string" && purchaseType ? purchaseType : (normalizedPlanCode ? "monthly" : "once_off"),
        },
      };

      if (normalizedPlanCode) {
        payload.plan = normalizedPlanCode;
        payload.channels = ["card"];
        delete payload.amount;
      } else {
        payload.amount = Math.trunc(amountCents);
        payload.channels = ["card", "bank", "eft", "capitec_pay", "mobile_money"];
        delete payload.plan;
      }

      let response = await fetch("https://api.paystack.co/transaction/initialize", {
        method: "POST",
        headers: {
          Authorization: `Bearer ${secretKey}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify(payload),
      });

      let result = await response.json();

      if ((!response.ok || !result?.status) && normalizedPlanCode) {
        const fallbackAmount = resolvePlanAmount(normalizedPlanCode);
        if (fallbackAmount) {
          const fallbackPayload = {
            email: payerEmail,
            amount: fallbackAmount,
            reference: `limpopo_${Date.now()}_${Math.random().toString(36).slice(2, 7)}`,
            callback_url: typeof callback_url === "string" ? callback_url : undefined,
            metadata: {
              userId: decodedToken.uid,
              retryPlanCode: normalizedPlanCode,
            },
          };

          response = await fetch("https://api.paystack.co/transaction/initialize", {
            method: "POST",
            headers: {
              Authorization: `Bearer ${secretKey}`,
              "Content-Type": "application/json",
            },
            body: JSON.stringify(fallbackPayload),
          });

          result = await response.json();
        }
      }

      if (!response.ok || !result?.status) {
        console.error("Paystack init failed", result);
        return res.status(502).send({ error: "Paystack transaction creation failed", details: result });
      }

      if (normalizedPlanCode) {
        const { subscriptionCode, subscriptionToken } = extractSubscriptionMetadata(result?.data || {});
        if (subscriptionCode || subscriptionToken) {
          const db = getFirestoreDb();
          await persistSubscriptionMetadata(db, decodedToken.uid, {
            subscriptionCode: subscriptionCode || null,
            subscriptionToken: subscriptionToken || null,
            subscriptionPlanCode: normalizedPlanCode,
            monthlyRenewalActive: true,
            subscriptionStatus: "active_monthly_pending_confirmation",
          });
        }
      }

      return res.status(200).send({
        authorization_url: result.data?.authorization_url || null,
        access_code: result.data?.access_code || null,
        reference,
      });
    } catch (error) {
      console.error("Paystack HTTP init triggered an internal exception:", error);
      return res.status(500).send({
        error: "Paystack transaction creation failed",
        details: error.message || String(error),
        stack: error.stack || ""
      });
    }
  },
);

const cancelPaystackSubscriptionHttp = onRequest(
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

    const userId = decodedToken.uid;
    const db = getFirestoreDb();
    const userRef = db.collection("users").doc(String(userId));
    const userDoc = await userRef.get();
    const userData = userDoc.exists ? userDoc.data() || {} : {};
    const bodyCode = String(
      req.body?.subscriptionCode ||
      req.body?.code ||
      req.body?.subscription_code ||
      "",
    ).trim();
    const bodyToken = String(
      req.body?.subscriptionToken ||
      req.body?.token ||
      req.body?.authorization_code ||
      req.body?.authorizationCode ||
      "",
    ).trim();
    const subscriptionCode = bodyCode || String(
      userData.subscriptionCode ||
      userData.paystackSubscriptionCode ||
      userData.activeSubscriptionCode ||
      "",
    ).trim();
    const subscriptionToken = bodyToken || String(
      userData.subscriptionToken ||
      userData.paystackToken ||
      userData.authorizationCode ||
      userData.paystackAuthorizationCode ||
      userData.subscriptionAuthorizationCode ||
      "",
    ).trim();

    const expiryDate = new Date(Date.now() + 30 * 24 * 60 * 60 * 1000);

    if (!subscriptionCode || !subscriptionToken) {
      await userRef.set(
        {
          monthlyDebitCancelled: true,
          subscriptionStatus: "cancelled_pending_expiry",
          monthlyRenewalActive: false,
          tierActive: true,
          cancelledUntil: admin.firestore.Timestamp.fromDate(expiryDate),
          subscriptionPeriodEnd: admin.firestore.Timestamp.fromDate(expiryDate),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
      return res.status(200).send({
        ok: true,
        cancelled: false,
        reason: "No active Paystack subscription data found. Local record marked as cancelled.",
        subscriptionCode: subscriptionCode || null,
      });
    }

    try {
      const secretKey = getPaystackSecret();
      const paystackResponse = await fetch("https://api.paystack.co/subscription/disable", {
        method: "POST",
        headers: {
          Authorization: `Bearer ${secretKey}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          code: subscriptionCode,
          token: subscriptionToken,
        }),
      });

      const rawText = await paystackResponse.text();
      let result = {};
      try {
        result = rawText ? JSON.parse(rawText) : {};
      } catch {
        await userRef.set(
          {
            monthlyDebitCancelled: true,
            subscriptionStatus: "cancelled_pending_expiry",
            cancelledUntil: admin.firestore.Timestamp.fromDate(expiryDate),
            subscriptionPeriodEnd: admin.firestore.Timestamp.fromDate(expiryDate),
            monthlyRenewalActive: false,
            tierActive: true,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          { merge: true },
        );

        return res.status(200).send({
          ok: true,
          cancelled: false,
          reason: "Paystack returned a non-JSON payload, but the local subscription was marked as cancelled.",
          providerStatus: paystackResponse.status,
        });
      }

      const providerMessage = String(result?.message || "");
      const subscriptionNotFound =
        paystackResponse.status === 404 ||
        /not found|subscription.*not found|invalid.*subscription/i.test(providerMessage);

      if (!paystackResponse.ok || (!result?.status && !subscriptionNotFound)) {
        if (subscriptionNotFound) {
          await userRef.set(
            {
              monthlyDebitCancelled: true,
              subscriptionStatus: "cancelled_pending_expiry",
              cancelledUntil: admin.firestore.Timestamp.fromDate(expiryDate),
              subscriptionPeriodEnd: admin.firestore.Timestamp.fromDate(expiryDate),
              monthlyRenewalActive: false,
              tierActive: true,
              subscriptionCode: null,
              subscriptionToken: null,
              updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            },
            { merge: true },
          );
          return res.status(200).send({
            ok: true,
            cancelled: false,
            reason: "Paystack reported no active subscription; local cancellation state was applied.",
            providerStatus: paystackResponse.status,
          });
        }

        return res.status(502).send({
          error: "Paystack subscription cancellation failed",
          detail: providerMessage || "Unknown provider error",
          providerStatus: paystackResponse.status,
        });
      }

      await userRef.set(
        {
          monthlyDebitCancelled: true,
          subscriptionStatus: "cancelled_pending_expiry",
          cancelledUntil: admin.firestore.Timestamp.fromDate(expiryDate),
          subscriptionPeriodEnd: admin.firestore.Timestamp.fromDate(expiryDate),
          tierActive: true,
          monthlyRenewalActive: false,
          subscriptionCode: null,
          subscriptionToken: null,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true },
      );

      return res.status(200).send({ ok: true, cancelled: true, subscriptionCode });
    } catch (error) {
      console.error("Paystack cancellation request failed", error);
      return res.status(500).send({
        error: "Paystack subscription cancellation failed",
        detail: String(error instanceof Error ? error.message : error),
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
    const rawBody = req.rawBody;
    const bodyToVerify = rawBody || Buffer.from(JSON.stringify(req.body || {}));
    const hash = crypto.createHmac("sha512", secretKey).update(bodyToVerify).digest("hex");

    if (hash !== signature) {
      console.warn("Invalid Paystack webhook signature");
      return res.status(400).send("Invalid signature");
    }

    const event = req.body || {};
    const eventName = String(event.event || "");
    const data = event.data || {};
    const metadata = data.metadata || {};
    const customerMetadata = data.customer && data.customer.metadata ? data.customer.metadata : {};
    const customerInfo = data.customer || {};
    const planCode = data.plan && data.plan.plan_code ? data.plan.plan_code : (metadata.planCode || null);
    const db = getFirestoreDb();
    const { subscriptionCode, subscriptionToken } = extractSubscriptionMetadata(data);

    if (planCode && getCreditsForPlanCode(planCode) === null) {
      console.warn(`[Paystack Webhook] Rejected unknown plan code: ${planCode}`);
      return res.status(400).send(`Unknown or missing plan code: ${planCode}`);
    }

    const resolvedUserId = normalizeUserId(
      metadata.userId ||
      metadata.uid ||
      metadata.authUid ||
      metadata.firebaseUid ||
      customerMetadata.userId ||
      customerMetadata.uid ||
      customerMetadata.authUid ||
      customerMetadata.firebaseUid
    );
    const resolvedUserRef = resolvedUserId
      ? db.collection("users").doc(String(resolvedUserId))
      : await resolveWebhookUserRef(db, metadata, customerInfo, data.customer?.email || "");

    const isSubscriptionEvent =
      eventName === "subscription.create" ||
      (eventName === "invoice.update" && data.paid === true) ||
      metadata.payment_type === "subscription" ||
      customerMetadata.payment_type === "subscription";

    if (
      eventName === "subscription.create" ||
      (eventName === "invoice.update" && data.paid === true) ||
      (eventName === "charge.success" && isSubscriptionEvent)
    ) {
      const resolvedCredits = resolvePlanCredits(planCode) || 100;
      const effectiveUserId = resolvedUserId || (resolvedUserRef ? resolvedUserRef.id : null) || data.customer?.email || null;

      if (!effectiveUserId || !resolvedUserRef) {
        return res.status(400).send("Missing metadata");
      }

      await resolvedUserRef.set(
        {
          subscriptionCredits: admin.firestore.FieldValue.increment(resolvedCredits),
          tierActive: true,
          monthlyRenewalActive: true,
          subscriptionStatus: "active_monthly",
          lastRenewalDate: admin.firestore.FieldValue.serverTimestamp(),
          subscriptionPlanCode: planCode || null,
          subscriptionCode: subscriptionCode || null,
          subscriptionToken: subscriptionToken || null,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true },
      );

      await persistSubscriptionMetadata(db, effectiveUserId, {
        subscriptionCode,
        subscriptionToken,
        subscriptionPlanCode: planCode || null,
        monthlyRenewalActive: true,
        subscriptionStatus: "active_monthly",
      });

      return res.status(200).send("OK");
    }

    if (eventName === "subscription.disable") {
      const customerEmail = data.customer && data.customer.email ? String(data.customer.email) : "";
      const effectiveUserRef = resolvedUserRef || await resolveWebhookUserRef(db, metadata, customerInfo, customerEmail);

      if (!effectiveUserRef) {
        return res.status(400).send("Missing metadata");
      }

      const periodEnd = data.current_period_end
        ? new Date(Number(data.current_period_end) * 1000)
        : null;

      await effectiveUserRef.set(
        {
          subscriptionStatus: "cancelled_pending_expiry",
          monthlyRenewalActive: false,
          tierActive: true,
          subscriptionPeriodEnd: periodEnd ? admin.firestore.Timestamp.fromDate(periodEnd) : null,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true },
      );

      return res.status(200).send("OK");
    }

    if (eventName !== "charge.success") {
      return res.status(200).send("Ignored");
    }

    const effectiveUserRef = resolvedUserRef || await resolveWebhookUserRef(db, metadata, customerInfo, data.customer?.email || "");
    if (!effectiveUserRef) {
      return res.status(400).send("Missing metadata");
    }

    const onceOffPlanCode = data.plan_code || (data.metadata && data.metadata.plan_code) || null;
    if (onceOffPlanCode && getCreditsForPlanCode(onceOffPlanCode) === null) {
      return res.status(400).send(`Unknown or missing plan code: ${onceOffPlanCode}`);
    }

    const amount = Number(data.amount || 0);
    const metadataCredits = Number(data.metadata && data.metadata.creditsToAdd ? data.metadata.creditsToAdd : 0);
    const planCredits = resolvePlanCredits(planCode || "") || 0;
    const creditsToAdd = metadataCredits > 0 ? metadataCredits : (planCredits > 0 ? planCredits : Math.max(0, Math.floor(amount / 100)));
    const expiryDate = new Date();
    expiryDate.setDate(expiryDate.getDate() + 30);

    await effectiveUserRef.set(
      {
        onceOffCredits: admin.firestore.FieldValue.increment(creditsToAdd),
        tierActive: true,
        monthlyRenewalActive: false,
        subscriptionStatus: "active_once_off",
        subscriptionCode: subscriptionCode || null,
        subscriptionToken: subscriptionToken || null,
        subscriptionPeriodEnd: admin.firestore.Timestamp.fromDate(expiryDate),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true },
    );

    await persistSubscriptionMetadata(db, effectiveUserRef.id, {
      subscriptionCode,
      subscriptionToken,
      monthlyRenewalActive: false,
      subscriptionStatus: "active_once_off",
    });

    return res.status(200).send("OK");
  },
);

module.exports = {
  createPaystackTransaction,
  createPaystackTransactionHttp,
  cancelPaystackSubscriptionHttp,
  paystackWebhook,
};