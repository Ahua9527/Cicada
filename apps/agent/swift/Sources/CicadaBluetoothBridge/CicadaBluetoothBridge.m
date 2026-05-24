#import "CicadaBluetoothBridge.h"
#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <unistd.h>

typedef int (*CicadaBluetoothGetPowerStateFn)(void);
typedef void (*CicadaBluetoothSetPowerStateFn)(int);

static void *CicadaBluetoothFrameworkHandle(void) {
    static void *handle = NULL;
    if (handle != NULL) {
        return handle;
    }
    handle = dlopen("/System/Library/Frameworks/IOBluetooth.framework/IOBluetooth", RTLD_LAZY);
    return handle;
}

static CicadaBluetoothGetPowerStateFn CicadaBluetoothGetPowerStateFunction(void) {
    void *handle = CicadaBluetoothFrameworkHandle();
    if (handle == NULL) {
        return NULL;
    }
    return (CicadaBluetoothGetPowerStateFn)dlsym(handle, "IOBluetoothPreferenceGetControllerPowerState");
}

static CicadaBluetoothSetPowerStateFn CicadaBluetoothSetPowerStateFunction(void) {
    void *handle = CicadaBluetoothFrameworkHandle();
    if (handle == NULL) {
        return NULL;
    }
    return (CicadaBluetoothSetPowerStateFn)dlsym(handle, "IOBluetoothPreferenceSetControllerPowerState");
}

int32_t CicadaBluetoothGetControllerPowerState(void) {
    @try {
        CicadaBluetoothGetPowerStateFn getPowerState = CicadaBluetoothGetPowerStateFunction();
        if (getPowerState == NULL) {
            return -1;
        }
        return getPowerState() ? 1 : 0;
    } @catch (NSException *exception) {
        return -1;
    }
}

int32_t CicadaBluetoothSetControllerPowerState(int32_t enabled) {
    @try {
        CicadaBluetoothGetPowerStateFn getPowerState = CicadaBluetoothGetPowerStateFunction();
        CicadaBluetoothSetPowerStateFn setPowerState = CicadaBluetoothSetPowerStateFunction();
        if (getPowerState == NULL || setPowerState == NULL) {
            return -1;
        }

        int target = enabled ? 1 : 0;
        if ((getPowerState() ? 1 : 0) == target) {
            return target;
        }

        setPowerState(target);
        for (int i = 0; i <= 100; i++) {
            if (i > 0) {
                usleep(100000);
            }
            if ((getPowerState() ? 1 : 0) == target) {
                return target;
            }
        }
        return -1;
    } @catch (NSException *exception) {
        return -1;
    }
}
