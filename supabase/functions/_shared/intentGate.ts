// Inbound intent gate (spec: docs/superpowers/specs/
// 2026-08-29-ask-retrieval-reliability-and-intent-gate-spec.md, G1 + G5).
//
// Decides whether a free-form inbound message is something to SAVE, something
// to ANSWER, or a command about the service itself. Deterministic rules run
// first — bare URLs and media attachments are saves, never worth
// interrogating the user about — and only genuinely mixed text pays for a
// model call, which returns a confidence so the caller can ask "save it or
// answer it?" instead of guessing. Lives in _shared so the web/iOS Ask
// composer can run the same gate later (G4).
//
// Failure default is ASK at low confidence: wrongly answering is recoverable
// in one reply, silently saving someone's question as a note reads as the
// product not listening.

export type InboundIntent = 'save' | 'ask' | 'command';

export interface IntentDecision {
  intent: InboundIntent;
  confidence: 'high' | 'low';
  source: 'rule' | 'model' | 'fallback';
}

export interface RecentMessage {
  role: 'user' | 'assistant';
  content: string;
}

const URL_RE = /(https?:\/\/[^\s]+|www\.[^\s]+\.[a-z]{2,}[^\s]*)/gi;

const QUESTION_START_RE =
  /^(what|who|whom|whose|when|where|which|why|how|did|do|does|is|are|was|were|can|could|would|will|have i|has|show me|find|search|remind me what)\b/i;

export const isQuestionish = (text: string): boolean => {
  const t = text.trim();
  if (!t) return false;
  return t.endsWith('?') || QUESTION_START_RE.test(t);
};

export const firstUrl = (text: string): string | null => {
  URL_RE.lastIndex = 0;
  const m = URL_RE.exec(text || '');
  return m ? m[0] : null;
};

export async function classifyInbound(input: {
  text: string;
  hasMedia: boolean;
  recentMessages?: RecentMessage[];
  openaiApiKey: string;
}): Promise<IntentDecision> {
  const text = (input.text || '').trim();

  // --- Rules: act, don't ask ---
  if (input.hasMedia && !isQuestionish(text)) {
    return { intent: 'save', confidence: 'high', source: 'rule' };
  }
  if (!text) {
    // No text and no media shouldn't reach us; treat as save-noop upstream.
    return { intent: 'save', confidence: 'high', source: 'rule' };
  }
  const url = firstUrl(text);
  if (url) {
    const leftover = text.replace(URL_RE, ' ').replace(/\s+/g, ' ').trim();
    if (leftover.length < 80 && !isQuestionish(leftover)) {
      return { intent: 'save', confidence: 'high', source: 'rule' };
    }
  }

  // --- Model: mixed text ---
  try {
    const history = (input.recentMessages ?? [])
      .slice(-4)
      .map((m) => `${m.role}: ${m.content.slice(0, 200)}`)
      .join('\n');
    const response = await fetch('https://api.openai.com/v1/chat/completions', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${input.openaiApiKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        model: 'gpt-4o-mini',
        response_format: { type: 'json_object' },
        messages: [
          {
            role: 'system',
            content: `You classify one inbound message to Stash, a personal memory app where users both SAVE things (notes, reminders, links, ideas, quotes) and ASK about things they saved earlier.

Return JSON: {"intent": "save" | "ask" | "command", "confidence": "high" | "low"}

- "save": the message IS content to keep ("remember to call Dr. Green", "the wifi password is hunter2", a book title, an idea, a quote).
- "ask": the message wants an answer from their saved content ("what was that chair I liked", "do I have anything about Claude", a bare topic word they're looking up).
- "command": about the service itself ("help", "delete my last note", "what can you do").
- confidence "high" only when the reading is unmistakable. Imperatives like "remember X" are high save; questions are high ask. A bare noun phrase with no verb ("dentist tuesday 3pm" vs "that pasta place") is often genuinely ambiguous — use "low".${input.hasMedia ? '\n\nThe message has a media attachment with this caption.' : ''}${history ? `\n\nRecent conversation (may disambiguate follow-ups):\n${history}` : ''}`,
          },
          { role: 'user', content: text },
        ],
        max_tokens: 30,
        temperature: 0,
      }),
    });
    if (!response.ok) throw new Error(`classifier HTTP ${response.status}`);
    const data = await response.json();
    const parsed = JSON.parse(data.choices?.[0]?.message?.content ?? '{}');
    const intent: InboundIntent = ['save', 'ask', 'command'].includes(parsed.intent) ? parsed.intent : 'ask';
    const confidence = parsed.confidence === 'high' ? 'high' : 'low';
    return { intent, confidence, source: 'model' };
  } catch (error) {
    console.error('intentGate classify failed:', error);
    return { intent: 'ask', confidence: 'low', source: 'fallback' };
  }
}
