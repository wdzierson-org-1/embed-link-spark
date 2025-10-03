import { Crown, Sparkles, X } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Card, CardContent } from '@/components/ui/card';
import { useSubscription } from '@/hooks/useSubscription';
import { useState, useEffect } from 'react';

const SubscriptionBanner = () => {
  const { 
    subscribed,
    subscriptionStatus,
    onTrial,
    trialEnd,
    daysLeftInTrial,
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

  const trialEndDate = trialEnd ? new Date(trialEnd).toLocaleDateString() : null;
  const isPaused = subscriptionStatus === 'paused';

  // Only show banner if:
  // 1. Less than 2 days left in trial, OR
  // 2. Subscription is paused (cannot be dismissed)
  if (!isPaused && daysLeftInTrial >= 2) {
    return null;
  }

  // Don't show if dismissed for this session (only for trial, not paused)
  if (!isPaused && isDismissed) {
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
              {isPaused ? (
                <>
                  <h3 className="font-semibold text-foreground">Trial ended - Account is now read-only</h3>
                  <p className="text-sm text-muted-foreground">
                    Add a payment method to restore full access and continue adding content, searching, and using AI features.
                  </p>
                </>
              ) : onTrial && daysLeftInTrial > 0 ? (
                <>
                  <h3 className="font-semibold text-foreground">Your 7-day free trial is ending soon</h3>
                  <p className="text-sm text-muted-foreground">
                    {daysLeftInTrial} {daysLeftInTrial === 1 ? 'day' : 'days'} remaining. Trial ends on {trialEndDate}. Add a payment method to continue enjoying all Stash features.
                  </p>
                </>
              ) : (
                <>
                  <h3 className="font-semibold text-foreground">Start Your Free 7-Day Trial</h3>
                  <p className="text-sm text-muted-foreground">
                    Get unlimited storage, advanced AI chat, and priority support. No credit card required to start.
                  </p>
                </>
              )}
            </div>
          </div>
          <div className="flex items-center gap-2 shrink-0">
            <Button onClick={createCheckoutSession}>
              {isPaused ? "Add Payment Method" : "Get Premium"}
            </Button>
            {!isPaused && (
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