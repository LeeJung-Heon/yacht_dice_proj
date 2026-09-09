// 차례가 바뀌거나 게스트가 들어오면 DB 웹훅이 부른다. 알릴 좌석의 기기 토큰을 읽어 APNs로 "내 차례"를 보낸다.
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";
import { importPrivateKey, makeToken, sendPush } from "./apns.ts";

interface MatchRecord {
  id: string;
  host_uid: string;
  guest_uid: string | null;
  host_name: string;
  guest_name: string | null;
  status: string;
  turn_seat: number | null;
}

interface Webhook {
  type: string;
  record: MatchRecord;
  old_record: MatchRecord | null;
}

/// 누구에게 무엇을 알릴지 정한다. 순수 함수라 따로 검증할 수 있다.
export function planNotification(hook: Webhook): { uid: string; title: string; body: string } | null {
  const { record, old_record } = hook;
  if (old_record && old_record.guest_uid === null && record.guest_uid !== null) {
    return { uid: record.host_uid, title: "상대가 들어왔다", body: `${record.guest_name ?? "상대"}이(가) 방에 들어왔다` };
  }
  if (record.status === "finished") {
    return null;
  }
  if (record.turn_seat === null || old_record?.turn_seat === record.turn_seat) return null;
  const uid = record.turn_seat === 0 ? record.host_uid : record.guest_uid;
  const opponent = record.turn_seat === 0 ? record.guest_name : record.host_name;
  if (!uid) return null;
  return { uid, title: "내 차례", body: `${opponent ?? "상대"}이(가) 두었다` };
}

function env(name: string): string {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`${name} 시크릿이 없다`);
  return value;
}

Deno.serve(async (req: Request) => {
  if (req.headers.get("x-webhook-secret") !== env("WEBHOOK_SECRET")) {
    return new Response("forbidden", { status: 403 });
  }
  const hook = (await req.json()) as Webhook;
  const plan = planNotification(hook);
  if (!plan) return Response.json({ sent: 0, skipped: true });

  const admin = createClient(env("SUPABASE_URL"), env("SUPABASE_SERVICE_ROLE_KEY"));
  const { data: tokens, error } = await admin.from("device_tokens").select("token").eq("uid", plan.uid);
  if (error) return Response.json({ error: error.message }, { status: 500 });
  if (!tokens || tokens.length === 0) return Response.json({ sent: 0 });

  const apns = {
    keyId: env("APNS_KEY_ID"),
    teamId: env("APNS_TEAM_ID"),
    privateKey: env("APNS_PRIVATE_KEY").replace(/\\n/g, "\n"),
    bundleId: env("APNS_BUNDLE_ID"),
    host: Deno.env.get("APNS_HOST") ?? undefined,
  };
  const jwt = await makeToken(await importPrivateKey(apns.privateKey), apns.keyId, apns.teamId);
  const payload = {
    aps: { alert: { title: plan.title, body: plan.body }, sound: "default", "thread-id": hook.record.id },
    matchID: hook.record.id,
  };
  let sent = 0;
  const dead: string[] = [];
  const failures: string[] = [];
  for (const { token } of tokens) {
    const result = await sendPush(token, payload, apns, jwt);
    if (result.ok) sent += 1;
    else if (result.dropToken) dead.push(token);
    else failures.push(`${result.status} ${result.reason}`);
  }
  if (dead.length > 0) await admin.from("device_tokens").delete().in("token", dead);
  return Response.json({ sent, dropped: dead.length, failures });
});
