import React, { useState } from 'react';
import { ExternalLink } from 'lucide-react';
import { domainOfUrl } from '@/utils/linkFlavor';

interface EditItemLinkSectionProps {
  url: string;
}

/** Hairline link row: favicon · mono url · open — no boxed section */
const EditItemLinkSection = ({ url }: EditItemLinkSectionProps) => {
  const [faviconFailed, setFaviconFailed] = useState(false);
  const domain = domainOfUrl(url);

  const handleOpenLink = () => {
    window.open(url, '_blank', 'noopener,noreferrer');
  };

  return (
    <div className="flex items-center gap-2.5 rounded-xl border border-black/[0.07] bg-white/70 px-3.5 py-2.5">
      {domain && !faviconFailed && (
        <img
          src={`https://www.google.com/s2/favicons?domain=${domain}&sz=32`}
          alt=""
          aria-hidden
          className="h-4 w-4 flex-none rounded"
          onError={() => setFaviconFailed(true)}
        />
      )}
      <span className="min-w-0 flex-1 truncate font-mono text-[12.5px] text-[#646b76]">
        {url}
      </span>
      <button
        onClick={handleOpenLink}
        title="Open link"
        aria-label="Open link"
        className="grid flex-none place-items-center text-[#959ba6] transition-colors hover:text-[#6d5bd0]"
      >
        <ExternalLink className="h-3.5 w-3.5" />
      </button>
    </div>
  );
};

export default EditItemLinkSection;
