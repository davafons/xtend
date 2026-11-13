// Links the extension to Xtend with OAuth: the authorization code flow with PKCE, opened through chrome.identity so
// the approval page uses this browser's Cloudflare Access and Xtend sessions. Tokens are kept in extension storage
// and renewed with the refresh token before they expire.
export const CLIENT_ID = "xtend-capture";
const RENEW_BEFORE_MS = 24 * 60 * 60 * 1000;

const base64url = (bytes) => btoa(String.fromCharCode(...new Uint8Array(bytes))).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
const random = (length) => base64url(crypto.getRandomValues(new Uint8Array(length)));
const form = (fields) => ({ method: "POST", headers: { "Content-Type": "application/x-www-form-urlencoded" }, body: new URLSearchParams(fields) });

async function tokenRequest(origin, fields) {
  const response = await fetch(`${origin}/oauth/token`, form({ client_id: CLIENT_ID, resource: `${origin}/x/captures`, ...fields }));
  const body = await response.json().catch(() => ({}));
  if (!response.ok) throw Object.assign(new Error(body.error_description || `Xtend answered ${response.status}.`), { code: body.error });
  return { token: body.access_token, refreshToken: body.refresh_token, expiresAt: Date.now() + body.expires_in * 1000 };
}

// Opens Xtend's approval page. Resolves to { token, refreshToken, expiresAt }.
export async function connect(origin) {
  const verifier = random(48);
  const challenge = base64url(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(verifier)));
  const state = random(16);
  const redirectUri = chrome.identity.getRedirectURL("oauth");
  const url = new URL(`${origin}/oauth/authorize`);
  for (const [key, value] of Object.entries({ response_type: "code", client_id: CLIENT_ID, redirect_uri: redirectUri, scope: "capture",
    code_challenge: challenge, code_challenge_method: "S256", state, resource: `${origin}/x/captures` })) url.searchParams.set(key, value);
  const reply = new URL(await chrome.identity.launchWebAuthFlow({ url: url.href, interactive: true }));
  const answer = Object.fromEntries(reply.searchParams);
  if (answer.state !== state || (answer.iss && answer.iss !== origin)) throw new Error("The reply didn't come from this request to Xtend.");
  if (answer.error) throw new Error(answer.error === "access_denied" ? "You didn't approve the connection." : `Xtend refused the connection (${answer.error}).`);
  return tokenRequest(origin, { grant_type: "authorization_code", code: answer.code, redirect_uri: redirectUri, code_verifier: verifier });
}

export const refresh = (origin, refreshToken) => tokenRequest(origin, { grant_type: "refresh_token", refresh_token: refreshToken });
export const needsRenewal = ({ refreshToken, expiresAt }) => Boolean(refreshToken && expiresAt && expiresAt - Date.now() < RENEW_BEFORE_MS);

export function revoke(origin, token) {
  return fetch(`${origin}/oauth/revoke`, form({ client_id: CLIENT_ID, token })).catch(() => {});
}
