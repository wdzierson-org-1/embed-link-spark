
import React from 'react';
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog';
import { X } from 'lucide-react';
import { Button } from '@/components/ui/button';
import PhoneNumberSetup from '@/components/PhoneNumberSetup';

interface SettingsModalProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
}

const SettingsModal = ({ open, onOpenChange }: SettingsModalProps) => {
  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-[500px] p-0">
        <div className="flex items-center justify-between p-6 border-b">
          <div>
            <DialogTitle className="text-2xl font-bold">Settings</DialogTitle>
            <DialogDescription className="text-muted-foreground mt-1">
              Adjust your personal settings here.
            </DialogDescription>
          </div>
          <Button
            variant="ghost"
            size="icon"
            onClick={() => onOpenChange(false)}
            className="h-8 w-8"
          >
            <X className="h-4 w-4" />
          </Button>
        </div>
        
        <div className="p-6">
          <div className="space-y-6">
            <div>
              <h3 className="text-lg font-medium mb-4">Phone Number</h3>
              <PhoneNumberSetup />
            </div>
          </div>
        </div>
      </DialogContent>
    </Dialog>
  );
};

export default SettingsModal;
