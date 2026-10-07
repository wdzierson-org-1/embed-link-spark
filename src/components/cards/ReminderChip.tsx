import React from 'react';
import { Bell, Clock, X } from 'lucide-react';
import { format } from 'date-fns';
import type { ReminderState } from '@/utils/reminders';

/**
 * Meta-row reminder indicator, in the machine voice. Scheduled reads quiet ("in 3d"); due is
 * a black tag with an always-visible remove control (the control is never hover-only; the
 * remove target is 24 px, WCAG's floor on the web).
 */
export const ReminderChip = ({
  state,
  label,
  remindAt,
  onDismiss,
}: {
  state: ReminderState;
  label: string;
  remindAt: string;
  onDismiss: () => void;
}) => {
  const absolute = format(new Date(remindAt), 'MMM d, h:mm a');
  if (state === 'due') {
    return (
      <span
        className="inline-flex items-center gap-1 bg-ink py-0 pl-1.5 font-pixel text-pixel leading-none text-white"
        title={`Reminder was set for ${absolute}`}
        data-testid="reminder-chip-due"
      >
        <Bell className="h-3 w-3 flex-none" aria-hidden />
        {label.toLowerCase()}
        <button
          type="button"
          onClick={(e) => { e.stopPropagation(); onDismiss(); }}
          aria-label="Remove reminder"
          className="ml-0.5 inline-grid h-6 w-6 place-items-center text-white/75 hover:bg-white hover:text-ink focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-1 focus-visible:outline-white"
        >
          <X className="h-3 w-3" />
        </button>
      </span>
    );
  }
  return (
    <span
      className="inline-flex items-center gap-1 whitespace-nowrap"
      title={`Reminder ${absolute}`}
      data-testid="reminder-chip-scheduled"
    >
      <Clock className="h-3 w-3 flex-none" aria-hidden />
      {label}
    </span>
  );
};
