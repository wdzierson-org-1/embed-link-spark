
import React from 'react';
import { ExternalLink } from 'lucide-react';
import { Button } from '@/components/ui/button';

interface EditItemLinkSectionProps {
  url: string;
}

const EditItemLinkSection = ({ url }: EditItemLinkSectionProps) => {
  const handleOpenLink = () => {
    window.open(url, '_blank', 'noopener,noreferrer');
  };

  return (
    <div className="space-y-2">
      <label className="text-sm font-medium text-muted-foreground">Link</label>
      <div className="flex items-center gap-2 p-3 border rounded-md bg-muted/50">
        <div className="flex-1 text-sm text-muted-foreground truncate">
          {url}
        </div>
        <Button
          variant="ghost"
          size="sm"
          onClick={handleOpenLink}
          className="h-7 px-2 text-xs"
        >
          <ExternalLink className="h-3 w-3 mr-1" />
          Open
        </Button>
      </div>
    </div>
  );
};

export default EditItemLinkSection;
