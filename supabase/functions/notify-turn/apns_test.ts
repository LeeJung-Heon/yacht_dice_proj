import { assert, assertEquals } from "jsr:@std/assert@1";
import { importPrivateKey, makeToken, sendPush } from "./apns.ts";

function decode(part: string): Record<string, unknown> {
  const b64 = part.replace(/-/g, "+").replace(/_/g, "/");
  return JSON.parse(atob(b64 + "=".repeat((4 - b64.length % 4) % 4)));
}

async function testKeyPair() {
  const pair = await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign", "verify"]);
  const der = new Uint8Array(await crypto.subtle.exportKey("pkcs8", pair.privateKey));
  let s = "";
  for (const b of der) s += String.fromCharCode(b);
  const pem = `-----BEGIN PRIVATE KEY-----\n${btoa(s).match(/.{1,64}/g)!.join("\n")}\n-----END PRIVATE KEY-----`;
  return { pem, publicKey: pair.publicKey };
}

Deno.test("JWT 헤더·페이로드가 맞고 서명이 검증된다", async () => {
  const { pem, publicKey } = await testKeyPair();
  const key = await importPrivateKey(pem);
  const jwt = await makeToken(key, "KEY123", "TEAM456", 1_700_000_000);
  const [h, p, sig] = jwt.split(".");
  assertEquals(decode(h), { alg: "ES256", kid: "KEY123" });
  assertEquals(decode(p), { iss: "TEAM456", iat: 1_700_000_000 });
  const sigBytes = Uint8Array.from(atob(sig.replace(/-/g, "+").replace(/_/g, "/") + "=".repeat((4 - sig.length % 4) % 4)), (c) => c.charCodeAt(0));
  assertEquals(sigBytes.length, 64, "JOSE r||s 형식이어야 한다");
  const ok = await crypto.subtle.verify(
    { name: "ECDSA", hash: "SHA-256" },
    publicKey,
    sigBytes,
    new TextEncoder().encode(`${h}.${p}`),
  );
  assert(ok);
});

Deno.test("sendPush는 APNs 헤더를 싣고 죽은 토큰을 알려 준다", async () => {
  const { pem } = await testKeyPair();
  const env = { keyId: "K", teamId: "T", privateKey: pem, bundleId: "com.example.app", host: "https://apns.test" };
  let seen: Request | undefined;
  const fake: typeof fetch = (input, init) => {
    seen = new Request(input as string, init);
    return Promise.resolve(new Response(JSON.stringify({ reason: "BadDeviceToken" }), { status: 400 }));
  };
  const result = await sendPush("abc123", { aps: { alert: "hi" } }, env, undefined, fake);
  assertEquals(seen!.url, "https://apns.test/3/device/abc123");
  assertEquals(seen!.headers.get("apns-topic"), "com.example.app");
  assertEquals(seen!.headers.get("apns-push-type"), "alert");
  assert(seen!.headers.get("authorization")!.startsWith("bearer ey"));
  assertEquals(result, { ok: false, status: 400, reason: "BadDeviceToken", dropToken: true });

  const okFetch: typeof fetch = () => Promise.resolve(new Response("", { status: 200 }));
  assertEquals(await sendPush("abc123", {}, env, undefined, okFetch), { ok: true });
});
