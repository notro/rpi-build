import sys
from _common import *

class Tasks(TasksBase):
	def setup(self):
		if not hasattr(self, 'branch'):
			self.branch = 'fbtft-next'
			self.kernel_branch = "rpi-3.13.y"

		self.tools = Git("https://github.com/raspberrypi/tools", self.workdir + "/tools")
		self.firmware = GithubTarball("https://github.com/raspberrypi/firmware", self.workdir + "/firmware")
		self.linux = Linux("https://github.com/raspberrypi/linux", self.workdir + "/linux-%s" % self.kernel_branch, self.kernel_branch, self.ccprefix)
		self.spi_bcm2708 = Git("https://github.com/notro/spi-bcm2708", self.workdir + "/spi-bcm2708", "spi-bcm2708: DMA capable SPI master driver")
		self.fbtft = Git("https://github.com/notro/fbtft-next.git", "%s/drivers/video/fbtft" % self.linux.workdir, desc="FBTFT")
		self.patches = Patches("%s/patches/%s" % (self.scriptdir, self.branch), self.branch)

		self.fdt_loader = Git("https://github.com/notro/fdt_loader", self.workdir + "/fdt_loader", "Device Tree Loader")
		self.fbtft_tools = Git("https://github.com/notro/fbtft_tools", self.workdir + "/fbtft_tools", "Various SPI device adding modules")
		self.rpi_firmware = Git("https://github.com/notro/rpi-firmware", self.workdir + "/rpi-firmware")

		self.dts = Devicetrees(self.patches.path + "/dts", self.linux.workdir + "/scripts/dtc/dtc")

		self.readme = Readme(self.workdir + "/README.md", release_branch=self.branch, desc="""
Raspberry Pi kernel and firmware with support for the next generation FBTFT.
""")
		self.readme.add_source(self.linux, self.spi_bcm2708, self.fbtft, self.fbtft_tools)
		self.readme.add_patches(self.patches)
		self.readme.config_diff(self.linux.workdir)

	def task_all(self):
		for task in ['init', 'config', 'build', 'modules_install', 'extra', 'readme']:
			self.__call__(task)

	def task_init(self):
		heading("Get build tools")
		self.tools.clone()
		self.tools.pull()

		heading("Get firmware")
		self.firmware.clone()
		self.firmware.pull()

		heading("Get kernel source")
		self.linux.update()

		heading("Get DMA capable SPI master driver")
		self.spi_bcm2708.clone()
		self.spi_bcm2708.pull()
		cp_a(self.spi_bcm2708.workdir + "/spi-bcm2708.c", self.linux.workdir + "/drivers/spi/")

		heading("Apply kernel patches")
		for patch in self.patches:
			self.linux.repo.apply(patch)

		heading("Get fdt_loader")
		self.fdt_loader.clone()
		self.fdt_loader.pull()
		cp_a(self.fdt_loader.workdir + "/fdt_loader.c", self.linux.workdir + "/drivers/misc/")
		cp_a(self.fdt_loader.workdir + "/pinctrl-bcm2708.c", self.linux.workdir + "/arch/arm/mach-bcm2708/")

#		heading("Get FBTFT")
#		self.fbtft.clone()
#		self.fbtft.checkout('take1')
##		self.fbtft.pull()

	def task_config(self):
		self.task_config_do('m')

	def task_config_do(self, fbtft='m'):
		heading("make mrproper")
		self.linux.make.mrproper()

		heading("make bcmrpi_defconfig")
		self.linux.make("bcmrpi_defconfig")
		cp_a("%s/.config" % self.linux.workdir, "%s/.config.standard" % self.linux.workdir)

		heading("Enable Dynamic Debug")
		self.linux.config(["DYNAMIC_DEBUG"], "y")
		self.linux.make.oldconfig('')

		heading("fdt_loader")
		self.linux.config(["USE_OF", "FDT_LOADER", "PINCTRL_BCM2708"], "y")
		self.linux.make.oldconfig('')
		self.linux.config(["PROC_DEVICETREE"], "y")
		self.linux.config(["BCM2708_SPIDEV"], "n")
		self.linux.make.oldconfig()

		heading("Turn some modules into builtins")
		self.linux.config(["SPI_BCM2708"], "y")
		self.linux.config(["I2C_BCM2708", "I2C_CHARDEV"], "y")
		self.linux.config(["W1", "W1_MASTER_GPIO"], "y")
		self.linux.make.oldconfig()
		self.linux.config(["LEDS_CLASS", "LEDS_GPIO"], "y")
		self.linux.make.oldconfig('')

		heading("FBTFT modules")
		self.linux.config(['FB_TFT'], fbtft)
		self.linux.make.oldconfig(fbtft)

		self.linux.config(['CONFIG_BACKLIGHT_GPIO'], 'm')
		self.linux.make.oldconfig(fbtft)

		heading("All console fonts as builtins and rotation")
		self.linux.config(["FONTS", "FRAMEBUFFER_CONSOLE_ROTATION"], "y")
		self.linux.make.oldconfig('y')

		heading("Touchscreen, mouse and keyboard subsystem support")
		self.linux.config(["INPUT_TOUCHSCREEN", "INPUT_MOUSE", "INPUT_KEYBOARD"], "y")
		self.linux.make.oldconfig('n')

		cfgs = ["TOUCHSCREEN_ADS7846", "MOUSE_GPIO", "KEYBOARD_GPIO", "KEYBOARD_GPIO_POLLED"]
		heading(", ".join(cfgs))
		self.linux.config(cfgs, "m")
		self.linux.make.oldconfig()

		heading("STMPE GPIO and Touch")
		self.linux.config(['MFD_STMPE'], 'y')
		self.linux.make.oldconfig('')
		self.linux.config(['STMPE_SPI'], 'y')
		self.linux.config(['GPIO_STMPE'], 'y')
		self.linux.config(['TOUCHSCREEN_STMPE'], 'm')
		self.linux.make.oldconfig()

#		heading("CAN bus")
#		self.linux.config(['CONFIG_CAN'], 'y')      # CAN bus subsystem support
#		self.linux.make.oldconfig('')
#		self.linux.config(['CONFIG_CAN_RAW'], 'm')      # Raw CAN Protocol (raw access with CAN-ID filtering)
#		self.linux.config(['CONFIG_CAN_BCM'], 'm')      # Broadcast Manager CAN Protocol (with content filtering)
#		self.linux.config(['CONFIG_CAN_VCAN'], 'm')         # Virtual Local CAN Interface (vcan) - CAN loopback
#		self.linux.config(['CONFIG_CAN_SLCAN'], 'm')        # Serial / USB serial CAN Adaptors (slcan)
#		self.linux.config(['CONFIG_CAN_MCP251X'], 'm')      # Microchip MCP251x SPI CAN controllers
#		self.linux.make.oldconfig()

	def task_extra(self):

#### FIX ####
		self.task_test()
####     ####

		make = self.linux.make

		mods = ["gpio_mouse_device", "gpio_keys_device", "ads7846_device",
			"gpio_backlight_device", "stmpe_device", "rpi_power_switch"]
		heading(", ".join(mods))
		self.fbtft_tools.clone()
		self.fbtft_tools.pull()
		for mod in mods:
			modpath = "%s/%s" % (self.fbtft_tools.workdir, mod)
			make.modules(modpath)
			make.modules_install(self.modules_tmp, modpath)

	def task_update_repo(self):
		TasksBase.task_update_repo(self)
		dst = self.rpi_firmware.workdir
		msrc = self.modules_tmp

		mkdir_p(dst + "/firmware")
		cp_a(msrc + "/lib/firmware/*.dtsi", dst + "/firmware/")
		cp_a(msrc + "/lib/firmware/*.dts", dst + "/firmware/")
		cp_a(msrc + "/lib/firmware/*.dtb", dst + "/firmware/")

		pre_install = """
echo "Copy to /lib/firmware"
	cp -vR "${FW_REPOLOCAL}/firmware/"* "${ROOT_PATH}/lib/firmware/"
echo
"""
		writef("%s/pre-install" % dst, pre_install, 'a')

	def task_commit(self):
		print("\n\nTask 'commit' is disabled")

	def task_test(self):
		self.dts.install(self.modules_tmp + "/lib/firmware")
