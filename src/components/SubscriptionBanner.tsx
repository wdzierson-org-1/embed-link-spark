import { ChevronDown, ChevronUp } from 'lucide-react';
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
        className="flex w-full items-center justify-between border border-line bg-white px-3 py-1.5 font-pixel text-pixel text-ink transition-colors hover:border-ink"
      >
        <span>
          trial · {daysLeftInTrial} {daysLeftInTrial === 1 ? 'day' : 'days'} left
        </span>
        <ChevronDown className="h-3 w-3 opacity-60" />
      </button>
    );
  }

  return (
    // DESIGN-v2: the plan is the machine's business, so a square strip with an ink edge; when it
    // matters now (trial nearly over, or paused) it takes the spot field, the one action that counts
    <div
      className={`flex items-center justify-between gap-4 border border-ink px-4 py-3 ${
        urgent ? 'bg-spot text-spot-on' : 'bg-white text-ink'
      }`}
    >
      <div className="flex min-w-0 items-center gap-3.5">
        <span className="flex-none bg-ink px-1.5 pb-[3px] pt-1 font-pixel text-pixel leading-none text-white">
          {isPaused ? 'trial ended' : `trial · ${daysLeftInTrial} ${daysLeftInTrial === 1 ? 'day' : 'days'} left`}
        </span>
        <div className="min-w-0">
          {isPaused ? (
            <>
              <h3 className="text-[15px] font-medium">Your stash is read-only</h3>
              <p className={`truncate text-[14px] ${urgent ? 'opacity-80' : 'text-muted-foreground'}`}>
                Add a payment method to keep saving and asking.
              </p>
            </>
          ) : (
            <>
              <h3 className="text-[15px] font-medium">
                {daysLeftInTrial < 2
                  ? `Your trial ends ${trialEndDate ? `on ${trialEndDate}` : 'soon'}`
                  : `${daysLeftInTrial} days left in your free trial`}
              </h3>
              <p className={`truncate text-[14px] ${urgent ? 'opacity-80' : 'text-muted-foreground'}`}>
                Keep everything for $4.99 a month. Cancel anytime.
              </p>
            </>
          )}
        </div>
      </div>
      <div className="flex flex-none items-center gap-1.5">
        <Button onClick={openCustomerPortal} size="sm" className="h-9 bg-ink px-4 text-[14px] text-white hover:bg-ink-soft">
          {isPaused ? 'Add payment method' : 'Get Premium'}
        </Button>
        {!isPaused && (
          <button
            onClick={() => setMinimizedPersisted(true)}
            title="Minimize"
            aria-label="Minimize"
            className="grid h-9 w-9 place-items-center hover:bg-ink hover:text-white"
          >
            <ChevronUp className="h-4 w-4" />
          </button>
        )}
      </div>
    </div>
  );
};

export default SubscriptionBanner;
