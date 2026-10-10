import React from 'react';

/**
 * A row of the panel's fact trees (DESIGN-v2 §12.8): a lowercase Departure Mono label on the
 * left, the fact on the right. The branch glyph (`├─`, and `└─` on the last row) comes from
 * CSS on the enclosing `.v2-tree`, so rows can come and go. Shared by the Details drawer and
 * the location section.
 */
export const FactRow = ({
  label,
  mono = false,
  children,
}: {
  label: string;
  mono?: boolean;
  children: React.ReactNode;
}) => (
  <div className="v2-tree-row flex items-baseline gap-3 py-[6px]">
    <span className="flex w-[124px] flex-none items-baseline font-pixel text-pixel lowercase text-muted-foreground">{label}</span>
    <span
      className={`min-w-0 flex-1 [overflow-wrap:anywhere] ${
        mono ? 'font-pixel text-pixel text-ink' : 'text-[14px] text-ink'
      }`}
    >
      {children}
    </span>
  </div>
);
