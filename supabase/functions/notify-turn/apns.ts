// APNs 토큰 인증(ES256 JWT)과 전송. Edge Function과 deno test가 함께 쓴다.

function base64url(bytes: Uint8Array): string {
  let s = "";
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function pemToDer(pem: string): ArrayBuffer {
  const body = pem.replace(/-----[A-Z ]+-----/g, "").replace(/\s+/g, "");
  const bin = atob(body);
  const out = new Uint8Array(new ArrayBuffer(bin.length));
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out.buffer;
}

/// .p8(PKCS#8) 본문으로 서명 키를 만든다.
export async function importPrivateKey(pem: string): Promise<CryptoKey> {
  return await crypto.subtle.importKey(
    "pkcs8",
    pemToDer(pem),
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );
}

/// APNs용 JWT. 헤더 { alg: ES256, kid }, 페이로드 { iss: teamId, iat }. WebCrypto의 ECDSA 서명은 이미 r||s(JOSE) 형식이다.
export async function makeToken(
  key: CryptoKey,
  keyId: string,
  teamId: string,
  issuedAt = Math.floor(Date.now() / 1000),
): Promise<string> {
  const enc = new TextEncoder();
  const header = base64url(enc.encode(JSON.stringify({ alg: "ES256", kid: keyId })));
  const payload = base64url(enc.encode(JSON.stringify({ iss: teamId, iat: issuedAt })));
  const signing = `${header}.${payload}`;
  const sig = await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, enc.encode(signing));
  return `${signing}.${base64url(new Uint8Array(sig))}`;
}

export interface ApnsEnv {
  keyId: string;
  teamId: string;
  privateKey: string;
  bundleId: string;
  /// 기본은 운영 서버. TestFlight·App Store 빌드는 운영 토큰을 쓴다. 개발 빌드(aps-environment development)는 sandbox다.
  host?: string;
}

export type PushResult = { ok: true } | { ok: false; status: number; reason: string; dropToken: boolean };

/// 기기 하나에 알림을 보낸다. 토큰이 죽었으면(410, 400 BadDeviceToken) dropToken을 참으로 돌려준다.
export async function sendPush(
  deviceToken: string,
  payload: Record<string, unknown>,
  env: ApnsEnv,
  jwt?: string,
  fetchImpl: typeof fetch = fetch,
): Promise<PushResult> {
  const token = jwt ?? await makeToken(await importPrivateKey(env.privateKey), env.keyId, env.teamId);
  const host = env.host ?? "https://api.push.apple.com";
  const res = await fetchImpl(`${host}/3/device/${deviceToken}`, {
    method: "POST",
    headers: {
      authorization: `bearer ${token}`,
      "apns-topic": env.bundleId,
      "apns-push-type": "alert",
      "apns-priority": "10",
      "content-type": "application/json",
    },
    body: JSON.stringify(payload),
  });
  if (res.ok) return { ok: true };
  let reason = "";
  try {
    reason = ((await res.json()) as { reason?: string }).reason ?? "";
  } catch { /* 본문 없음 */ }
  const dropToken = res.status === 410 || (res.status === 400 && reason === "BadDeviceToken") ||
    reason === "Unregistered";
  return { ok: false, status: res.status, reason, dropToken };
}
