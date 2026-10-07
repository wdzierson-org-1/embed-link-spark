import { useAuth } from '@/hooks/useAuth';
import { useNavigate } from 'react-router-dom';
import { useEffect, useState } from 'react';
import * as TabsPrimitive from '@radix-ui/react-tabs';
import { Tabs, TabsContent } from '@/components/ui/tabs';
import PhoneNumberSetup from '@/components/PhoneNumberSetup';
import SubscriptionSettings from '@/components/SubscriptionSettings';
import AccountSettings from '@/components/settings/AccountSettings';
import TagsSettings from '@/components/settings/TagsSettings';
import ConnectedAgentsSettings from '@/components/settings/ConnectedAgentsSettings';
import HeaderSection from '@/components/HeaderSection';
import { StatusLine } from '@/components/machine/Machine';
import { useIsMobile } from '@/hooks/use-mobile';

/**
 * Settings (DESIGN-v2 §12): an index on the left the way a terminal lists a menu (numbered,
 * in Departure Mono, the open section inverted to ink), and the section itself on the right
 * as plain white sheets. On a phone the index becomes a row of paper tabs.
 */
const SECTIONS = [
  { value: 'account', label: 'Your information', hint: 'name, email, feed, reminders' },
  { value: 'agents', label: 'Connected agents', hint: 'your ai, over mcp' },
  { value: 'phone', label: 'Phone & WhatsApp', hint: 'save by text message' },
  { value: 'subscription', label: 'Subscription', hint: 'plan and billing' },
  { value: 'tags', label: 'Tags', hint: 'tags you made before' },
] as const;

type SectionValue = (typeof SECTIONS)[number]['value'];
const isSection = (value: string): value is SectionValue => SECTIONS.some((s) => s.value === value);

const Settings = () => {
  const { user, loading } = useAuth();
  const navigate = useNavigate();
  const isMobile = useIsMobile();
  // A section can be linkedto directly (/settings#agents); the hash follows the index
  const [section, setSection] = useState<SectionValue>(() => {
    const fromHash = window.location.hash.replace(/^#/, '');
    return isSection(fromHash) ? fromHash : 'account';
  });

  useEffect(() => {
    if (!loading && !user) {
      navigate('/auth');
    }
  }, [loading, user, navigate]);

  const changeSection = (value: string) => {
    if (!isSection(value)) return;
    setSection(value);
    history.replaceState(null, '', `${window.location.pathname}${window.location.search}#${value}`);
  };

  if (loading) {
    return (
      <div className="flex min-h-screen items-center justify-center bg-paper">
        <StatusLine tone="busy">loading your settings…</StatusLine>
      </div>
    );
  }

  if (!user) {
    return null;
  }

  return (
    <div className="min-h-screen bg-paper">
      <HeaderSection user={user} />

      <div className="container mx-auto px-4 pb-24 pt-8">
        <div className="mb-8 sm:mb-12">
          <h1 className="text-[clamp(36px,4.6vw,60px)] font-medium leading-[0.94] tracking-[-0.045em] text-ink">Settings</h1>
          {user.email && (
            <p className="mt-3 font-pixel text-pixel text-muted-foreground">signed in as {user.email}</p>
          )}
        </div>

        <Tabs
          value={section}
          onValueChange={changeSection}
          orientation={isMobile ? 'horizontal' : 'vertical'}
          className="grid gap-6 md:grid-cols-[248px_minmax(0,780px)] md:gap-12"
        >
          <TabsPrimitive.List
            aria-label="Settings sections"
            className="-mx-4 flex gap-[3px] overflow-x-auto px-4 pb-1 md:sticky md:top-6 md:mx-0 md:flex-col md:gap-0 md:self-start md:overflow-visible md:border-t md:border-ink md:px-0 md:pb-0"
          >
            {SECTIONS.map((s, index) => (
              <TabsPrimitive.Trigger
                key={s.value}
                value={s.value}
                className="group/tab flex flex-none items-baseline gap-3 bg-white px-3 py-2 text-left text-[15px] font-medium tracking-[-0.01em] text-ink shadow-[0_0_0_1px_rgba(0,0,0,0.06)] outline-none transition-colors focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-spot data-[state=active]:bg-ink data-[state=active]:text-white md:border-b md:border-line md:bg-transparent md:px-2.5 md:py-3 md:shadow-none md:hover:bg-white md:data-[state=active]:border-ink md:data-[state=active]:bg-ink"
              >
                <span aria-hidden className="font-pixel text-pixel font-normal text-muted-foreground group-data-[state=active]/tab:text-spot-on-ink">
                  {String(index + 1).padStart(2, '0')}
                </span>
                <span className="flex min-w-0 flex-col">
                  <span className="whitespace-nowrap">{s.label}</span>
                  <span aria-hidden className="mt-1 hidden whitespace-nowrap font-pixel text-pixel font-normal text-muted-foreground group-data-[state=active]/tab:text-white/70 md:block">
                    {s.hint}
                  </span>
                </span>
              </TabsPrimitive.Trigger>
            ))}
          </TabsPrimitive.List>

          <div className="min-w-0">
            <TabsContent value="account" className="mt-0">
              <AccountSettings />
            </TabsContent>

            <TabsContent value="agents" className="mt-0">
              <ConnectedAgentsSettings />
            </TabsContent>

            <TabsContent value="phone" className="mt-0">
              <PhoneNumberSetup />
            </TabsContent>

            <TabsContent value="subscription" className="mt-0">
              <SubscriptionSettings />
            </TabsContent>

            <TabsContent value="tags" className="mt-0">
              <TagsSettings />
            </TabsContent>
          </div>
        </Tabs>
      </div>
    </div>
  );
};

export default Settings;
