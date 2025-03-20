//
//  RCTAppleHealthKit+Methods_ClinicalRecords.m
//  RCTAppleHealthKit
//
//  This source code is licensed under the MIT-style license found in the
//  LICENSE file in the root directory of this source tree.

#import "RCTAppleHealthKit+Methods_ClinicalRecords.h"
#import "RCTAppleHealthKit+Queries.h"
#import "RCTAppleHealthKit+Utils.h"

@implementation RCTAppleHealthKit (Methods_ClinicalRecords)

- (void)clinicalRecords_getClinicalRecords:(NSDictionary *)input callback:(RCTResponseSenderBlock)callback
{
    NSString *type = [RCTAppleHealthKit stringFromOptions:input key:@"type" withDefault:nil];
    if(type == nil){
     callback(@[RCTMakeError(@"type is required in options", nil, nil)]);
     return;
    }
    
    if (
        ![type isEqual:@"AllergyRecord"] &&
        ![type isEqual:@"ConditionRecord"] &&
        ![type isEqual:@"CoverageRecord"] &&
        ![type isEqual:@"ImmunizationRecord"] &&
        ![type isEqual:@"LabResultRecord"] &&
        ![type isEqual:@"MedicationRecord"] &&
        ![type isEqual:@"ProcedureRecord"] &&
        ![type isEqual:@"VitalSignRecord"] &&
        ![type isEqual:@"ClinicalNoteRecord"]
    ) {
        callback(@[RCTMakeError(@"invalid type, type must be one of 'AllergyRecord'|'ConditionRecord'|'CoverageRecord'|'ImmunizationRecord'|'LabResultRecord'|'MedicationRecord'|'ProcedureRecord'|'VitalSignRecord'|'ClinicalNoteRecord'", nil, nil)]);
        return;
    }
    
    HKObjectType *recordType = [RCTAppleHealthKit clinicalTypeFromName:type];
    if (recordType == nil) {
        callback(@[RCTMakeError(@"the requested clinical record type is not available for this iOS version", nil, nil)]);
        return;
    }
    
    NSUInteger limit = [RCTAppleHealthKit uintFromOptions:input key:@"limit" withDefault:HKObjectQueryNoLimit];
    BOOL ascending = [RCTAppleHealthKit boolFromOptions:input key:@"ascending" withDefault:false];
    
    NSDate *startDate = [RCTAppleHealthKit dateFromOptions:input key:@"startDate" withDefault:nil];
    if(startDate == nil){
     callback(@[RCTMakeError(@"startDate is required in options", nil, nil)]);
     return;
    }
    
    NSDate *endDate = [RCTAppleHealthKit dateFromOptions:input key:@"endDate" withDefault:[NSDate date]];
    NSPredicate * predicate = [RCTAppleHealthKit predicateForSamplesBetweenDates:startDate endDate:endDate];
    
    [self fetchClinicalRecordsOfType:recordType predicate:predicate ascending:ascending limit:limit completion:^(NSArray *results, NSError *error) {
        if(results){
            callback(@[[NSNull null], results]);
            return;
        } else {
            callback(@[RCTJSErrorFromNSError(error)]);
            return;
        }
    }];
}

- (void)clinicalRecords_getAttachment:(NSDictionary *)input callback:(RCTResponseSenderBlock)callback
{
    // Check if running on iOS 16 or later
    if (@available(iOS 16.0, *)) {
        // Check for direct record ID approach
        NSString *recordId = [RCTAppleHealthKit stringFromOptions:input key:@"recordId" withDefault:nil];
        
        // Check for binary ID approach (existing)
        NSString *binaryId = [RCTAppleHealthKit stringFromOptions:input key:@"binaryId" withDefault:nil];
        
        // Must have either recordId or binaryId
        if (!recordId && !binaryId) {
            callback(@[RCTMakeError(@"Either recordId or binaryId is required", nil, nil)]);
            return;
        }
        
        // Using the direct record ID approach
        if (recordId) {
            NSLog(@"Using direct approach with record ID: %@", recordId);
            
            // Create an identifier predicate
            NSUUID *uuid = [[NSUUID alloc] initWithUUIDString:recordId];
            if (!uuid) {
                // Try to handle Epic-style IDs which aren't standard UUIDs
                // These often end with a digit (e.g., "eazK8FLDwQHB1WkLMuWx0t-8Ba7v8SjlNWk9XpWLv7j03")
                NSString *normalizedId = recordId;
                if ([recordId hasSuffix:@"3"] || [recordId hasSuffix:@"4"]) {
                    // Remove the last digit for Epic-style IDs
                    normalizedId = [recordId substringToIndex:[recordId length] - 1];
                }
                
                // Try with different predicates since different EHR vendors use different ID formats
                [self fetchRecordByIdentifierString:normalizedId callback:callback];
                return;
            }
            
            // Use UUID predicate if we have a valid UUID
            NSPredicate *predicate = [HKQuery predicateForObjectWithUUID:uuid];
            
            // Get all clinical record types to search through
            NSArray *clinicalTypes = @[
                [HKObjectType clinicalTypeForIdentifier:HKClinicalTypeIdentifierAllergyRecord],
                [HKObjectType clinicalTypeForIdentifier:HKClinicalTypeIdentifierConditionRecord],
                [HKObjectType clinicalTypeForIdentifier:HKClinicalTypeIdentifierImmunizationRecord],
                [HKObjectType clinicalTypeForIdentifier:HKClinicalTypeIdentifierLabResultRecord],
                [HKObjectType clinicalTypeForIdentifier:HKClinicalTypeIdentifierMedicationRecord],
                [HKObjectType clinicalTypeForIdentifier:HKClinicalTypeIdentifierProcedureRecord],
                [HKObjectType clinicalTypeForIdentifier:HKClinicalTypeIdentifierVitalSignRecord],
                [HKObjectType clinicalTypeForIdentifier:HKClinicalTypeIdentifierClinicalNoteRecord]
            ];
            
            // Try to find the record from any clinical type
            [self findRecordOfAnyType:clinicalTypes withPredicate:predicate callback:callback];
        }
        // Using the binary ID approach (existing implementation)
        else {
            NSLog(@"Using binary ID approach with ID: %@", binaryId);
            
            // Extract the ID part if it has a "Binary/" prefix
            if ([binaryId hasPrefix:@"Binary/"]) {
                binaryId = [binaryId substringFromIndex:7]; // Remove "Binary/" prefix
            }
            
            // Get clinical note records
            HKSampleType *clinicalNoteType = [HKObjectType clinicalTypeForIdentifier:HKClinicalTypeIdentifierClinicalNoteRecord];
            
            // Create a query to get all clinical records
            HKSampleQuery *query = [[HKSampleQuery alloc] initWithSampleType:clinicalNoteType 
                                                                   predicate:nil
                                                                       limit:100 
                                                             sortDescriptors:nil 
                                                              resultsHandler:^(HKSampleQuery * _Nonnull query, NSArray<__kindof HKSample *> * _Nullable results, NSError * _Nullable error) {
                
                if (error) {
                    NSLog(@"Error querying clinical records: %@", error);
                    callback(@[RCTMakeError(@"Error querying clinical records", error, nil)]);
                    return;
                }
                
                if (results.count == 0) {
                    NSLog(@"No clinical records found");
                    callback(@[RCTMakeError(@"No clinical records found", nil, nil)]);
                    return;
                }
                
                NSLog(@"Found %lu clinical records. Looking for binary ID: %@", (unsigned long)results.count, binaryId);
                
                // Find the clinical record that references our binary
                HKClinicalRecord *targetRecord = nil;
                NSString *contentType = nil;
                
                for (HKClinicalRecord *record in results) {
                    // Parse the FHIR data
                    NSError *jsonError = nil;
                    NSDictionary *fhirData = [NSJSONSerialization JSONObjectWithData:record.FHIRResource.data 
                                                                              options:0 
                                                                                error:&jsonError];
                    
                    if (jsonError) {
                        NSLog(@"Error parsing FHIR data: %@", jsonError);
                        continue; // Skip this record and try the next one
                    }
                    
                    // Look for presentedForm array (for DiagnosticReport)
                    NSArray *presentedForms = fhirData[@"presentedForm"];
                    if (presentedForms && [presentedForms isKindOfClass:[NSArray class]]) {
                        for (NSDictionary *form in presentedForms) {
                            NSString *url = form[@"url"];
                            if (url && [url hasSuffix:binaryId]) {
                                targetRecord = record;
                                contentType = form[@"contentType"];
                                NSLog(@"Found matching record with contentType: %@", contentType);
                                break;
                            }
                        }
                    }
                    
                    // Also look for content array (for DocumentReference)
                    if (!targetRecord) {
                        NSArray *contentArray = fhirData[@"content"];
                        if (contentArray && [contentArray isKindOfClass:[NSArray class]]) {
                            for (NSDictionary *contentItem in contentArray) {
                                NSDictionary *attachment = contentItem[@"attachment"];
                                if (attachment) {
                                    NSString *url = attachment[@"url"];
                                    if (url && [url hasSuffix:binaryId]) {
                                        targetRecord = record;
                                        contentType = attachment[@"contentType"];
                                        NSLog(@"Found matching record in content array with contentType: %@", contentType);
                                        break;
                                    }
                                }
                            }
                        }
                    }
                    
                    if (targetRecord) break;
                }
                
                if (!targetRecord) {
                    NSLog(@"No clinical record found with binary ID: %@", binaryId);
                    callback(@[RCTMakeError(@"No clinical record references this binary ID", nil, nil)]);
                    return;
                }
                
                // Process the attachments for the found record
                [self processAttachmentsForRecord:targetRecord contentType:contentType callback:callback];
            }];
            
            [self.healthStore executeQuery:query];
        }
    } else {
        // For iOS < 16.0
        callback(@[RCTMakeError(@"Attachment retrieval is only available on iOS 16 and above", nil, nil)]);
    }
}

// Helper method to fetch a record by identifier string
- (void)fetchRecordByIdentifierString:(NSString *)identifierString callback:(RCTResponseSenderBlock)callback
{
    // Create predicate for FHIR resource ID
    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"metadata.%K CONTAINS %@", HKMetadataKeyExternalUUID, identifierString];
    
    // Get all clinical record types to search through
    NSArray *clinicalTypes = @[
        [HKObjectType clinicalTypeForIdentifier:HKClinicalTypeIdentifierAllergyRecord],
        [HKObjectType clinicalTypeForIdentifier:HKClinicalTypeIdentifierConditionRecord],
        [HKObjectType clinicalTypeForIdentifier:HKClinicalTypeIdentifierImmunizationRecord],
        [HKObjectType clinicalTypeForIdentifier:HKClinicalTypeIdentifierLabResultRecord],
        [HKObjectType clinicalTypeForIdentifier:HKClinicalTypeIdentifierMedicationRecord],
        [HKObjectType clinicalTypeForIdentifier:HKClinicalTypeIdentifierProcedureRecord],
        [HKObjectType clinicalTypeForIdentifier:HKClinicalTypeIdentifierVitalSignRecord],
        [HKObjectType clinicalTypeForIdentifier:HKClinicalTypeIdentifierClinicalNoteRecord]
    ];
    
    [self findRecordOfAnyType:clinicalTypes withPredicate:predicate callback:callback];
}

// Helper method to find a record of any clinical type matching the predicate
- (void)findRecordOfAnyType:(NSArray<HKObjectType *> *)types withPredicate:(NSPredicate *)predicate callback:(RCTResponseSenderBlock)callback
{
    if (types.count == 0) {
        callback(@[RCTMakeError(@"No clinical record found with the specified ID", nil, nil)]);
        return;
    }
    
    // Try the first type
    HKObjectType *currentType = types[0];
    NSArray *remainingTypes = [types subarrayWithRange:NSMakeRange(1, types.count - 1)];
    
    HKSampleQuery *query = [[HKSampleQuery alloc] initWithSampleType:currentType
                                                           predicate:predicate
                                                               limit:1
                                                     sortDescriptors:nil
                                                      resultsHandler:^(HKSampleQuery * _Nonnull query, NSArray<__kindof HKSample *> * _Nullable results, NSError * _Nullable error) {
        
        if (error) {
            NSLog(@"Error querying for record: %@", error);
            // Try next type instead of failing completely
            [self findRecordOfAnyType:remainingTypes withPredicate:predicate callback:callback];
            return;
        }
        
        if (results.count == 0) {
            // Try next type
            [self findRecordOfAnyType:remainingTypes withPredicate:predicate callback:callback];
            return;
        }
        
        // Found a record, process its attachments
        HKClinicalRecord *record = (HKClinicalRecord *)results[0];
        [self processAttachmentsForRecord:record contentType:nil callback:callback];
    }];
    
    [self.healthStore executeQuery:query];
}

// Helper method to process attachments for a given record
- (void)processAttachmentsForRecord:(HKClinicalRecord *)record contentType:(NSString *)contentType callback:(RCTResponseSenderBlock)callback
{
    // Using the new iOS 16+ APIs for attachments
    HKAttachmentStore *attachmentStore = [[HKAttachmentStore alloc] initWithHealthStore:self.healthStore];
    
    // Use the correct method name from the documentation
    [attachmentStore getAttachmentsForObject:record completion:^(NSArray<HKAttachment *> * _Nullable attachments, NSError * _Nullable attachmentError) {
        if (attachmentError) {
            NSLog(@"Error getting attachments: %@", attachmentError);
            callback(@[RCTMakeError(@"Error getting attachments", attachmentError, nil)]);
            return;
        }
        
        if (attachments.count == 0) {
            NSLog(@"No attachments found for record");
            callback(@[RCTMakeError(@"No attachments found for this record", nil, nil)]);
            return;
        }
        
        NSLog(@"Found %lu attachments", (unsigned long)attachments.count);
        
        // Create a dispatch group to manage async calls
        dispatch_group_t group = dispatch_group_create();
        // Create an array to store all attachment results
        NSMutableArray *attachmentResults = [NSMutableArray arrayWithCapacity:attachments.count];
        // Use a serial queue for processing attachments
        dispatch_queue_t queue = dispatch_queue_create("com.healthkit.attachments", DISPATCH_QUEUE_SERIAL);
        
        // Add a synchronization lock for the results array
        NSObject *arrayLock = [[NSObject alloc] init];
        
        // Try to get contentType from FHIR data if not provided
        NSString *defaultContentType = contentType;
        if (!defaultContentType) {
            // Parse FHIR data to try to find content type
            NSError *jsonError = nil;
            NSDictionary *fhirData = [NSJSONSerialization JSONObjectWithData:record.FHIRResource.data 
                                                                     options:0 
                                                                       error:&jsonError];
            if (!jsonError) {
                // For DocumentReference, look in content array
                NSArray *contentArray = fhirData[@"content"];
                if (contentArray && [contentArray isKindOfClass:[NSArray class]] && contentArray.count > 0) {
                    NSDictionary *contentItem = contentArray[0];
                    NSDictionary *attachment = contentItem[@"attachment"];
                    if (attachment) {
                        defaultContentType = attachment[@"contentType"];
                    }
                }
                
                // For DiagnosticReport, look in presentedForm array
                if (!defaultContentType) {
                    NSArray *presentedForms = fhirData[@"presentedForm"];
                    if (presentedForms && [presentedForms isKindOfClass:[NSArray class]] && presentedForms.count > 0) {
                        NSDictionary *form = presentedForms[0];
                        defaultContentType = form[@"contentType"];
                    }
                }
            }
        }
        
        // Process all attachments
        for (HKAttachment *attachment in attachments) {
            dispatch_group_enter(group);
            
            [attachmentStore getDataForAttachment:attachment completion:^(NSData * _Nullable data, NSError * _Nullable dataError) {
                if (dataError) {
                    NSLog(@"Error getting attachment data: %@", dataError);
                    // Continue with other attachments instead of completely failing
                    dispatch_group_leave(group);
                    return;
                }
                
                if (!data) {
                    NSLog(@"No data retrieved from attachment");
                    dispatch_group_leave(group);
                    return;
                }
                
                // Convert to base64
                NSString *base64Data = [data base64EncodedStringWithOptions:0];
                
                // Create attachment data dictionary
                NSDictionary *attachmentData = @{
                    @"id": [[attachment identifier] UUIDString],
                    @"name": attachment.name ?: @"",
                    @"contentType": defaultContentType ?: @"unknown",
                    @"size": @(attachment.size),
                    @"creationDate": [RCTAppleHealthKit buildISO8601StringFromDate:attachment.creationDate],
                    @"data": base64Data
                };
                
                // Thread-safe addition to results array
                @synchronized(arrayLock) {
                    [attachmentResults addObject:attachmentData];
                }
                
                dispatch_group_leave(group);
            }];
        }
        
        // When all attachments have been processed
        dispatch_group_notify(group, dispatch_get_main_queue(), ^{
            if (attachmentResults.count == 0) {
                callback(@[RCTMakeError(@"Failed to retrieve any attachment data", nil, nil)]);
            } else {
                callback(@[[NSNull null], attachmentResults]);
            }
        });
    }];
}

- (void)clinical_registerObserver:(NSString *)type bridge:(RCTBridge *)bridge hasListeners:(bool)hasListeners
{
    HKSampleType *recordType = [RCTAppleHealthKit clinicalTypeFromName:type];
    if (recordType != nil) {
        [self setObserverForType:recordType type:type bridge:bridge hasListeners:hasListeners];
    }
}

@end