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
}

struct Video: Identifiable, Codable {
    let id: String
    let code: String
    let title: String?
    let image: String?
    let filename: String
    let url: String?
    let size: Int64?
    let duration: Int?
    let createdAt: Date
    let updatedAt: Date
    let status: VideoStatus?  // The server’s processing status
    
    // NEW FIELDS:
    let processedSegments: Int?
    let expectedSegments: Int?

    enum CodingKeys: String, CodingKey {
        case id, code, title, image, filename, url, size, duration, status
        case processedSegments = "processed_segments"
        case expectedSegments  = "expected_segments"
        case createdAt         = "created_at"
        case updatedAt         = "updated_at"
    }
}
