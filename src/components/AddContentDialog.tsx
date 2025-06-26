
import { useState } from 'react';
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Textarea } from '@/components/ui/textarea';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { Label } from '@/components/ui/label';
import { FileText, Link, Image, Mic, Video, Plus } from 'lucide-react';
import MediaUploadTab from '@/components/MediaUploadTab';
import LinkTab from '@/components/LinkTab';
import TextNoteTab from '@/components/TextNoteTab';

interface AddContentDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  onAddContent: (type: string, data: any) => void;
  getSuggestedTags?: (content: { title?: string; content?: string; description?: string }) => Promise<string[]>;
}

const AddContentDialog = ({ open, onOpenChange, onAddContent, getSuggestedTags }: AddContentDialogProps) => {
  return (
    <>
      {/* Floating Add Button */}
      <div className="fixed bottom-6 right-6 z-50">
        <Button
          onClick={() => onOpenChange(true)}
          size="lg"
          className="rounded-full h-14 w-14 shadow-lg hover:shadow-xl transition-shadow"
        >
          <Plus className="h-6 w-6" />
        </Button>
      </div>

      <Dialog open={open} onOpenChange={onOpenChange}>
        <DialogContent className="sm:max-w-[600px] max-h-[80vh] overflow-y-auto">
          <DialogHeader>
            <DialogTitle>Add Content to Stash</DialogTitle>
            <DialogDescription>
              Choose how you want to add content to your stash.
            </DialogDescription>
          </DialogHeader>
          
          <Tabs defaultValue="media" className="w-full">
            <TabsList className="grid w-full grid-cols-3">
              <TabsTrigger value="media" className="flex items-center gap-2">
                <Image className="h-4 w-4" />
                Media
              </TabsTrigger>
              <TabsTrigger value="link" className="flex items-center gap-2">
                <Link className="h-4 w-4" />
                Link
              </TabsTrigger>
              <TabsTrigger value="text" className="flex items-center gap-2">
                <FileText className="h-4 w-4" />
                Text
              </TabsTrigger>
            </TabsList>
            
            <TabsContent value="media" className="mt-6">
              <MediaUploadTab 
                onAddContent={onAddContent}
                getSuggestedTags={getSuggestedTags || (() => Promise.resolve([]))}
              />
            </TabsContent>
            
            <TabsContent value="link" className="mt-6">
              <LinkTab 
                onAddContent={onAddContent}
                getSuggestedTags={getSuggestedTags || (() => Promise.resolve([]))}
              />
            </TabsContent>
            
            <TabsContent value="text" className="mt-6">
              <TextNoteTab 
                onAddContent={onAddContent}
                getSuggestedTags={getSuggestedTags || (() => Promise.resolve([]))}
              />
            </TabsContent>
          </Tabs>
        </DialogContent>
      </Dialog>
    </>
  );
};

export default AddContentDialog;
