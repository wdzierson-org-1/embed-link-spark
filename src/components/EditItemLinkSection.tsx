import React, { useState } from 'react';
import { ArrowUpRight } from 'lucide-react';
import { domainOfUrl } from '@/utils/linkFlavor';

interface EditItemLinkSectionProps {
  url: string;
}

/** The source address as a machine strip: favicon · the URL in Departure Mono · open */
const EditItemLinkSection = ({ url }: EditItemLinkSectionProps) => {
  const [faviconFailed, setFaviconFailed] = useState(false);
  const domain = domainOfUrl(url);

  const handleOpenLink = () => {
    window.open(url, '_blank', 'noopener,noreferrer');
  };

  return (
    <div className="flex items-stretch border border-ink bg-white">
      <div className="flex min-w-0 flex-1 items-center gap-2.5 px-3 py-2">
        {domain && !faviconFailed && (
          <img
            src={`https://www.google.com/s2/favicons?domain=${domain}&sz=32`}
            alt=""
            aria-hidden
            className="h-3.5 w-3.5 flex-none [image-rendering:pixelated]"
            onError={() => setFaviconFailed(true)}
          />
        )}
        <span className="min-w-0 flex-1 truncate font-code text-[12.5px] text-ink [font-variant-ligatures:none]" title={url}>
          {url}
        </span>
      </div>
      <button
        onClick={handleOpenLink}
        title="Open link"
        aria-label="Open link"
        className="grid w-10 flex-none place-items-center border-l border-ink text-ink transition-colors hover:bg-ink hover:text-white"
      >
        <ArrowUpRight className="h-4 w-4" />
      </button>
    </div>
  );
};

export default EditItemLinkSection;
