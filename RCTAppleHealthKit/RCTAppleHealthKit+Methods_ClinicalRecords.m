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

- (void)attachments_getAttachment:(NSDictionary *)input callback:(RCTResponseSenderBlock)callback
{
    NSString *attachmentUrl = [RCTAppleHealthKit stringFromOptions:input key:@"url" withDefault:nil];
    NSString *attachmentId = [RCTAppleHealthKit stringFromOptions:input key:@"id" withDefault:nil];
    
    if (!attachmentUrl && !attachmentId) {
        callback(@[RCTMakeError(@"Either url or id is required in options", nil, nil)]);
        return;
    }
    
    // Check if HKAttachment is available (iOS 16+)
    if (@available(iOS 16.0, *)) {
        // Convert the Binary/identifier URL format to just the identifier
        NSString *identifierString = attachmentUrl;
        if (attachmentUrl && [attachmentUrl hasPrefix:@"Binary/"]) {
            identifierString = [attachmentUrl stringByReplacingOccurrencesOfString:@"Binary/" withString:@""];
        } else if (attachmentId) {
            identifierString = attachmentId;
        }
        
        NSUUID *uuid = [[NSUUID alloc] initWithUUIDString:identifierString];
        if (!uuid) {
            callback(@[RCTMakeError(@"Invalid attachment identifier format", nil, nil)]);
            return;
        }
        
        // Use the HealthKit store to get the attachment
        HKAttachmentStore *attachmentStore = [[HKAttachmentStore alloc] initWithHealthStore:self.healthStore];
        
        // Get attachment asynchronously
        [attachmentStore attachmentWithIdentifier:uuid completionHandler:^(HKAttachment * _Nullable attachment, NSError * _Nullable error) {
            if (error) {
                callback(@[RCTMakeError(@"Error retrieving attachment", error, nil)]);
                return;
            }
            
            if (!attachment) {
                callback(@[RCTMakeError(@"Attachment not found", nil, nil)]);
                return;
            }
            
            // Create a data reader for the attachment
            HKAttachmentDataReader *reader = [attachmentStore dataReaderForAttachment:attachment];
            
            // Read the data
            [reader readDataWithCompletionHandler:^(NSData * _Nullable data, NSError * _Nullable readError) {
                if (readError) {
                    callback(@[RCTMakeError(@"Error reading attachment data", readError, nil)]);
                    return;
                }
                
                if (!data) {
                    callback(@[RCTMakeError(@"No data found in attachment", nil, nil)]);
                    return;
                }
                
                // Convert the data based on content type for human readability
                NSString *contentType = attachment.contentType;
                NSString *dataString = nil;
                
                if ([contentType hasPrefix:@"text/"]) {
                    // For text content, convert to a UTF-8 string
                    dataString = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                } else {
                    // For binary content like images, convert to base64
                    dataString = [data base64EncodedStringWithOptions:0];
                }
                
                // Create the result object
                NSDictionary *result = @{
                    @"id": [[attachment identifier] UUIDString],
                    @"name": attachment.name ?: @"",
                    @"contentType": contentType ?: @"application/octet-stream",
                    @"size": @(attachment.size),
                    @"creationDate": attachment.creationDate ? [RCTAppleHealthKit buildISO8601StringFromDate:attachment.creationDate] : [NSNull null],
                    @"data": dataString ?: [NSNull null],
                    @"isBase64": [contentType hasPrefix:@"text/"] ? @NO : @YES,
                    @"metadata": attachment.metadata ?: [NSNull null]
                };
                
                callback(@[[NSNull null], result]);
            }];
        }];
    } else {
        callback(@[RCTMakeError(@"HKAttachment is only available in iOS 16.0 and above", nil, nil)]);
        return;
    }
}
@end
