import { useState, useEffect } from 'react';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Switch } from '@/components/ui/switch';
import { Label } from '@/components/ui/label';
import { Input } from '@/components/ui/input';
import { useToast } from '@/hooks/use-toast';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/hooks/useAuth';
import { Copy, ExternalLink } from 'lucide-react';

export const ProfileSettings = () => {
  const [username, setUsername] = useState('');
  const [publicFeedEnabled, setPublicFeedEnabled] = useState(true);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const { user } = useAuth();
  const { toast } = useToast();

  const publicFeedUrl = username ? `https://gostash.it/feed/${username}` : '';

  useEffect(() => {
    if (user) {
      fetchProfile();
    }
  }, [user]);

  const fetchProfile = async () => {
    try {
      const { data, error } = await supabase
        .from('user_profiles')
        .select('username, public_feed_enabled')
        .eq('id', user?.id)
        .single();

      if (error) throw error;

      if (data) {
        setUsername(data.username);
        setPublicFeedEnabled(data.public_feed_enabled);
      }
    } catch (error) {
      console.error('Error fetching profile:', error);
      toast({
        title: 'Error',
        description: 'Failed to load profile settings',
        variant: 'destructive',
      });
    } finally {
      setLoading(false);
    }
  };

  const handleTogglePublicFeed = async (enabled: boolean) => {
    setSaving(true);
    try {
      const { error } = await supabase
        .from('user_profiles')
        .update({ public_feed_enabled: enabled })
        .eq('id', user?.id);

      if (error) throw error;

      setPublicFeedEnabled(enabled);
      toast({
        title: 'Success',
        description: enabled 
          ? 'Your public feed is now enabled' 
          : 'Your public feed is now disabled',
      });
    } catch (error) {
      console.error('Error updating public feed setting:', error);
      toast({
        title: 'Error',
        description: 'Failed to update public feed setting',
        variant: 'destructive',
      });
    } finally {
      setSaving(false);
    }
  };

  const copyToClipboard = () => {
    navigator.clipboard.writeText(publicFeedUrl);
    toast({
      title: 'Copied!',
      description: 'Public feed URL copied to clipboard',
    });
  };

  if (loading) {
    return (
      <Card>
        <CardHeader>
          <CardTitle>Profile Settings</CardTitle>
          <CardDescription>Loading...</CardDescription>
        </CardHeader>
      </Card>
    );
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle>Profile Settings</CardTitle>
        <CardDescription>
          Manage your public profile and feed settings
        </CardDescription>
      </CardHeader>
      <CardContent className="space-y-6">
        {/* Username Display */}
        <div className="space-y-2">
          <Label htmlFor="username">Username</Label>
          <Input
            id="username"
            value={username}
            disabled
            className="bg-muted"
          />
          <p className="text-xs text-muted-foreground">
            Your username cannot be changed after signup
          </p>
        </div>

        {/* Public Feed Toggle */}
        <div className="space-y-4">
          <div className="flex items-center justify-between">
            <div className="space-y-0.5">
              <Label htmlFor="public-feed">Public Feed</Label>
              <p className="text-sm text-muted-foreground">
                Allow others to view your public items
              </p>
            </div>
            <Switch
              id="public-feed"
              checked={publicFeedEnabled}
              onCheckedChange={handleTogglePublicFeed}
              disabled={saving}
            />
          </div>

          {publicFeedEnabled && (
            <div className="space-y-2 p-4 bg-muted rounded-lg">
              <Label>Your Public Feed URL</Label>
              <div className="flex gap-2">
                <Input
                  value={publicFeedUrl}
                  readOnly
                  className="font-mono text-sm"
                />
                <Button
                  variant="outline"
                  size="icon"
                  onClick={copyToClipboard}
                  title="Copy URL"
                >
                  <Copy className="h-4 w-4" />
                </Button>
                <Button
                  variant="outline"
                  size="icon"
                  onClick={() => window.open(publicFeedUrl, '_blank')}
                  title="Open in new tab"
                >
                  <ExternalLink className="h-4 w-4" />
                </Button>
              </div>
              <p className="text-xs text-muted-foreground">
                Share this URL to let others view your public items
              </p>
            </div>
          )}
        </div>
      </CardContent>
    </Card>
  );
};
