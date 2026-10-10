
import {
  CheckSquare,
  Code,
  Heading1,
  Heading2,
  Heading3,
  ImageIcon,
  List,
  ListOrdered,
  Text,
  TextQuote,
} from 'lucide-react';
import { Command, createSuggestionItems, renderItems } from 'novel';
import { formatLine } from './lineCommands';
import { useAuth } from '@/hooks/useAuth';
import { uploadImage } from '@/services/imageUploadService';
import { toast } from 'sonner';

// Block formats run on the current line only (formatLine): the slash text goes, the line is
// cut out of any hard-broken block it sits in, then the format lands on it alone
export const suggestionItems = createSuggestionItems([
  {
    title: "Text",
    description: "Just start typing with plain text.",
    searchTerms: ["p", "paragraph"],
    icon: <Text size={18} />,
    command: ({ editor, range }) => {
      formatLine(editor, range, (chain) => chain.clearNodes());
    },
  },
  {
    title: "To-do List",
    description: "Track tasks with a to-do list.",
    searchTerms: ["todo", "task", "list", "check", "checkbox"],
    icon: <CheckSquare size={18} />,
    command: ({ editor, range }) => {
      formatLine(editor, range, (chain) => chain.toggleTaskList());
    },
  },
  {
    title: "Heading 1",
    description: "Big section heading.",
    searchTerms: ["title", "big", "large"],
    icon: <Heading1 size={18} />,
    command: ({ editor, range }) => {
      formatLine(editor, range, (chain) => chain.setNode('heading', { level: 1 }));
    },
  },
  {
    title: "Heading 2",
    description: "Medium section heading.",
    searchTerms: ["subtitle", "medium"],
    icon: <Heading2 size={18} />,
    command: ({ editor, range }) => {
      formatLine(editor, range, (chain) => chain.setNode('heading', { level: 2 }));
    },
  },
  {
    title: "Heading 3",
    description: "Small section heading.",
    searchTerms: ["subtitle", "small"],
    icon: <Heading3 size={18} />,
    command: ({ editor, range }) => {
      formatLine(editor, range, (chain) => chain.setNode('heading', { level: 3 }));
    },
  },
  {
    title: "Bullet List",
    description: "Create a simple bullet list.",
    searchTerms: ["unordered", "point"],
    icon: <List size={18} />,
    command: ({ editor, range }) => {
      formatLine(editor, range, (chain) => chain.toggleBulletList());
    },
  },
  {
    title: "Numbered List",
    description: "Create a list with numbering.",
    searchTerms: ["ordered"],
    icon: <ListOrdered size={18} />,
    command: ({ editor, range }) => {
      formatLine(editor, range, (chain) => chain.toggleOrderedList());
    },
  },
  {
    title: "Quote",
    description: "Capture a quote.",
    searchTerms: ["blockquote"],
    icon: <TextQuote size={18} />,
    command: ({ editor, range }) => formatLine(editor, range, (chain) => chain.toggleBlockquote()),
  },
  {
    title: "Code",
    description: "Capture a code snippet.",
    searchTerms: ["codeblock"],
    icon: <Code size={18} />,
    command: ({ editor, range }) => formatLine(editor, range, (chain) => chain.toggleCodeBlock()),
  },
  {
    title: "Image",
    description: "Upload an image from your computer.",
    searchTerms: ["photo", "picture", "media"],
    icon: <ImageIcon size={18} />,
    command: ({ editor, range }) => {
      editor.chain().focus().deleteRange(range).run();
      
      // Create file input
      const input = document.createElement("input");
      input.type = "file";
      input.accept = "image/*";
      input.onchange = async () => {
        if (input.files?.length) {
          const file = input.files[0];
          
          try {
            // Get user from auth context - this will need to be passed or accessed
            // For now, we'll use a direct Supabase call
            const { supabase } = await import('@/integrations/supabase/client');
            const { data: { session } } = await supabase.auth.getSession();
            
            if (!session?.user) {
              toast.error("Please log in to upload images");
              return;
            }
            
            const result = await uploadImage({
              file,
              userId: session.user.id
            });
            
            editor.chain().focus().setImage({ src: result.publicUrl }).run();
          } catch (error) {
            console.error('Error uploading image:', error);
            toast.error('Failed to upload image');
          }
        }
      };
      input.click();
    },
  },
]);

export const slashCommand = Command.configure({
  suggestion: {
    items: () => suggestionItems,
    render: renderItems,
  },
});
