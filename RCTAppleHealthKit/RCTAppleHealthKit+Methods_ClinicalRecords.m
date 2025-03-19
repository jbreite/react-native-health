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
    
    // Get the attachment store
    HKAttachmentStore *attachmentStore = [[HKAttachmentStore alloc] initWithHealthStore:self.healthStore];
    
    // Use the clinical records API to find the attachment
    HKSampleType *clinicalType = [HKObjectType clinicalTypeForIdentifier:HKClinicalTypeIdentifierClinicalNoteRecord];
    
    // Create a predicate to search for the specific binary ID in metadata
    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"metadata.%@ = %@", @"binaryId", binaryId];
    
    [self.healthStore fhirResourcesWithType:clinicalType identifier:binaryId completion:^(NSArray *resources, NSError *error) {
        if(error) {
            callback(@[RCTMakeError(@"Error fetching binary resource", error, nil)]);
            return;
        }
        
        if(resources.count == 0) {
            callback(@[RCTMakeError(@"No binary resource found with the given ID", nil, nil)]);
            return;
        }
        
        // Get the attachment
        HKAttachment *attachment = resources.firstObject;
        
        // Create a data reader for the attachment
        HKAttachmentDataReader *dataReader = [attachmentStore dataReaderForAttachment:attachment];
        
        // Read the attachment data
        [dataReader readDataWithCompletion:^(NSData *data, NSError *dataError) {
            if(dataError) {
                callback(@[RCTMakeError(@"Error reading attachment data", dataError, nil)]);
                return;
            }
            
            // Convert the data to base64
            NSString *base64String = [data base64EncodedStringWithOptions:0];
            
            // Create the response object
            NSDictionary *response = @{
                @"id": [[attachment identifier] UUIDString],
                @"name": [attachment name],
                @"contentType": [[attachment contentType] identifier],
                @"size": @([attachment size]),
                @"creationDate": [RCTAppleHealthKit buildISO8601StringFromDate:[attachment creationDate]],
                @"metadata": [attachment metadata] ?: @{},
                @"data": base64String
            };
            
            callback(@[[NSNull null], response]);
        }];
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
