
import React from 'react';
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { MessageSquare } from 'lucide-react';
import ChatInterface from '@/components/ChatInterface';

interface GlobalChatInterfaceProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
}

const GlobalChatInterface = ({ open, onOpenChange }: GlobalChatInterfaceProps) => {
  // Create a mock item for global chat
  const globalChatItem = {
    id: 'global-chat',
    type: 'all-content',
    title: 'All Content',
    content: '',
    description: 'Chat with all content in your stash'
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-4xl w-full max-w-[90vw] h-[80vh] max-h-[80vh] flex flex-col p-0">
        <DialogHeader className="px-6 py-4 border-b flex-shrink-0">
          <DialogTitle className="flex items-center gap-2">
            <MessageSquare className="h-5 w-5" />
            Chat with All Content
          </DialogTitle>
          <DialogDescription>
            Ask questions about all the content in your stash.
          </DialogDescription>
        </DialogHeader>
        
        <div className="flex-1 min-h-0 overflow-hidden">
          <ChatInterface
            isOpen={open}
            onClose={() => onOpenChange(false)}
            item={globalChatItem}
          />
        </div>
      </DialogContent>
    </Dialog>
  );
};

export default GlobalChatInterface;
