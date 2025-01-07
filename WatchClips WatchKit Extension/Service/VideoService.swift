import Combine
import Supabase

class VideosService: ObservableObject {
    let client: SupabaseClient
    
    init(client: SupabaseClient) {
        self.client = client
    }
    
    func fetchVideos(forCode code: String) async throws -> [Video] {
        // Exclude PLAN_LIMIT_EXCEEDED and PLAN_FILESIZE_EXCEEDED
        // so they do not appear in the results
        print("Code: |\(code)|")
        
        print(
            try await client
                .from("videos")
                .select()
                .eq("code", value: code)
                .neq("status", value: "PLAN_LIMIT_EXCEEDED")
                .neq("status", value: "PLAN_FILESIZE_EXCEEDED")
                .order("created_at", ascending: false)
                .execute()
                .value
        )
        
        return try await client
            .from("videos")
            .select()
            .eq("code", value: code)
            .neq("status", value: "PLAN_LIMIT_EXCEEDED")
            .neq("status", value: "PLAN_FILESIZE_EXCEEDED")
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
