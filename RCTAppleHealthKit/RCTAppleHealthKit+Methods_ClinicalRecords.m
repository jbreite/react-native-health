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
        NSString *binaryId = [RCTAppleHealthKit stringFromOptions:input key:@"binaryId" withDefault:nil];
        
        if(binaryId == nil) {
            callback(@[RCTMakeError(@"binaryId is required in options", nil, nil)]);
            return;
        }
        
        // Extract the ID part if it has a "Binary/" prefix
        if ([binaryId hasPrefix:@"Binary/"]) {
            binaryId = [binaryId substringFromIndex:7]; // Remove "Binary/" prefix
        }
        
        NSLog(@"Attempting to retrieve attachment with ID: %@", binaryId);
        
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
                
                // Look for presentedForm array
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
                
                if (targetRecord) break;
            }
            
            if (!targetRecord) {
                NSLog(@"No clinical record found with binary ID: %@", binaryId);
                callback(@[RCTMakeError(@"No clinical record references this binary ID", nil, nil)]);
                return;
            }
            
            // Using the new iOS 16+ APIs for attachments
            HKAttachmentStore *attachmentStore = [[HKAttachmentStore alloc] initWithHealthStore:self.healthStore];
            
            // Use the correct method name from the documentation
            [attachmentStore getAttachmentsForObject:targetRecord completion:^(NSArray<HKAttachment *> * _Nullable attachments, NSError * _Nullable attachmentError) {
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
                
                // For this example, we'll just use the first attachment
                HKAttachment *attachment = attachments[0];
                
                // Use the correct method to get the data
                [attachmentStore getDataForAttachment:attachment completion:^(NSData * _Nullable data, NSError * _Nullable dataError) {
                    if (dataError) {
                        NSLog(@"Error getting attachment data: %@", dataError);
                        callback(@[RCTMakeError(@"Error getting attachment data", dataError, nil)]);
                        return;
                    }
                    
                    if (!data) {
                        NSLog(@"No data retrieved from attachment");
                        callback(@[RCTMakeError(@"No data retrieved from attachment", nil, nil)]);
                        return;
                    }
                    
                    // Convert to base64
                    NSString *base64Data = [data base64EncodedStringWithOptions:0];
                    
                    // Create response with attachment data
                    callback(@[[NSNull null], @{
                        @"id": [[attachment identifier] UUIDString],
                        @"name": attachment.name,
                        @"contentType": contentType ?: @"unknown",
                        @"size": @(attachment.size),
                        @"creationDate": [RCTAppleHealthKit buildISO8601StringFromDate:attachment.creationDate],
                        @"data": base64Data
                    }]);
                }];
            }];
        }];
        
        [self.healthStore executeQuery:query];
    } else {
        // For iOS < 16.0
        callback(@[RCTMakeError(@"Attachment retrieval is only available on iOS 16 and above", nil, nil)]);
    }
}

- (void)clinical_registerObserver:(NSString *)type bridge:(RCTBridge *)bridge hasListeners:(bool)hasListeners
{
    HKSampleType *recordType = [RCTAppleHealthKit clinicalTypeFromName:type];
    if (recordType != nil) {
        [self setObserverForType:recordType type:type bridge:bridge hasListeners:hasListeners];
    }
}

@end