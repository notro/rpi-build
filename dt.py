import sys
from _common import *

class Tasks(TasksBase):
	def setup(self):
		self.branch = 'dt'
		self.kernel_branch = "rpi-3.10.y"

		self.tools = Git("https://github.com/raspberrypi/tools", self.workdir + "/tools")
		self.firmware = GithubTarball("https://github.com/raspberrypi/firmware", self.workdir + "/firmware")
		self.linux = Linux("https://github.com/raspberrypi/linux", self.workdir + "/linux", self.kernel_branch, self.ccprefix)
		self.ads7846 = WgetFile("https://raw.github.com/torvalds/linux/master/drivers/input/touchscreen/ads7846.c", "%s/drivers/input/touchscreen/ads7846.c" % self.linux.workdir, desc="ads7846: Use Device Tree enabled version")

		self.patches = Patches("%s/patches/%s" % (self.scriptdir, self.branch))

		self.rpi_firmware = Git("https://github.com/notro/rpi-firmware", self.workdir + "/rpi-firmware")

		self.readme = Readme(self.workdir + "/README.md", release_branch=self.branch, desc="""
Raspberry Pi kernel with Device Tree support.  
See [wiki](https://github.com/notro/rpi-firmware/wiki/Device-Tree) for more info.
""")
		self.readme.add_source(self.linux)
		self.readme.add_patches(self.patches)
		self.readme.config_diff(self.linux.workdir)

	def task_init(self):
		heading("Get build tools")
		self.tools.clone()
		self.tools.pull()

		heading("Get firmware")
		self.firmware.clone()
		self.firmware.pull()

		heading("Get kernel source")
		self.linux.update()

		heading(self.ads7846.desc)
		self.ads7846.pull()

		heading("Apply kernel patches")
		for patch in self.patches:
			self.linux.repo.apply(patch)

	def task_config(self):
		heading("make mrproper")
		self.linux.make.mrproper()

		heading("make bcmrpi_defconfig")
		self.linux.make("bcmrpi_defconfig")
		cp_a("%s/.config" % self.linux.workdir, "%s/.config.standard" % self.linux.workdir)

		heading("Enable Device Tree")
		self.linux.config(["BCM2708_DT"], "y")
		self.linux.make.oldconfig('')
		self.linux.config(["PROC_DEVICETREE"], "y")
		self.linux.make.oldconfig()

		heading("Turn some modules into builtins")
		self.linux.config(["BCM2708_SPIDEV"], "n")
		self.linux.config(["SPI_BCM2708"], "y")
		self.linux.config(["I2C_BCM2708", "I2C_CHARDEV"], "y")
		self.linux.config(["W1", "W1_MASTER_GPIO"], "y")
		self.linux.make.oldconfig()
		self.linux.config(["LEDS_CLASS", "LEDS_GPIO"], "y")
		self.linux.make.oldconfig('')

		heading("Touchscreen, mouse and keyboard subsystem support")
		self.linux.config(["INPUT_TOUCHSCREEN", "INPUT_MOUSE", "INPUT_KEYBOARD"], "y")
		self.linux.make.oldconfig('n')

		cfgs = ["TOUCHSCREEN_ADS7846", "MOUSE_GPIO", "KEYBOARD_GPIO", "KEYBOARD_GPIO_POLLED"]
		heading(", ".join(cfgs))
		self.linux.config(cfgs, "y")
		self.linux.make.oldconfig()

	def task_extra(self):
		pass

	def task_update_repo(self):
		TasksBase.task_update_repo(self)
		cp_a(self.linux.workdir + "/arch/arm/boot/dts/*.dtb", self.rpi_firmware.workdir + "/")
		pre_install = """
echo "     Work around rpi-update issue #106 by deleting ${FW_MODPATH}/$(uname -r)/kernel"
rm -rf "${FW_MODPATH}/$(uname -r)/kernel"
echo
"""
		writef("%s/pre-install" % self.rpi_firmware.workdir, pre_install)
		post_install="""
cat <<EOM




    !!!!!!!!!!!!!!!!!!!!!!!!!!!
    !!                       !!
    !!       IMPORTANT       !!
    !!                       !!
    !!!!!!!!!!!!!!!!!!!!!!!!!!!

Make sure /boot/config.txt contains the following:

device_tree=bcm2708-rpi-b.dtb
device_tree_address=0x100
kernel_address=0x8000
disable_commandline_tags=1




EOM
"""
		writef("%s/post-install" % self.rpi_firmware.workdir, post_install)

