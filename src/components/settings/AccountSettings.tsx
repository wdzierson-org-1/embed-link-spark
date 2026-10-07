import { useState, useEffect } from 'react';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Button } from '@/components/ui/button';
import { Switch } from '@/components/ui/switch';
import { useProfile } from '@/hooks/useProfile';
import { useUserPreferences } from '@/hooks/useUserPreferences';
import { ArrowUpRight, Copy } from 'lucide-react';
import { Spinner, StatusLine } from '@/components/machine/Machine';
import { useToast } from '@/hooks/use-toast';
import DeleteAccountSection from './DeleteAccountSection';

const AccountSettings = () => {
  const { profile, email, loading, saving, updateProfile, updateEmail } = useProfile();
  const { reminderEmails, updateReminderEmails, loading: prefsLoading } = useUserPreferences();
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
      title: "Copied",
      description: "Your feed address is on the clipboard."
    });
  };

  const openFeedUrl = () => {
    const url = `https://gostash.it/feed/${profile?.username}`;
    window.open(url, '_blank');
  };

  if (loading) {
    return (
      <Card>
        <CardContent className="flex items-center justify-center pt-6">
          <StatusLine tone="busy">loading your details…</StatusLine>
        </CardContent>
      </Card>
    );
  }

  return (
    <div className="space-y-6">
    <Card>
      <CardHeader>
        <CardTitle>Your information</CardTitle>
        <CardDescription>
          Your name, the email you sign in with, and your public feed.
        </CardDescription>
      </CardHeader>
      <CardContent className="space-y-6">
        <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
          <div className="space-y-2">
            <Label htmlFor="first_name">First name</Label>
            <Input
              id="first_name"
              value={formData.first_name}
              onChange={(e) => handleChange('first_name', e.target.value)}
              placeholder="Enter your first name"
            />
          </div>

          <div className="space-y-2">
            <Label htmlFor="last_name">Last name</Label>
            <Input
              id="last_name"
              value={formData.last_name}
              onChange={(e) => handleChange('last_name', e.target.value)}
              placeholder="Enter your last name"
            />
          </div>
        </div>

        <div className="space-y-2">
          <Label htmlFor="display_name">Display name</Label>
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
            className="bg-fill font-code text-[14px] disabled:opacity-100 md:text-[14px] v2:bg-fill"
          />
          <p className="text-[13px] text-muted-foreground">
            Your username can't be changed.
          </p>
        </div>

        <div className="space-y-2">
          <Label htmlFor="feed_url">Public feed</Label>
          {/* The address as a machine strip: read it, copy it, open it */}
          <div className="flex items-stretch border border-ink bg-white">
            <Input
              id="feed_url"
              value={`https://gostash.it/feed/${profile?.username}`}
              disabled
              className="h-10 flex-1 border-0 bg-transparent font-code text-[13.5px] text-ink disabled:cursor-text disabled:opacity-100 md:text-[13.5px] v2:bg-transparent"
            />
            <button
              type="button"
              onClick={copyFeedUrl}
              title="Copy address"
              aria-label="Copy feed address"
              className="grid w-10 flex-none place-items-center border-l border-ink text-ink transition-colors hover:bg-ink hover:text-white"
            >
              <Copy className="h-4 w-4" />
            </button>
            <button
              type="button"
              onClick={openFeedUrl}
              title="Open in a new tab"
              aria-label="Open feed in a new tab"
              className="grid w-10 flex-none place-items-center border-l border-ink text-ink transition-colors hover:bg-ink hover:text-white"
            >
              <ArrowUpRight className="h-4 w-4" />
            </button>
          </div>
        </div>

        <div className="flex justify-end">
          <Button
            onClick={handleSave}
            disabled={!isDirty || saving}
          >
            {saving && <Spinner className="mr-1 font-pixel text-pixel-md leading-none" />}
            Save changes
          </Button>
        </div>
      </CardContent>
    </Card>
    <Card>
      <CardHeader>
        <CardTitle>Reminder emails</CardTitle>
        <CardDescription>One email a day listing the items whose reminder came due. Nothing is sent on days with no reminders.</CardDescription>
      </CardHeader>
      <CardContent className="flex items-center justify-between gap-4">
        <Label htmlFor="reminder-emails">Email me when reminders are due</Label>
        <Switch id="reminder-emails" checked={reminderEmails} onCheckedChange={updateReminderEmails} disabled={prefsLoading} />
      </CardContent>
    </Card>
    <DeleteAccountSection />
    </div>
  );
};

export default AccountSettings;
