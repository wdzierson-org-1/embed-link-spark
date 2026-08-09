import React, { useState } from 'react';
import { Lightbulb, X } from 'lucide-react';

interface DismissibleHintProps {
  id: string;
  children: React.ReactNode;
}

// A one-time coach mark: shows until the user dismisses it, then never again
// (per hint id, localStorage-backed).
const DismissibleHint = ({ id, children }: DismissibleHintProps) => {
  const storageKey = `stash_hint_dismissed_${id}`;
  const [dismissed, setDismissed] = useState(() => {
    try {
      return localStorage.getItem(storageKey) === 'true';
    } catch {
      return false;
    }
  });

  if (dismissed) return null;

  const dismiss = () => {
    setDismissed(true);
    try {
      localStorage.setItem(storageKey, 'true');
    } catch {
      // Session-only dismissal is fine
    }
  };

  return (
    <div className="flex items-center gap-2.5 rounded-xl border border-violet-200/60 bg-violet-50/70 px-3.5 py-2.5 text-[13px] text-violet-900/80 shadow-[0_1px_2px_rgba(0,0,0,0.04)]">
      <Lightbulb className="h-4 w-4 flex-none text-violet-500" />
      <div className="min-w-0 flex-1">{children}</div>
      <button
        onClick={dismiss}
        aria-label="Dismiss hint"
        className="grid h-6 w-6 flex-none place-items-center rounded-md text-violet-400 hover:bg-violet-100 hover:text-violet-600"
      >
        <X className="h-3.5 w-3.5" />
      </button>
    </div>
  );
};

export default DismissibleHint;
