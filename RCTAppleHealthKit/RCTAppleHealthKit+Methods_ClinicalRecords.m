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

- (void)clinicalRecord_getAttachments:(NSDictionary *)input callback:(RCTResponseSenderBlock)callback
{
    if (!input || !callback) {
        callback(@[RCTMakeError(@"Input and callback are required", nil, nil)]);
        return;
    }

    NSString *sampleId = [RCTAppleHealthKit stringFromOptions:input key:@"id" withDefault:nil];
    if (!sampleId) {
        callback(@[RCTMakeError(@"Sample id is required", nil, nil)]);
        return;
    }

    HKSampleType *sampleType = [HKObjectType clinicalTypeForIdentifier:HKClinicalTypeIdentifierClinicalNoteRecord];
    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"UUID == %@", [[NSUUID alloc] initWithUUIDString:sampleId]];

    HKHealthStore *healthStore = [[HKHealthStore alloc] init];
    HKAttachmentStore *attachmentStore = [[HKAttachmentStore alloc] initWithHealthStore:healthStore];

    HKSampleQuery *query = [[HKSampleQuery alloc] initWithSampleType:sampleType
                                                         predicate:predicate
                                                         limit:1
                                                         sortDescriptors:nil
                                                         resultsHandler:^(HKSampleQuery *query, NSArray *results, NSError *error) {
        if (error) {
            callback(@[RCTMakeError(@"Error getting clinical record", error, nil)]);
            return;
        }

        if (!results || results.count == 0) {
            callback(@[RCTMakeError(@"No clinical record found", nil, nil)]);
            return;
        }

        HKClinicalRecord *clinicalRecord = results.firstObject;
        
        [attachmentStore getAttachmentsForObject:clinicalRecord completion:^(NSArray<HKAttachment *> *attachments, NSError *attachmentError) {
            if (attachmentError) {
                callback(@[RCTMakeError(@"Error getting attachments", attachmentError, nil)]);
                return;
            }

            NSMutableArray *attachmentData = [NSMutableArray array];
            dispatch_group_t group = dispatch_group_create();
            
            for (HKAttachment *attachment in attachments) {
                dispatch_group_enter(group);
                [attachmentStore getDataForAttachment:attachment completion:^(NSData *data, NSError *dataError) {
                    if (!dataError && data) {
                        NSString *base64String = [data base64EncodedStringWithOptions:0];
                        [attachmentData addObject:@{
                            @"id": attachment.identifier,
                            @"contentType": attachment.contentType,
                            @"data": base64String,
                            @"name": attachment.name ?: [NSNull null],
                            @"creationDate": [RCTAppleHealthKit buildISO8601StringFromDate:attachment.creationDate] ?: [NSNull null],
                            @"metadata": attachment.metadata ?: [NSNull null]
                        }];
                    }
                    dispatch_group_leave(group);
                }];
            }

            dispatch_group_notify(group, dispatch_get_main_queue(), ^{
                callback(@[[NSNull null], attachmentData]);
            });
        }];
    }];

    [healthStore executeQuery:query];
}

@end
