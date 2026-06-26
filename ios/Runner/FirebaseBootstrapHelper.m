#import <Foundation/Foundation.h>
@import FirebaseCore;

/// Безопасный Firebase.configure — NSException не роняет процесс на iOS 26.
BOOL HANEatConfigureFirebase(void) {
  @try {
    if ([FIRApp defaultApp] != nil) {
      return YES;
    }

    NSString *plistPath =
        [[NSBundle mainBundle] pathForResource:@"GoogleService-Info" ofType:@"plist"];
    if (plistPath.length > 0 &&
        [[NSFileManager defaultManager] fileExistsAtPath:plistPath]) {
      FIROptions *fromPlist = [[FIROptions alloc] initWithContentsOfFile:plistPath];
      if (fromPlist != nil) {
        [FIRApp configureWithOptions:fromPlist];
        NSLog(@"FirebaseBootstrapHelper: configured from plist");
        return YES;
      }
    }

    FIROptions *options = [[FIROptions alloc] initWithGoogleAppID:@"1:834367201092:ios:297f6b4e449dc345cf0111"
                                                      GCMSenderID:@"834367201092"];
    options.APIKey = @"AIzaSyA2YEEwYD36C_34Bq6Cb1AnDHuCSkV2tIg";
    options.projectID = @"han-eat";
    options.storageBucket = @"han-eat.firebasestorage.app";
    options.bundleID = [[NSBundle mainBundle] bundleIdentifier] ?: @"com.haneat.app";
    [FIRApp configureWithOptions:options];
    NSLog(@"FirebaseBootstrapHelper: configured from embedded options");
    return YES;
  } @catch (NSException *exception) {
    NSLog(@"FirebaseBootstrapHelper: configure failed: %@", exception);
    return NO;
  }
}
