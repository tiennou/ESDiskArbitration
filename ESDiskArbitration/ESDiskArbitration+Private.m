//
//  ESDiskArbitration+Private.m
//  ESDiskArbitration
//
//  Created by Etienne on 24/02/2016.
//  Copyright © 2016 Etienne Samson. All rights reserved.
//

#import "ESDiskArbitration+Private.h"

@implementation ESObserverObject
@end

NSString *const ESDiskArbitrationDomain = @"ESDiskArbitrationDomain";

@implementation NSError (DADissenter)

+ (instancetype)es_errorWithDADissenter:(DADissenterRef)dissenter {
    DAReturn status = DADissenterGetStatus(dissenter);
    if (status == kDAReturnSuccess) return nil;

    NSString *statusString = [(__bridge NSString *)DADissenterGetStatusString(dissenter) copy];
    if (!statusString) {
        switch (status) {
            default:
            case kDAReturnError: statusString = @"Error"; break;
            case kDAReturnBusy: statusString = @"Busy"; break;
            case kDAReturnBadArgument: statusString = @"BadArgument"; break;
            case kDAReturnExclusiveAccess: statusString = @"ExclusiveAccess"; break;
            case kDAReturnNoResources: statusString = @"NoResources"; break;
            case kDAReturnNotFound: statusString = @"NotFound"; break;
            case kDAReturnNotMounted: statusString = @"NotMounted"; break;
            case kDAReturnNotPermitted: statusString = @"NotPermitted"; break;
            case kDAReturnNotPrivileged: statusString = @"NotPrivileged"; break;
            case kDAReturnNotReady: statusString = @"NotReady"; break;
            case kDAReturnNotWritable: statusString = @"NotWritable"; break;
            case kDAReturnUnsupported: statusString = @"Unsupported"; break;
        }
    }

    NSDictionary *info = @{
                           NSLocalizedDescriptionKey:@"DiskArbitration failure",
                           NSLocalizedFailureReasonErrorKey: statusString,
                           };
    // XXX: DAProcessID in approval notifications ?
    return [NSError errorWithDomain:ESDiskArbitrationDomain code:status userInfo:info];
}

@end