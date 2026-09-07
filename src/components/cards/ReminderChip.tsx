import React from 'react';
import { Bell, Clock, X } from 'lucide-react';
import { format } from 'date-fns';
import type { ReminderState } from '@/utils/reminders';

/**
 * Footer reminder indicator. Scheduled reads quiet ("in 3d"); due reads in the
 * interactive violet with an always-visible remove control (DESIGN.md: the
 * control is never hover-only; hover only strengthens colour).
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
        className="inline-flex items-center gap-1 rounded-full bg-violet-600/10 pl-2 pr-0.5 py-0.5 text-[11px] font-medium text-violet-700"
        title={`Reminder was set for ${absolute}`}
        data-testid="reminder-chip-due"
      >
        <Bell className="h-3 w-3 flex-none" />
        {label}
        <button
          type="button"
          onClick={(e) => { e.stopPropagation(); onDismiss(); }}
          aria-label="Remove reminder"
          className="ml-0.5 inline-flex h-5 w-5 items-center justify-center rounded-full text-violet-700/70 hover:bg-violet-600/15 hover:text-violet-800 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-violet-600"
        >
          <X className="h-3 w-3" />
        </button>
      </span>
    );
  }
  return (
    <span
      className="inline-flex items-center gap-1 text-[11px] text-muted-foreground"
      title={`Reminder ${absolute}`}
      data-testid="reminder-chip-scheduled"
    >
      <Clock className="h-3 w-3 flex-none" />
      {label}
    </span>
  );
};
