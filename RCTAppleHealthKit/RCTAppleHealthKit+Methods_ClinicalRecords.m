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
    NSString *binaryId = [RCTAppleHealthKit stringFromOptions:input key:@"binaryId" withDefault:nil];
    
    if(binaryId == nil) {
        callback(@[RCTMakeError(@"binaryId is required in options", nil, nil)]);
        return;
    }
    
    // Convert string to UUID
    NSUUID *uuid;
    @try {
        uuid = [[NSUUID alloc] initWithUUIDString:binaryId];
    } @catch (NSException *exception) {
        callback(@[RCTMakeError(@"Invalid binary ID format. Must be a valid UUID string.", nil, nil)]);
        return;
    }
    
    if (!uuid) {
        callback(@[RCTMakeError(@"Invalid binary ID", nil, nil)]);
        return;
    }
    
    // Create an attachment store
    HKAttachmentStore *attachmentStore = [[HKAttachmentStore alloc] initWithHealthStore:self.healthStore];
    
    // Find the clinical sample that contains this attachment
    HKSampleType *clinicalNoteType = [HKObjectType clinicalTypeForIdentifier:HKClinicalTypeIdentifierClinicalNoteRecord];
    NSPredicate *predicate = [HKQuery predicateForObjectWithUUID:uuid];
    
    [self.healthStore executeQuery:[[HKSampleQuery alloc] initWithSampleType:clinicalNoteType predicate:predicate limit:1 sortDescriptors:nil resultsHandler:^(HKSampleQuery * _Nonnull query, NSArray<__kindof HKSample *> * _Nullable results, NSError * _Nullable error) {
        
        if (error) {
            callback(@[RCTMakeError(@"Error querying for clinical sample", error, nil)]);
            return;
        }
        
        if (results.count == 0) {
            callback(@[RCTMakeError(@"No clinical note found with the provided ID", nil, nil)]);
            return;
        }
        
        // Get the clinical sample
        HKClinicalRecord *clinicalRecord = results.firstObject;
        
        // Get attachments for this sample
        [attachmentStore attachmentsForSample:clinicalRecord completion:^(NSArray<HKAttachment *> * _Nullable attachments, NSError * _Nullable attachmentError) {
            
            if (attachmentError) {
                callback(@[RCTMakeError(@"Error retrieving attachments", attachmentError, nil)]);
                return;
            }
            
            if (attachments.count == 0) {
                callback(@[RCTMakeError(@"No attachments found for this clinical record", nil, nil)]);
                return;
            }
            
            // For now, we'll just get the first attachment
            HKAttachment *attachment = attachments.firstObject;
            
            // Create a data reader for the attachment
            HKAttachmentDataReader *dataReader = [attachmentStore dataReaderForAttachment:attachment];
            
            // Get the data
            [dataReader readDataWithCompletion:^(NSData * _Nullable data, NSError * _Nullable dataError) {
                if (dataError) {
                    callback(@[RCTMakeError(@"Error reading attachment data", dataError, nil)]);
                    return;
                }
                
                // Convert data to base64
                NSString *base64Data = [data base64EncodedStringWithOptions:0];
                
                // Create response object
                NSDictionary *response = @{
                    @"id": [[attachment identifier] UUIDString],
                    @"name": [attachment name],
                    @"contentType": [[attachment contentType] identifier],
                    @"size": @([attachment size]),
                    @"creationDate": [RCTAppleHealthKit buildISO8601StringFromDate:[attachment creationDate]],
                    @"data": base64Data
                };
                
                if ([attachment metadata]) {
                    NSMutableDictionary *mutableResponse = [response mutableCopy];
                    [mutableResponse setObject:[attachment metadata] forKey:@"metadata"];
                    response = [mutableResponse copy];
                }
                
                callback(@[[NSNull null], response]);
            }];
        }];
    }]];
}

- (void)clinical_registerObserver:(NSString *)type bridge:(RCTBridge *)bridge hasListeners:(bool)hasListeners
{
    HKSampleType *recordType = [RCTAppleHealthKit clinicalTypeFromName:type];
    if (recordType != nil) {
        [self setObserverForType:recordType type:type bridge:bridge hasListeners:hasListeners];
    }
}

@end
