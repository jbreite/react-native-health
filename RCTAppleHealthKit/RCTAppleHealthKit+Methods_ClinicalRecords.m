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

- (void)clinical_registerObserver:(NSString *)type bridge:(RCTBridge *)bridge hasListeners:(bool)hasListeners
{
    HKSampleType *recordType = [RCTAppleHealthKit clinicalTypeFromName:type];
    if (recordType != nil) {
        [self setObserverForType:recordType type:type bridge:bridge hasListeners:hasListeners];
    }
}

- (void)clinicalRecords_getClinicalRecordAttachments:(NSDictionary *)input callback:(RCTResponseSenderBlock)callback
{
    NSDate *startDate = [RCTAppleHealthKit dateFromOptions:input key:@"startDate" withDefault:nil];
    NSDate *endDate = [RCTAppleHealthKit dateFromOptions:input key:@"endDate" withDefault:[NSDate date]];
    NSUInteger limit = [RCTAppleHealthKit uintFromOptions:input key:@"limit" withDefault:HKObjectQueryNoLimit];
    BOOL ascending = [RCTAppleHealthKit boolFromOptions:input key:@"ascending" withDefault:false];

    if(startDate == nil) {
        callback(@[RCTMakeError(@"startDate is required in options", nil, nil)]);
        return;
    }

    NSPredicate *predicate = [RCTAppleHealthKit predicateForSamplesBetweenDates:startDate endDate:endDate];

    [self fetchClinicalRecordAttachments:predicate
                              ascending:ascending
                                 limit:limit
                           completion:^(NSArray *results, NSError *error) {
        if(results){
            callback(@[[NSNull null], results]);
            return;
        } else {
            NSLog(@"error getting clinical record attachments: %@", error);
            callback(@[RCTMakeError(@"error getting clinical record attachments:", error, nil)]);
            return;
        }
    }];
}

@end
