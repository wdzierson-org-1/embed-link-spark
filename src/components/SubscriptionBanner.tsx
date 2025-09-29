import { Crown, Sparkles } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Card, CardContent } from '@/components/ui/card';
import { useSubscription } from '@/hooks/useSubscription';

const SubscriptionBanner = () => {
  const { subscribed, onTrial, subscriptionEnd, loading, createCheckoutSession } = useSubscription();

  // Don't show banner if subscribed (not on trial)
  if (loading || (subscribed && !onTrial)) {
    return null;
  }

  const trialEndDate = subscriptionEnd ? new Date(subscriptionEnd).toLocaleDateString() : null;

  return (
    <Card className="mb-6 border-primary/20 bg-gradient-to-r from-primary/5 to-accent/5">
      <CardContent className="p-4">
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-3">
            <div className="p-2 bg-primary/10 rounded-full">
              {onTrial ? <Crown className="h-5 w-5 text-primary" /> : <Sparkles className="h-5 w-5 text-primary" />}
            </div>
            <div>
              {onTrial ? (
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
          <Button onClick={createCheckoutSession} className="shrink-0">
            {onTrial ? "Upgrade Now" : "Start Free Trial"}
          </Button>
        </div>
      </CardContent>
    </Card>
  );
};

export default SubscriptionBanner;