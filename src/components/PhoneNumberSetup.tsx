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
import { Loader2, Trash2 } from 'lucide-react';

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
          <CardTitle>Phone &amp; WhatsApp</CardTitle>
          <CardDescription>
            Register up to 3 phone numbers, then text or WhatsApp a link or a note to save it.
          </CardDescription>
        </CardHeader>
        <CardContent className="space-y-4">
          {registeredNumbers.length > 0 && (
            <div className="space-y-2">
              <h3 className="font-pixel text-pixel text-muted-foreground">registered numbers · {registeredNumbers.length}/3</h3>
              <div className="space-y-2">
                {registeredNumbers.map((number) => (
                  <div key={number.id} className="flex items-center justify-between border border-line bg-white py-2 pl-3 pr-1.5">
                    <div className="flex items-center gap-3">
                      <span className="font-code text-[15px] leading-none text-ink">{formatStoredPhoneNumber(number.phone_number)}</span>
                      <Badge variant={number.verified ? "default" : "secondary"}>
                        {number.verified ? "verified" : "pending"}
                      </Badge>
                    </div>
                    <Button
                      variant="ghost"
                      size="icon"
                      aria-label="Remove this number"
                      onClick={() => setDeleteNumber(number)}
                      className="h-8 w-8 text-error hover:bg-error hover:text-white"
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
                <label htmlFor="phone" className="text-label font-medium">
                  Add a phone number
                </label>
                <Input
                  id="phone"
                  type="tel"
                  placeholder="+1 (555) 123-4567"
                  value={phoneInput}
                  onChange={(e) => handlePhoneChange(e.target.value)}
                  disabled={isLoading}
                />
                <p className="text-[13px] text-muted-foreground">
                  A US number, 10 digits.
                </p>
              </div>

              <Button type="submit" disabled={isLoading || !phoneInput}>
                {isLoading && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}
                Register number
              </Button>
            </form>
          )}

          <div className="border-t border-ink pt-4">
            <h3 className="mb-3 font-pixel text-pixel text-ink">save from whatsapp</h3>
            {/* A real sequence, so numbered, in the machine voice (the homepage's .howto) */}
            <ol className="space-y-2.5 text-[15px] text-muted-foreground">
              {[
                <>Save <span className="font-code text-[13.5px] text-ink">+1 (302) 329-6893</span> to your contacts.</>,
                <>Send it a link or a note on WhatsApp.</>,
                <>It lands in your stash, read and filed like anything else you save.</>,
              ].map((step, i) => (
                <li key={i} className="flex items-start gap-3">
                  <span className="grid h-6 w-6 flex-none place-items-center bg-ink font-pixel text-pixel text-white">{i + 1}</span>
                  <span className="pt-0.5">{step}</span>
                </li>
              ))}
            </ol>
          </div>
        </CardContent>
      </Card>

      <AlertDialog open={!!deleteNumber} onOpenChange={() => setDeleteNumber(null)}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Remove {deleteNumber && formatStoredPhoneNumber(deleteNumber.phone_number)}?</AlertDialogTitle>
            <AlertDialogDescription>
              Texts from this number stop saving to your stash until you register it again.
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
              Remove number
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </>
  );
};

export default PhoneNumberSetup;
