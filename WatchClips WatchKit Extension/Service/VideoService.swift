import Combine
import Supabase

class VideosService: ObservableObject {
    let client: SupabaseClient
    
    init(client: SupabaseClient) {
        self.client = client
    }
    
    func fetchVideos(forCode code: String) async throws -> [Video] {
        try await client
            .from("videos")
            .select()
            .eq("code", value: code)
            .order("created_at", ascending: false)
            .execute()
            .value
    }
    
    func deleteVideo(withId id: String) async throws {
        try await client
            .from("videos")
            .delete()
            .eq("id", value: id)
            .execute()
    }
}
