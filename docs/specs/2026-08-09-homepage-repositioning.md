# Homepage repositioning — 2026-08-09

## Positioning decision

Stash is not a bookmark manager. It is a capture tool for links, documents, images, and
voice notes **plus the context that made you save them** — occupying the middle between
Apple Notes (too little: easy in, impossible out) and Obsidian-class PKM systems (too
much: you become the librarian).

Approaches considered:

- **A. Capture-with-context lead** — "Save anything. Keep the context." Sells the
  distinctive capture behavior (AI reads/describes everything, no filing). **Chosen** as
  the hero: it matches Will's own positioning brief most directly.
- **B. Anti-maintenance contrast** — "second brain without the second job." Used as the
  supporting section ("More than a notes app. Less than a second job.") with a
  three-column spectrum: Notes apps / Stash / Knowledge systems. Stash's column is set in
  the display serif to typographically mark it as the one with a point of view.
- **C. Outcome-first retrieval lead** — "ask and it answers." Kept as the existing chat
  demo section and the closing CTA ("Your future self will ask. Stash will have the
  answer.").

## Honesty fixes shipped with it

- "Get Started for Free" → "Start your free trial", with explicit "7 days free, then
  $4.99/month. No credit card to start." (matches Stripe config: trial_period_days 7,
  missing_payment_method: pause).
- Removed fabricated social proof ("Join thousands…").
- Features grid now lists real capabilities (universal capture, self-describing links,
  PDF reading, voice transcription, WhatsApp capture, chat-with-sources) instead of
  aspirational use-case tiles (Health Tracking, Travel & Places…).
- Footer Privacy/Terms dead anchors → real `/privacy` and `/terms` pages (plain-language,
  name the actual subprocessors: Supabase, OpenAI, Stripe, Twilio, Firecrawl).
  **These pages need legal review before being treated as binding.**
- index.html title/description/OG updated to match.

## Explicitly out of scope (future)

- Social/interest-graph positioning (differentiator to revisit once sharing matures).
- Paid-outcome vertical positioning (e.g. "Stash for product leaders") from the external
  assessment — a go-to-market decision, not a homepage copy change.
- Feature marketing for the Mac menubar app (stash-mac) — worth adding once that app is
  updated and distributable.
