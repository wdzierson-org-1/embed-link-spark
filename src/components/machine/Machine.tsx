import React from 'react';
import { cn } from '@/lib/utils';
import { useSpinnerFrame } from './spinner';

/**
 * The machine voice (DESIGN-v2 §2, §6): everything Stash says about the person's things, set
 * in Departure Mono, square, in ink. These are the shared pieces; the person's own things
 * (cards, notes, the composer) stay in Neue Montreal.
 */

/** The turning `| / - \` cursor. Decorative: the words beside it carry the state. */
export const Spinner = ({ className }: { className?: string }) => {
  const frame = useSpinnerFrame();
  return (
    <span aria-hidden className={cn('inline-block w-[1ch] text-center', className)}>
      {frame}
    </span>
  );
};

type StatusTone = 'busy' | 'done' | 'idle' | 'error';

/**
 * A one-line machine status: lowercase, present tense, `…` while busy ("| reading the page…"),
 * a check when done ("✓ saved"). Announced politely to screen readers.
 */
export const StatusLine = ({
  tone = 'busy',
  children,
  className,
  live = true,
}: {
  tone?: StatusTone;
  children: React.ReactNode;
  className?: string;
  live?: boolean;
}) => (
  <span
    role={live ? 'status' : undefined}
    aria-live={live ? 'polite' : undefined}
    className={cn(
      'inline-flex min-w-0 items-baseline gap-[0.5ch] font-pixel text-pixel',
      tone === 'error' ? 'text-error' : 'text-muted-foreground',
      className,
    )}
  >
    {tone === 'busy' && <Spinner />}
    {tone === 'done' && <span aria-hidden>✓</span>}
    <span className="min-w-0 truncate">{children}</span>
  </span>
);

type TagVariant = 'ink' | 'outline' | 'spot' | 'white';

/**
 * Tags are the machine's labels: an object's kind (`repo`, `pdf`), status, eyebrows. Black with
 * white Departure Mono by default; outlined for "coming soon"; spot when something just landed.
 */
export const Tag = ({
  variant = 'ink',
  className,
  children,
  ...rest
}: { variant?: TagVariant } & React.HTMLAttributes<HTMLSpanElement>) => (
  <span
    className={cn(
      'inline-flex items-center gap-[0.5ch] whitespace-nowrap px-1.5 pb-[3px] pt-1 font-pixel text-pixel leading-none',
      variant === 'ink' && 'bg-ink text-white',
      variant === 'outline' && 'bg-transparent text-ink shadow-[inset_0_0_0_1px_var(--ink)]',
      variant === 'white' && 'bg-white text-ink shadow-[inset_0_0_0_1px_var(--ink)]',
      variant === 'spot' && 'bg-spot text-spot-on',
      className,
    )}
    {...rest}
  >
    {children}
  </span>
);

/** Crop marks: four 14 px L-corners, 10 px outside the box, as on a press sheet */
export const CropMarks = ({ className }: { className?: string }) => {
  const corner = 'pointer-events-none absolute h-3.5 w-3.5 border-ink';
  return (
    <span aria-hidden className={className}>
      <span className={`${corner} -left-2.5 -top-2.5 border-l border-t`} />
      <span className={`${corner} -right-2.5 -top-2.5 border-r border-t`} />
      <span className={`${corner} -bottom-2.5 -left-2.5 border-b border-l`} />
      <span className={`${corner} -bottom-2.5 -right-2.5 border-b border-r`} />
    </span>
  );
};

/**
 * A window: machine output always lives in one. 1 px ink border, a 22 px black bar with a
 * Departure Mono title (and an optional right-hand label), a white body. Square, no shadow.
 */
export const MachineWindow = ({
  title,
  aside,
  barClassName,
  className,
  bodyClassName,
  children,
}: {
  title: React.ReactNode;
  aside?: React.ReactNode;
  barClassName?: string;
  className?: string;
  bodyClassName?: string;
  children?: React.ReactNode;
}) => (
  <div className={cn('border border-ink bg-white', className)}>
    <div
      className={cn(
        'flex h-[22px] items-center justify-between gap-2.5 overflow-hidden whitespace-nowrap bg-ink px-2 font-pixel text-pixel leading-none text-white',
        barClassName,
      )}
    >
      <span className="min-w-0 truncate">{title}</span>
      {aside}
    </div>
    {children !== undefined && <div className={bodyClassName}>{children}</div>}
  </div>
);
