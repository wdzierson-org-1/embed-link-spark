
import React from 'react';
import {
  EditorCommand,
  EditorCommandItem,
  EditorCommandList,
  EditorCommandEmpty,
  handleCommandNavigation,
} from 'novel';
import { suggestionItems } from './SlashCommand';

const EditorCommandMenu = () => {
  return (
    <EditorCommand className="z-50 h-auto max-h-[330px] w-72 overflow-y-auto border border-ink bg-white shadow-print-sm transition-all">
      <div className="sticky top-0 z-[1] flex h-[22px] items-center justify-between bg-ink px-2 font-pixel text-pixel leading-none text-white">
        <span>commands</span>
        <span className="text-white/60">↑↓ ⏎</span>
      </div>
      <EditorCommandEmpty className="px-2.5 py-2 font-pixel text-pixel text-muted-foreground">no matching command</EditorCommandEmpty>
      <EditorCommandList className="p-0.5">
        {suggestionItems.map((item) => (
          <EditorCommandItem
            value={item.title}
            onCommand={(val) => item.command?.(val)}
            className="group/cmd flex w-full items-center gap-2.5 px-2 py-1.5 text-left text-sm aria-selected:bg-ink aria-selected:text-white"
            key={item.title}
          >
            <div className="flex h-8 w-8 flex-none items-center justify-center border border-line bg-white text-ink group-aria-selected/cmd:border-white/30 group-aria-selected/cmd:bg-transparent group-aria-selected/cmd:text-white">
              {item.icon}
            </div>
            <div className="min-w-0">
              <p className="font-medium">{item.title}</p>
              <p className="truncate font-pixel text-pixel text-muted-foreground group-aria-selected/cmd:text-white/70">{item.description}</p>
            </div>
          </EditorCommandItem>
        ))}
      </EditorCommandList>
    </EditorCommand>
  );
};

export default EditorCommandMenu;
