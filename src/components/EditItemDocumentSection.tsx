import React from 'react';
import { Download, ExternalLink } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import EditItemDocumentStage, { documentKind } from '@/components/edit/EditItemDocumentStage';

interface EditItemDocumentSectionProps {
  filePath: string;
  fileName?: string;
  mimeType?: string;
}

/**
 * An upload in the item panel (DESIGN-v2 §12.8): the document itself on a stage — a PDF reader,
 * Microsoft's viewer for Office files, a sandboxed frame for HTML — then the quiet text actions.
 * Anything the panel can't show keeps only the actions. Filename/format facts live in Details.
 */
const EditItemDocumentSection = ({ filePath, fileName, mimeType }: EditItemDocumentSectionProps) => {
  const { data } = supabase.storage.from('stash-media').getPublicUrl(filePath);
  const fileUrl = data.publicUrl;
  const kind = documentKind(filePath, mimeType);

  const handleOpenDocument = () => {
    window.open(fileUrl, '_blank', 'noopener,noreferrer');
  };

  return (
    <div>
      {kind !== 'other' && <EditItemDocumentStage url={fileUrl} kind={kind} title={fileName || 'document'} />}

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
