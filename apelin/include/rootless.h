#ifndef ROOTLESS_H
#define ROOTLESS_H

#import <Foundation/Foundation.h>

#ifdef __cplusplus
extern "C" {
#endif

const char *jbroot(const char *path);
const char *rootfs(const char *path);

#ifdef __cplusplus
}
#endif

#define ROOT_PATH(path) jbroot(path)
#define ROOT_PATH_NS(path) [NSString stringWithUTF8String:jbroot([path fileSystemRepresentation])]

#endif
