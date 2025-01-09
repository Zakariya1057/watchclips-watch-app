//
//  CodeService.swift
//  WatchClips
//
//  Created by Zakariya Hassan on 31/12/2024.
//

import Supabase

struct CodeService {
    let client: SupabaseClient
    
    // 1) Returns the entire Code record from "codes" by `id`
    func fetchCode(byId id: String) async throws -> Code {
        try await client
            .from("codes")
            .select()
            .eq("id", value: id)
            .single()
            .execute()
            .value
    }
}
