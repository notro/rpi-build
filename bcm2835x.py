import sys
from _common import *

class Tasks(TasksBase):
	def setup(self):
		self.branch = 'bcm2835x'
		self.kernel_branch = "rpi-3.12.y"

		self.tools = Git("https://github.com/raspberrypi/tools", self.workdir + "/tools")
		self.firmware = GithubTarball("https://github.com/raspberrypi/firmware", self.workdir + "/firmware")
		self.uboot = Git("git://git.denx.de/u-boot-arm.git", self.workdir + "/u-boot-arm")
		self.uboot.scr = "%s/boot.scr.uimg" % self.workdir
		self.linux = Linux("https://github.com/raspberrypi/linux", self.workdir + "/linux", self.kernel_branch, self.ccprefix)

		self.patches = Patches("%s/patches/%s" % (self.scriptdir, self.branch), self.branch)

		self.rpi_firmware = Git("https://github.com/notro/rpi-firmware", self.workdir + "/rpi-firmware")

		self.readme = Readme(self.workdir + "/README.md", release_branch=self.branch, desc="""
Raspberry Pi kernel using BCM2835 from raspberrypi/linux rpi-3.12.y.  
See [wiki](https://github.com/notro/rpi-firmware/wiki/BCM2835) for more info.
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

		heading("Get U-Boot")
		self.uboot.clone()
		self.uboot.pull()

		heading("Get kernel source")
		self.linux.update()

		heading("Apply kernel patches")
		for patch in self.patches:
			self.linux.repo.apply(patch)

	def task_config(self):
		heading("make mrproper")
		self.linux.make.mrproper()

		heading("make bcmrpi_defconfig")
		self.linux.make("bcm2835_defconfig")
		cp_a("%s/.config" % self.linux.workdir, "%s/.config.standard" % self.linux.workdir)

		heading("Enable Dynamic Debug")
		self.linux.config(["DYNAMIC_DEBUG"], "y")
		self.linux.make.oldconfig('')

		self.linux.config(["PROC_DEVICETREE"], "y")
		self.linux.make.oldconfig()

	def task_modules_install(self):
		pass

	def task_extra(self):
		scr_fn = "%s/boot.scr" % self.workdir
		sh("cd %s && CROSS_COMPILE=%s ./MAKEALL rpi_b" % (self.uboot.workdir, self.ccprefix))
		scr = """
setenv bootargs 'earlyprintk loglevel=8 console=ttyAMA0 verbose rootwait root=/dev/mmcblk0p2 rw debug dyndbg=\\\"module pinctrl_bcm2835 +p; file drivers/gpio/gpiolib.c +p; file drivers/of/platform.c +p; file kernel/irq/irqdomain.c +p; file kernel/irq/manage.c +p; file kernel/resource.c +p;\\\"'
fatload ${devtype} ${devnum}:1 ${kernel_addr_r} /zImage
fatload ${devtype} ${devnum}:1 ${fdt_addr_r} /bcm2835-rpi-b.dtb
bootz ${kernel_addr_r} - ${fdt_addr_r}
"""
		with open(scr_fn, 'w') as f:
			f.write(scr)
		sh("%s/tools/mkimage -T script -d %s %s" % (self.uboot.workdir, scr_fn, self.uboot.scr))

	def task_readme(self):
		pass

	def task_update_repo(self):
		pass

	def task_commit(self):
		pass
