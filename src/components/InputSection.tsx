
import React from 'react';
import { Button } from '@/components/ui/button';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { FileText, Link, Upload, ChevronUp, ChevronDown } from 'lucide-react';
import TextNoteTab from '@/components/TextNoteTab';
import LinkTab from '@/components/LinkTab';
import MediaUploadTab from '@/components/MediaUploadTab';

interface InputSectionProps {
  activeTab: string;
  isInputUICollapsed: boolean;
  onTabChange: (value: string) => void;
  onToggleInputUI: () => void;
  onAddContent: (type: string, data: any) => Promise<void>;
  getSuggestedTags: (content: any) => Promise<string[]>;
}

const InputSection = ({ 
  activeTab, 
  isInputUICollapsed, 
  onTabChange, 
  onToggleInputUI, 
  onAddContent, 
  getSuggestedTags 
}: InputSectionProps) => {
  return (
    <div className="w-full bg-gray-100">
      <div className="pt-8 pb-8">
        <div className="container mx-auto px-4">
          <div className="flex items-center bg-gray-200 rounded-lg p-1 w-full">
            <Tabs value={activeTab} onValueChange={onTabChange} className="flex-1">
              <TabsList className="grid w-full grid-cols-3 h-12 bg-transparent border-0">
                <TabsTrigger 
                  value="text" 
                  className="flex items-center gap-2 data-[state=active]:bg-white data-[state=active]:shadow-sm hover:bg-gray-300 transition-colors"
                >
                  <FileText className="h-4 w-4" />
                  Text Note
                </TabsTrigger>
                <TabsTrigger 
                  value="link" 
                  className="flex items-center gap-2 data-[state=active]:bg-white data-[state=active]:shadow-sm hover:bg-gray-300 transition-colors"
                >
                  <Link className="h-4 w-4" />
                  Link
                </TabsTrigger>
                <TabsTrigger 
                  value="media" 
                  className="flex items-center gap-2 data-[state=active]:bg-white data-[state=active]:shadow-sm hover:bg-gray-300 transition-colors"
                >
                  <Upload className="h-4 w-4" />
                  Upload
                </TabsTrigger>
              </TabsList>
            </Tabs>
            
            <Button
              variant="ghost"
              size="sm"
              onClick={onToggleInputUI}
              className="ml-2 flex items-center gap-1 bg-transparent hover:bg-gray-300/50"
            >
              {isInputUICollapsed ? (
                <ChevronDown className="h-4 w-4" />
              ) : (
                <ChevronUp className="h-4 w-4" />
              )}
            </Button>
          </div>
          
          {/* Input UI Area with reduced spacing */}
          <div className={`overflow-hidden transition-all duration-300 ease-in-out ${
            isInputUICollapsed ? 'max-h-0 opacity-0' : 'max-h-96 opacity-100'
          }`}>
            <Tabs value={activeTab} onValueChange={onTabChange} className="w-full">
              <TabsContent value="text" className="mt-2 pb-0">
                <TextNoteTab
                  onAddContent={onAddContent}
                  getSuggestedTags={getSuggestedTags}
                />
              </TabsContent>
              
              <TabsContent value="link" className="mt-2 pb-0">
                <LinkTab
                  onAddContent={onAddContent}
                  getSuggestedTags={() => []}
                />
              </TabsContent>
              
              <TabsContent value="media" className="mt-2 pb-0">
                <MediaUploadTab
                  onAddContent={onAddContent}
                  getSuggestedTags={getSuggestedTags}
                />
              </TabsContent>
            </Tabs>
          </div>
        </div>
      </div>
    </div>
  );
};

export default InputSection;
