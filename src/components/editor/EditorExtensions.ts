
import {
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
import { slashCommand } from './SlashCommand';

export const createEditorExtensions = () => [
  StarterKit.configure({
    heading: {
      HTMLAttributes: {
        class: "font-title font-bold",
      },
      levels: [1, 2, 3, 4, 5, 6],
    },
    bulletList: {
      HTMLAttributes: {
        class: "list-disc list-outside leading-3 -mt-2 ml-4",
      },
    },
    orderedList: {
      HTMLAttributes: {
        class: "list-decimal list-outside leading-3 -mt-2 ml-4",
      },
    },
    listItem: {
      HTMLAttributes: {
        class: "leading-normal -mb-2",
      },
    },
    blockquote: {
      HTMLAttributes: {
        class: "border-l-4 border-primary pl-4 italic",
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
  slashCommand,
];
