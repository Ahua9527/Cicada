#ifndef CICADA_BLUETOOTH_BRIDGE_H
#define CICADA_BLUETOOTH_BRIDGE_H

#include <stdint.h>

int32_t CicadaBluetoothGetControllerPowerState(void);
int32_t CicadaBluetoothSetControllerPowerState(int32_t enabled);

#endif
