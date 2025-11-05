#import <Metal/Metal.h>
#import <Foundation/Foundation.h>

#ifdef EMBEDDED_METALLIB_HEADER
#include EMBEDDED_METALLIB_HEADER
#else
#error "EMBEDDED_METALLIB_HEADER not defined"
#endif

// C++ interface to load the embedded metallib without exposing ObjC types
extern "C" {
  void* loadEmbeddedMetalLibrary(void* device, const char** errorMsg) {
    id<MTLDevice> mtlDevice = (__bridge id<MTLDevice>)device;
    NSError* error = nil;

    id<MTLLibrary> library = EMBEDDED_METALLIB_NAMESPACE::createLibrary(mtlDevice, &error);

    if (!library && errorMsg && error) {
      *errorMsg = strdup([error.localizedDescription UTF8String]);
    }

    return (__bridge void*)library;
  }
}
