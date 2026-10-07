
import React from 'react';
import { StatusLine } from '@/components/machine/Machine';

interface EditItemAutoSaveIndicatorProps {
  saveStatus: 'idle' | 'saving' | 'saved';
  lastSaved?: Date | null;
}

/** The panel's save state, in the machine voice: `| saving…`, then `✓ saved 9:41 pm` */
const EditItemAutoSaveIndicator = ({ saveStatus, lastSaved }: EditItemAutoSaveIndicatorProps) => {
  if (saveStatus === 'saving') return <StatusLine tone="busy">saving…</StatusLine>;
  if (saveStatus === 'saved') {
    const at = lastSaved
      ? ` ${lastSaved.toLocaleTimeString(undefined, { hour: 'numeric', minute: '2-digit' }).toLowerCase()}`
      : '';
    return <StatusLine tone="done">saved{at}</StatusLine>;
  }
  return <StatusLine tone="idle" live={false}>changes save automatically</StatusLine>;
};

export default EditItemAutoSaveIndicator;
