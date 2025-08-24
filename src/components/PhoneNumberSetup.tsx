
import { useState, useEffect } from 'react';
import { Input } from '@/components/ui/input';
import { Button } from '@/components/ui/button';
import { Label } from '@/components/ui/label';
import { Badge } from '@/components/ui/badge';
import { Smartphone, MessageCircle } from 'lucide-react';
import { usePhoneNumber } from '@/hooks/usePhoneNumber';
import { formatPhoneNumber, formatStoredPhoneNumber } from '@/utils/phoneNumber';

const PhoneNumberSetup = () => {
  const { 
    phoneNumber, 
    setPhoneNumber, 
    isLoading, 
    registerPhoneNumber, 
    getRegisteredPhoneNumbers 
  } = usePhoneNumber();
  
  const [registeredNumbers, setRegisteredNumbers] = useState<any[]>([]);

  useEffect(() => {
    loadRegisteredNumbers();
  }, []);

  const loadRegisteredNumbers = async () => {
    const numbers = await getRegisteredPhoneNumbers();
    setRegisteredNumbers(numbers);
  };

  const handleRegister = async (e: React.FormEvent) => {
    e.preventDefault();
    const formatted = formatPhoneNumber(phoneNumber);
    
    if (!formatted.isValid) {
      return; // Input validation will show error
    }
    
    const success = await registerPhoneNumber(formatted.cleanValue);
    if (success) {
      setPhoneNumber('');
      loadRegisteredNumbers();
    }
  };


  return (
    <div className="space-y-6">
      {registeredNumbers.length > 0 && (
        <div className="space-y-3">
          <Label className="text-sm font-medium">Registered Numbers:</Label>
          {registeredNumbers.map((number) => (
            <div key={number.id} className="flex items-center justify-between p-3 bg-muted rounded-lg">
              <span className="text-sm font-medium">{formatStoredPhoneNumber(number.phone_number)}</span>
              <Badge variant={number.verified ? "default" : "secondary"}>
                {number.verified ? "Verified" : "Pending"}
              </Badge>
            </div>
          ))}
        </div>
      )}
      
      <form onSubmit={handleRegister} className="space-y-4">
        <div className="space-y-2">
          <Label htmlFor="phone" className="text-sm font-medium">Add Phone Number</Label>
          <Input
            id="phone"
            type="tel"
            placeholder="+1 (555) 123-4567"
            value={phoneNumber}
            onChange={(e) => {
              const formatted = formatPhoneNumber(e.target.value);
              setPhoneNumber(formatted.displayValue);
            }}
            required
            className="w-full"
          />
        </div>
        
        <Button type="submit" disabled={isLoading || !formatPhoneNumber(phoneNumber).isValid} className="w-full">
          {isLoading ? 'Registering...' : 'Register Phone Number'}
        </Button>
      </form>

      <div className="p-4 bg-blue-50 dark:bg-blue-950 rounded-lg">
        <div className="flex items-start gap-3">
          <MessageCircle className="h-5 w-5 text-blue-600 mt-0.5 flex-shrink-0" />
          <div className="text-sm text-blue-800 dark:text-blue-200">
            <p className="font-medium mb-2">How to use WhatsApp:</p>
            <ul className="list-disc list-inside space-y-1 text-xs">
              <li>After you've registered your phone number, send notes to (229) 466-6353</li>
              <li>Send notes: "remember to call Dr. Green"</li>
              <li>Ask questions: "what did I save about meetings?"</li>
              <li>Send images and audio for processing</li>
              <li>Type "help" for more commands</li>
            </ul>
          </div>
        </div>
      </div>
    </div>
  );
};

export default PhoneNumberSetup;
