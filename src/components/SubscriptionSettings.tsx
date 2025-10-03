import { Crown, Calendar, CreditCard, RefreshCw } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { useSubscription } from '@/hooks/useSubscription';

const SubscriptionSettings = () => {
  const { 
    subscribed, 
    onTrial, 
    subscriptionEnd, 
    loading, 
    createCheckoutSession, 
    openCustomerPortal,
    checkSubscription 
  } = useSubscription();

  if (loading) {
    return (
      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-2">
            <Crown className="h-5 w-5" />
            Subscription
          </CardTitle>
          <CardDescription>Loading subscription details...</CardDescription>
        </CardHeader>
      </Card>
    );
  }

  const subscriptionEndDate = subscriptionEnd ? new Date(subscriptionEnd).toLocaleDateString() : null;

  return (
    <Card>
      <CardHeader>
        <CardTitle className="flex items-center gap-2">
          <Crown className="h-5 w-5" />
          Subscription
        </CardTitle>
        <CardDescription>
          Manage your subscription and billing preferences
        </CardDescription>
      </CardHeader>
      <CardContent className="space-y-4">
        <div className="flex items-center justify-between p-4 bg-muted/50 rounded-lg">
          <div className="space-y-1">
            <div className="flex items-center gap-2">
              <h3 className="font-medium">
                {subscribed ? "Premium Plan" : "Free Plan"}
              </h3>
              {onTrial && (
                <Badge variant="secondary" className="text-xs">
                  Free Trial
                </Badge>
              )}
              {subscribed && !onTrial && (
                <Badge variant="default" className="text-xs">
                  Active
                </Badge>
              )}
            </div>
            <p className="text-sm text-muted-foreground">
              {subscribed ? (
                onTrial ? (
                  `Trial ends on ${subscriptionEndDate}`
                ) : (
                  `Next billing date: ${subscriptionEndDate}`
                )
              ) : (
                "Limited features and storage"
              )}
            </p>
          </div>
          <div className="text-right">
            <p className="font-semibold">
              {subscribed ? "$4.99/month" : "Free"}
            </p>
          </div>
        </div>

        <div className="flex gap-2">
          {!subscribed ? (
            <Button onClick={createCheckoutSession} className="flex-1">
              <Crown className="h-4 w-4 mr-2" />
              Start 7-Day Free Trial
            </Button>
          ) : (
            <Button onClick={openCustomerPortal} className="flex-1">
              <CreditCard className="h-4 w-4 mr-2" />
              Manage Subscription
            </Button>
          )}
          
          <Button 
            variant="outline" 
            size="icon"
            onClick={checkSubscription}
            title="Refresh subscription status"
          >
            <RefreshCw className="h-4 w-4" />
          </Button>
        </div>

        {subscribed && (
          <div className="text-sm text-muted-foreground border-t pt-4">
            <h4 className="font-medium mb-2 text-foreground">Premium Features:</h4>
            <ul className="space-y-1">
              <li className="flex items-center gap-2">
                <Calendar className="h-3 w-3" />
                Unlimited storage and content items
              </li>
              <li className="flex items-center gap-2">
                <Crown className="h-3 w-3" />
                Advanced AI chat with all your content
              </li>
              <li className="flex items-center gap-2">
                <CreditCard className="h-3 w-3" />
                Priority customer support
              </li>
            </ul>
          </div>
        )}
      </CardContent>
    </Card>
  );
};

export default SubscriptionSettings;