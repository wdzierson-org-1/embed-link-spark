
import React from 'react';
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { MessageSquare } from 'lucide-react';
import ChatInterface from '@/components/ChatInterface';

interface GlobalChatInterfaceProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
}

const GlobalChatInterface = ({ open, onOpenChange }: GlobalChatInterfaceProps) => {
  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-4xl max-h-[80vh] flex flex-col">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2">
            <MessageSquare className="h-5 w-5" />
            Chat with All Content
          </DialogTitle>
          <DialogDescription>
            Ask questions about all the content in your stash.
          </DialogDescription>
        </DialogHeader>
        
        <div className="flex-1 min-h-0">
          <ChatInterface
            itemId={null}
            itemTitle="All Content"
            chatEndpoint="chat-with-all-content"
          />
        </div>
      </DialogContent>
    </Dialog>
  );
};

export default GlobalChatInterface;
