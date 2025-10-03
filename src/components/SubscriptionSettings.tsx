import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { Separator } from '@/components/ui/separator';
import { useSubscription } from '@/hooks/useSubscription';
import { Loader2, RefreshCw, Crown, ExternalLink, Check } from 'lucide-react';
import { format } from 'date-fns';

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
        <CardContent className="pt-6 flex items-center justify-center">
          <Loader2 className="h-6 w-6 animate-spin" />
        </CardContent>
      </Card>
    );
  }

  const getPlanName = () => {
    if (!subscribed) return 'Free Plan';
    if (onTrial) return 'Premium Trial';
    return 'Premium Plan';
  };

  const getPlanPrice = () => {
    if (!subscribed) return '$0/month';
    return '$4.99/month';
  };

  return (
    <Card>
      <CardHeader>
        <div className="flex items-center gap-2">
          <Crown className="h-5 w-5" />
          <CardTitle>Subscription</CardTitle>
        </div>
        <CardDescription>
          Manage your premium subscription
        </CardDescription>
      </CardHeader>
      <CardContent className="space-y-6">
        {/* Current Plan Section */}
        <div className="space-y-4">
          <div className="flex items-start justify-between">
            <div className="space-y-1">
              <h3 className="text-lg font-semibold">{getPlanName()}</h3>
              <p className="text-2xl font-bold">{getPlanPrice()}</p>
            </div>
            <Badge 
              variant={subscribed ? "default" : "secondary"}
              className="text-sm"
            >
              {subscribed ? (onTrial ? 'Trial' : 'Active') : 'Free'}
            </Badge>
          </div>

          {/* Subscription Details */}
          <div className="space-y-2 text-sm">
            {onTrial && daysLeftInTrial !== null && (
              <div className="flex items-center justify-between p-3 bg-accent rounded-lg">
                <span className="text-muted-foreground">Trial Days Remaining</span>
                <span className="font-semibold">{daysLeftInTrial} days</span>
              </div>
            )}
            
            {onTrial && trialEnd && (
              <div className="flex items-center justify-between p-3 bg-accent rounded-lg">
                <span className="text-muted-foreground">Trial Ends</span>
                <span className="font-semibold">{format(new Date(trialEnd), 'MMM dd, yyyy')}</span>
              </div>
            )}

            {subscribed && !onTrial && subscriptionEnd && (
              <div className="flex items-center justify-between p-3 bg-accent rounded-lg">
                <span className="text-muted-foreground">Next Billing Date</span>
                <span className="font-semibold">{format(new Date(subscriptionEnd), 'MMM dd, yyyy')}</span>
              </div>
            )}

            {subscribed && subscriptionStatus && (
              <div className="flex items-center justify-between p-3 bg-accent rounded-lg">
                <span className="text-muted-foreground">Status</span>
                <span className="font-semibold capitalize">{subscriptionStatus}</span>
              </div>
            )}
          </div>
        </div>

        <Separator />

        {/* Action Buttons */}
        <div className="flex gap-2">
          {!subscribed ? (
            <Button onClick={() => createCheckoutSession()} className="flex-1">
              <Crown className="mr-2 h-4 w-4" />
              Start 7-Day Free Trial
            </Button>
          ) : (
            <Button 
              onClick={() => openCustomerPortal()} 
              variant="outline" 
              className="flex-1"
            >
              Manage Subscription
              <ExternalLink className="ml-2 h-4 w-4" />
            </Button>
          )}
          <Button
            variant="outline"
            size="icon"
            onClick={() => checkSubscription()}
            title="Refresh subscription status"
          >
            <RefreshCw className="h-4 w-4" />
          </Button>
        </div>

        {/* Premium Features */}
        <div className="space-y-3 pt-2">
          <h3 className="text-sm font-semibold">Premium Features</h3>
          <div className="grid gap-2">
            {[
              'Unlimited AI-powered insights',
              'Advanced search capabilities',
              'Chat with your entire content library',
              'Priority support',
              'Early access to new features'
            ].map((feature, index) => (
              <div key={index} className="flex items-center gap-2 text-sm">
                <Check className={`h-4 w-4 ${subscribed ? 'text-primary' : 'text-muted-foreground'}`} />
                <span className={subscribed ? '' : 'text-muted-foreground'}>{feature}</span>
              </div>
            ))}
          </div>
        </div>
      </CardContent>
    </Card>
  );
};

export default SubscriptionSettings;
