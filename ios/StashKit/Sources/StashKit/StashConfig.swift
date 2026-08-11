import Foundation

public enum StashConfig {
    public static let supabaseURL = URL(string: "https://uqqsgmwkvslaomzxptnp.supabase.co")!
    // Public anon key — same value the committed web client ships
    public static let supabaseAnonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVxcXNnbXdrdnNsYW9tenhwdG5wIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTA2MjU0ODcsImV4cCI6MjA2NjIwMTQ4N30.vGWb1EdshtLFLpUHQ54Vy2CDmuPVCTbvc8UYW6_cvmE"

    public static func publicStorageURL(for path: String) -> URL {
        supabaseURL.appending(path: "/storage/v1/object/public/stash-media/\(path)")
    }
}
