import { useState, useEffect } from 'react';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Button } from '@/components/ui/button';
import { useProfile } from '@/hooks/useProfile';
import { Copy, ExternalLink, Loader2 } from 'lucide-react';
import { useToast } from '@/hooks/use-toast';

const AccountSettings = () => {
  const { profile, email, loading, saving, updateProfile, updateEmail } = useProfile();
  const { toast } = useToast();
  
  const [formData, setFormData] = useState({
    first_name: '',
    last_name: '',
    display_name: '',
    email: ''
  });
  
  const [isDirty, setIsDirty] = useState(false);

  useEffect(() => {
    if (profile) {
      setFormData({
        first_name: profile.first_name || '',
        last_name: profile.last_name || '',
        display_name: profile.display_name || '',
        email: email
      });
    }
  }, [profile, email]);

  const handleChange = (field: string, value: string) => {
    setFormData(prev => ({ ...prev, [field]: value }));
    setIsDirty(true);
  };

  const handleSave = async () => {
    // Update profile fields
    await updateProfile({
      first_name: formData.first_name,
      last_name: formData.last_name,
      display_name: formData.display_name
    });

    // Update email if changed
    if (formData.email !== email) {
      await updateEmail(formData.email);
    }

    setIsDirty(false);
  };

  const copyFeedUrl = () => {
    const url = `https://gostash.it/feed/${profile?.username}`;
    navigator.clipboard.writeText(url);
    toast({
      title: "Copied!",
      description: "Feed URL copied to clipboard"
    });
  };

  const openFeedUrl = () => {
    const url = `https://gostash.it/feed/${profile?.username}`;
    window.open(url, '_blank');
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
    <Card>
      <CardHeader>
        <CardTitle>Your Information</CardTitle>
        <CardDescription>
          Manage your personal information and account details
        </CardDescription>
      </CardHeader>
      <CardContent className="space-y-6">
        <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
          <div className="space-y-2">
            <Label htmlFor="first_name">First Name</Label>
            <Input
              id="first_name"
              value={formData.first_name}
              onChange={(e) => handleChange('first_name', e.target.value)}
              placeholder="Enter your first name"
            />
          </div>

          <div className="space-y-2">
            <Label htmlFor="last_name">Last Name</Label>
            <Input
              id="last_name"
              value={formData.last_name}
              onChange={(e) => handleChange('last_name', e.target.value)}
              placeholder="Enter your last name"
            />
          </div>
        </div>

        <div className="space-y-2">
          <Label htmlFor="display_name">Display Name</Label>
          <Input
            id="display_name"
            value={formData.display_name}
            onChange={(e) => handleChange('display_name', e.target.value)}
            placeholder="Enter your display name"
          />
        </div>

        <div className="space-y-2">
          <Label htmlFor="email">Email</Label>
          <Input
            id="email"
            type="email"
            value={formData.email}
            onChange={(e) => handleChange('email', e.target.value)}
            placeholder="Enter your email"
          />
        </div>

        <div className="space-y-2">
          <Label htmlFor="username">Username</Label>
          <Input
            id="username"
            value={profile?.username || ''}
            disabled
            className="bg-muted"
          />
          <p className="text-xs text-muted-foreground">
            Your username cannot be changed
          </p>
        </div>

        <div className="space-y-2">
          <Label htmlFor="feed_url">Public Feed URL</Label>
          <div className="flex gap-2">
            <Input
              id="feed_url"
              value={`https://gostash.it/feed/${profile?.username}`}
              disabled
              className="bg-muted flex-1"
            />
            <Button
              variant="outline"
              size="icon"
              onClick={copyFeedUrl}
              title="Copy URL"
            >
              <Copy className="h-4 w-4" />
            </Button>
            <Button
              variant="outline"
              size="icon"
              onClick={openFeedUrl}
              title="Open in new tab"
            >
              <ExternalLink className="h-4 w-4" />
            </Button>
          </div>
        </div>

        <div className="flex justify-end">
          <Button
            onClick={handleSave}
            disabled={!isDirty || saving}
          >
            {saving && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}
            Save Changes
          </Button>
        </div>
      </CardContent>
    </Card>
  );
};

export default AccountSettings;
