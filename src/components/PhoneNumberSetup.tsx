import { useState, useEffect } from 'react';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Input } from '@/components/ui/input';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
} from "@/components/ui/alert-dialog";
import { usePhoneNumber } from '@/hooks/usePhoneNumber';
import { formatPhoneNumber, formatStoredPhoneNumber } from '@/utils/phoneNumber';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/hooks/useAuth';
import { useToast } from '@/hooks/use-toast';
import { Smartphone, Loader2, Trash2 } from 'lucide-react';

const PhoneNumberSetup = () => {
  const { user } = useAuth();
  const { toast } = useToast();
  const { isLoading, registerPhoneNumber, getRegisteredPhoneNumbers } = usePhoneNumber();
  const [phoneInput, setPhoneInput] = useState('');
  const [registeredNumbers, setRegisteredNumbers] = useState<any[]>([]);
  const [deleteNumber, setDeleteNumber] = useState<any | null>(null);
  const [deleting, setDeleting] = useState(false);

  useEffect(() => {
    loadRegisteredNumbers();
  }, []);

  const loadRegisteredNumbers = async () => {
    const numbers = await getRegisteredPhoneNumbers();
    setRegisteredNumbers(numbers);
  };

  const handlePhoneChange = (value: string) => {
    const { displayValue } = formatPhoneNumber(value);
    setPhoneInput(displayValue);
  };

  const handleRegister = async (e: React.FormEvent) => {
    e.preventDefault();

    if (registeredNumbers.length >= 3) {
      toast({
        title: "Limit Reached",
        description: "You can only register up to 3 phone numbers",
        variant: "destructive"
      });
      return;
    }

    const { cleanValue, isValid } = formatPhoneNumber(phoneInput);
    
    if (!isValid) {
      return;
    }

    const success = await registerPhoneNumber(cleanValue);
    if (success) {
      setPhoneInput('');
      await loadRegisteredNumbers();
    }
  };

  const handleDeleteNumber = async () => {
    if (!deleteNumber || !user) return;

    try {
      setDeleting(true);
      const { error } = await supabase
        .from('user_phone_numbers')
        .delete()
        .eq('id', deleteNumber.id)
        .eq('user_id', user.id);

      if (error) throw error;

      toast({
        title: "Success",
        description: "Phone number removed successfully"
      });

      await loadRegisteredNumbers();
      setDeleteNumber(null);
    } catch (error) {
      console.error('Error deleting phone number:', error);
      toast({
        title: "Error",
        description: "Failed to remove phone number",
        variant: "destructive"
      });
    } finally {
      setDeleting(false);
    }
  };

  return (
    <>
      <Card>
        <CardHeader>
          <div className="flex items-center gap-2">
            <Smartphone className="h-5 w-5" />
            <CardTitle>Phone Number Setup</CardTitle>
          </div>
          <CardDescription>
            Register up to 3 phone numbers to send notes via SMS or WhatsApp
          </CardDescription>
        </CardHeader>
        <CardContent className="space-y-4">
          {registeredNumbers.length > 0 && (
            <div className="space-y-2">
              <h3 className="text-sm font-medium">Registered Numbers ({registeredNumbers.length}/3)</h3>
              <div className="space-y-2">
                {registeredNumbers.map((number) => (
                  <div key={number.id} className="flex items-center justify-between p-3 border rounded-lg">
                    <div className="flex items-center gap-3">
                      <span className="font-mono">{formatStoredPhoneNumber(number.phone_number)}</span>
                      <Badge variant={number.verified ? "default" : "secondary"}>
                        {number.verified ? "Verified" : "Pending"}
                      </Badge>
                    </div>
                    <Button
                      variant="ghost"
                      size="icon"
                      onClick={() => setDeleteNumber(number)}
                      className="h-8 w-8 text-destructive hover:text-destructive hover:bg-destructive/10"
                    >
                      <Trash2 className="h-4 w-4" />
                    </Button>
                  </div>
                ))}
              </div>
            </div>
          )}

          {registeredNumbers.length < 3 && (
            <form onSubmit={handleRegister} className="space-y-4">
              <div className="space-y-2">
                <label htmlFor="phone" className="text-sm font-medium">
                  Add Phone Number
                </label>
                <Input
                  id="phone"
                  type="tel"
                  placeholder="+1 (555) 123-4567"
                  value={phoneInput}
                  onChange={(e) => handlePhoneChange(e.target.value)}
                  disabled={isLoading}
                />
                <p className="text-xs text-muted-foreground">
                  Enter your US phone number (10 digits)
                </p>
              </div>

              <Button type="submit" disabled={isLoading || !phoneInput}>
                {isLoading && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}
                Register Phone Number
              </Button>
            </form>
          )}

          <div className="pt-4 border-t">
            <h3 className="text-sm font-medium mb-2">How to Use WhatsApp</h3>
            <div className="space-y-2 text-sm text-muted-foreground">
              <p>1. Save the number +1 (302) 329-6893 to your contacts</p>
              <p>2. Send a message on WhatsApp to start saving notes</p>
              <p>3. Your notes will appear in your Stash automatically</p>
            </div>
          </div>
        </CardContent>
      </Card>

      <AlertDialog open={!!deleteNumber} onOpenChange={() => setDeleteNumber(null)}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Remove Phone Number</AlertDialogTitle>
            <AlertDialogDescription>
              Are you sure you want to remove {deleteNumber && formatStoredPhoneNumber(deleteNumber.phone_number)}?
              <br />
              <br />
              You will no longer be able to send notes from this number until you register it again.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel disabled={deleting}>Cancel</AlertDialogCancel>
            <AlertDialogAction
              onClick={handleDeleteNumber}
              disabled={deleting}
              className="bg-destructive text-destructive-foreground hover:bg-destructive/90"
            >
              {deleting && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}
              Remove Number
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </>
  );
};

export default PhoneNumberSetup;
