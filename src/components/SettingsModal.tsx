
import React from 'react';
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import PhoneNumberSetup from '@/components/PhoneNumberSetup';
import { useSubscription } from '@/hooks/useSubscription';

interface SettingsModalProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
}

const SettingsModal = ({ open, onOpenChange }: SettingsModalProps) => {
  const { hasStripeCustomer, createCheckoutSession, openCustomerPortal } = useSubscription();

  const handleSubscriptionClick = () => {
    if (hasStripeCustomer) {
      openCustomerPortal();
    } else {
      createCheckoutSession();
    }
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-[500px] p-0">
        <div className="p-6 border-b">
          <DialogTitle className="text-2xl font-bold">Settings</DialogTitle>
          <DialogDescription className="text-muted-foreground mt-1">
            Adjust your personal settings here.
          </DialogDescription>
        </div>
        
        <div className="p-6">
          <div className="space-y-6">
            <div>
              <h3 className="text-lg font-medium mb-4">Phone Number</h3>
              <PhoneNumberSetup />
            </div>

            <div>
              <h3 className="text-lg font-medium mb-4">Subscription</h3>
              <Button onClick={handleSubscriptionClick} variant="outline" className="w-full">
                {hasStripeCustomer ? "Manage Subscription" : "Start Subscription"}
              </Button>
            </div>
          </div>
        </div>
      </DialogContent>
    </Dialog>
  );
};

export default SettingsModal;
