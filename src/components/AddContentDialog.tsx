
import { useState } from 'react';
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { FileText, Link, Upload } from 'lucide-react';
import TextNoteTab from '@/components/TextNoteTab';
import LinkTab from '@/components/LinkTab';
import MediaUploadTab from '@/components/MediaUploadTab';

interface AddContentDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  onAddContent: (type: string, data: any) => Promise<void>;
  getSuggestedTags: (content: any) => Promise<string[]>;
}

const AddContentDialog = ({ open, onOpenChange, onAddContent, getSuggestedTags }: AddContentDialogProps) => {
  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-[600px] max-h-[80vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>Add Content to Stash</DialogTitle>
          <DialogDescription>
            Choose the type of content you want to add to your stash.
          </DialogDescription>
        </DialogHeader>
        
        <Tabs defaultValue="text" className="w-full">
          <TabsList className="grid w-full grid-cols-3">
            <TabsTrigger value="text" className="flex items-center gap-2">
              <FileText className="h-4 w-4" />
              Text Note
            </TabsTrigger>
            <TabsTrigger value="link" className="flex items-center gap-2">
              <Link className="h-4 w-4" />
              Link
            </TabsTrigger>
            <TabsTrigger value="media" className="flex items-center gap-2">
              <Upload className="h-4 w-4" />
              Upload
            </TabsTrigger>
          </TabsList>
          
          <TabsContent value="text" className="mt-6">
            <TextNoteTab
              onAddContent={onAddContent}
              getSuggestedTags={getSuggestedTags}
            />
          </TabsContent>
          
          <TabsContent value="link" className="mt-6">
            <LinkTab
              onAddContent={onAddContent}
              getSuggestedTags={() => []}
            />
          </TabsContent>
          
          <TabsContent value="media" className="mt-6">
            <MediaUploadTab
              onAddContent={onAddContent}
              getSuggestedTags={getSuggestedTags}
            />
          </TabsContent>
        </Tabs>
      </DialogContent>
    </Dialog>
  );
};

export default AddContentDialog;
