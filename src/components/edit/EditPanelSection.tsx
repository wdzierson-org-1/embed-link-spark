import React from 'react';

/**
 * Panel section grammar (DESIGN.md): every section is an uppercase 11px
 * micro-label (weight 600, +0.11em tracking, faint color) over a 1px hairline
 * rule — never a nested card or box. Dotted rules appear only between facts
 * rows inside the Details drawer.
 */

export const SECTION_LABEL_CLASS =
  'text-[11px] font-semibold uppercase tracking-[0.11em] text-[#959ba6]';

interface SectionHeadProps {
  label: React.ReactNode;
  aside?: React.ReactNode;
  className?: string;
}

export const SectionHead = ({ label, aside, className = '' }: SectionHeadProps) => (
  <div
    className={`flex items-center justify-between gap-3 border-b border-black/[0.07] pb-[7px] ${className}`}
  >
    <span className={SECTION_LABEL_CLASS}>{label}</span>
    {aside}
  </div>
);
