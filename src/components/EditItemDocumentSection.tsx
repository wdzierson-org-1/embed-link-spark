
import React, { useEffect, useState } from 'react';
import { ExternalLink, FileText } from 'lucide-react';
import { Button } from '@/components/ui/button';
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

  const getFileIcon = () => {
    if (mimeType?.includes('pdf')) return <FileText className="h-3 w-3 text-red-600" />;
    if (mimeType?.includes('word') || mimeType?.includes('document')) return <FileText className="h-3 w-3 text-blue-600" />;
    return <FileText className="h-3 w-3 text-gray-600" />;
  };

  const getFileTypeLabel = () => {
    if (mimeType?.includes('pdf')) return 'PDF Document';
    if (mimeType?.includes('word') || mimeType?.includes('document')) return 'Word Document';
    if (mimeType?.includes('text')) return 'Text Document';
    return 'Document';
  };

  return (
    <div className="space-y-2">
      <label className="text-sm font-medium text-muted-foreground">Original Document</label>

      {/* First-page preview; clicking opens the full document in a new tab */}
      {preview.loading && (
        <div className="h-64 animate-pulse rounded-xl border border-black/5 bg-muted/60" />
      )}
      {preview.url && (
        <button
          type="button"
          onClick={handleOpenDocument}
          title="Open document in new tab"
          aria-label="Open document in new tab"
          className="group/preview relative block w-full overflow-hidden rounded-xl border border-black/10 bg-white shadow-[0_1px_2px_rgba(0,0,0,0.05),0_6px_18px_rgba(160,120,200,0.08)] transition-shadow hover:shadow-[0_2px_4px_rgba(0,0,0,0.08),0_10px_28px_rgba(160,120,200,0.14)]"
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

      <div className="flex items-center gap-2 p-3 border rounded-md bg-muted/50">
        <div className="flex items-center gap-2 flex-1">
          {getFileIcon()}
          <div className="flex-1 min-w-0">
            <div className="text-sm font-medium truncate">
              {fileName || 'Document'}
            </div>
            <div className="text-xs text-muted-foreground">
              {getFileTypeLabel()}
            </div>
          </div>
        </div>
        <Button
          variant="ghost"
          size="sm"
          onClick={handleOpenDocument}
          className="h-7 w-7 p-0"
        >
          <ExternalLink className="h-3 w-3" />
        </Button>
      </div>
    </div>
  );
};

export default EditItemDocumentSection;
