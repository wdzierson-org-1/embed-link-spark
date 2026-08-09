import { Crown, ChevronDown, ChevronUp } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { useSubscription } from '@/hooks/useSubscription';
import { useState } from 'react';

const MINIMIZED_KEY = 'subscription-banner-minimized';

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

  const [minimized, setMinimized] = useState(() => {
    try {
      return localStorage.getItem(MINIMIZED_KEY) === 'true';
    } catch {
      return false;
    }
  });

  const setMinimizedPersisted = (value: boolean) => {
    setMinimized(value);
    try {
      localStorage.setItem(MINIMIZED_KEY, String(value));
    } catch {
      // Session-only is fine
    }
  };

  // Don't show while loading to prevent flash
  if (loading) return null;

  // Nothing to say to fully subscribed users
  if (subscribed && !onTrial) return null;

  const isPaused = subscriptionStatus === 'paused';
  if (!isPaused && !onTrial) return null;

  const trialEndDate = trialEnd
    ? new Date(trialEnd).toLocaleDateString(undefined, { month: 'long', day: 'numeric' })
    : null;
  const urgent = isPaused || daysLeftInTrial < 2;

  // Minimized: a slim strip that stays out of the way (paused accounts always
  // see the full banner — that state matters)
  if (minimized && !isPaused) {
    return (
      <button
        onClick={() => setMinimizedPersisted(false)}
        className="mt-4 flex w-full items-center justify-between rounded-xl border border-violet-200/50 bg-gradient-to-r from-violet-50/80 to-fuchsia-50/60 px-4 py-1.5 text-xs text-violet-700/80 shadow-[0_1px_2px_rgba(0,0,0,0.04)] hover:from-violet-50 hover:to-fuchsia-50 transition-colors"
      >
        <span className="flex items-center gap-1.5">
          <Crown className="h-3 w-3" />
          Trial · {daysLeftInTrial} {daysLeftInTrial === 1 ? 'day' : 'days'} left
        </span>
        <ChevronDown className="h-3 w-3 opacity-60" />
      </button>
    );
  }

  return (
    <div
      className={`mt-4 flex items-center justify-between gap-4 rounded-2xl border px-5 py-3.5 shadow-[0_1px_3px_rgba(0,0,0,0.05),0_8px_24px_rgba(160,120,200,0.12)] ${
        urgent
          ? 'border-amber-200/70 bg-gradient-to-r from-amber-50 to-orange-50/70'
          : 'border-violet-200/50 bg-gradient-to-r from-violet-50/90 via-white to-fuchsia-50/70'
      }`}
    >
      <div className="flex min-w-0 items-center gap-3.5">
        <div className={`grid h-10 w-10 flex-none place-items-center rounded-xl shadow-inner ${urgent ? 'bg-gradient-to-b from-amber-400 to-orange-500' : 'bg-gradient-to-b from-violet-400 to-fuchsia-500'}`}>
          <Crown className="h-5 w-5 text-white" />
        </div>
        <div className="min-w-0">
          {isPaused ? (
            <>
              <h3 className="text-sm font-semibold text-foreground">Trial ended — your stash is read-only</h3>
              <p className="truncate text-[13px] text-muted-foreground">
                Add a payment method to keep capturing and asking.
              </p>
            </>
          ) : (
            <>
              <h3 className="text-sm font-semibold text-foreground">
                {daysLeftInTrial < 2
                  ? `Your trial ends ${trialEndDate ? `on ${trialEndDate}` : 'soon'}`
                  : `${daysLeftInTrial} days left in your free trial`}
              </h3>
              <p className="truncate text-[13px] text-muted-foreground">
                Keep everything for $4.99/month. Cancel anytime.
              </p>
            </>
          )}
        </div>
      </div>
      <div className="flex flex-none items-center gap-1.5">
        <Button
          onClick={openCustomerPortal}
          size="sm"
          className={`rounded-full px-4 shadow-sm ${urgent ? 'bg-gray-900 hover:bg-gray-800' : 'bg-gray-900 hover:bg-gray-800'}`}
        >
          {isPaused ? 'Add payment method' : 'Get Premium'}
        </Button>
        {!isPaused && (
          <button
            onClick={() => setMinimizedPersisted(true)}
            title="Minimize"
            className="grid h-8 w-8 place-items-center rounded-lg text-muted-foreground/70 hover:bg-black/5 hover:text-muted-foreground"
          >
            <ChevronUp className="h-4 w-4" />
          </button>
        )}
      </div>
    </div>
  );
};

export default SubscriptionBanner;
