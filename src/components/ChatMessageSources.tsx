
import React from 'react';
import { Button } from '@/components/ui/button';
import {
  Tooltip,
  TooltipContent,
  TooltipProvider,
  TooltipTrigger,
} from '@/components/ui/tooltip';

interface Source {
  id: string;
  title: string;
  type: string;
  url?: string;
}

interface ChatMessageSourcesProps {
  sources: Source[];
  onSourceClick: (sourceId: string) => void;
  onViewAllSources: (sourceIds: string[]) => void;
}

const ChatMessageSources = ({ sources, onSourceClick, onViewAllSources }: ChatMessageSourcesProps) => {
  if (!sources || sources.length === 0) {
    return null;
  }

  return (
    <div className="mt-3 pt-2 border-t border-muted text-sm text-muted-foreground">
      <div className="flex flex-wrap items-center gap-1">
        <span>Source(s):</span>
        <TooltipProvider>
          {sources.map((source, index) => (
            <React.Fragment key={source.id}>
              <Tooltip>
                <TooltipTrigger asChild>
                  <Button
                    variant="link"
                    size="sm"
                    className="h-auto p-0 text-sm text-muted-foreground hover:text-foreground underline"
                    onClick={() => onSourceClick(source.id)}
                  >
                    note {index + 1}
                  </Button>
                </TooltipTrigger>
                <TooltipContent>
                  <p>{source.title}</p>
                </TooltipContent>
              </Tooltip>
              {index < sources.length - 1 && <span>,</span>}
            </React.Fragment>
          ))}
        </TooltipProvider>
        <span>.</span>
        <Button
          variant="link"
          size="sm"
          className="h-auto p-0 text-sm text-muted-foreground hover:text-foreground underline ml-1"
          onClick={() => onViewAllSources(sources.map(s => s.id))}
        >
          View all sources
        </Button>
      </div>
    </div>
  );
};

export default ChatMessageSources;
