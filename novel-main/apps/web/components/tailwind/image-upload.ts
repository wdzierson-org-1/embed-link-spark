
import { createImageUpload } from "novel";
import { toast } from "sonner";

// Import Supabase client - we'll need to configure this path
const createSupabaseClient = () => {
  // This would normally import from your Supabase client
  // For now, we'll create a minimal client setup
  const SUPABASE_URL = "https://uqqsgmwkvslaomzxptnp.supabase.co";
  const SUPABASE_ANON_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVxcXNnbXdrdnNsYW9tenhwdG5wIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTA2MjU0ODcsImV4cCI6MjA2NjIwMTQ4N30.vGWb1EdshtLFLpUHQ54Vy2CDmuPVCTbvc8UYW6_cvmE";
  
  // Import createClient from @supabase/supabase-js
  const { createClient } = require('@supabase/supabase-js');
  return createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
};

const onUpload = async (file: File) => {
  const supabase = createSupabaseClient();
  
  // Get current user session
  const { data: { session }, error: sessionError } = await supabase.auth.getSession();
  
  if (sessionError || !session?.user) {
    toast.error("Authentication required for file upload");
    throw new Error("Authentication required for file upload");
  }

  const userId = session.user.id;
  
  // Generate file path
  const fileExt = file.name.split('.').pop();
  const fileName = `${Date.now()}.${fileExt}`;
  const filePath = `${userId}/${fileName}`;

  return new Promise((resolve, reject) => {
    toast.promise(
      (async () => {
        // Upload to Supabase storage
        const { error: uploadError } = await supabase.storage
          .from('stash-media')
          .upload(filePath, file);

        if (uploadError) {
          throw new Error(`Failed to upload image: ${uploadError.message}`);
        }

        // Get public URL
        const { data } = supabase.storage.from('stash-media').getPublicUrl(filePath);
        
        // Preload the image
        const image = new Image();
        image.src = data.publicUrl;
        
        return new Promise<string>((imageResolve) => {
          image.onload = () => {
            imageResolve(data.publicUrl);
          };
          image.onerror = () => {
            imageResolve(data.publicUrl);
          };
        });
      })(),
      {
        loading: "Uploading image...",
        success: "Image uploaded successfully.",
        error: (e) => {
          reject(e);
          return e.message;
        },
      },
    ).then(resolve);
  });
};

export const uploadFn = createImageUpload({
  onUpload,
  validateFn: (file) => {
    if (!file.type.includes("image/")) {
      toast.error("File type not supported.");
      return false;
    }
    if (file.size / 1024 / 1024 > 20) {
      toast.error("File size too big (max 20MB).");
      return false;
    }
    return true;
  },
});
