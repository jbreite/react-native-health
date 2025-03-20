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
        // Get the record ID from input
        NSString *recordId = [RCTAppleHealthKit stringFromOptions:input key:@"recordId" withDefault:nil];
        
        if(!recordId) {
            callback(@[RCTMakeError(@"recordId is required in options", nil, nil)]);
            return;
        }
        
        NSLog(@"Getting attachments for record ID: %@", recordId);
        
        // Create a UUID from the record ID
        NSUUID *uuid = [[NSUUID alloc] initWithUUIDString:recordId];
        if (!uuid) {
            callback(@[RCTMakeError(@"Invalid record ID format", nil, nil)]);
            return;
        }
        
        // Create a query to find the object directly by UUID
        NSPredicate *predicate = [HKQuery predicateForObjectWithUUID:uuid];
        
        // Query for all clinical record types - HealthKit will find the matching UUID
        // regardless of which clinical type it belongs to
        HKSampleType *clinicalType = [HKObjectType clinicalTypeForIdentifier:HKClinicalTypeIdentifierClinicalNoteRecord];
        
        HKSampleQuery *query = [[HKSampleQuery alloc] initWithSampleType:clinicalType
                                                               predicate:predicate
                                                                   limit:1
                                                         sortDescriptors:nil
                                                          resultsHandler:^(HKSampleQuery * _Nonnull query, NSArray<__kindof HKSample *> * _Nullable results, NSError * _Nullable error) {
            
            if (error) {
                NSLog(@"Error finding record with UUID %@: %@", recordId, error);
                callback(@[RCTMakeError(@"Error finding record", error, nil)]);
                return;
            }
            
            if (results.count == 0) {
                NSLog(@"No record found with UUID %@", recordId);
                callback(@[RCTMakeError(@"No record found with the specified ID", nil, nil)]);
                return;
            }
            
            // Found the record, now get its attachments
            HKClinicalRecord *record = (HKClinicalRecord *)results[0];
            
            HKAttachmentStore *attachmentStore = [[HKAttachmentStore alloc] initWithHealthStore:self.healthStore];
            
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
                
                NSLog(@"Found %lu attachments for record", (unsigned long)attachments.count);
                
                // Create a dispatch group for async processing
                dispatch_group_t group = dispatch_group_create();
                NSMutableArray *attachmentResults = [NSMutableArray arrayWithCapacity:attachments.count];
                
                // Process all attachments
                for (HKAttachment *attachment in attachments) {
                    dispatch_group_enter(group);
                    
                    [attachmentStore getDataForAttachment:attachment completion:^(NSData * _Nullable data, NSError * _Nullable dataError) {
                        if (dataError || !data) {
                            NSLog(@"Error getting attachment data: %@", dataError);
                            dispatch_group_leave(group);
                            return;
                        }
                        
                        // Get contentType from FHIR data if possible
                        NSString *contentType = @"unknown";
                        
                        // Parse FHIR data to find content type for this attachment
                        NSError *jsonError = nil;
                        NSDictionary *fhirData = [NSJSONSerialization JSONObjectWithData:record.FHIRResource.data 
                                                                                options:0 
                                                                                  error:&jsonError];
                        
                        if (!jsonError) {
                            // Try to match content type for DocumentReference
                            NSArray *contentArray = fhirData[@"content"];
                            if (contentArray && [contentArray isKindOfClass:[NSArray class]]) {
                                for (NSDictionary *item in contentArray) {
                                    NSDictionary *attachmentObj = item[@"attachment"];
                                    if (attachmentObj && attachmentObj[@"contentType"]) {
                                        contentType = attachmentObj[@"contentType"];
                                        break;
                                    }
                                }
                            }
                            
                            // Try to match content type for DiagnosticReport
                            if ([contentType isEqualToString:@"unknown"]) {
                                NSArray *presentedForms = fhirData[@"presentedForm"];
                                if (presentedForms && [presentedForms isKindOfClass:[NSArray class]] && presentedForms.count > 0) {
                                    NSDictionary *form = presentedForms[0];
                                    if (form[@"contentType"]) {
                                        contentType = form[@"contentType"];
                                    }
                                }
                            }
                        }
                        
                        // Create result dictionary
                        NSString *base64Data = [data base64EncodedStringWithOptions:0];
                        NSDictionary *attachmentData = @{
                            @"id": [[attachment identifier] UUIDString],
                            @"name": attachment.name ?: @"",
                            @"contentType": contentType,
                            @"size": @(attachment.size),
                            @"creationDate": [RCTAppleHealthKit buildISO8601StringFromDate:attachment.creationDate],
                            @"data": base64Data
                        };
                        
                        // Thread-safe addition to results array
                        @synchronized(attachmentResults) {
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