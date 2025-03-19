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
        
        // We found the record, return basic info about it for now
        callback(@[[NSNull null], @{
            @"status": @"success",
            @"message": @"Found the specific clinical record",
            @"recordId": [[targetRecord UUID] UUIDString],
            @"binaryId": binaryId,
            @"contentType": contentType ?: @"unknown"
        }]);
        
        // TODO: Next step will be to access the attachment data
    }];
    
    [self.healthStore executeQuery:query];
}
- (void)clinical_registerObserver:(NSString *)type bridge:(RCTBridge *)bridge hasListeners:(bool)hasListeners
{
    HKSampleType *recordType = [RCTAppleHealthKit clinicalTypeFromName:type];
    if (recordType != nil) {
        [self setObserverForType:recordType type:type bridge:bridge hasListeners:hasListeners];
    }
}

@end
