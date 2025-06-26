
import React, { useState, useEffect } from 'react';
import { Label } from '@/components/ui/label';
import {
  EditorRoot,
  EditorContent,
  EditorCommand,
  EditorCommandItem,
  EditorCommandList,
  EditorCommandEmpty,
  type JSONContent,
  type EditorInstance,
  StarterKit,
  Placeholder,
  TiptapLink,
  TiptapImage,
  TaskList,
  TaskItem,
  HorizontalRule,
  CodeBlockLowlight,
  TiptapUnderline,
  TextStyle,
  Color,
  HighlightExtension,
  CustomKeymap,
  GlobalDragHandle,
} from 'novel';
import { createLowlight, common } from 'lowlight';

interface EditItemContentEditorProps {
  content: string;
  onContentChange: (content: string) => void;
}

const EditItemContentEditor = ({ content, onContentChange }: EditItemContentEditorProps) => {
  const [initialContent, setInitialContent] = useState<JSONContent | null>(null);

  // Configure extensions similar to the Novel example
  const extensions = [
    StarterKit.configure({
      bulletList: {
        HTMLAttributes: {
          class: "list-disc list-outside leading-3 -mt-2",
        },
      },
      orderedList: {
        HTMLAttributes: {
          class: "list-decimal list-outside leading-3 -mt-2",
        },
      },
      listItem: {
        HTMLAttributes: {
          class: "leading-normal -mb-2",
        },
      },
      blockquote: {
        HTMLAttributes: {
          class: "border-l-4 border-primary",
        },
      },
      codeBlock: {
        HTMLAttributes: {
          class: "rounded-md bg-muted text-muted-foreground border p-5 font-mono font-medium",
        },
      },
      code: {
        HTMLAttributes: {
          class: "rounded-md bg-muted px-1.5 py-1 font-mono font-medium",
          spellcheck: "false",
        },
      },
      horizontalRule: false,
      dropcursor: {
        color: "#DBEAFE",
        width: 4,
      },
      gapcursor: false,
    }),
    Placeholder.configure({
      placeholder: ({ node }) => {
        if (node.type.name === "heading") {
          return `Heading ${node.attrs.level}`;
        }
        return "Press '/' for commands or start typing...";
      },
      includeChildren: true,
    }),
    TiptapLink.configure({
      HTMLAttributes: {
        class: "text-muted-foreground underline underline-offset-[3px] hover:text-primary transition-colors cursor-pointer",
      },
    }),
    TiptapImage.configure({
      allowBase64: true,
      HTMLAttributes: {
        class: "rounded-lg border border-muted",
      },
    }),
    TaskList.configure({
      HTMLAttributes: {
        class: "not-prose pl-2",
      },
    }),
    TaskItem.configure({
      HTMLAttributes: {
        class: "flex gap-2 items-start my-4",
      },
      nested: true,
    }),
    HorizontalRule.configure({
      HTMLAttributes: {
        class: "mt-4 mb-6 border-t border-muted-foreground",
      },
    }),
    CodeBlockLowlight.configure({
      lowlight: createLowlight(common),
    }),
    TiptapUnderline,
    TextStyle,
    Color,
    HighlightExtension.configure({
      multicolor: true,
    }),
    CustomKeymap,
    GlobalDragHandle,
  ];

  // Convert HTML string to JSONContent for the editor
  const convertHtmlToJson = (htmlString: string): JSONContent => {
    if (!htmlString || htmlString.trim() === '') {
      return {
        type: 'doc',
        content: [
          {
            type: 'paragraph',
            content: []
          }
        ]
      };
    }
    
    // Create a simple paragraph with the text content
    // Strip HTML tags for now - in a real implementation you'd want proper HTML parsing
    const textContent = htmlString.replace(/<[^>]*>/g, '');
    
    return {
      type: 'doc',
      content: [
        {
          type: 'paragraph',
          content: textContent ? [
            {
              type: 'text',
              text: textContent
            }
          ] : []
        }
      ]
    };
  };

  useEffect(() => {
    const jsonContent = convertHtmlToJson(content);
    setInitialContent(jsonContent);
  }, [content]);

  if (!initialContent) {
    return (
      <div>
        <Label className="text-base font-medium mb-3 block">Content</Label>
        <div className="border rounded-md p-4 min-h-[300px] flex items-center justify-center text-muted-foreground">
          Loading editor...
        </div>
      </div>
    );
  }

  return (
    <div>
      <Label className="text-base font-medium mb-3 block">Content</Label>
      <div className="border rounded-md">
        <EditorRoot>
          <EditorContent
            initialContent={initialContent}
            extensions={extensions}
            className="min-h-[300px] w-full max-w-none"
            editorProps={{
              attributes: {
                class: 'prose prose-sm dark:prose-invert prose-headings:font-title font-default focus:outline-none max-w-full p-4'
              }
            }}
            onUpdate={({ editor }: { editor: EditorInstance }) => {
              const html = editor.getHTML();
              onContentChange(html);
            }}
          >
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
          </EditorContent>
        </EditorRoot>
      </div>
    </div>
  );
};

export default EditItemContentEditor;
