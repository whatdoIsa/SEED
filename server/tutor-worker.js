/**
 * SEED AI 튜터 프록시 — Cloudflare Worker
 *
 * 역할: API 키를 기기에 두지 않기 위한 얇은 중계 + 기기별 일일 상한(서버측 2차 방어).
 *
 * 배포 (5분):
 *   1. dash.cloudflare.com 가입 (무료) → Workers & Pages → Create Worker
 *   2. 이 파일 내용을 붙여넣고 Deploy
 *   3. Settings → Variables → Secret 추가: ANTHROPIC_API_KEY = (console.anthropic.com에서 발급)
 *   4. Settings → Bindings → KV Namespace 추가: 이름 LIMITS (새로 생성)
 *   5. 배포된 URL(https://xxx.workers.dev)을 앱의 TutorService.endpoint에 반영
 */

const MODEL = "claude-haiku-4-5";
const MAX_OUTPUT_TOKENS = 500;
const DAILY_LIMIT_PER_DEVICE = 30; // 서버측 상한 — 클라이언트 상한(5/일)보다 넉넉히, 탈취 방어용

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

    let body;
    try {
      body = await request.json();
    } catch {
      return json({ error: "bad request" }, 400);
    }

    const { deviceId, messages } = body;
    if (!deviceId || !Array.isArray(messages) || messages.length === 0 || messages.length > 8) {
      return json({ error: "bad request" }, 400);
    }

    // 기기별 일일 상한 (KV)
    const today = new Date().toISOString().slice(0, 10);
    const limitKey = `${deviceId}:${today}`;
    const used = parseInt((await env.LIMITS.get(limitKey)) || "0", 10);
    if (used >= DAILY_LIMIT_PER_DEVICE) {
      return json({ error: "daily limit" }, 429);
    }
    await env.LIMITS.put(limitKey, String(used + 1), { expirationTtl: 172800 });

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
          role: m.role === "user" ? "user" : "assistant",
          content: String(m.content).slice(0, 2000),
        })),
      }),
    });

    if (!anthropicResponse.ok) {
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
