
import React, { useEffect, useState } from 'react';
import { Download, ExternalLink } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { renderPdfFirstPage } from '@/utils/pdfPreview';
import { PixelMosaic } from '@/components/machine/PixelMosaic';

interface EditItemDocumentSectionProps {
  filePath: string;
  fileName?: string;
  mimeType?: string;
}

const EditItemDocumentSection = ({ filePath, fileName, mimeType }: EditItemDocumentSectionProps) => {
  const { data } = supabase.storage.from('stash-media').getPublicUrl(filePath);
  const fileUrl = data.publicUrl;
  const isPdf = Boolean(mimeType?.includes('pdf')) || filePath.toLowerCase().endsWith('.pdf');

  const [preview, setPreview] = useState<{ url: string | null; loading: boolean }>({
    url: null,
    loading: isPdf,
  });

  useEffect(() => {
    if (!isPdf) return;
    let cancelled = false;
    setPreview({ url: null, loading: true });
    void renderPdfFirstPage(fileUrl).then((dataUrl) => {
      if (!cancelled) setPreview({ url: dataUrl, loading: false });
    });
    return () => {
      cancelled = true;
    };
  }, [fileUrl, isPdf]);

  const handleOpenDocument = () => {
    window.open(fileUrl, '_blank', 'noopener,noreferrer');
  };

  // Filename/format facts live in the Details drawer now — this block is only
  // the first-page preview plus quiet text actions (panel section grammar).
  return (
    <div>
      {preview.loading && (
        // The first page not yet rendered: the unresolved mosaic, as on a card being read
        <div className="h-64 overflow-hidden border border-line bg-fill">
          <PixelMosaic />
        </div>
      )}
      {preview.url && (
        <button
          type="button"
          onClick={handleOpenDocument}
          title="Open document in new tab"
          aria-label="Open document in new tab"
          className="group/preview relative block w-full overflow-hidden rounded-object border border-line bg-white shadow-object transition-[border-color,box-shadow,transform] duration-150 hover:-translate-x-0.5 hover:-translate-y-0.5 hover:border-ink hover:shadow-print"
        >
          <img
            src={preview.url}
            alt={`First page of ${fileName || 'document'}`}
            className="max-h-96 w-full object-contain object-top"
          />
          <div className="pointer-events-none absolute inset-0 flex items-end justify-center pb-3 opacity-0 transition-opacity group-hover/preview:opacity-100">
            <span className="flex items-center gap-1.5 bg-ink px-2 pb-[5px] pt-1.5 font-pixel text-pixel leading-none text-white">
              <ExternalLink className="h-3 w-3" />
              open document
            </span>
          </div>
        </button>
      )}

      <div className="mt-2 flex gap-4">
        <a
          href={fileUrl}
          download
          target="_blank"
          rel="noreferrer"
          className="inline-flex items-center gap-1.5 font-pixel text-pixel text-muted-foreground underline-offset-2 transition-colors hover:text-ink hover:underline"
        >
          <Download className="h-3 w-3" />
          download original
        </a>
        <button
          onClick={handleOpenDocument}
          className="inline-flex items-center gap-1.5 font-pixel text-pixel text-muted-foreground underline-offset-2 transition-colors hover:text-ink hover:underline"
        >
          <ExternalLink className="h-3 w-3" />
          open document
        </button>
      </div>
    </div>
  );
};

export default EditItemDocumentSection;
