// src/components/auth/AuthControls.tsx
import { ArrowRight } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Spinner } from '@/components/machine/Machine';

// DESIGN-v2 forms: Montreal labels over square white fields (ink edge and spot ring on focus,
// from the shared Input), one ink button, quiet machine-voice text actions
export const field = 'h-11 text-[15px] md:text-[15px]';

/** The one ink button: its label, or the machine at work with the spinner */
export const SubmitButton = ({ busy, busyLabel, children, disabled }: { busy: boolean; busyLabel: string; children: React.ReactNode; disabled?: boolean }) => (
  <Button type="submit" disabled={busy || disabled} className="h-11 w-full justify-between px-4 text-[15px] font-medium">
    {busy ? (
      <span className="flex items-baseline gap-[0.5ch] font-pixel text-pixel">
        <Spinner />
        {busyLabel}
      </span>
    ) : (
      <>
        <span>{children}</span>
        <ArrowRight className="h-4 w-4" />
      </>
    )}
  </Button>
);
