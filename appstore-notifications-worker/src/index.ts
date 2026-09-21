import { Buffer } from 'node:buffer';
import type {
  Environment as EnvironmentType,
  SignedDataVerifier as SignedDataVerifierType,
  JWSRenewalInfoDecodedPayload,
  JWSTransactionDecodedPayload,
  ResponseBodyV2DecodedPayload,
} from '@apple/app-store-server-library';

export interface Env {
  APP_BUNDLE_ID: string;
  APP_APPLE_ID: string;
  NOTIFY_EMAIL: string;
  NOTIFY_FROM_EMAIL: string;
  RESEND_API_KEY: string;
}

// jsrsasign (a transitive dependency of @apple/app-store-server-library) touches things the
// Workers runtime only allows inside a request handler when its module body first runs, so this
// package must be imported dynamically from inside fetch() rather than statically at the top of
// this file — a static import crashes the worker before it can handle any request.
type AppleLib = typeof import('@apple/app-store-server-library');
let applePromise: Promise<AppleLib> | null = null;
function loadAppleLib(): Promise<AppleLib> {
  if (!applePromise) {
    applePromise = import('@apple/app-store-server-library');
  }
  return applePromise;
}

// Apple publishes this cert for anyone verifying App Store Server Notifications; it changes
// rarely, so a day of caching keeps most requests from paying the extra fetch.
const APPLE_ROOT_CA_URL = 'https://www.apple.com/certificateauthority/AppleRootCA-G3.cer';
const ROOT_CERT_TTL_MS = 24 * 60 * 60 * 1000;

let cachedRootCert: Buffer | null = null;
let cachedRootCertAt = 0;

async function getAppleRootCert(): Promise<Buffer> {
  const now = Date.now();
  if (cachedRootCert && now - cachedRootCertAt < ROOT_CERT_TTL_MS) {
    return cachedRootCert;
  }
  const res = await fetch(APPLE_ROOT_CA_URL);
  if (!res.ok) {
    throw new Error(`failed to fetch Apple root CA cert: HTTP ${res.status}`);
  }
  cachedRootCert = Buffer.from(await res.arrayBuffer());
  cachedRootCertAt = now;
  return cachedRootCert;
}

async function buildVerifier(env: Env, environment: EnvironmentType): Promise<SignedDataVerifierType> {
  const { SignedDataVerifier, Environment } = await loadAppleLib();
  const rootCert = await getAppleRootCert();
  const appAppleId = environment === Environment.PRODUCTION ? Number(env.APP_APPLE_ID) : undefined;
  if (environment === Environment.PRODUCTION && (!env.APP_APPLE_ID || Number.isNaN(appAppleId))) {
    throw new Error('APP_APPLE_ID must be set to a numeric Apple ID to verify production notifications');
  }
  // Revocation (OCSP) checks are left off: Apple's signing certs are effectively never revoked,
  // and skipping it keeps this handler from depending on a third-party responder being reachable.
  return new SignedDataVerifier([rootCert], false, environment, env.APP_BUNDLE_ID, appAppleId);
}

function formatMilliunits(amount: number | undefined, currency: string | undefined): string | undefined {
  if (amount === undefined) return undefined;
  const value = (amount / 1000).toFixed(2);
  return currency ? `${value} ${currency}` : value;
}

function formatDate(ms: number | undefined): string {
  if (ms === undefined) return 'unknown';
  return new Date(ms).toISOString();
}

function buildEmail(
  environment: EnvironmentType,
  notification: ResponseBodyV2DecodedPayload,
  transaction: JWSTransactionDecodedPayload | null,
  renewal: JWSRenewalInfoDecodedPayload | null,
): { subject: string; text: string } {
  const kind = [notification.notificationType, notification.subtype].filter(Boolean).join(' / ');
  const productBit = transaction?.productId ? ` — ${transaction.productId}` : '';
  const subject = `[CamoTracker] App Store ${environment}: ${kind}${productBit}`;

  const lines: string[] = [
    `Notification type: ${kind || 'unknown'}`,
    `Environment: ${environment}`,
    `Notification UUID: ${notification.notificationUUID ?? 'unknown'}`,
  ];

  if (transaction) {
    lines.push(
      '',
      'Transaction:',
      `  Product ID: ${transaction.productId ?? 'unknown'}`,
      `  Type: ${transaction.type ?? 'unknown'}`,
      `  Transaction ID: ${transaction.transactionId ?? 'unknown'}`,
      `  Original transaction ID: ${transaction.originalTransactionId ?? 'unknown'}`,
      `  Purchase date: ${formatDate(transaction.purchaseDate)}`,
    );
    const price = formatMilliunits(transaction.price, transaction.currency);
    if (price) lines.push(`  Price: ${price}`);
    if (transaction.inAppOwnershipType) lines.push(`  Ownership: ${transaction.inAppOwnershipType}`);
    if (transaction.revocationReason !== undefined) {
      lines.push(`  Revocation reason: ${transaction.revocationReason}`, `  Revocation date: ${formatDate(transaction.revocationDate)}`);
    }
  }

  if (renewal) {
    lines.push(
      '',
      'Renewal info:',
      `  Auto-renew product: ${renewal.autoRenewProductId ?? 'unknown'}`,
      `  Auto-renew status: ${renewal.autoRenewStatus ?? 'unknown'}`,
    );
    const renewalPrice = formatMilliunits(renewal.renewalPrice, renewal.currency);
    if (renewalPrice) lines.push(`  Renewal price: ${renewalPrice}`);
  }

  return { subject, text: lines.join('\n') };
}

async function sendEmail(env: Env, subject: string, text: string): Promise<void> {
  const res = await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${env.RESEND_API_KEY}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      from: env.NOTIFY_FROM_EMAIL,
      to: env.NOTIFY_EMAIL,
      subject,
      text,
    }),
  });
  if (!res.ok) {
    throw new Error(`Resend API error ${res.status}: ${await res.text()}`);
  }
}

async function handleNotification(env: Env, environment: EnvironmentType, signedPayload: string): Promise<void> {
  const verifier = await buildVerifier(env, environment);
  const notification = await verifier.verifyAndDecodeNotification(signedPayload);

  let transaction: JWSTransactionDecodedPayload | null = null;
  if (notification.data?.signedTransactionInfo) {
    transaction = await verifier.verifyAndDecodeTransaction(notification.data.signedTransactionInfo);
  }

  let renewal: JWSRenewalInfoDecodedPayload | null = null;
  if (notification.data?.signedRenewalInfo) {
    renewal = await verifier.verifyAndDecodeRenewalInfo(notification.data.signedRenewalInfo);
  }

  const { subject, text } = buildEmail(environment, notification, transaction, renewal);
  await sendEmail(env, subject, text);
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const { pathname } = new URL(request.url);

    if (request.method === 'GET' && (pathname === '/' || pathname === '/health')) {
      return new Response('ok', { status: 200 });
    }

    if (request.method !== 'POST') {
      return new Response('Method Not Allowed', { status: 405 });
    }

    const { Environment, VerificationException } = await loadAppleLib();

    let environment: EnvironmentType;
    if (pathname === '/production') {
      environment = Environment.PRODUCTION;
    } else if (pathname === '/sandbox') {
      environment = Environment.SANDBOX;
    } else {
      return new Response('Not Found', { status: 404 });
    }

    let body: { signedPayload?: string };
    try {
      body = await request.json();
    } catch {
      return new Response('Bad Request: invalid JSON', { status: 400 });
    }
    if (!body.signedPayload) {
      return new Response('Bad Request: missing signedPayload', { status: 400 });
    }

    try {
      await handleNotification(env, environment, body.signedPayload);
      return new Response('OK', { status: 200 });
    } catch (err) {
      console.error('Failed to process App Store notification', err);
      // A payload that fails verification will never succeed on retry, so ack it with 4xx.
      // Any other failure (e.g. the email API being down) is worth Apple retrying, so 5xx.
      const status = err instanceof VerificationException ? 400 : 500;
      return new Response('Error processing notification', { status });
    }
  },
};
