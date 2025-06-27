
import React from 'react';
import { Button } from '@/components/ui/button';
import { Separator } from '@/components/ui/separator';
import { EditorBubble, EditorBubbleItem, useEditor } from 'novel';
import { 
  Bold, 
  Italic, 
  Underline, 
  Strikethrough, 
  Code, 
  Link 
} from 'lucide-react';

const EditorBubbleMenu = () => {
  const { editor } = useEditor();

  if (!editor) return null;

  const formatButtons = [
    {
      name: 'bold',
      icon: Bold,
      isActive: () => editor.isActive('bold'),
      action: () => editor.chain().focus().toggleBold().run(),
    },
    {
      name: 'italic',
      icon: Italic,
      isActive: () => editor.isActive('italic'),
      action: () => editor.chain().focus().toggleItalic().run(),
    },
    {
      name: 'underline',
      icon: Underline,
      isActive: () => editor.isActive('underline'),
      action: () => editor.chain().focus().toggleUnderline().run(),
    },
    {
      name: 'strikethrough',
      icon: Strikethrough,
      isActive: () => editor.isActive('strike'),
      action: () => editor.chain().focus().toggleStrike().run(),
    },
    {
      name: 'code',
      icon: Code,
      isActive: () => editor.isActive('code'),
      action: () => editor.chain().focus().toggleCode().run(),
    },
  ];

  const headingButtons = [
    {
      name: 'h1',
      label: 'H1',
      isActive: () => editor.isActive('heading', { level: 1 }),
      action: () => editor.chain().focus().toggleHeading({ level: 1 }).run(),
    },
    {
      name: 'h2',
      label: 'H2',
      isActive: () => editor.isActive('heading', { level: 2 }),
      action: () => editor.chain().focus().toggleHeading({ level: 2 }).run(),
    },
    {
      name: 'h3',
      label: 'H3',
      isActive: () => editor.isActive('heading', { level: 3 }),
      action: () => editor.chain().focus().toggleHeading({ level: 3 }).run(),
    },
  ];

  const handleLinkToggle = () => {
    if (editor.isActive('link')) {
      editor.chain().focus().unsetLink().run();
    } else {
      const url = window.prompt('Enter URL:');
      if (url) {
        editor.chain().focus().setLink({ href: url }).run();
      }
    }
  };

  return (
    <EditorBubble
      tippyOptions={{
        placement: 'top',
        moveTransition: 'transform 0.15s ease-out',
      }}
      className="flex items-center gap-1 p-1 bg-background border rounded-lg shadow-lg"
    >
      {/* Text Formatting */}
      {formatButtons.map((button) => (
        <EditorBubbleItem key={button.name} onSelect={() => button.action()}>
          <Button
            size="sm"
            variant="ghost"
            className={`h-8 w-8 p-0 ${button.isActive() ? 'bg-accent text-accent-foreground' : ''}`}
          >
            <button.icon className="h-4 w-4" />
          </Button>
        </EditorBubbleItem>
      ))}

      <Separator orientation="vertical" className="h-6 mx-1" />

      {/* Headings */}
      {headingButtons.map((button) => (
        <EditorBubbleItem key={button.name} onSelect={() => button.action()}>
          <Button
            size="sm"
            variant="ghost"
            className={`h-8 px-2 text-xs font-semibold ${button.isActive() ? 'bg-accent text-accent-foreground' : ''}`}
          >
            {button.label}
          </Button>
        </EditorBubbleItem>
      ))}

      <Separator orientation="vertical" className="h-6 mx-1" />

      {/* Link */}
      <EditorBubbleItem onSelect={handleLinkToggle}>
        <Button
          size="sm"
          variant="ghost"
          className={`h-8 w-8 p-0 ${editor.isActive('link') ? 'bg-accent text-accent-foreground' : ''}`}
        >
          <Link className="h-4 w-4" />
        </Button>
      </EditorBubbleItem>
    </EditorBubble>
  );
};

export default EditorBubbleMenu;
