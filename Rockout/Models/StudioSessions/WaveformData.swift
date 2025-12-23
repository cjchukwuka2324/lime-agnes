import Foundation

struct WaveformData: Codable {
    let trackId: UUID
    let samples: [Float] // Normalized amplitude values 0-1
    let sampleRate: Int // Samples per second
    
    enum CodingKeys: String, CodingKey {
        case trackId = "track_id"
        case samples
        case sampleRate = "sample_rate"
    }
    
    init(trackId: UUID, samples: [Float], sampleRate: Int) {
        self.trackId = trackId
        self.samples = samples
        self.sampleRate = sampleRate
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        trackId = try container.decode(UUID.self, forKey: .trackId)
        sampleRate = try container.decode(Int.self, forKey: .sampleRate)
        
        // Decode samples from JSONB array
        if let samplesArray = try? container.decode([Double].self, forKey: .samples) {
            samples = samplesArray.map { Float($0) }
        } else if let samplesArray = try? container.decode([Float].self, forKey: .samples) {
            samples = samplesArray
        } else {
            samples = []
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(trackId, forKey: .trackId)
        try container.encode(sampleRate, forKey: .sampleRate)
        // Encode as array of doubles for JSONB compatibility
        try container.encode(samples.map { Double($0) }, forKey: .samples)
    }
}
