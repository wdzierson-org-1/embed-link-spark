
import { useState, useEffect } from 'react';
import { MessageCircle, Smartphone, Mic, Image, FileText, QrCode } from 'lucide-react';
import { Card, CardContent } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { usePhoneNumber } from '@/hooks/usePhoneNumber';
import { useAuth } from '@/hooks/useAuth';
import { useToast } from '@/hooks/use-toast';
import { supabase } from '@/integrations/supabase/client';
import QRCode from 'qrcode';
import { formatPhoneNumber, formatStoredPhoneNumber } from '@/utils/phoneNumber';

const WhatsAppInfo = () => {
  const { user } = useAuth();
  const { toast } = useToast();
  const { phoneNumber, setPhoneNumber, isLoading, registerPhoneNumber, getRegisteredPhoneNumbers } = usePhoneNumber();
  const [registeredNumbers, setRegisteredNumbers] = useState<any[]>([]);
  const [qrCodeUrl, setQrCodeUrl] = useState('');
  const [showRegistrationForm, setShowRegistrationForm] = useState(false);
  const [phoneError, setPhoneError] = useState('');
  const [showCancelMessage, setShowCancelMessage] = useState(false);

  useEffect(() => {
    if (user) {
      loadRegisteredNumbers();
    }
  }, [user]);

  const loadRegisteredNumbers = async () => {
    const numbers = await getRegisteredPhoneNumbers();
    setRegisteredNumbers(numbers);
    if (numbers.length > 0) {
      generateQRCode();
    }
  };

  const generateQRCode = async () => {
    const whatsappNumber = '+12294666353';
    const message = encodeURIComponent('Hi! I want to use Stash to save my notes via WhatsApp.');
    const whatsappUrl = `https://wa.me/${whatsappNumber.replace('+', '')}?text=${message}`;
    
    try {
      const qrUrl = await QRCode.toDataURL(whatsappUrl);
      setQrCodeUrl(qrUrl);
    } catch (error) {
      console.error('Error generating QR code:', error);
    }
  };

  const checkPhoneUniqueness = async (cleanPhone: string) => {
    if (!cleanPhone || cleanPhone.length === 0) {
      setPhoneError('');
      return true;
    }
    
    const { data, error } = await supabase
      .from('user_phone_numbers')
      .select('phone_number')
      .eq('phone_number', cleanPhone)
      .single();
    
    if (error && error.code !== 'PGRST116') {
      console.error('Error checking phone:', error);
      return true; // Allow registration if we can't check
    }
    
    if (data) {
      setPhoneError('This number is already registered to another user.');
      return false;
    } else {
      setPhoneError('');
      return true;
    }
  };

  const handleRegisterPhone = async (e: React.FormEvent) => {
    e.preventDefault();
    
    const formatted = formatPhoneNumber(phoneNumber);
    
    if (!formatted.isValid) {
      setPhoneError('Please enter a valid US phone number.');
      return;
    }

    // Check uniqueness first
    const isUnique = await checkPhoneUniqueness(formatted.cleanValue);
    if (!isUnique) {
      return;
    }

    const success = await registerPhoneNumber(formatted.cleanValue);
    if (success) {
      setPhoneNumber('');
      setShowRegistrationForm(false);
      setPhoneError('');
      loadRegisteredNumbers();
      generateQRCode();
    }
  };

  const handleCancelRegistration = () => {
    setShowRegistrationForm(false);
    setPhoneNumber('');
    setPhoneError('');
    setShowCancelMessage(true);
  };

  const isRegistered = registeredNumbers.length > 0;

  return (
    <Card className="w-full max-w-2xl mx-auto">
      <CardContent className="p-6">
        <div className="text-center space-y-4">
          <div className="flex items-center justify-center gap-2 mb-4">
            <MessageCircle className="h-6 w-6 text-green-600" />
            <h3 className="text-xl font-semibold text-gray-900">Use Stash via WhatsApp</h3>
          </div>
          
          {!user ? (
            <p className="text-gray-600 mb-6">
              Sign up to use WhatsApp integration and text your notes to<br />
              <span className="font-semibold text-green-600">+1 229 466 6353</span>
            </p>
          ) : !isRegistered && !showCancelMessage ? (
            <div className="mb-6 space-y-4">
              <p className="text-gray-600">
                Register your phone number to text your notes via WhatsApp to<br />
                <span className="font-semibold text-green-600">+1 229 466 6353</span>
              </p>
              
              {!showRegistrationForm ? (
                <Button 
                  onClick={() => setShowRegistrationForm(true)}
                  className="bg-green-600 hover:bg-green-700"
                >
                  <Smartphone className="h-4 w-4 mr-2" />
                  Register Phone Number
                </Button>
              ) : (
                <form onSubmit={handleRegisterPhone} className="space-y-4">
                  <div className="space-y-2">
                    <Input
                      type="tel"
                      placeholder="+1 (555) 123-4567"
                      value={phoneNumber}
                      onChange={(e) => {
                        const formatted = formatPhoneNumber(e.target.value);
                        setPhoneNumber(formatted.displayValue);
                        
                        if (formatted.cleanValue.length > 1) {
                          checkPhoneUniqueness(formatted.cleanValue);
                        } else {
                          setPhoneError('');
                        }
                      }}
                      required
                      className={`flex-1 ${phoneError ? 'border-red-500' : ''}`}
                    />
                    {phoneError && (
                      <p className="text-xs text-red-600">{phoneError}</p>
                    )}
                  </div>
                  
                  <div className="flex gap-2">
                    <Button 
                      type="submit" 
                      disabled={isLoading || !!phoneError} 
                      size="sm" 
                      className="bg-green-600 hover:bg-green-700"
                    >
                      {isLoading ? 'Registering...' : 'Register'}
                    </Button>
                    <Button 
                      type="button" 
                      variant="outline" 
                      size="sm"
                      onClick={handleCancelRegistration}
                    >
                      Cancel
                    </Button>
                  </div>
                  
                  <p className="text-xs text-gray-500 text-center">
                    We will never sell your information, or use your information for marketing, spam, or undisclosed purposes.
                  </p>
                </form>
              )}
            </div>
          ) : !isRegistered && showCancelMessage ? (
            <div className="mb-6">
              <p className="text-gray-600">
                You can always register your number later on.
              </p>
            </div>
          ) : (
            <div className="mb-6 space-y-4">
              <p className="text-gray-600">
                Your phone number is registered! Text your notes via WhatsApp to<br />
                <span className="font-semibold text-green-600">+1 229 466 6353</span>
              </p>
              
              {qrCodeUrl && (
                <div className="flex flex-col items-center space-y-2 p-4 bg-gray-50 rounded-lg">
                  <QrCode className="h-5 w-5 text-gray-600" />
                  <span className="text-sm font-medium">Add Stash to WhatsApp</span>
                  <img src={qrCodeUrl} alt="WhatsApp QR Code" className="w-32 h-32" />
                  <p className="text-xs text-gray-500 text-center">
                    Scan with your phone's camera to add Stash as a contact
                  </p>
                </div>
              )}
            </div>
          )}

          <div className="grid grid-cols-2 md:grid-cols-4 gap-4 text-sm">
            <div className="flex flex-col items-center space-y-2 p-3 bg-gray-50 rounded-lg">
              <FileText className="h-5 w-5 text-blue-600" />
              <span className="font-medium">Text Notes</span>
              <span className="text-xs text-gray-500 text-center">Send any text to save it</span>
            </div>
            
            <div className="flex flex-col items-center space-y-2 p-3 bg-gray-50 rounded-lg">
              <Mic className="h-5 w-5 text-red-600" />
              <span className="font-medium">Voice Notes</span>
              <span className="text-xs text-gray-500 text-center">Record and send audio</span>
            </div>
            
            <div className="flex flex-col items-center space-y-2 p-3 bg-gray-50 rounded-lg">
              <Image className="h-5 w-5 text-purple-600" />
              <span className="font-medium">Images</span>
              <span className="text-xs text-gray-500 text-center">Photos & screenshots</span>  
            </div>
            
            <div className="flex flex-col items-center space-y-2 p-3 bg-gray-50 rounded-lg">
              <FileText className="h-5 w-5 text-orange-600" />
              <span className="font-medium">Documents</span>
              <span className="text-xs text-gray-500 text-center">PDFs & files</span>
            </div>
          </div>

          <div className="mt-6 p-4 bg-blue-50 rounded-lg">
            <p className="text-sm text-blue-800 mb-2">
              <strong>Ask questions about your content:</strong>
            </p>
            <p className="text-sm text-blue-700">
              "What did I save about meetings?" • "Show me my travel notes" • "Find my recipe for pasta"
            </p>
          </div>

          {user && !isRegistered && (
            <p className="text-xs text-gray-500 mt-4">
              Register your phone number above to use WhatsApp features.
            </p>
          )}
        </div>
      </CardContent>
    </Card>
  );
};

export default WhatsAppInfo;
