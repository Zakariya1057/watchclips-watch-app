import Foundation

/// The main server-side model.
enum VideoStatus: String, Codable {
    case preProcessing = "PRE_PROCESSING"
    case processing = "PROCESSING"
    case postProcessingSuccess = "POST_PROCESSING_SUCCESS"
    case postProcessingFailure = "POST_PROCESSING_FAILURE"
    case chunking = "CHUNKING"
    case chunkingComplete = "CHUNKING_COMPLETE"
    case chunkingFailure = "CHUNKING_FAILURE"
    case processingChunk = "PROCESSING_CHUNK"
    case chunkProcessed = "CHUNK_PROCESSED"
    case chunkProcessingFailure = "CHUNK_PROCESSING_FAILURE"
    case finalizing = "FINALIZING"
}

struct Video: Identifiable, Codable, Equatable {
    let id: String
    let code: String
    let title: String?
    let image: String?
    var filename: String
    var size: Int64?
    let duration: Int?
    let createdAt: Date
    let updatedAt: Date
    let status: VideoStatus?  // The server’s processing status
    
    // NEW FIELDS:
    let processedSegments: Int?
    let expectedSegments: Int?
    
    /// **NEW**: Whether the file is being optimized (maps to `is_optimizing` in DB).
    let isOptimizing: Bool

    enum CodingKeys: String, CodingKey {
        case id, code, title, image, filename, size, duration, status
        case processedSegments = "processed_segments"
        case expectedSegments  = "expected_segments"
        case createdAt         = "created_at"
        case updatedAt         = "updated_at"
        
        // NEW CODING KEY:
        case isOptimizing      = "is_optimizing"
    }
}
