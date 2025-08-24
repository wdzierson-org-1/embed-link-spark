
import { useState, useEffect } from 'react';
import { MessageCircle, Smartphone, Mic, Image, FileText, QrCode } from 'lucide-react';
import { Card, CardContent } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { usePhoneNumber } from '@/hooks/usePhoneNumber';
import { useAuth } from '@/hooks/useAuth';
import QRCode from 'qrcode';

const WhatsAppInfo = () => {
  const { user } = useAuth();
  const { phoneNumber, setPhoneNumber, isLoading, registerPhoneNumber, getRegisteredPhoneNumbers } = usePhoneNumber();
  const [registeredNumbers, setRegisteredNumbers] = useState<any[]>([]);
  const [qrCodeUrl, setQrCodeUrl] = useState('');
  const [showRegistrationForm, setShowRegistrationForm] = useState(false);

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

  const handleRegisterPhone = async (e: React.FormEvent) => {
    e.preventDefault();
    const success = await registerPhoneNumber(phoneNumber);
    if (success) {
      setPhoneNumber('');
      setShowRegistrationForm(false);
      loadRegisteredNumbers();
    }
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
          ) : !isRegistered ? (
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
                <form onSubmit={handleRegisterPhone} className="flex flex-col sm:flex-row gap-2">
                  <Input
                    type="tel"
                    placeholder="+1 (555) 123-4567"
                    value={phoneNumber}
                    onChange={(e) => setPhoneNumber(e.target.value)}
                    required
                    className="flex-1"
                  />
                  <div className="flex gap-2">
                    <Button type="submit" disabled={isLoading} size="sm">
                      {isLoading ? 'Registering...' : 'Register'}
                    </Button>
                    <Button 
                      type="button" 
                      variant="outline" 
                      size="sm"
                      onClick={() => {
                        setShowRegistrationForm(false);
                        setPhoneNumber('');
                      }}
                    >
                      Cancel
                    </Button>
                  </div>
                </form>
              )}
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
