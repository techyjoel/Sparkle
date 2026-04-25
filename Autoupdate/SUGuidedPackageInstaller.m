//
//  SUGuidedPackageInstaller.m
//  Sparkle
//
//  Created by Graham Miln on 14/05/2010.
//  Copyright 2010 Dragon Systems Software Limited. All rights reserved.
//

#if SPARKLE_BUILD_PACKAGE_SUPPORT

#import <sys/stat.h>
#import <time.h>
#import "SUGuidedPackageInstaller.h"
#import "SUErrors.h"
#import "SULog.h"


#include "AppKitPrevention.h"

__attribute__((used)) static const char *SUBreakdownPackageUpdateMarkerString = "BREAKDOWN_SPARKLE_PACKAGE_UPDATE_MARKER";
static NSString * const SUBreakdownPackageUpdateMarkerDirectory = @"/private/var/run/breakdown";
static NSString * const SUBreakdownPackageUpdateMarkerPath = @"/private/var/run/breakdown/com.breakdown.menu.sparkle-package-update";

@implementation SUGuidedPackageInstaller
{
    NSString *_packagePath;
    NSString *_homeDirectory;
    NSString *_userName;
}

- (instancetype)initWithPackagePath:(NSString *)packagePath homeDirectory:(NSString *)homeDirectory userName:(NSString *)userName
{
    self = [super init];
    if (self != nil) {
        _packagePath = [packagePath copy];
        _homeDirectory = [homeDirectory copy];
        _userName = [userName copy];
    }
    return self;
}

- (BOOL)performInitialInstallation:(NSError * __autoreleasing *)__unused error
{
    return YES;
}

- (BOOL)performFinalInstallationProgressBlock:(nullable void(^)(double))__unused cb error:(NSError * __autoreleasing *)error
{
    // This command *must* be run as root
    NSString *installerPath = @"/usr/sbin/installer";
    
    // PackageKit does not reliably preserve task.environment across the
    // privileged script boundary. Breakdown consumes this root-owned runtime
    // marker to leave host-app relaunch ownership to Sparkle.
    NSFileManager *fileManager = NSFileManager.defaultManager;
    if (![fileManager createDirectoryAtPath:SUBreakdownPackageUpdateMarkerDirectory withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions: @(0700)} error:nil]) {
        SULog(SULogLevelError, @"Failed to create Breakdown Sparkle package update marker directory at %@", SUBreakdownPackageUpdateMarkerDirectory);
    }
    NSString *marker = [NSString stringWithFormat:@"package_path=%@\ncreated_at=%lld\n", _packagePath, (long long)time(NULL)];
    if (![marker writeToFile:SUBreakdownPackageUpdateMarkerPath atomically:YES encoding:NSUTF8StringEncoding error:nil]) {
        SULog(SULogLevelError, @"Failed to write Breakdown Sparkle package update marker at %@", SUBreakdownPackageUpdateMarkerPath);
    } else {
        chmod(SUBreakdownPackageUpdateMarkerPath.fileSystemRepresentation, S_IRUSR | S_IWUSR);
    }
    
    NSTask *task = [[NSTask alloc] init];
    task.launchPath = installerPath;
    task.arguments = @[@"-pkg", _packagePath, @"-target", @"/"];
    // Set the $HOME and $USER variables so pre/post install scripts reference the correct user environment.
    // Breakdown uses the Sparkle marker to avoid racing Sparkle's own app relaunch during package updates.
    task.environment = @{@"HOME": _homeDirectory, @"USER": _userName, @"BREAKDOWN_SPARKLE_PACKAGE_UPDATE": @"1"};
    task.standardError = nil;
    task.standardOutput = nil;
    
    NSError *launchError = nil;
    if (![task launchAndReturnError:&launchError]) {
        if (error != NULL) {
            NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithDictionary:@{ NSLocalizedDescriptionKey: @"Guided package installer failed to launch" }];
            
            if (launchError != nil) {
                userInfo[NSUnderlyingErrorKey] = launchError;
            }
            
            *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUInstallationError userInfo:userInfo];
        }
        return NO;
    }
    
    [task waitUntilExit];
    
    if (task.terminationStatus != EXIT_SUCCESS) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUInstallationError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Guided package installer returned non-zero exit status (%d)", task.terminationStatus] }];
        }
        
        return NO;
    }
    
    return YES;
}

- (void)performCleanup
{
}

@end

#endif
