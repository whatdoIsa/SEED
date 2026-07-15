/**
 * SEED AI 튜터 프록시 — Cloudflare Worker
 *
 * 역할: API 키를 기기에 두지 않기 위한 얇은 중계 + 남용 방어(서버측 2차 방어).
 *   방어 계층: ①공유 토큰 헤더 ②deviceId 형식 검증 ③전역 일일 캡 ④기기별 일일 캡 ⑤서버측 금칙어 필터
 *   (최후 방어벽은 console.anthropic.com의 월 지출 한도 — 반드시 별도 설정할 것)
 *
 * 배포 (5분):
 *   1. dash.cloudflare.com 가입 (무료) → Workers & Pages → Create Worker
 *   2. 이 파일 내용을 붙여넣고 Deploy
 *   3. Settings → Variables → Secret 추가:
 *        ANTHROPIC_API_KEY = (console.anthropic.com에서 발급)
 *        CLIENT_TOKEN      = (앱의 TutorSecrets.clientToken과 동일한 값 — 저장소엔 커밋 금지)
 *   4. Settings → Bindings → KV Namespace 추가: 이름 LIMITS (새로 생성)
 *   5. 배포된 URL(https://xxx.workers.dev)을 앱의 TutorService.endpoint에 반영
 */

const MODEL = "claude-haiku-4-5-20251001";
const MAX_OUTPUT_TOKENS = 500;
const DAILY_LIMIT_PER_DEVICE = 30; // 서버측 상한 — 클라이언트 상한(5/일)보다 넉넉히, 탈취 방어용
const DAILY_LIMIT_GLOBAL = 2000; // 전 기기 합산 일일 캡 — deviceId 위조와 무관한 총 비용 상한
const UUID_PATTERN = /^[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}$/i;

// 클라이언트 규칙 필터와 동일 목록 (TutorService.bannedPatterns) — 워커 직접 호출 우회 방어
const BANNED_PATTERNS = [
  "사야", "살까", "팔까", "팔아야", "추천", "종목알려", "뭐사", "뭘사",
  "오를까", "내릴까", "떨어질까", "얼마까지", "목표가", "가즈아", "몰빵해도",
];
const REFUSAL_TEXT =
  "저는 지식을 설명하는 튜터라, 무엇을 사고팔지·오를지 내릴지는 답하지 않아요. " +
  "대신 그 판단에 필요한 개념이 궁금하면 물어보세요 — 예를 들어 “PER이 뭐야?” 같은 것들요.";

const SYSTEM_PROMPT = `당신은 한국의 주식 초보를 위한 모의투자 학습 앱 'SEED'의 금융 튜터입니다.

역할: 주식·ETF·채권·비트코인 등 금융 기초 지식을 초보 눈높이의 한국어 존댓말로, 두세 문단 안에서 설명합니다.

반드시 지킬 것:
- 특정 종목·코인의 매수/매도 추천, 가격 예측, 수익 보장은 절대 하지 않습니다. 이런 질문에는 "저는 지식을 설명하는 튜터라, 무엇을 사고팔지는 답하지 않아요"라고 정중히 거절하고 관련 원리를 대신 설명합니다.
- 세금·제도·수수료 같은 수치는 바뀔 수 있으므로 "정확한 최신 기준은 공식 기관에서 확인하세요"를 덧붙입니다.
- 모르는 것은 모른다고 말합니다.
- 투자의 판단과 책임은 본인에게 있음을 전제로 말합니다.
- 금융과 무관한 질문(코딩, 연애, 숙제 등)은 "금융 학습 질문만 도와드려요"라고 안내합니다.`;

export default {
  async fetch(request, env) {
    if (request.method !== "POST") {
      return new Response("SEED tutor proxy", { status: 200 });
    }

    // ① 공유 토큰 — 앱이 아닌 클라이언트의 저비용 난사 차단 (값은 Cloudflare Secret, 저장소엔 없음)
    if (!env.CLIENT_TOKEN || request.headers.get("x-seed-client") !== env.CLIENT_TOKEN) {
      return json({ error: "unauthorized" }, 401);
    }

    let body;
    try {
      body = await request.json();
    } catch {
      return json({ error: "bad request" }, 400);
    }

    const { deviceId, messages } = body;
    if (!deviceId || !UUID_PATTERN.test(deviceId) ||
        !Array.isArray(messages) || messages.length === 0 || messages.length > 8) {
      return json({ error: "bad request" }, 400);
    }

    // 히스토리 정규화: 마지막은 반드시 user (가짜 assistant 프리필 주입 방어)
    const last = messages[messages.length - 1];
    if (!last || last.role !== "user" || typeof last.content !== "string") {
      return json({ error: "bad request" }, 400);
    }

    // ⑤ 서버측 금칙어 — 클라이언트 필터 우회(직접 POST) 방어, 0토큰 거절
    const compactQuestion = String(last.content).replace(/\s+/g, "");
    if (BANNED_PATTERNS.some((p) => compactQuestion.includes(p))) {
      return json({ text: REFUSAL_TEXT });
    }

    const today = new Date().toISOString().slice(0, 10);

    // ③ 전역 일일 캡 — deviceId를 아무리 위조해도 총 비용은 여기서 멈춘다
    const globalKey = `global:${today}`;
    const globalUsed = parseInt((await env.LIMITS.get(globalKey)) || "0", 10);
    if (globalUsed >= DAILY_LIMIT_GLOBAL) {
      return json({ error: "daily limit" }, 429);
    }

    // ④ 기기별 일일 상한 (KV)
    const limitKey = `${deviceId}:${today}`;
    const used = parseInt((await env.LIMITS.get(limitKey)) || "0", 10);
    if (used >= DAILY_LIMIT_PER_DEVICE) {
      return json({ error: "daily limit" }, 429);
    }
    await env.LIMITS.put(limitKey, String(used + 1), { expirationTtl: 172800 });
    await env.LIMITS.put(globalKey, String(globalUsed + 1), { expirationTtl: 172800 });

    // Anthropic 호출 (프롬프트 캐싱: 시스템 프롬프트 90% 할인)
    const anthropicResponse = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "x-api-key": env.ANTHROPIC_API_KEY,
        "anthropic-version": "2023-06-01",
      },
      body: JSON.stringify({
        model: MODEL,
        max_tokens: MAX_OUTPUT_TOKENS,
        system: [
          { type: "text", text: SYSTEM_PROMPT, cache_control: { type: "ephemeral" } },
        ],
        messages: messages.map((m) => ({
          role: m.role === "assistant" ? "assistant" : "user",
          content: String(m.content).slice(0, 2000),
        })),
      }),
    });

    if (!anthropicResponse.ok) {
      // 상세(키 오류 401 / 모델 404 / 크레딧 400)는 워커 로그로만 — 클라이언트에 내부 정보 노출 금지
      const detail = (await anthropicResponse.text()).slice(0, 300);
      console.log(`upstream ${anthropicResponse.status}: ${detail}`);
      return json({ error: "upstream" }, 502);
    }
    const data = await anthropicResponse.json();
    const text = (data.content || [])
      .filter((block) => block.type === "text")
      .map((block) => block.text)
      .join("");
    return json({ text });
  },
};

function json(obj, status = 200) {
  return new Response(JSON.stringify(obj), {
    status,
    headers: { "content-type": "application/json" },
  });
}
