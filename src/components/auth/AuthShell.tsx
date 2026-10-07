import React from 'react';
import { Link } from 'react-router-dom';
import { St4shWordmark } from '@/components/brand/St4sh';
import { MachineWindow, StatusLine } from '@/components/machine/Machine';
import { PaperBackdrop } from '@/components/machine/PaperBackdrop';
import { useDecrypt } from '@/components/machine/useDecrypt';

/**
 * The way in (DESIGN-v2 §12.14): the library's paper and texture, the wordmark home, and one
 * floating machine window with a hard print shadow, its bar titled with the page's address in
 * the code voice (`stash://sign-in`). Inside, a big Montreal line in the person's voice and a
 * cheeky prompt in the machine's, which decrypts in and waits behind a block cursor. Sign in,
 * sign up, reset and choose-a-new-password all wear it.
 */
export const AuthShell = ({
  address,
  busy,
  title,
  prompt,
  children,
}: {
  /** Shown in the bar: `stash://sign-in` */
  address: string;
  /** While a request is out, the bar says so: `| signing in…` */
  busy?: string | null;
  /** The person's line, set big: "Welcome back." */
  title: string;
  /** The machine's aside under it: "knock knock. who's there?" */
  prompt: string;
  children: React.ReactNode;
}) => {
  const decrypted = useDecrypt(prompt, true);

  return (
    <div className="relative isolate flex min-h-screen flex-col bg-paper font-montreal text-ink">
      <PaperBackdrop />
      <header className="container mx-auto flex items-center px-4 pt-4">
        <Link
          to="/"
          aria-label="Stash, home"
          className="inline-flex h-9 items-center bg-white px-3 text-ink shadow-[0_0_0_1px_rgba(0,0,0,0.06)] transition-colors hover:bg-ink hover:text-white focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ink"
        >
          <St4shWordmark className="h-[14px]" />
        </Link>
      </header>

      <main className="flex flex-1 items-center justify-center px-4 py-10">
        <MachineWindow
          title={<span className="font-code text-[11px] [font-variant-ligatures:none]">{address}</span>}
          aside={busy ? <StatusLine tone="busy" className="text-white/80">{busy}</StatusLine> : null}
          barClassName="h-7 px-3"
          className="v2-print-in w-full max-w-[420px] shadow-print"
          bodyClassName="px-6 pb-7 pt-6 sm:px-8"
        >
          <h1 className="text-screen-title font-medium">{title}</h1>
          <p className="v2-caret mt-2 font-code text-[13px] text-muted-foreground [font-variant-ligatures:none]">
            <span className="sr-only">{prompt}</span>
            <span aria-hidden className={decrypted.scrambling ? 'v2-decrypting' : undefined}>
              <span className="text-ink">&gt;</span> {decrypted.display}
            </span>
          </p>
          <div className="mt-6">{children}</div>
        </MachineWindow>
      </main>

      <footer className="container mx-auto flex items-center justify-between gap-4 px-4 pb-5 font-pixel text-pixel text-muted-foreground">
        <span>save it fast. find it when you need it.</span>
        <nav aria-label="Legal" className="flex gap-4">
          <Link to="/privacy" className="hover:text-ink hover:underline">
            privacy
          </Link>
          <Link to="/terms" className="hover:text-ink hover:underline">
            terms
          </Link>
        </nav>
      </footer>
    </div>
  );
};

/** What's wrong with a field, in the machine voice, wrapping under it (a status line truncates) */
export const FieldError = ({ id, children }: { id?: string; children: React.ReactNode }) => (
  <p id={id} className="font-pixel text-pixel leading-[1.45] text-error">
    <span aria-hidden>✕ </span>
    {children}
  </p>
);

/** A quiet text action under a form: "forgot it?", "back to sign in" */
export const AuthTextAction = ({ children, ...props }: React.ButtonHTMLAttributes<HTMLButtonElement>) => (
  <button
    type="button"
    {...props}
    className="font-pixel text-pixel text-muted-foreground underline-offset-[3px] hover:text-ink hover:underline focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ink"
  >
    {children}
  </button>
);
