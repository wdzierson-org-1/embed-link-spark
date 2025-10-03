import { Crown, Sparkles, X } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Card, CardContent } from '@/components/ui/card';
import { useSubscription } from '@/hooks/useSubscription';
import { useState, useEffect } from 'react';

const SubscriptionBanner = () => {
  const { 
    subscribed, 
    onTrial, 
    subscriptionEnd, 
    trialStatus, 
    accountStatus, 
    daysSinceCreation,
    loading, 
    createCheckoutSession 
  } = useSubscription();

  const [isDismissed, setIsDismissed] = useState(() => {
    return sessionStorage.getItem('subscription-banner-dismissed') === 'true';
  });

  useEffect(() => {
    sessionStorage.setItem('subscription-banner-dismissed', isDismissed.toString());
  }, [isDismissed]);

  // Don't show banner if fully subscribed (not on trial)
  if (loading || (subscribed && !onTrial)) {
    return null;
  }

  // Don't show banner if account is expired
  if (accountStatus === 'expired') {
    return null;
  }

  const trialEndDate = subscriptionEnd ? new Date(subscriptionEnd).toLocaleDateString() : null;
  const daysLeft = Math.max(0, 7 - daysSinceCreation);

  // Only show banner if less than 2 days left in trial OR if in read-only mode
  // For read-only mode, always show (cannot be dismissed)
  if (accountStatus !== 'read_only' && daysLeft >= 2) {
    return null;
  }

  // Don't show if dismissed for this session (only for trial, not read-only)
  if (accountStatus !== 'read_only' && isDismissed) {
    return null;
  }

  return (
    <Card className="mt-6 mb-6 border-primary/20 bg-gradient-to-r from-primary/5 to-accent/5">
      <CardContent className="p-4">
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-3">
            <div className="p-2 bg-primary/10 rounded-full">
              {onTrial ? <Crown className="h-5 w-5 text-primary" /> : <Sparkles className="h-5 w-5 text-primary" />}
            </div>
            <div>
              {trialStatus === 'active' && !subscribed ? (
                <>
                  <h3 className="font-semibold text-foreground">Your 7-day trial period is active</h3>
                  <p className="text-sm text-muted-foreground">
                    {daysLeft > 0 ? `${daysLeft} days remaining. ` : ''}
                    After it's over, you'll be prompted to create an account in order to continue to enjoy all Stash features.
                  </p>
                </>
              ) : accountStatus === 'read_only' ? (
                <>
                  <h3 className="font-semibold text-foreground">Trial expired - Account is now read-only</h3>
                  <p className="text-sm text-muted-foreground">
                    Subscribe now to restore full access and continue adding content. Your account will be deleted in {Math.max(0, 37 - daysSinceCreation)} days without a subscription.
                  </p>
                </>
              ) : onTrial ? (
                <>
                  <h3 className="font-semibold text-foreground">You're on a free trial!</h3>
                  <p className="text-sm text-muted-foreground">
                    Your trial ends on {trialEndDate}. Upgrade to continue enjoying premium features.
                  </p>
                </>
              ) : (
                <>
                  <h3 className="font-semibold text-foreground">Unlock Premium Features</h3>
                  <p className="text-sm text-muted-foreground">
                    Get unlimited storage, advanced AI chat, and priority support with a 7-day free trial.
                  </p>
                </>
              )}
            </div>
          </div>
          <div className="flex items-center gap-2 shrink-0">
            <Button onClick={createCheckoutSession}>
              {accountStatus === 'read_only' ? "Subscribe Now" : "Get Premium"}
            </Button>
            {accountStatus !== 'read_only' && (
              <Button
                variant="ghost"
                size="icon"
                onClick={() => setIsDismissed(true)}
                className="h-9 w-9"
              >
                <X className="h-4 w-4" />
              </Button>
            )}
          </div>
        </div>
      </CardContent>
    </Card>
  );
};

export default SubscriptionBanner;