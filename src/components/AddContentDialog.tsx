
import { useState } from 'react';
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Textarea } from '@/components/ui/textarea';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { Label } from '@/components/ui/label';
import { FileText, Link, Image, Mic, Video } from 'lucide-react';

interface AddContentDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  onAddContent: (type: string, data: any) => void;
}

const AddContentDialog = ({ open, onOpenChange, onAddContent }: AddContentDialogProps) => {
  const [title, setTitle] = useState('');
  const [content, setContent] = useState('');
  const [url, setUrl] = useState('');
  const [file, setFile] = useState<File | null>(null);

  const handleSubmit = (type: string) => {
    const data = {
      title: title || undefined,
      content: content || undefined,
      url: url || undefined,
      file: file || undefined,
    };
    
    onAddContent(type, data);
    
    // Reset form
    setTitle('');
    setContent('');
    setUrl('');
    setFile(null);
    onOpenChange(false);
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-[425px]">
        <DialogHeader>
          <DialogTitle>Add Content to Stash</DialogTitle>
          <DialogDescription>
            Choose the type of content you want to add to your stash.
          </DialogDescription>
        </DialogHeader>
        
        <Tabs defaultValue="text" className="w-full">
          <TabsList className="grid w-full grid-cols-5">
            <TabsTrigger value="text" className="p-2">
              <FileText className="h-4 w-4" />
            </TabsTrigger>
            <TabsTrigger value="link" className="p-2">
              <Link className="h-4 w-4" />
            </TabsTrigger>
            <TabsTrigger value="image" className="p-2">
              <Image className="h-4 w-4" />
            </TabsTrigger>
            <TabsTrigger value="audio" className="p-2">
              <Mic className="h-4 w-4" />
            </TabsTrigger>
            <TabsTrigger value="video" className="p-2">
              <Video className="h-4 w-4" />
            </TabsTrigger>
          </TabsList>
          
          <TabsContent value="text" className="space-y-4">
            <div className="space-y-2">
              <Label htmlFor="text-title">Title (optional)</Label>
              <Input
                id="text-title"
                placeholder="Enter a title..."
                value={title}
                onChange={(e) => setTitle(e.target.value)}
              />
            </div>
            <div className="space-y-2">
              <Label htmlFor="text-content">Content</Label>
              <Textarea
                id="text-content"
                placeholder="Enter your text content..."
                value={content}
                onChange={(e) => setContent(e.target.value)}
                rows={6}
              />
            </div>
            <Button onClick={() => handleSubmit('text')} disabled={!content}>
              Add Text
            </Button>
          </TabsContent>
          
          <TabsContent value="link" className="space-y-4">
            <div className="space-y-2">
              <Label htmlFor="link-title">Title (optional)</Label>
              <Input
                id="link-title"
                placeholder="Enter a title..."
                value={title}
                onChange={(e) => setTitle(e.target.value)}
              />
            </div>
            <div className="space-y-2">
              <Label htmlFor="link-url">URL</Label>
              <Input
                id="link-url"
                type="url"
                placeholder="https://example.com"
                value={url}
                onChange={(e) => setUrl(e.target.value)}
              />
            </div>
            <Button onClick={() => handleSubmit('link')} disabled={!url}>
              Add Link
            </Button>
          </TabsContent>
          
          <TabsContent value="image" className="space-y-4">
            <div className="space-y-2">
              <Label htmlFor="image-title">Title (optional)</Label>
              <Input
                id="image-title"
                placeholder="Enter a title..."
                value={title}
                onChange={(e) => setTitle(e.target.value)}
              />
            </div>
            <div className="space-y-2">
              <Label htmlFor="image-file">Image File</Label>
              <Input
                id="image-file"
                type="file"
                accept="image/*"
                onChange={(e) => setFile(e.target.files?.[0] || null)}
              />
            </div>
            <Button onClick={() => handleSubmit('image')} disabled={!file}>
              Add Image
            </Button>
          </TabsContent>
          
          <TabsContent value="audio" className="space-y-4">
            <div className="space-y-2">
              <Label htmlFor="audio-title">Title (optional)</Label>
              <Input
                id="audio-title"
                placeholder="Enter a title..."
                value={title}
                onChange={(e) => setTitle(e.target.value)}
              />
            </div>
            <div className="space-y-2">
              <Label htmlFor="audio-file">Audio File</Label>
              <Input
                id="audio-file"
                type="file"
                accept="audio/*"
                onChange={(e) => setFile(e.target.files?.[0] || null)}
              />
            </div>
            <Button onClick={() => handleSubmit('audio')} disabled={!file}>
              Add Audio
            </Button>
          </TabsContent>
          
          <TabsContent value="video" className="space-y-4">
            <div className="space-y-2">
              <Label htmlFor="video-title">Title (optional)</Label>
              <Input
                id="video-title"
                placeholder="Enter a title..."
                value={title}
                onChange={(e) => setTitle(e.target.value)}
              />
            </div>
            <div className="space-y-2">
              <Label htmlFor="video-file">Video File</Label>
              <Input
                id="video-file"
                type="file"
                accept="video/*"
                onChange={(e) => setFile(e.target.files?.[0] || null)}
              />
            </div>
            <Button onClick={() => handleSubmit('video')} disabled={!file}>
              Add Video
            </Button>
          </TabsContent>
        </Tabs>
      </DialogContent>
    </Dialog>
  );
};

export default AddContentDialog;
