//
//  ESDisk.m
//  ESDiskArbitration
//
//  Created by Etienne on 18/01/2014.
//  Copyright (c) 2014 Etienne Samson. All rights reserved.
//

#import "ESDisk.h"

#import "ESDiskManager.h"
#import "ESDiskArbitration+Private.h"

#import <IOKit/kext/KextManager.h>

@interface ESAbstractDisk ()
- (void)setValue:(id)value forDAKey:(NSString *)key;
@end

static void ESDiskDescriptionChangedCallback(DADiskRef diskRef, CFArrayRef keys, void * __nullable context) {
    ESAbstractDisk *disk = (__bridge ESAbstractDisk *)context;

    NSDictionary *diskInfo = (__bridge_transfer NSDictionary *)DADiskCopyDescription(diskRef);

    for (NSString *key in (__bridge NSArray *)keys) {
        id value = diskInfo[key];
        [disk setValue:[value copy] forDAKey:key];
    }
}

@implementation ESAbstractDisk

+ (instancetype)diskWithDADisk:(DADiskRef)diskRef {
    return [self diskWithDADisk:diskRef manager:[ESDiskManager sharedManager]];
}

+ (instancetype)diskWithDADisk:(DADiskRef)diskRef manager:(ESDiskManager *)manager {
    NSParameterAssert(diskRef != nil);
    NSParameterAssert(manager != nil);

    ESDisk *disk = [manager knownDiskForDADisk:diskRef];
    if (!disk) return nil;

    return disk;
}

- (instancetype)initWithDADisk:(DADiskRef)diskRef description:(NSDictionary *)diskDescription manager:(ESDiskManager *)manager {
    NSParameterAssert(diskRef != nil);
    NSParameterAssert(manager != nil);

    self = [super init];
    if (!self) return nil;

    _diskRef = (DADiskRef)CFRetain(diskRef);
    _manager = manager;

    for (NSString *key in diskDescription) {
        [self setValue:diskDescription[key] forDAKey:key];
    }

    NSDictionary *match = nil;
    id value = nil;
    if ((value = diskDescription[(__bridge NSString *)kDADiskDescriptionVolumeUUIDKey])) {
        match = @{(__bridge NSString *)kDADiskDescriptionVolumeUUIDKey: value};
    } else if ((value = diskDescription[(__bridge NSString *)kDADiskDescriptionDeviceGUIDKey])) {
        match = @{(__bridge NSString *)kDADiskDescriptionDeviceGUIDKey: value};
    } else if ((value = diskDescription[(__bridge NSString *)kDADiskDescriptionMediaBSDNameKey])) {
        match = @{(__bridge NSString *)kDADiskDescriptionMediaBSDNameKey: value};
    } else if ((value = diskDescription[(__bridge NSString *)kDADiskDescriptionVolumePathKey])) {
        match = @{(__bridge NSString *)kDADiskDescriptionVolumePathKey: value};
    } else {
        NSAssert(match != nil, @"Unable to build matcher for %@", self);
    }

    DARegisterDiskDescriptionChangedCallback(manager.session, (__bridge CFDictionaryRef)match, NULL, ESDiskDescriptionChangedCallback, (__bridge void *)self);

    return self;
}

- (void)dealloc {
    DAUnregisterCallback(self.manager.session, ESDiskDescriptionChangedCallback, (__bridge void *)self);
    if (_diskRef) {
        CFRelease(_diskRef), _diskRef = NULL;
    }
}

- (id)copyWithZone:(NSZone *)zone {
    return self;
}

- (NSMutableDictionary *)DAKeysMapping {
    return @{
             (__bridge NSString *)kDADiskDescriptionMediaWritableKey:   @"writable",
             (__bridge NSString *)kDADiskDescriptionMediaBSDNameKey:    @"BSDName",
             }.mutableCopy;
}

- (void)setValue:(id)value forDAKey:(NSString *)daKey {
    NSString *key = self.DAKeysMapping[daKey];
    if (!key) return;

    [self setValue:value forKey:key];
}

- (NSUInteger)hash {
    return CFHash(_diskRef) ^ (unsigned long)self;
}

- (BOOL)isEqual:(id)object {
    return (self.hash == [object hash]);
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p ID:%@>", NSStringFromClass([self class]), self, self.BSDName];
}

- (NSDictionary *)diskDescription {
    return (__bridge_transfer id)DADiskCopyDescription(self.diskRef);
}

- (BOOL)isDisk { return [self isKindOfClass:[ESDisk class]]; }
- (BOOL)isVolume { return [self isKindOfClass:[ESVolume class]]; }
- (BOOL)isNetworkVolume { return [self isKindOfClass:[ESNetworkVolume class]]; }

- (NSImage *)icon {
    NSDictionary *iconDict = self.diskDescription[(__bridge NSString *)kDADiskDescriptionMediaIconKey];
    NSBundle *bundle = [NSBundle bundleWithIdentifier:iconDict[(__bridge NSString *)kCFBundleIdentifierKey]];
    if (!bundle) {
        NSURL *bundleURL = (__bridge_transfer NSURL *)KextManagerCreateURLForBundleIdentifier(kCFAllocatorDefault, (__bridge_retained CFStringRef)iconDict[(__bridge NSString *)kCFBundleIdentifierKey]);
        if (!bundleURL) return nil;

        bundle = [NSBundle bundleWithURL:bundleURL];
    }

    // We have an appropriate bundle, look for an icon
    NSURL *imageURL = [bundle URLForImageResource:iconDict[@(kIOBundleResourceFileKey)]];
    if (!imageURL) return nil;

    return [[NSImage alloc] initByReferencingURL:imageURL];
}

@end

#pragma mark -
#pragma mark Generic DA callbacks

typedef void (^ESCompletionHandler)(NSError *);

void ESCompletionCallback(DADiskRef diskRef, DADissenterRef __nullable dissenter, void * __nullable context) {
    ESCompletionHandler handler = (__bridge ESCompletionHandler)context;

    NSError *error = nil;
    if (dissenter) {
        error = [NSError es_errorWithDADissenter:dissenter];
    }
    handler(error);
}

@implementation ESDisk

- (NSMutableDictionary *)DAKeysMapping {
    NSMutableDictionary *keys = [super DAKeysMapping];

    keys[(__bridge NSString *)kDADiskDescriptionMediaNameKey]      = @"name";
    keys[(__bridge NSString *)kDADiskDescriptionDeviceInternalKey] = @"internal";
    keys[(__bridge NSString *)kDADiskDescriptionMediaRemovableKey] = @"removable";

    return keys;
}

- (void)addVolume:(ESVolume *)volume {
    [self.mutableVolumes addObject:volume];
    volume.disk = self;
}

- (NSArray<ESVolume *> *)volumes {
    return [self.mutableVolumes copy];
}

- (void)eject:(ESDiskEjectOptions)options completionHandler:(void (^)(NSError *))completionHandler {
    DADiskEject(self.diskRef, options, ESCompletionCallback, _Block_copy((__bridge void *)completionHandler));
}

@end

@implementation ESVolume

- (instancetype)initWithDADisk:(DADiskRef)diskRef description:(NSDictionary *)diskDescription manager:(ESDiskManager *)manager {
    self = [super initWithDADisk:diskRef description:diskDescription manager:manager];

    DADiskRef wholeDiskRef = DADiskCopyWholeDisk(diskRef);
    if (wholeDiskRef) {
        ESDisk *wholeDisk = [manager knownDiskForDADisk:wholeDiskRef];
        [wholeDisk addVolume:self];
        CFRelease(wholeDiskRef);
    }

    return self;
}

- (NSMutableDictionary *)DAKeysMapping {
    NSMutableDictionary *keys = [super DAKeysMapping];

    [keys setObject:@"name"      forKey:(__bridge NSString *)kDADiskDescriptionVolumeNameKey];
    [keys setObject:@"path"      forKey:(__bridge NSString *)kDADiskDescriptionVolumePathKey];
    [keys setObject:@"mountable" forKey:(__bridge NSString *)kDADiskDescriptionVolumeMountableKey];

    return keys;
}

- (void)rename:(NSString *)name options:(ESVolumeRenameOptions)options completionHandler:(void (^)(NSError *error))completionHandler {
    DADiskRename(self.diskRef, (__bridge CFStringRef)name, options, ESCompletionCallback, _Block_copy((__bridge void *)completionHandler));
}

- (void)mount:(void (^)(NSError *))completionHandler {
    [self mountAtURL:nil completionHandler:completionHandler];
}

- (void)mountAtURL:(NSURL *)URL completionHandler:(void (^)(NSError *error))completionHandler {
    DADiskMount(self.diskRef, (__bridge_retained CFURLRef)URL, kDADiskMountOptionDefault, ESCompletionCallback, _Block_copy((__bridge void *)completionHandler));
}

- (void)unmount:(ESVolumeUnmountOptions)options completionHandler:(void (^)(NSError *))completionHandler {
    DADiskUnmountOptions opts = kDADiskUnmountOptionDefault;
    if (options & ESVolumeUnmountOptionsForce) opts |= kDADiskUnmountOptionForce;
    if (options & ESVolumeUnmountOptionsWholeDisk) opts |= kDADiskMountOptionWhole;

    DADiskUnmount(self.diskRef, opts, ESCompletionCallback, _Block_copy((__bridge void *)completionHandler));
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p BSDName:%@ path:\"%@\">", NSStringFromClass([self class]), self, self.BSDName, self.path];
}

- (BOOL)isMounted {
    return (self.path != nil);
}

@end

@implementation ESNetworkVolume

@end
