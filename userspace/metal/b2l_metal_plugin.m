/* SPDX-License-Identifier: BSD-2-Clause
 * B1L-0080, Metal M6b: the plug-in Metal loads for IOAcceleratorES when the kernel's switch b2l_metal_ui is on
 * (MetalPluginName B2LMetalV4, MetalPluginClassName B2LMetalUIDevice; B2LMetalAccel.cpp). It is a thin bundle over
 * Scion's Mali driver, libhakiosmetal (linked by its install name, so every process shares the one image the tests and
 * M6a also load): B2LMetalUIDevice is HakiosMetalDevice, shown ONLY to the window server, backboardd -- QuartzCore
 * there takes it instead of the CPU renderer. Every other process gets no device from Metal's discovery, as before.
 * Log prefix "b2l-plugin:" (kern.hakios.say).
 */
#import <Foundation/Foundation.h>
#include <IOKit/IOKitLib.h>
#include <stdarg.h>
#include <stdio.h>
#include <string.h>
#include <sys/sysctl.h>
#include <unistd.h>

@interface HakiosMetalDevice : NSObject
- (instancetype)initWithAcceleratorPort:(io_service_t)port;
@end

@interface B2LMetalUIDevice : HakiosMetalDevice
@end

static void
psay(const char *format, ...)
{
	char line[400], out[440];
	va_list ap;
	va_start(ap, format);
	vsnprintf(line, sizeof(line), format, ap);
	va_end(ap);
	snprintf(out, sizeof(out), "b2l-plugin: %s", line);
	(void)sysctlbyname("kern.hakios.say", NULL, NULL, out, strlen(out));
}

@implementation B2LMetalUIDevice
- (instancetype)initWithAcceleratorPort:(io_service_t)port
{
	/* B2L (B1L-0185): the window server, and the processes that draw icons, widgets and Control Center glyphs
	 * offscreen and get nothing on screen without a GPU (SpringBoard, chronod, iconservicesagent) */
	/* S10 build 0028: backboardd only (upstream B1L-0269). Without a Mali, SpringBoard and iconservicesagent draw the
	 * app icons with Apple's own processor path, and right; through our translator they were flat squares. The price
	 * (upstream's 0184): the Clock and Calendar icons, widgets and some Control Center glyphs stay empty. */
	static const char *const allowed[] = { "backboardd" };
	const char *me = getprogname();
	bool ok = false;
	for (unsigned i = 0; me != NULL && i < sizeof(allowed) / sizeof(allowed[0]); i++)
		ok |= strcmp(me, allowed[i]) == 0;
	if (!ok) {
		/* not the window server: no device, as the hidden plug-in of B1L-0049. NOT released: -[_MTLDevice dealloc]
		 * on an object _MTLDevice never initialised crashed SpringBoard four times a boot (B1L-0085..0087, EXC_BAD_ACCESS
		 * in its dealloc, via -[HakiosMetalDevice dealloc]); one unused object a process is the price. */
		return nil;
	}
	psay("%s (pid %d) asks for a device: the Mali's", me, getpid());
	self = [super initWithAcceleratorPort:port];
	psay("device %s", self != nil ? "made" : "NOT made");
	return self;
}
@end
