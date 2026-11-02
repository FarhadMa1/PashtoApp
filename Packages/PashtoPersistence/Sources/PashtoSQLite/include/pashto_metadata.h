#ifndef PASHto_METADATA_H
#define PASHto_METADATA_H

#import <Foundation/Foundation.h>

/// Metadata for a SQLite store. `NSError` and `NSException` both come back
/// as `error`. The caller never sees an uncaught exception.
NSDictionary * _Nullable pashto_store_metadata(NSURL * _Nonnull url, NSError * _Nullable * _Nullable error);

#endif
