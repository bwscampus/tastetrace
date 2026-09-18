import Foundation

public extension APIClient {
    func symptoms() async throws -> [Symptom] {
        try await request(.get, "/api/symptoms")
    }

    func createSymptom(_ symptom: NewSymptom) async throws -> Symptom {
        try await request(.post, "/api/symptoms", body: symptom)
    }

    /// `POST /api/symptoms/batch` — logs several symptoms at one time.
    func createSymptoms(_ batch: SymptomBatch) async throws -> [Symptom] {
        try await request(.post, "/api/symptoms/batch", body: batch)
    }

    func updateSymptom(id: Int, _ patch: SymptomPatch) async throws -> Symptom {
        try await request(.put, "/api/symptoms/\(id)", body: patch)
    }

    func deleteSymptom(id: Int) async throws {
        try await requestVoid(.delete, "/api/symptoms/\(id)")
    }

    func symptomCatalog() async throws -> SymptomCatalog {
        try await request(.get, "/api/symptom-catalog")
    }

    func createCustomSymptom(_ symptom: NewCustomSymptom) async throws -> CustomSymptom {
        try await request(.post, "/api/symptom-catalog", body: symptom)
    }

    func deleteCustomSymptom(id: Int) async throws {
        try await requestVoid(.delete, "/api/symptom-catalog/\(id)")
    }
}
