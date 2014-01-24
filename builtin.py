from _common import *
from master import Tasks as MasterTasks

class Tasks(MasterTasks):
	def setup(self):
		self.branch = 'builtin'
		self.kernel_branch = "rpi-3.10.y"
		MasterTasks.setup(self)
		self.readme.desc = "Raspberry Pi kernel and firmware with builtin support for FBTFT (not loadable modules)."

	def task_config(self):
		heading("make mrproper")
		self.linux.make.mrproper()

		heading("make bcmrpi_defconfig")
		self.linux.make("bcmrpi_defconfig")
		cp_a("%s/.config" % self.linux.workdir, "%s/.config.standard" % self.linux.workdir)

		self.linux.config(['SPI_BCM2708'], 'y')
		self.linux.config(['BCM2708_SPIDEV'], 'n')

		heading("All FBTFT modules as loadable modules")
		self.linux.config(['FB_TFT'], 'y')
		self.linux.make.oldconfig('y')

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
		self.linux.config(['CONFIG_CAN'], 'y')              # CAN bus subsystem support
		self.linux.make.oldconfig('')
		self.linux.config(['CONFIG_CAN_RAW'], 'm')          # Raw CAN Protocol (raw access with CAN-ID filtering)
		self.linux.config(['CONFIG_CAN_BCM'], 'm')          # Broadcast Manager CAN Protocol (with content filtering)
		self.linux.config(['CONFIG_CAN_VCAN'], 'm')         # Virtual Local CAN Interface (vcan) - CAN loopback
		self.linux.config(['CONFIG_CAN_SLCAN'], 'm')        # Serial / USB serial CAN Adaptors (slcan)
		self.linux.config(['CONFIG_CAN_MCP251X'], 'm')      # Microchip MCP251x SPI CAN controllers
		self.linux.make.oldconfig()
