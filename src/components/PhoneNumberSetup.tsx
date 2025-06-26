
import { useState, useEffect } from 'react';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Input } from '@/components/ui/input';
import { Button } from '@/components/ui/button';
import { Label } from '@/components/ui/label';
import { Badge } from '@/components/ui/badge';
import { Smartphone, MessageCircle } from 'lucide-react';
import { usePhoneNumber } from '@/hooks/usePhoneNumber';

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
    const success = await registerPhoneNumber(phoneNumber);
    if (success) {
      setPhoneNumber('');
      loadRegisteredNumbers();
    }
  };

  const formatPhoneNumber = (phone: string) => {
    const cleaned = phone.replace(/\D/g, '');
    const match = cleaned.match(/^(\d{1})(\d{3})(\d{3})(\d{4})$/);
    if (match) {
      return `+${match[1]} (${match[2]}) ${match[3]}-${match[4]}`;
    }
    return phone;
  };

  return (
    <Card className="w-full max-w-md mx-auto">
      <CardHeader>
        <CardTitle className="flex items-center gap-2">
          <Smartphone className="h-5 w-5" />
          SMS/WhatsApp Setup
        </CardTitle>
        <CardDescription>
          Register your phone number to use SMS and WhatsApp features
        </CardDescription>
      </CardHeader>
      <CardContent className="space-y-4">
        {registeredNumbers.length > 0 && (
          <div className="space-y-2">
            <Label>Registered Numbers:</Label>
            {registeredNumbers.map((number) => (
              <div key={number.id} className="flex items-center justify-between p-2 bg-muted rounded">
                <span className="text-sm">{formatPhoneNumber(number.phone_number)}</span>
                <Badge variant={number.verified ? "default" : "secondary"}>
                  {number.verified ? "Verified" : "Pending"}
                </Badge>
              </div>
            ))}
          </div>
        )}
        
        <form onSubmit={handleRegister} className="space-y-4">
          <div className="space-y-2">
            <Label htmlFor="phone">Phone Number</Label>
            <Input
              id="phone"
              type="tel"
              placeholder="+1 (555) 123-4567"
              value={phoneNumber}
              onChange={(e) => setPhoneNumber(e.target.value)}
              required
            />
          </div>
          
          <Button type="submit" disabled={isLoading} className="w-full">
            {isLoading ? 'Registering...' : 'Register Phone Number'}
          </Button>
        </form>

        <div className="mt-6 p-4 bg-blue-50 dark:bg-blue-950 rounded-lg">
          <div className="flex items-start gap-2">
            <MessageCircle className="h-5 w-5 text-blue-600 mt-0.5" />
            <div className="text-sm text-blue-800 dark:text-blue-200">
              <p className="font-medium mb-1">How to use:</p>
              <ul className="list-disc list-inside space-y-1 text-xs">
                <li>Send notes: "remember to call Dr. Green"</li>
                <li>Ask questions: "what did I save about meetings?"</li>
                <li>Send images and audio for processing</li>
                <li>Type "help" for more commands</li>
              </ul>
            </div>
          </div>
        </div>
      </CardContent>
    </Card>
  );
};

export default PhoneNumberSetup;
