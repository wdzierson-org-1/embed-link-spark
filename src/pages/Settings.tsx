import { useAuth } from '@/hooks/useAuth';
import { useNavigate } from 'react-router-dom';
import { useEffect } from 'react';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { Settings as SettingsIcon, Smartphone, User, Crown, Tag } from 'lucide-react';
import PhoneNumberSetup from '@/components/PhoneNumberSetup';
import SubscriptionSettings from '@/components/SubscriptionSettings';
import AccountSettings from '@/components/settings/AccountSettings';
import TagsSettings from '@/components/settings/TagsSettings';
import HeaderSection from '@/components/HeaderSection';

const Settings = () => {
  const { user, loading } = useAuth();
  const navigate = useNavigate();

  useEffect(() => {
    if (!loading && !user) {
      navigate('/auth');
    }
  }, [loading, user, navigate]);

  if (loading) {
    return (
      <div className="min-h-screen bg-white flex items-center justify-center">
        <div className="text-center">
          <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-primary mx-auto"></div>
          <p className="mt-4 text-muted-foreground">Loading...</p>
        </div>
      </div>
    );
  }

  if (!user) {
    return null;
  }

  return (
    <div className="min-h-screen bg-white">
      <HeaderSection user={user} />
      
      <div className="container mx-auto py-8 px-4 max-w-4xl">
      <div className="flex items-center gap-2 mb-6">
        <SettingsIcon className="h-6 w-6" />
        <h1 className="text-2xl font-bold">Settings</h1>
      </div>

      <Tabs defaultValue="account" className="w-full">
        <TabsList className="grid w-full grid-cols-4 mb-6">
          <TabsTrigger value="account" className="flex items-center gap-2">
            <User className="h-4 w-4" />
            Your Information
          </TabsTrigger>
          <TabsTrigger value="phone" className="flex items-center gap-2">
            <Smartphone className="h-4 w-4" />
            Phone Number
          </TabsTrigger>
          <TabsTrigger value="tags" className="flex items-center gap-2">
            <Tag className="h-4 w-4" />
            Tags
          </TabsTrigger>
          <TabsTrigger value="subscription" className="flex items-center gap-2">
            <Crown className="h-4 w-4" />
            Subscription
          </TabsTrigger>
        </TabsList>

        <TabsContent value="account" className="mt-0">
          <AccountSettings />
        </TabsContent>

        <TabsContent value="phone" className="mt-0">
          <PhoneNumberSetup />
        </TabsContent>

        <TabsContent value="tags" className="mt-0">
          <TagsSettings />
        </TabsContent>

        <TabsContent value="subscription" className="mt-0">
          <SubscriptionSettings />
        </TabsContent>
      </Tabs>
      </div>
    </div>
  );
};

export default Settings;
