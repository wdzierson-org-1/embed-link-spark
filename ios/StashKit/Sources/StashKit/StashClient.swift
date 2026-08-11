import Foundation
import Supabase

public enum StashClient {
    public static let shared = SupabaseClient(
        supabaseURL: StashConfig.supabaseURL,
        supabaseKey: StashConfig.supabaseAnonKey
    )
}
