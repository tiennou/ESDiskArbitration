//
//  ESDisk.h
//  ESDiskArbitration
//
//  Created by Etienne on 18/01/2014.
//  Copyright (c) 2014 Etienne Samson. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface ESAbstractDisk : NSObject <NSCopying>

+ (instancetype)diskWithDADisk:(DADiskRef)disk;

- (instancetype)init NS_UNAVAILABLE;

- (BOOL)isDisk;
- (BOOL)isVolume;
- (BOOL)isNetworkVolume;

@property (readonly) NSDictionary *diskDescription; // DEBUGGING ONLY

@property (readonly, retain) NSString *BSDName;

@property (readonly, retain) NSString *name;
@property (readonly, assign) NSImage *icon;

@property (readonly, assign, getter=isWritable) BOOL writable;

@end

@class ESVolume;

typedef NS_ENUM(NSUInteger, ESDiskEjectOptions) {
    ESDiskEjectOptionsDefault = 0,
};

@interface ESDisk : ESAbstractDisk

@property (readonly, retain) NSArray<ESVolume *> *volumes;

@property (readonly, assign, getter=isInternal) BOOL internal;
@property (readonly, assign, getter=isRemovable) BOOL removable;

- (void)eject:(ESDiskEjectOptions)options completionHandler:(void (^)(NSError *error))completionHandler;

@end

typedef NS_ENUM(NSUInteger, ESVolumeUnmountOptions) {
    ESVolumeUnmountOptionsDefault   = 0,
    ESVolumeUnmountOptionsForce     = 1,
    ESVolumeUnmountOptionsWholeDisk = 2,
};

typedef NS_ENUM(NSUInteger, ESVolumeRenameOptions) {
    ESVolumeRenameOptionsDefault = 0,
};

@interface ESVolume : ESAbstractDisk

- (void)rename:(NSString *)name options:(ESVolumeRenameOptions)options completionHandler:(void (^)(NSError *error))completionHandler;
- (void)mount:(void (^)(NSError *error))completionHandler;
- (void)mountAtURL:(NSURL *)URL completionHandler:(void (^)(NSError *error))completionHandler;
- (void)unmount:(ESVolumeUnmountOptions)options completionHandler:(void (^)(NSError *error))completionHandler;

@property (readonly, weak) ESDisk *disk;

@property (readonly, assign, getter=isMountable) BOOL mountable;
@property (readonly, assign, getter=isMounted) BOOL mounted;
@property (readonly, retain) NSURL *path;

@end

@interface ESNetworkVolume : ESVolume

@end