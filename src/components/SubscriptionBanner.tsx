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
    openCustomerPortal 
  } = useSubscription();

  const [dismissedAt, setDismissedAt] = useState<string | null>(() => {
    return localStorage.getItem('subscription-banner-dismissed');
  });

  const handleDismiss = () => {
    const timestamp = new Date().toISOString();
    setDismissedAt(timestamp);
    localStorage.setItem('subscription-banner-dismissed', timestamp);
  };

  // Don't show while loading to prevent flash
  if (loading) {
    return null;
  }

  // Don't show banner if fully subscribed (not on trial)
  if (subscribed && !onTrial) {
    return null;
  }

  const trialEndDate = trialEnd ? new Date(trialEnd).toLocaleDateString() : null;
  const isPaused = subscriptionStatus === 'paused';
  const currentTrialDay = 8 - daysLeftInTrial;

  // Show if paused (always visible)
  if (isPaused) {
    // Banner content will be shown below
  }
  // Show if on day 1 of trial OR less than 2 days remaining
  else if (onTrial && (currentTrialDay === 1 || daysLeftInTrial < 2)) {
    // Banner content will be shown below
  }
  // Otherwise hide (days 2-5 of trial with 2+ days remaining)
  else {
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
              ) : onTrial && daysLeftInTrial < 2 ? (
                <>
                  <h3 className="font-semibold text-foreground">Your 7-day free trial is ending soon</h3>
                  <p className="text-sm text-muted-foreground">
                    {daysLeftInTrial} {daysLeftInTrial === 1 ? 'day' : 'days'} remaining. Trial ends on {trialEndDate}. Upgrade now for $4.99/month.
                  </p>
                </>
              ) : (
                <>
                  <h3 className="font-semibold text-foreground">You're on day {currentTrialDay} of your 7 day free trial</h3>
                  <p className="text-sm text-muted-foreground">
                    Upgrade to Stash Premium at any time for $4.99 per month.
                  </p>
                </>
              )}
            </div>
          </div>
          <div className="flex items-center gap-2 shrink-0">
            <Button onClick={openCustomerPortal}>
              {isPaused ? "Add Payment Method" : "Get Premium"}
            </Button>
            {!isPaused && (
              <Button
                variant="ghost"
                size="icon"
                onClick={handleDismiss}
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