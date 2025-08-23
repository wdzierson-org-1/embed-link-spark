
import { MessageCircle, Smartphone, Mic, Image, FileText } from 'lucide-react';
import { Card, CardContent } from '@/components/ui/card';

const WhatsAppInfo = () => {
  return (
    <Card className="w-full max-w-2xl mx-auto">
      <CardContent className="p-6">
        <div className="text-center space-y-4">
          <div className="flex items-center justify-center gap-2 mb-4">
            <MessageCircle className="h-6 w-6 text-green-600" />
            <h3 className="text-xl font-semibold text-gray-900">Use Stash via WhatsApp</h3>
          </div>
          
          <p className="text-gray-600 mb-6">
            Add your phone number in the settings panel (upper right), and then text your notes via WhatsApp to<br />
            <span className="font-semibold text-green-600">+1 229 466 6353</span>
          </p>

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

          <p className="text-xs text-gray-500 mt-4">
            Make sure your phone number is registered in Settings to use this feature.
          </p>
        </div>
      </CardContent>
    </Card>
  );
};

export default WhatsAppInfo;
