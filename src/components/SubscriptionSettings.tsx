import type { ReactNode } from 'react';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { useSubscription } from '@/hooks/useSubscription';
import { RefreshCw, ArrowUpRight, Check } from 'lucide-react';
import { format } from 'date-fns';
import { StatusLine, Tag } from '@/components/machine/Machine';

/** One plan fact as a tree row (DESIGN-v2: facts listed the way a terminal lists them) */
const FactRow = ({ label, children }: { label: string; children: ReactNode }) => (
  <div className="v2-tree-row flex items-baseline gap-3 py-[6px]">
    <span className="w-[150px] flex-none font-pixel text-pixel text-muted-foreground">{label}</span>
    <span className="min-w-0 flex-1 text-[15px] text-ink">{children}</span>
  </div>
);

const SubscriptionSettings = () => {
  const {
    subscribed,
    onTrial,
    trialEnd,
    daysLeftInTrial,
    subscriptionEnd,
    subscriptionStatus,
    loading,
    createCheckoutSession,
    openCustomerPortal,
    checkSubscription
  } = useSubscription();

  if (loading) {
    return (
      <Card>
        <CardContent className="flex items-center justify-center pt-6">
          <StatusLine tone="busy">checking your plan…</StatusLine>
        </CardContent>
      </Card>
    );
  }

  const planName = !subscribed ? 'Free' : onTrial ? 'Premium, on trial' : 'Premium';
  const planPrice = subscribed ? '$4.99 a month' : '$0 a month';
  const facts: Array<[string, string]> = [];
  if (onTrial && daysLeftInTrial !== null) facts.push(['trial days left', `${daysLeftInTrial} ${daysLeftInTrial === 1 ? 'day' : 'days'}`]);
  if (onTrial && trialEnd) facts.push(['trial ends', format(new Date(trialEnd), 'MMM d, yyyy')]);
  if (subscribed && !onTrial && subscriptionEnd) facts.push(['next billing date', format(new Date(subscriptionEnd), 'MMM d, yyyy')]);
  if (subscribed && subscriptionStatus) facts.push(['status', subscriptionStatus]);

  return (
    <Card>
      <CardHeader>
        <CardTitle>Subscription</CardTitle>
        <CardDescription>Your plan, and where to change it.</CardDescription>
      </CardHeader>
      <CardContent className="space-y-6">
        <div className="flex flex-wrap items-start justify-between gap-4 border-t border-ink pt-4">
          <div>
            <h3 className="text-section-title font-medium text-ink">{planName}</h3>
            <p className="mt-1 text-[28px] font-medium leading-tight tracking-[-0.03em] tabular-nums text-ink">{planPrice}</p>
          </div>
          <Tag variant={subscribed ? 'spot' : 'outline'}>{subscribed ? (onTrial ? 'trial' : 'active') : 'free'}</Tag>
        </div>

        {facts.length > 0 && (
          <div className="v2-tree">
            {facts.map(([label, value]) => (
              <FactRow key={label} label={label}>{value}</FactRow>
            ))}
          </div>
        )}

        <div className="flex gap-2">
          {!subscribed ? (
            <Button onClick={() => createCheckoutSession()} className="h-11 flex-1 text-[15px]">
              Start the 7-day free trial
            </Button>
          ) : (
            <Button
              onClick={() => openCustomerPortal()}
              variant="outline"
              className="h-11 flex-1 text-[15px]"
            >
              Manage subscription
              <ArrowUpRight className="h-4 w-4" />
            </Button>
          )}
          <Button
            variant="outline"
            size="icon"
            className="h-11 w-11"
            onClick={() => checkSubscription()}
            title="Refresh subscription status"
            aria-label="Refresh subscription status"
          >
            <RefreshCw className="h-4 w-4" />
          </Button>
        </div>

        <div className="space-y-3 pt-2">
          <h3 className="font-pixel text-pixel text-ink">what premium includes</h3>
          <ul className="grid gap-2">
            {[
              'Unlimited summaries, transcripts and enrichment',
              'Search by meaning, not just keywords',
              'Ask about everything you’ve saved',
              'Priority support',
              'Early access to new features'
            ].map((feature) => (
              <li key={feature} className="flex items-center gap-2.5 text-[15px]">
                <span className={`grid h-5 w-5 flex-none place-items-center ${subscribed ? 'bg-ink text-spot-on-ink' : 'border border-line text-muted-foreground'}`}>
                  <Check className="h-3 w-3" />
                </span>
                <span className={subscribed ? 'text-ink' : 'text-muted-foreground'}>{feature}</span>
              </li>
            ))}
          </ul>
        </div>
      </CardContent>
    </Card>
  );
};

export default SubscriptionSettings;
