
import React, { useEffect, useState } from 'react';
import { Download, ExternalLink } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { renderPdfFirstPage } from '@/utils/pdfPreview';

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
        <div className="h-64 animate-pulse rounded-[14px] border border-black/[0.07] bg-black/[0.03] motion-reduce:animate-none" />
      )}
      {preview.url && (
        <button
          type="button"
          onClick={handleOpenDocument}
          title="Open document in new tab"
          aria-label="Open document in new tab"
          className="group/preview relative block w-full overflow-hidden rounded-[14px] border border-black/[0.07] bg-white shadow-[0_1px_2px_rgba(20,22,30,0.05),0_8px_24px_rgba(30,33,44,0.08)] transition-shadow hover:shadow-[0_2px_4px_rgba(20,22,30,0.06),0_14px_36px_rgba(30,33,44,0.13)]"
        >
          <img
            src={preview.url}
            alt={`First page of ${fileName || 'document'}`}
            className="max-h-96 w-full object-contain object-top"
          />
          <div className="pointer-events-none absolute inset-0 flex items-end justify-center bg-gradient-to-t from-black/25 via-transparent to-transparent pb-3 opacity-0 transition-opacity group-hover/preview:opacity-100">
            <span className="flex items-center gap-1.5 rounded-full bg-white/95 px-3 py-1.5 text-xs font-medium text-gray-800 shadow-md">
              <ExternalLink className="h-3 w-3" />
              Open document
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
          className="inline-flex items-center gap-1.5 text-xs text-[#959ba6] transition-colors hover:text-[#6d5bd0]"
        >
          <Download className="h-[13px] w-[13px]" />
          Download original
        </a>
        <button
          onClick={handleOpenDocument}
          className="inline-flex items-center gap-1.5 text-xs text-[#959ba6] transition-colors hover:text-[#6d5bd0]"
        >
          <ExternalLink className="h-[13px] w-[13px]" />
          Open document
        </button>
      </div>
    </div>
  );
};

export default EditItemDocumentSection;
