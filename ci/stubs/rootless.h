#import <Foundation/Foundation.h>
// Match the complete real path under a process-isolated temporary test root.
#define ROOT_PATH_NS(path) [[NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"kayoko-manager-%d", NSProcessInfo.processInfo.processIdentifier]] stringByAppendingString:(path)]
