
import React from 'react';
import {
  EditorCommand,
  EditorCommandItem,
  EditorCommandList,
  EditorCommandEmpty,
} from 'novel';

const EditorCommandMenu = () => {
  return (
    <EditorCommand className="z-50 h-auto max-h-[330px] overflow-y-auto rounded-md border border-muted bg-background px-1 py-2 shadow-md transition-all">
      <EditorCommandEmpty className="px-2 text-muted-foreground">No results</EditorCommandEmpty>
      <EditorCommandList>
        <EditorCommandItem
          value="paragraph"
          onCommand={() => {}}
          className="flex w-full items-center space-x-2 rounded-md px-2 py-1 text-left text-sm hover:bg-accent aria-selected:bg-accent"
        >
          <div className="flex h-8 w-8 items-center justify-center rounded-md border border-muted bg-background">
            ¶
          </div>
          <div>
            <p className="font-medium">Paragraph</p>
            <p className="text-xs text-muted-foreground">Start writing with plain text</p>
          </div>
        </EditorCommandItem>
      </EditorCommandList>
    </EditorCommand>
  );
};

export default EditorCommandMenu;
