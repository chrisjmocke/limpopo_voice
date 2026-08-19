const { onRequest } = require("firebase-functions/v2/https");
const admin = require("firebase-admin");

if (!admin.apps.length) {
  admin.initializeApp();
}

function getRuntimePayPalMode() {
  const mode = String(process.env.PAYPAL_MODE || "").trim().toLowerCase();
  if (mode === "sandbox" || mode === "live") {
    return mode;
  }
  throw new Error("PAYPAL_MODE must be set to 'sandbox' or 'live'.");
}

function getPayPalCredentials() {
  const clientId = String(process.env.PAYPAL_CLIENT_ID || "").trim();
  const clientSecret = String(process.env.PAYPAL_SECRET || "").trim();
  if (!clientId || !clientSecret) {
    throw new Error("PAYPAL_CLIENT_ID and PAYPAL_SECRET must be configured in function runtime.");
  }
  return { clientId, clientSecret };
}

function getPayPalApiBase(mode) {
  return mode === "live"
    ? "https://api-m.paypal.com"
    : "https://api-m.sandbox.paypal.com";
}

function buildFallbackEmail(uid) {
  const safe = String(uid || "anon").replace(/[^a-zA-Z0-9]/g, "").toLowerCase();
  return `${safe || "anon"}@letstalk.local`;
}

async function getAccessToken({ apiBase, clientId, clientSecret }) {
  const basic = Buffer.from(`${clientId}:${clientSecret}`).toString("base64");
  const response = await fetch(`${apiBase}/v1/oauth2/token`, {
    method: "POST",
    headers: {
      Authorization: `Basic ${basic}`,
      "Content-Type": "application/x-www-form-urlencoded",
    },
    body: "grant_type=client_credentials",
  });

  const result = await response.json();
  if (!response.ok || !result?.access_token) {
    console.error("PayPal token request failed", result);
    throw new Error("PayPal OAuth token request failed.");
  }

  return String(result.access_token);
}

function getAuthIdToken(req) {
  const authHeader = String(req.headers.authorization || "");
  if (!authHeader.startsWith("Bearer ")) {
    return null;
  }
  const idToken = authHeader.slice("Bearer ".length).trim();
  return idToken || null;
}

async function verifyFirebaseUserFromRequest(req, res) {
  const idToken = getAuthIdToken(req);
  if (!idToken) {
    res.status(401).send({ error: "Missing Authorization bearer token." });
    return null;
  }

  try {
    return await admin.auth().verifyIdToken(idToken);
  } catch {
    res.status(401).send({ error: "Unauthorized" });
    return null;
  }
}

const createPayPalOrderHttp = onRequest(
  {
    region: "africa-south1",
    secrets: ["PAYPAL_CLIENT_ID", "PAYPAL_SECRET"],
  },
  async (req, res) => {
    if (req.method !== "POST") {
      return res.status(405).send({ error: "Method Not Allowed" });
    }

    const decodedToken = await verifyFirebaseUserFromRequest(req, res);
    if (!decodedToken) return;

    const { amountCents, email, tierName, mode } = req.body || {};
    if (typeof amountCents !== "number" || amountCents <= 0) {
      return res.status(400).send({ error: "Invalid amount" });
    }

    const runtimeMode = (() => {
      try {
        return getRuntimePayPalMode();
      } catch (error) {
        return null;
      }
    })();

    if (!runtimeMode) {
      return res.status(500).send({
        error: "PayPal mode misconfigured.",
        details: "Set PAYPAL_MODE to 'sandbox' or 'live'.",
      });
    }

    const requestMode = String(mode || "").trim().toLowerCase();
    if (!requestMode || requestMode !== runtimeMode) {
      return res.status(400).send({
        error: "PayPal mode mismatch.",
        expectedMode: runtimeMode,
        receivedMode: requestMode || null,
      });
    }

    const payerEmail =
      typeof email === "string" && email.includes("@")
        ? email
        : buildFallbackEmail(decodedToken.uid);

    const currencyCode = String(process.env.PAYPAL_CURRENCY || "USD").trim().toUpperCase();
    const amountValue = (Math.trunc(amountCents) / 100).toFixed(2);

    try {
      const { clientId, clientSecret } = getPayPalCredentials();
      const apiBase = getPayPalApiBase(runtimeMode);
      const accessToken = await getAccessToken({ apiBase, clientId, clientSecret });

      const returnUrl = String(process.env.PAYPAL_RETURN_URL || "https://example.com/paypal-return").trim();
      const cancelUrl = String(process.env.PAYPAL_CANCEL_URL || "https://example.com/paypal-cancel").trim();

      const response = await fetch(`${apiBase}/v2/checkout/orders`, {
        method: "POST",
        headers: {
          Authorization: `Bearer ${accessToken}`,
          "Content-Type": "application/json",
          Prefer: "return=representation",
        },
        body: JSON.stringify({
          intent: "CAPTURE",
          purchase_units: [
            {
              amount: {
                currency_code: currencyCode,
                value: amountValue,
              },
              description: typeof tierName === "string" ? `LimpopoVoice ${tierName}` : "LimpopoVoice Credits",
            },
          ],
          payer: {
            email_address: payerEmail,
          },
          application_context: {
            return_url: returnUrl,
            cancel_url: cancelUrl,
            user_action: "PAY_NOW",
          },
        }),
      });

      const result = await response.json();
      if (!response.ok) {
        console.error("PayPal order create failed", result);
        return res.status(502).send({
          error: "PayPal order creation failed",
          details: result,
        });
      }

      const approvalLink = Array.isArray(result?.links)
        ? result.links.find((link) => String(link?.rel || "").toLowerCase() === "approve")
        : null;

      return res.status(200).send({
        order_id: result?.id || null,
        approval_url: approvalLink?.href || null,
        mode: runtimeMode,
      });
    } catch (error) {
      console.error("PayPal HTTP order init failed", error);
      return res.status(500).send({
        error: "PayPal order initialization failed",
        details: String(error?.message || error),
      });
    }
  },
);

const capturePayPalOrderHttp = onRequest(
  {
    region: "africa-south1",
    secrets: ["PAYPAL_CLIENT_ID", "PAYPAL_SECRET"],
  },
  async (req, res) => {
    if (req.method !== "POST") {
      return res.status(405).send({ error: "Method Not Allowed" });
    }

    const decodedToken = await verifyFirebaseUserFromRequest(req, res);
    if (!decodedToken) return;

    const { orderId, mode, amountCents } = req.body || {};
    const sanitizedOrderId = String(orderId || "").trim();
    if (!sanitizedOrderId) {
      return res.status(400).send({ error: "Missing orderId" });
    }

    const runtimeMode = (() => {
      try {
        return getRuntimePayPalMode();
      } catch {
        return null;
      }
    })();

    if (!runtimeMode) {
      return res.status(500).send({
        error: "PayPal mode misconfigured.",
        details: "Set PAYPAL_MODE to 'sandbox' or 'live'.",
      });
    }

    const requestMode = String(mode || "").trim().toLowerCase();
    if (!requestMode || requestMode !== runtimeMode) {
      return res.status(400).send({
        error: "PayPal mode mismatch.",
        expectedMode: runtimeMode,
        receivedMode: requestMode || null,
      });
    }

    const expectedAmountCents = Number.isFinite(Number(amountCents))
      ? Math.trunc(Number(amountCents))
      : null;

    try {
      const { clientId, clientSecret } = getPayPalCredentials();
      const apiBase = getPayPalApiBase(runtimeMode);
      const accessToken = await getAccessToken({ apiBase, clientId, clientSecret });

      const response = await fetch(`${apiBase}/v2/checkout/orders/${encodeURIComponent(sanitizedOrderId)}/capture`, {
        method: "POST",
        headers: {
          Authorization: `Bearer ${accessToken}`,
          "Content-Type": "application/json",
          "PayPal-Request-Id": `${sanitizedOrderId}-capture-${Date.now()}`,
        },
        body: JSON.stringify({}),
      });

      const result = await response.json();
      if (!response.ok) {
        console.error("PayPal order capture failed", result);
        return res.status(502).send({
          error: "PayPal order capture failed",
          details: result,
        });
      }

      const purchaseUnit = Array.isArray(result?.purchase_units) ? result.purchase_units[0] : null;
      const capture = Array.isArray(purchaseUnit?.payments?.captures)
        ? purchaseUnit.payments.captures[0]
        : null;
      const capturedValue = capture?.amount?.value;
      const capturedCents = Number.isFinite(Number(capturedValue))
        ? Math.round(Number(capturedValue) * 100)
        : null;

      if (
        expectedAmountCents != null &&
        expectedAmountCents > 0 &&
        capturedCents != null &&
        capturedCents !== expectedAmountCents
      ) {
        return res.status(400).send({
          error: "Captured amount mismatch.",
          expectedAmountCents,
          capturedCents,
          order_id: result?.id || sanitizedOrderId,
          capture_id: capture?.id || null,
        });
      }

      const completed = String(result?.status || "").toUpperCase() === "COMPLETED";
      if (!completed) {
        return res.status(409).send({
          error: "PayPal order not completed yet.",
          completed: false,
          status: result?.status || null,
          order_id: result?.id || sanitizedOrderId,
          capture_id: capture?.id || null,
          userId: decodedToken.uid,
        });
      }

      const creditsToAdd = Math.floor(capturedCents / 100);
      const db = admin.firestore();
      const userRef = db.collection("users").doc(decodedToken.uid);
      await userRef.set(
        {
          credits: admin.firestore.FieldValue.increment(creditsToAdd),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true },
      );

      return res.status(200).send({
        completed: true,
        status: result?.status || null,
        order_id: result?.id || sanitizedOrderId,
        capture_id: capture?.id || null,
        amount_cents: capturedCents,
        mode: runtimeMode,
        userId: decodedToken.uid,
      });
    } catch (error) {
      console.error("PayPal HTTP capture failed", error);
      return res.status(500).send({
        error: "PayPal order capture failed",
        details: String(error?.message || error),
      });
    }
  },
);

module.exports = {
  createPayPalOrderHttp,
  capturePayPalOrderHttp,
};
