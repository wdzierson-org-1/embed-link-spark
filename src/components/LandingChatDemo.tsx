import React, { useEffect, useRef, useState } from 'react';
import { Maximize2, Mic, Minus, Send, Volume2 } from 'lucide-react';

// Scripted, looping replica of the in-app Ask Stash panel (ChatMole) for the
// landing page. Kept dependency-free so the landing chunk doesn't pull in
// supabase/auth code. If ChatMole's visual design changes, mirror it here.

const MoleGlyph = ({ className }: { className?: string }) => (
  <svg viewBox="586 424 134 176" fill="currentColor" className={className} aria-hidden>
    <path d="M662.882 436.064C660.343 432.928 652.745 424.888 648.723 425.218C631.503 426.662 614.854 432.253 603.262 445.753C587.108 464.564 587.541 499.498 607.725 515.435C615.558 521.669 623.683 525.093 633.184 527.935L634.778 523.356C639.443 510.591 644.431 500.28 652.078 488.924C644.276 486.269 634.138 482.096 638.038 471.185C641.257 462.176 655.336 460.522 662.77 464.389C666.655 466.247 668.705 468.967 670.798 472.548C672.22 459.272 671.626 446.857 662.882 436.064Z"/>
    <path d="M701.56 506.142C694.717 501.845 686.051 496.885 678.015 495.281C673.407 508.547 667.021 522.648 659.27 534.412C664.95 536.676 667.754 537.589 671.562 542.6C675.651 562.928 651.251 565.37 638.727 554.86C638.034 568.698 639.823 579.499 649.517 590.156C652.59 593.542 656.178 596.422 660.149 598.688C664.733 598.313 669.741 597.863 674.224 596.763C705.395 589.088 725.754 563.456 717.527 530.886C716.39 526.275 714.58 521.857 712.154 517.775C703.796 517.693 695.437 517.714 687.079 517.837L687.093 506.374C691.914 506.247 696.737 506.17 701.56 506.142Z"/>
    <path d="M628.769 543.112L588.243 543.022C588.414 557.656 591.566 570.552 602.516 581.451C612.06 590.951 625.245 596.47 638.715 598.022C638.888 598.042 639.484 597.986 639.808 597.956C639.858 597.951 639.902 597.947 639.937 597.944L640.233 597.562C628.187 581.492 625.166 567.991 628.011 547.91C628.242 546.307 628.495 544.708 628.769 543.112Z"/>
    <path d="M714.734 466.665C711.179 443.064 693.24 430.046 670.275 426.354C682.455 442.656 684.321 457.169 681.496 477.28L681.406 477.898L715.346 477.83C716.012 474.525 715.529 471.575 715.016 468.439C714.921 467.855 714.824 467.265 714.734 466.665Z"/>
    <path d="M666.79 493.036C665.719 492.082 665.19 492.111 663.779 491.769C658.701 499.095 643.4 522.413 644.212 530.405C645.32 531.227 646.065 531.28 647.401 531.585C652.576 523.86 666.33 502.329 666.79 493.036Z"/>
  </svg>
);

const QUESTION = 'Which NYC restaurants have I saved?';
const PASTED_URL = 'cnn.com/travel/worlds-best-restaurants';
const SAVED_TITLE = "World's best restaurant for 2025 | CNN";

type Word = { t: string; b?: boolean };
const ANSWER: Word[] = [
  { t: "You've" }, { t: 'got' }, { t: 'three:' },
  { t: 'Jean-Georges', b: true },
  { t: 'from' }, { t: 'your' }, { t: 'fine-dining' }, { t: 'list,' },
  { t: 'The', b: true }, { t: 'Box', b: true },
  { t: 'from' }, { t: 'June,' }, { t: 'and' }, { t: 'the' },
  { t: 'roasted-pork' }, { t: 'bánh' }, { t: 'mì' }, { t: 'spot' },
  { t: 'in' }, { t: 'your' },
  { t: '"Places' }, { t: 'to' }, { t: 'try' }, { t: 'in' }, { t: 'NYC"' }, { t: 'note.' },
];

type Stage =
  | 'empty' | 'typing1' | 'thinking' | 'streaming' | 'answered'
  | 'typing2' | 'saving' | 'saved' | 'fade';

const LandingChatDemo = () => {
  const [stage, setStage] = useState<Stage>('empty');
  const [typed, setTyped] = useState('');
  const [wordCount, setWordCount] = useState(0);
  const [visible, setVisible] = useState(false);
  const [reducedMotion, setReducedMotion] = useState(false);
  const rootRef = useRef<HTMLDivElement>(null);
  const threadRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const mq = window.matchMedia('(prefers-reduced-motion: reduce)');
    setReducedMotion(mq.matches);
    const onChange = (e: MediaQueryListEvent) => setReducedMotion(e.matches);
    mq.addEventListener('change', onChange);
    return () => mq.removeEventListener('change', onChange);
  }, []);

  useEffect(() => {
    const node = rootRef.current;
    if (!node) return;
    const observer = new IntersectionObserver(
      ([entry]) => setVisible(entry.isIntersecting),
      { threshold: 0.3 }
    );
    observer.observe(node);
    return () => observer.disconnect();
  }, []);

  const running = visible && !reducedMotion;

  useEffect(() => {
    if (!running) return;
    let cancelled = false;
    const sleep = (ms: number) => new Promise<void>(resolve => setTimeout(resolve, ms));
    const tick = async (ms: number) => {
      await sleep(ms);
      return !cancelled;
    };

    const run = async () => {
      while (!cancelled) {
        setStage('empty'); setTyped(''); setWordCount(0);
        if (!(await tick(1100))) return;

        setStage('typing1');
        for (let i = 1; i <= QUESTION.length; i++) {
          setTyped(QUESTION.slice(0, i));
          if (!(await tick(34))) return;
        }
        if (!(await tick(350))) return;

        setTyped(''); setStage('thinking');
        if (!(await tick(1100))) return;

        setStage('streaming');
        for (let i = 1; i <= ANSWER.length; i++) {
          setWordCount(i);
          if (!(await tick(60))) return;
        }
        setStage('answered');
        if (!(await tick(2600))) return;

        setStage('typing2');
        for (let i = 1; i <= PASTED_URL.length; i++) {
          setTyped(PASTED_URL.slice(0, i));
          if (!(await tick(22))) return;
        }
        if (!(await tick(350))) return;

        setTyped(''); setStage('saving');
        if (!(await tick(1300))) return;
        setStage('saved');
        if (!(await tick(3400))) return;

        setStage('fade');
        if (!(await tick(600))) return;
      }
    };

    void run();
    return () => { cancelled = true; };
  }, [running]);

  // Reduced motion gets the finished conversation, no animation.
  const effStage: Stage = reducedMotion ? 'saved' : stage;
  const effWords = reducedMotion ? ANSWER.length : wordCount;
  const effTyped = reducedMotion ? '' : typed;

  const showUser = effStage !== 'empty' && effStage !== 'typing1';
  const showDots = effStage === 'thinking';
  const showAssistant = showUser && effStage !== 'thinking';
  const answerDone = showAssistant && effStage !== 'streaming';
  const showSavedCard = effStage === 'saving' || effStage === 'saved' || effStage === 'fade';
  const savedResolved = effStage === 'saved' || effStage === 'fade';
  const isTyping = effStage === 'typing1' || effStage === 'typing2';

  useEffect(() => {
    const thread = threadRef.current;
    if (thread) thread.scrollTop = thread.scrollHeight;
  }, [stage, wordCount]);

  return (
    <div
      ref={rootRef}
      role="img"
      aria-label="Demo of Ask Stash: it answers a question about saved restaurants with sources, then saves a pasted link"
      className="mx-auto flex h-[540px] w-full max-w-[400px] flex-col overflow-hidden rounded-2xl bg-gradient-to-b from-white to-[#fdf8fd] text-left shadow-[0_24px_60px_rgba(40,20,60,0.28),0_2px_8px_rgba(0,0,0,0.10)] ring-1 ring-black/5"
    >
      <div className="flex items-center gap-2.5 border-b border-black/5 px-4 py-3">
        <MoleGlyph className="h-5 w-5 text-gray-900" />
        <div className="min-w-0">
          <div className="text-sm font-semibold leading-tight text-gray-900">Ask Stash</div>
          <div className="truncate text-xs text-muted-foreground">
            Answers from your 214 items · paste links here to save them
          </div>
        </div>
        <div className="ml-auto flex gap-1.5">
          <span className="grid h-8 w-8 place-items-center rounded-lg border border-black/5 bg-white text-muted-foreground shadow-sm">
            <Maximize2 className="h-3.5 w-3.5" />
          </span>
          <span className="grid h-8 w-8 place-items-center rounded-lg border border-black/5 bg-white text-muted-foreground shadow-sm">
            <Minus className="h-4 w-4" />
          </span>
        </div>
      </div>

      <div
        ref={threadRef}
        className={`flex-1 space-y-3.5 overflow-y-hidden px-4 py-4 transition-opacity duration-500 ${effStage === 'fade' ? 'opacity-0' : 'opacity-100'}`}
      >
        {!showUser && (
          <div className="rounded-xl bg-muted/60 px-4 py-3 text-sm text-muted-foreground">
            Ask anything about what you've saved — or paste a link here and I'll stash it.
            Start a message with <b>remember:</b> to save a quick note.
          </div>
        )}

        {showUser && (
          <div className="ml-auto max-w-[86%] rounded-2xl rounded-br-sm bg-gray-900 px-3.5 py-2.5 text-sm text-white">
            {QUESTION}
          </div>
        )}

        {showDots && (
          <div className="flex gap-1.5 px-1 py-1">
            <span className="h-2 w-2 animate-bounce rounded-full bg-muted-foreground/50" />
            <span className="h-2 w-2 animate-bounce rounded-full bg-muted-foreground/50 [animation-delay:120ms]" />
            <span className="h-2 w-2 animate-bounce rounded-full bg-muted-foreground/50 [animation-delay:240ms]" />
          </div>
        )}

        {showAssistant && (
          <div className="max-w-[92%] rounded-2xl rounded-bl-sm bg-muted/70 px-3.5 py-2.5 text-sm text-gray-900">
            <p>
              {ANSWER.slice(0, effWords).map((word, i) => (
                <span key={i} className={word.b ? 'font-semibold' : undefined}>{word.t}{' '}</span>
              ))}
            </p>
            {answerDone && (
              <>
                <span className="mt-1 inline-grid h-6 w-6 place-items-center rounded-md bg-black/5 text-muted-foreground">
                  <Volume2 className="h-3.5 w-3.5" />
                </span>
                <div className="mt-2 border-t border-muted pt-2 text-sm text-muted-foreground">
                  Source(s): <span className="underline">Places to try in NYC</span>,{' '}
                  <span className="underline">Jean-Georges</span>.{' '}
                  <span className="underline">View all sources</span>
                </div>
              </>
            )}
          </div>
        )}

        {showSavedCard && (
          <div className="flex w-[92%] items-center gap-3 rounded-xl border border-border bg-white px-3 py-2.5">
            <div className="h-9 w-9 flex-none rounded-lg bg-blue-500" />
            <div className="min-w-0">
              <div className="truncate text-[13px] font-semibold leading-tight text-gray-900">
                {savedResolved ? SAVED_TITLE : 'Saving…'}
              </div>
              {savedResolved ? (
                <div className="text-[11.5px] text-green-600">✓ Saved to your stash · describing it now…</div>
              ) : (
                <div className="text-[11.5px] text-muted-foreground">Reading the page…</div>
              )}
            </div>
          </div>
        )}
      </div>

      <div className="border-t border-border px-3.5 py-3">
        <div className="flex items-center gap-2">
          <div className="flex h-10 flex-1 items-center overflow-hidden rounded-xl border border-border bg-gray-50 px-3 text-sm">
            {effTyped ? (
              <span className="whitespace-nowrap text-gray-900">{effTyped}</span>
            ) : (
              <span className="text-muted-foreground">Ask, or paste something to save…</span>
            )}
            {isTyping && <span className="ml-px h-4 w-0.5 flex-none animate-pulse bg-gray-500" />}
          </div>
          <span className="grid h-10 w-10 flex-none place-items-center rounded-xl border border-border bg-white text-gray-700">
            <Mic className="h-4 w-4" />
          </span>
          <span className={`grid h-10 w-10 flex-none place-items-center rounded-xl bg-violet-500 text-white transition-opacity ${effTyped ? 'opacity-100' : 'opacity-50'}`}>
            <Send className="h-4 w-4" />
          </span>
        </div>
        <div className="mt-2 text-[11.5px] text-muted-foreground">
          Answers come with sources · <b>links pasted here are saved</b> · <b>remember:</b> saves a note
        </div>
      </div>
    </div>
  );
};

export default LandingChatDemo;
