import { useState, useEffect } from 'react';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Badge } from '@/components/ui/badge';
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
} from "@/components/ui/alert-dialog";
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/hooks/useAuth';
import { useToast } from '@/hooks/use-toast';
import { Trash2, Loader2, Search } from 'lucide-react';

interface Tag {
  id: string;
  name: string;
  usage_count: number;
}

const TagsSettings = () => {
  const { user } = useAuth();
  const { toast } = useToast();
  const [tags, setTags] = useState<Tag[]>([]);
  const [filteredTags, setFilteredTags] = useState<Tag[]>([]);
  const [loading, setLoading] = useState(true);
  const [searchQuery, setSearchQuery] = useState('');
  const [deleteTag, setDeleteTag] = useState<Tag | null>(null);
  const [deleting, setDeleting] = useState(false);

  const fetchTags = async () => {
    if (!user) return;

    try {
      setLoading(true);
      const { data, error } = await supabase
        .from('tags')
        .select('*')
        .eq('user_id', user.id)
        .order('usage_count', { ascending: false });

      if (error) throw error;

      setTags(data || []);
      setFilteredTags(data || []);
    } catch (error) {
      console.error('Error fetching tags:', error);
      toast({
        title: "Error",
        description: "Failed to load tags",
        variant: "destructive"
      });
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    fetchTags();
  }, [user]);

  useEffect(() => {
    if (searchQuery) {
      setFilteredTags(
        tags.filter(tag => 
          tag.name.toLowerCase().includes(searchQuery.toLowerCase())
        )
      );
    } else {
      setFilteredTags(tags);
    }
  }, [searchQuery, tags]);

  const handleDeleteTag = async () => {
    if (!deleteTag) return;

    try {
      setDeleting(true);

      // First delete all item_tags relationships
      const { error: itemTagsError } = await supabase
        .from('item_tags')
        .delete()
        .eq('tag_id', deleteTag.id);

      if (itemTagsError) throw itemTagsError;

      // Then delete the tag itself
      const { error: tagError } = await supabase
        .from('tags')
        .delete()
        .eq('id', deleteTag.id);

      if (tagError) throw tagError;

      toast({
        title: "Success",
        description: `Tag "${deleteTag.name}" deleted successfully`
      });

      // Refresh tags list
      await fetchTags();
      setDeleteTag(null);
    } catch (error) {
      console.error('Error deleting tag:', error);
      toast({
        title: "Error",
        description: "Failed to delete tag",
        variant: "destructive"
      });
    } finally {
      setDeleting(false);
    }
  };

  if (loading) {
    return (
      <Card>
        <CardContent className="pt-6 flex items-center justify-center">
          <Loader2 className="h-6 w-6 animate-spin" />
        </CardContent>
      </Card>
    );
  }

  return (
    <>
      <Card>
        <CardHeader>
          <CardTitle>Tags</CardTitle>
          <CardDescription>
            The tags you made before. Cards don't show them any more, but you can still tidy them here.
            Deleting a tag removes it from every item.
          </CardDescription>
        </CardHeader>
        <CardContent className="space-y-4">
          <div className="relative">
            <Search className="absolute left-3 top-1/2 transform -translate-y-1/2 h-4 w-4 text-muted-foreground" />
            <Input
              placeholder="Search tags…"
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              className="pl-9"
            />
          </div>

          {filteredTags.length === 0 ? (
            <div className="v2-dots border border-line px-4 py-8 text-center text-[15px] text-muted-foreground">
              {searchQuery ? <p>No tags match “{searchQuery}”.</p> : <p>You haven't made any tags.</p>}
            </div>
          ) : (
            <div className="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-3 gap-3">
              {filteredTags.map((tag) => (
                <div
                  key={tag.id}
                  className="flex items-center justify-between border border-line bg-white py-2 pl-3 pr-1.5 transition-colors hover:border-ink"
                >
                  <div className="flex min-w-0 flex-1 items-center gap-2">
                    <Badge variant="default" className="min-w-0 truncate">
                      {tag.name}
                    </Badge>
                    <span className="font-pixel text-pixel text-muted-foreground">
                      {tag.usage_count}
                    </span>
                  </div>
                  <Button
                    variant="ghost"
                    size="icon"
                    aria-label={`Delete tag ${tag.name}`}
                    onClick={() => setDeleteTag(tag)}
                    className="h-8 w-8 text-error hover:bg-error hover:text-white"
                  >
                    <Trash2 className="h-4 w-4" />
                  </Button>
                </div>
              ))}
            </div>
          )}
        </CardContent>
      </Card>

      <AlertDialog open={!!deleteTag} onOpenChange={() => setDeleteTag(null)}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Delete the tag “{deleteTag?.name}”?</AlertDialogTitle>
            <AlertDialogDescription>
              It comes off {deleteTag?.usage_count} {deleteTag?.usage_count === 1 ? 'item' : 'items'}. This can't be undone.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel disabled={deleting}>Cancel</AlertDialogCancel>
            <AlertDialogAction
              onClick={handleDeleteTag}
              disabled={deleting}
              className="bg-destructive text-destructive-foreground hover:bg-destructive/90"
            >
              {deleting && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}
              Delete tag
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </>
  );
};

export default TagsSettings;
