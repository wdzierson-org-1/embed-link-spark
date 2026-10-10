import React from 'react';

/**
 * A cited save in an Ask Stash answer: an inline link that opens the save's panel. It is an
 * anchor, not a button — a button is laid out as an inline-block with centred text, which
 * centred every multi-line title in the answer list (Will, 2026-10-10: "these should be left
 * aligned"); an anchor flows with the sentence around it. The href is the baked `#item=<id>`
 * link (utils/chatCitations), kept for copy and for the keyboard; the click opens the panel.
 */
const CitationLink = ({
  href,
  itemId,
  onOpen,
  children,
}: {
  href: string;
  itemId: string;
  onOpen: (itemId: string) => void;
  children: React.ReactNode;
}) => (
  <a
    href={href}
    onClick={(event) => {
      event.preventDefault();
      onOpen(itemId);
    }}
    className="font-medium text-ink underline decoration-ink/40 decoration-1 underline-offset-[3px] hover:bg-spot hover:decoration-ink"
  >
    {children}
  </a>
);

export default CitationLink;
