import React from 'react';

/**
 * Panel section grammar (DESIGN-v2): every section opens with a machine label, Departure
 * Mono, lowercase, over a 1 px ink rule, as on a printed form; never a nested card or box.
 * The tree rows inside the Details drawer are the only other structure.
 */

export const SECTION_LABEL_CLASS = 'font-pixel text-pixel lowercase text-ink';

interface SectionHeadProps {
  label: React.ReactNode;
  aside?: React.ReactNode;
  className?: string;
}

export const SectionHead = ({ label, aside, className = '' }: SectionHeadProps) => (
  <div className={`flex min-h-7 items-end justify-between gap-3 border-b border-ink pb-1.5 ${className}`}>
    <span className={SECTION_LABEL_CLASS}>{label}</span>
    {aside}
  </div>
);
