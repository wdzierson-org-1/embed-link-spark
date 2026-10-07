
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
  type UploadFn,
} from 'novel';
import { createLowlight, common } from 'lowlight';
import { slashCommand } from './SlashCommand';
import { toast } from 'sonner';

interface EditorExtensionOptions {
  /** Override the empty-paragraph hint (headings keep their level hint) */
  placeholder?: string;
  /** Compact card editor: keep the schema, omit slash/drag chrome. */
  inline?: boolean;
}

export const createEditorExtensions = (uploadFn?: UploadFn, options?: EditorExtensionOptions) => {
  // The slash hint lives beside the editor in the machine voice ("type / for
  // formatting"), so the empty line only says what goes here
  const emptyHint = options?.placeholder ?? 'Add a note…';
  const baseExtensions = [
    StarterKit.configure({
      heading: {
        HTMLAttributes: {
          class: "font-bold",
        },
        levels: [1, 2, 3, 4, 5, 6],
      },
      bulletList: {
        HTMLAttributes: {
          class: "list-disc list-outside leading-normal ml-4",
        },
      },
      orderedList: {
        HTMLAttributes: {
          class: "list-decimal list-outside leading-normal ml-4",
        },
      },
      listItem: {
        HTMLAttributes: {
          class: "leading-normal mb-1",
        },
      },
      blockquote: {
        HTMLAttributes: {
          class: "border-l-2 border-ink pl-4 italic",
        },
      },
      codeBlock: options?.inline ? false : {
        HTMLAttributes: {
          class: "bg-fill text-ink border border-line p-5 font-code text-[13px] leading-[1.6]",
        },
      },
      code: {
        HTMLAttributes: {
          class: "bg-fill px-1 py-px font-code text-[0.86em]",
          spellcheck: "false",
        },
      },
      horizontalRule: false,
      dropcursor: {
        color: "#a3f53b",
        width: 4,
      },
      gapcursor: false,
    }),
    Placeholder.configure({
      placeholder: ({ node, pos }) => {
        if (node.type.name === "heading") {
          return `Heading ${node.attrs.level}`;
        }
        // Only the doc's first paragraph carries the hint — nested empties
        // (a fresh to-do row, a paragraph inside a quote) stay quiet
        return pos === 0 ? emptyHint : "";
      },
      includeChildren: true,
    }),
    TiptapLink.configure({
      HTMLAttributes: {
        class: "text-ink underline decoration-ink/40 underline-offset-[3px] hover:decoration-ink transition-colors cursor-pointer",
      },
      openOnClick: false,
    }),
    TiptapImage.configure({
      allowBase64: true,
      HTMLAttributes: {
        class: "rounded-object border border-line max-w-full h-auto",
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
    ...(options?.inline ? [] : [CustomKeymap, GlobalDragHandle, slashCommand]),
  ];

  if (uploadFn) {
    console.log('EditorExtensions: Upload function provided, image uploads will be handled by Novel');
  }

  return baseExtensions;
};

export const createReadOnlyEditorExtensions = () => {
  return [
    StarterKit.configure({
      heading: {
        HTMLAttributes: {
          class: "font-bold",
        },
        levels: [1, 2, 3, 4, 5, 6],
      },
      bulletList: {
        HTMLAttributes: {
          class: "list-disc list-outside leading-normal ml-4",
        },
      },
      orderedList: {
        HTMLAttributes: {
          class: "list-decimal list-outside leading-normal ml-4",
        },
      },
      listItem: {
        HTMLAttributes: {
          class: "leading-normal mb-1",
        },
      },
      blockquote: {
        HTMLAttributes: {
          class: "border-l-2 border-ink pl-4 italic",
        },
      },
      codeBlock: {
        HTMLAttributes: {
          class: "bg-fill text-ink border border-line p-5 font-code text-[13px] leading-[1.6]",
        },
      },
      code: {
        HTMLAttributes: {
          class: "bg-fill px-1 py-px font-code text-[0.86em]",
          spellcheck: "false",
        },
      },
      horizontalRule: false,
      dropcursor: false,
      gapcursor: false,
    }),
    TiptapLink.configure({
      HTMLAttributes: {
        class: "text-ink underline decoration-ink/40 underline-offset-[3px] hover:decoration-ink transition-colors cursor-pointer",
      },
      openOnClick: true, // Enable clicking links in read-only mode
    }),
    TiptapImage.configure({
      allowBase64: true,
      HTMLAttributes: {
        class: "rounded-object border border-line max-w-full h-auto",
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
  ];
};
