import sys
from _common import *

class Tasks(TasksBase):
	def setup(self):
		self.branch = 'bcm2835'
		self.kernel_branch = "master"

		self.tools = Git("https://github.com/raspberrypi/tools", self.workdir + "/tools")
		self.firmware = GithubTarball("https://github.com/raspberrypi/firmware", self.workdir + "/firmware")
		self.uboot = Git("git://git.denx.de/u-boot-arm.git", self.workdir + "/u-boot-arm")
		self.uboot.scr = "%s/boot.scr.uimg" % self.workdir
		linux312 = GitLocal("https://www.kernel.org/pub/linux/kernel/v3.x/linux-3.12.tar.xz", self.workdir + "/linux-3.12")
		self.linux = Linux(linux312, linux312.workdir, self.kernel_branch, self.ccprefix)

		self.patches = Patches("%s/patches/%s" % (self.scriptdir, self.branch), self.branch)

		self.rpi_firmware = Git("https://github.com/notro/rpi-firmware", self.workdir + "/rpi-firmware")

		self.readme = Readme(self.workdir + "/README.md", release_branch=self.branch, desc="""
Raspberry Pi kernel using BCM2835 from kernel.org 3.12.  
See [wiki](https://github.com/notro/rpi-firmware/wiki/bcm285) for more info.
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

		heading("Apply kernel patches")
		for patch in self.patches:
			self.linux.repo.apply(patch)

	def task_config(self):
		heading("make mrproper")
		self.linux.make.mrproper()

		self.linux.make("bcm2835_defconfig")
		cp_a("%s/.config" % self.linux.workdir, "%s/.config.standard" % self.linux.workdir)

		heading("/proc/config.gz")
		self.linux.config(["CONFIG_IKCONFIG_PROC"], "y")
		self.linux.make.oldconfig('')

		heading("Enable Dynamic Debug")
		self.linux.config(["DYNAMIC_DEBUG"], "y")
		self.linux.make.oldconfig('')

		self.linux.config(["PROC_DEVICETREE"], "y")
		self.linux.make.oldconfig()

		self.linux.config(["FB_BCM2835"], "y")
		self.linux.config(["FB_SIMPLE"], "n")
		self.linux.make.oldconfig('')


#		heading("Enable DHCP")
#		self.linux.config(['PACKET', 'NETFILTER', 'IP_PNP', 'IP_PNP_DHCP'], 'y')
#		self.linux.make.oldconfig('')

	def task_modules_install(self):
		pass

	def task_extra(self):
		heading("U-Boot")
		self.uboot.clone()
		self.uboot.pull()

		scr_fn = "%s/boot.scr" % self.workdir
		sh("cd %s && CROSS_COMPILE=%s ./MAKEALL rpi_b" % (self.uboot.workdir, self.ccprefix))
		scr = """
setenv prop-2-2 'mw.l 0x00001000 0x00000020 ; mw.l 0x00001004 0x00000000 ; mw.l 0x00001008 \$tag ; mw.l 0x0000100c 0x00000008 ; mw.l 0x00001010 0x00000008 ; mw.l 0x00001014 \$p1 ; mw.l 0x00001018 \$p2 ; mw.l 0x0000101c 0x00000000 ; md.l 0x1000 8'
setenv send-rec 'mw 0x2000b8a0 0x00001008 ; md 0x2000b880 1 ; md.l 0x00001000 8'
setenv tag 0x28001 ; setenv p1 3 ; setenv p2 3; run prop-2-2 ; run send-rec
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
