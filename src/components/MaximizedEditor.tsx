
import React from 'react';
import { Button } from '@/components/ui/button';
import { Minimize } from 'lucide-react';
import EditItemContentEditor from '@/components/EditItemContentEditor';
import EditItemAutoSaveIndicator from '@/components/EditItemAutoSaveIndicator';

interface MaximizedEditorProps {
  content: string;
  onContentChange: (content: string) => void;
  itemId?: string;
  editorKey: string;
  saveStatus?: 'idle' | 'saving' | 'saved';
  lastSaved?: Date | null;
  onMinimize: () => void;
}

const MaximizedEditor = ({
  content,
  onContentChange,
  itemId,
  editorKey,
  saveStatus = 'idle',
  lastSaved,
  onMinimize,
}: MaximizedEditorProps) => {
  return (
    <div className="absolute inset-0 bg-background flex flex-col z-10">
      <div className="flex h-11 items-center justify-between bg-ink pl-6 pr-11 text-white">
        <h2 className="font-pixel text-pixel leading-none">notes</h2>
        <Button
          variant="ghost"
          size="sm"
          onClick={onMinimize}
          className="h-8 w-8 p-0 text-white hover:bg-white hover:text-ink"
        >
          <Minimize className="h-4 w-4" />
        </Button>
      </div>
      
      <div className="flex-1 px-6 overflow-hidden">
        <div className="max-w-4xl mx-auto h-full">
          <EditItemContentEditor
            content={content}
            onContentChange={onContentChange}
            itemId={itemId}
            editorInstanceKey={editorKey}
            isMaximized={true}
          />
        </div>
      </div>

      <div className="flex items-center justify-between gap-4 px-6 py-3">
        <EditItemAutoSaveIndicator
          saveStatus={saveStatus}
          lastSaved={lastSaved}
        />
        <span className="font-pixel text-pixel text-muted-foreground">type / for formatting</span>
      </div>
    </div>
  );
};

export default MaximizedEditor;
