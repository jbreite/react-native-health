import Foundation
import HealthKit

@objc class AttachmentHelper: NSObject {
    @objc static func getAttachment(
        withIdentifier uuidString: String,
        healthStore: HKHealthStore,
        completion: @escaping (Data?, String?, String?, NSError?) -> Void
    ) {
        // Create UUID from string
        guard let uuid = UUID(uuidString: uuidString) else {
            completion(
                nil, nil, nil,
                NSError(
                    domain: "com.example", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Invalid UUID"]))
            return
        }

        // First, we need to find the clinical record that has this UUID
        let clinicalType = HKObjectType.clinicalType(forIdentifier: .clinicalNoteRecord)!
        let predicate = HKQuery.predicateForObject(with: uuid)

        // Get the clinical record first
        healthStore.execute(
            HKSampleQuery(
                sampleType: clinicalType, predicate: predicate, limit: 1, sortDescriptors: nil
            ) { (query, samples, error) in
                if let error = error {
                    completion(nil, nil, nil, error as NSError)
                    return
                }

                guard let clinicalRecord = samples?.first as? HKClinicalRecord else {
                    completion(
                        nil, nil, nil,
                        NSError(
                            domain: "com.example", code: 2,
                            userInfo: [
                                NSLocalizedDescriptionKey: "No clinical record found with this UUID"
                            ]))
                    return
                }

                // Now get attachments for this clinical record
                let attachmentStore = HKAttachmentStore(healthStore: healthStore)

                Task {
                    do {
                        let attachments = try await attachmentStore.attachments(for: clinicalRecord)
                        if let attachment = attachments.first {
                            let dataReader = attachmentStore.dataReader(for: attachment)
                            let data = try await dataReader.data
                            completion(data, attachment.identifier.uuidString, attachment.name, nil)
                        } else {
                            completion(
                                nil, nil, nil,
                                NSError(
                                    domain: "com.example", code: 3,
                                    userInfo: [
                                        NSLocalizedDescriptionKey:
                                            "No attachments found for this record"
                                    ]))
                        }
                    } catch {
                        completion(nil, nil, nil, error as NSError)
                    }
                }
            })
    }
}
