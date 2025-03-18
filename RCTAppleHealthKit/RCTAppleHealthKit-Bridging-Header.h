#import <React/RCTBridgeModule.h>
#import <HealthKit/HealthKit.h>

- (void)clinicalRecords_getClinicalRecordAttachment:(NSDictionary *)input callback:(RCTResponseSenderBlock)callback
{
    if (@available(iOS 16.0, *))
    {
        NSString *recordId = [RCTAppleHealthKit stringFromOptions:input key:@"id" withDefault:nil];

        if (recordId == nil)
        {
            callback(@[ RCTMakeError(@"id is required in options", nil, nil) ]);
            return;
        }

        [AttachmentHelper getAttachment:recordId
                            healthStore:self.healthStore
                             completion:^(NSData *_Nullable data, NSString *_Nullable identifier, NSString *_Nullable title, NSError *_Nullable error) {
                               if (error)
                               {
                                   callback(@[ RCTJSErrorFromNSError(error) ]);
                                   return;
                               }

                               if (!data)
                               {
                                   callback(@[ RCTMakeError(@"No attachment data found", nil, nil) ]);
                                   return;
                               }

                               NSString *base64String = [data base64EncodedStringWithOptions:0];
                               NSMutableDictionary *response = [NSMutableDictionary dictionaryWithCapacity:4];
                               [response setObject:base64String forKey:@"content"];

                               if (identifier)
                               {
                                   [response setObject:identifier forKey:@"id"];
                               }
                               if (title)
                               {
                                   [response setObject:title forKey:@"title"];
                               }
                               [response setObject:@(data.length) forKey:@"size"];

                               callback(@[ [NSNull null], response ]);
                             }];
    }
    else
    {
        callback(@[ RCTMakeError(@"This functionality is only available on iOS 16.0 and later", nil, nil) ]);
    }
}