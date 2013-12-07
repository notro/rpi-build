import sys
from _common import *

class Tasks(TasksBase):
	def setup(self):
		if not hasattr(self, 'branch'):
			self.branch = 'master'
			self.kernel_branch = "rpi-3.6.y"

		self.tools = Git("https://github.com/raspberrypi/tools", self.workdir + "/tools")
		self.firmware = GithubTarball("https://github.com/raspberrypi/firmware", self.workdir + "/firmware")
		self.linux = Linux("https://github.com/raspberrypi/linux", self.workdir + "/linux-%s" % self.kernel_branch, self.kernel_branch, self.ccprefix)
		self.spi_bcm2708 = WgetFile("https://raw.github.com/notro/spi-bcm2708/master/spi-bcm2708.c", "%s/drivers/spi/spi-bcm2708.c" % self.linux.workdir, desc="spi-bcm2708: DMA capable SPI master driver")
		self.fbtft = Git("https://github.com/notro/fbtft.git", "%s/drivers/video/fbtft" % self.linux.workdir, desc="FBTFT")
		self.patches = Patches("%s/patches/%s" % (self.scriptdir, self.branch), self.branch)

		self.fbtft_tools = Git("https://github.com/notro/fbtft_tools", self.workdir + "/fbtft_tools", "Various SPI device adding modules")
		self.servoblaster = Git("https://github.com/richardghirst/PiBits", self.workdir + "/PiBits", desc="ServoBlaster")
		self.spi_config = Git("https://github.com/msperl/spi-config", self.workdir + "/spi-config", desc="spi-config: SPI device adding module")
		self.rpi_firmware = Git("https://github.com/notro/rpi-firmware", self.workdir + "/rpi-firmware")

		self.readme = Readme(self.workdir + "/README.md", release_branch=self.branch, desc="Raspberry Pi kernel and firmware with support for FBTFT.")
		self.readme.add_source(self.linux, self.spi_bcm2708, self.fbtft, self.fbtft_tools, self.servoblaster, self.spi_config)
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
		with open("%s/extra/git_hash" % self.firmware.workdir, 'r') as f:
			commit = f.read()
		self.linux.update()
		#self.linux.repo.checkout(commit)

		heading("Get DMA capable SPI master driver")
		self.spi_bcm2708.pull()

		heading("Apply kernel patches")
		for patch in self.patches:
			self.linux.repo.apply(patch)

		heading("Get FBTFT")
		self.fbtft.clone()
		self.fbtft.pull()

	def task_config(self):
		heading("make mrproper")
		self.linux.make.mrproper()

		heading("make bcmrpi_defconfig")
		self.linux.make("bcmrpi_defconfig")
		cp_a("%s/.config" % self.linux.workdir, "%s/.config.standard" % self.linux.workdir)

		heading("All FBTFT modules as loadable modules")
		self.linux.config(['FB_TFT'], 'm')
		self.linux.make.oldconfig('m')

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

		heading("CAN bus")
		self.linux.config(['CONFIG_CAN'], 'y')      # CAN bus subsystem support
		self.linux.make.oldconfig('')
		self.linux.config(['CONFIG_CAN_RAW'], 'm')      # Raw CAN Protocol (raw access with CAN-ID filtering)
		self.linux.config(['CONFIG_CAN_BCM'], 'm')      # Broadcast Manager CAN Protocol (with content filtering)
		self.linux.config(['CONFIG_CAN_VCAN'], 'm')         # Virtual Local CAN Interface (vcan) - CAN loopback
		self.linux.config(['CONFIG_CAN_SLCAN'], 'm')        # Serial / USB serial CAN Adaptors (slcan)
		self.linux.config(['CONFIG_CAN_MCP251X'], 'm')      # Microchip MCP251x SPI CAN controllers
		self.linux.make.oldconfig()

	def task_extra(self):
		make = self.linux.make

		mods = ["gpio_mouse_device", "gpio_keys_device", "ads7846_device"]
		heading(", ".join(mods))
		self.fbtft_tools.clone()
		self.fbtft_tools.pull()
		for mod in mods:
			modpath = "%s/%s" % (self.fbtft_tools.workdir, mod)
			make.modules(modpath)
			make.modules_install(self.modules_tmp, modpath)

		heading("ServoBlaster kernel module for board revision 2")
		self.servoblaster.clone()
		self.servoblaster.checkout('-- .')
		self.servoblaster.pull()
		sh("sed -i '1s/^/#define REV_2\\n/' %s/ServoBlaster/kernel/servoblaster.c" % self.servoblaster.workdir)
		modpath = "%s/ServoBlaster/kernel" % self.servoblaster.workdir
		make.modules(modpath)
		make.modules_install(self.modules_tmp, modpath)

		heading("spi-config")
		self.spi_config.clone()
		self.spi_config.pull()
		modpath = self.spi_config.workdir
		make.modules(modpath)
		make.modules_install(self.modules_tmp, modpath)
