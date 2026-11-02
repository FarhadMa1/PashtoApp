#import "pashto_metadata.h"
#import <CoreData/CoreData.h>

NSDictionary *pashto_store_metadata(NSURL *url, NSError **error) {
    @try {
        return [NSPersistentStoreCoordinator metadataForPersistentStoreOfType:NSSQLiteStoreType
                                                                          URL:url
                                                                      options:nil
                                                                        error:error];
    } @catch (id exception) {
        if (error != NULL) {
            NSString *reason = @"The progress store metadata could not be read.";
            if ([exception isKindOfClass:[NSException class]]) {
                reason = [(NSException *)exception reason] ?: [(NSException *)exception name];
            }
            *error = [NSError errorWithDomain:@"PashtoPersistence"
                                         code:1
                                     userInfo:@{NSLocalizedDescriptionKey: reason}];
        }
        return nil;
    }
}
