
import React from 'react';
import { Button } from '@/components/ui/button';
import { Minimize } from 'lucide-react';
import EditItemContentEditor from '@/components/EditItemContentEditor';

interface MaximizedEditorProps {
  content: string;
  onContentChange: (content: string) => void;
  itemId?: string;
  editorKey: string;
  onMinimize: () => void;
}

const MaximizedEditor = ({
  content,
  onContentChange,
  itemId,
  editorKey,
  onMinimize,
}: MaximizedEditorProps) => {
  return (
    <div className="fixed inset-0 z-50 bg-background flex flex-col">
      <div className="flex items-center justify-between p-4 border-b">
        <h2 className="text-lg font-semibold">Editor</h2>
        <Button
          variant="ghost"
          size="sm"
          onClick={onMinimize}
          className="h-8 w-8 p-0"
        >
          <Minimize className="h-4 w-4" />
        </Button>
      </div>
      
      <div className="flex-1 p-6 overflow-y-auto">
        <div className="max-w-4xl mx-auto">
          <EditItemContentEditor
            content={content}
            onContentChange={onContentChange}
            itemId={itemId}
            editorInstanceKey={editorKey}
          />
        </div>
      </div>
    </div>
  );
};

export default MaximizedEditor;
