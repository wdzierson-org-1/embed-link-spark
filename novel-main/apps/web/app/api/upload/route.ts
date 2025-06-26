
import { NextResponse } from "next/server";

export const runtime = "edge";

export async function POST(req: Request) {
  // Since we're now using Supabase storage directly from the client,
  // this API route can be simplified or used as a fallback
  
  try {
    const formData = await req.formData();
    const file = formData.get('file') as File;
    
    if (!file) {
      return new Response("No file provided", { status: 400 });
    }

    // For the Novel demo, we'll return a success response
    // but recommend using the client-side Supabase upload instead
    return NextResponse.json({
      message: "Please use client-side Supabase upload for better integration",
      success: false
    });
    
  } catch (error) {
    console.error('Upload error:', error);
    return new Response("Upload failed", { status: 500 });
  }
}
