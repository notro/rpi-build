#!/usr/bin/env python
import subprocess
import optparse
import os
import sys
import time

WORKDIR = os.getenv('WORKDIR', os.environ['HOME'])
CCPREFIX = os.getenv('CCPREFIX', WORKDIR + "/tools/arm-bcm2708/arm-bcm2708-linux-gnueabi/bin/arm-bcm2708-linux-gnueabi-")


def main(argv):
	kernel_src = WORKDIR + "/linux"
	kernel_branch = "rpi-3.6.y"
	firmware_src = WORKDIR + "/firmware"
	firmware_dst = WORKDIR + "/ftest"
	modules_tmp = WORKDIR + "/modules"

	if "init" in argv:
		begin("init")
		git_clone("https://github.com/raspberrypi/tools", WORKDIR + "/tools")
		git_pull(WORKDIR + "/tools")

		get_firmware("raspberrypi/firmware")

		with open("%s/extra/git_hash" % firmware_src, 'r') as f:
			commit = f.read()

		get_kernel("https://github.com/raspberrypi/linux", kernel_src, kernel_branch, commit)

		# Remove speed limitation in spi-bcm2708
		f = kernel_src + "/drivers/spi/spi-bcm2708.c"
		pattern = "roundup_pow_of_two"
		print("\nRemove '%s' line in '%s'" % (pattern, f))
		sh("sed -i '/%s/d' %s" % (pattern, f))
		#sh("sed -i '1s/^/#define DEBUG\\n/' %s" % (f))

		get_fbtft("https://github.com/notro/fbtft.git", kernel_src)
		end()

	if "config" in argv:
		begin("config")
		make_mrproper(kernel_src)

		# Get config from the Raspberry Pi standard kernel
		sh("%s/scripts/extract-ikconfig %s/boot/kernel.img > %s/.config" % (kernel_src, firmware_src, kernel_src))
		cp_a("%s/.config" % kernel_src, "%s/.config.standard" % kernel_src)

		# All FBTFT modules as modules
		make_oldconfig(kernel_src, 'm')

		# Add all fonts as builtins
		kernel_config(kernel_src, ["FONTS"], "y")
		make_oldconfig(kernel_src, 'y')

		# Add menuconfigs, no to sub configs
		kernel_config(kernel_src, ["INPUT_TOUCHSCREEN", "INPUT_MOUSE", "INPUT_KEYBOARD"], "y")
		make_oldconfig(kernel_src, 'n')

		# Add some modules
		kernel_config(kernel_src, ["TOUCHSCREEN_ADS7846", "MOUSE_GPIO", "KEYBOARD_GPIO", "KEYBOARD_GPIO_POLLED"], "m")

		# Verify config
		make_oldconfig(kernel_src)
		end()

	if "build" in argv:
		begin("build")
		nproc = int(sh_output("nproc").strip())
		make(kernel_src, "-j%d" % (nproc * 2))
		end()

	if "modules_install" in argv:
		begin("modules_install")
		modules_install(kernel_src, modules_tmp)
		end()

	if "extra" in argv:
		begin("extra")

		# gpio_mouse_device, gpio_keys_device
		git_clone("https://github.com/notro/fbtft_tools", WORKDIR + "/fbtft_tools")
		git_pull(WORKDIR + "/fbtft_tools")
		for mod in ["gpio_mouse_device", "gpio_keys_device"]:
			make(kernel_src, "M=%s/fbtft_tools/%s modules" % (WORKDIR, mod))
			make(kernel_src, "M=%s/fbtft_tools/%s INSTALL_MOD_PATH=%s modules_install" % (WORKDIR, mod, modules_tmp))

		# ServoBlaster
		git_clone("https://github.com/richardghirst/PiBits", WORKDIR + "/PiBits")
		git_pull(WORKDIR + "/PiBits")
		make(kernel_src, "M=%s/PiBits/ServoBlaster modules" % WORKDIR)
		make(kernel_src, "M=%s/PiBits/ServoBlaster INSTALL_MOD_PATH=%s modules_install" % (WORKDIR, modules_tmp))

		end()

	if "update" in argv:
		begin("update")
		update_repo(firmware_src, firmware_dst, kernel_src, modules_tmp)
		end()

	if "readme" in argv:
		md = """
notro/rpi-firmware
=======================================================

Raspberry Pi kernel and firmware with support for FBTFT.

**How to install**
```
sudo mv /lib/modules/$(uname -r) /lib/modules/$(uname -r).bak
sudo REPO_URI=https://github.com/notro/ftest rpi-update
```
The first command is needed because of this [issue](https://github.com/Hexxeh/rpi-update/issues/106)

Build scripts used: https://github.com/notro/rpi-build  
Build logs in the [extra/](https://github.com/notro/ftest/tree/master/extra) directory

### Sources

"""
		commit = sh_output("git ls-remote -h https://github.com/raspberrypi/firmware refs/heads/master").strip().split()[0]
		md += "* Firmware  \nhttps://github.com/raspberrypi/firmware/tree/%s\n" % commit

		commit = sh_output("cd %s && git rev-parse HEAD" % kernel_src).strip().split()[0]
		md += "* Linux kernel  \nhttps://github.com/raspberrypi/linux/tree/%s\n" % commit

		commit = sh_output("cd %s/drivers/video/fbtft && git rev-parse HEAD" % kernel_src).strip().split()[0]
		md += "* FBTFT  \nhttps://github.com/notro/fbtft/tree/%s\n" % commit

		commit = sh_output("cd %s/fbtft_tools && git rev-parse HEAD" % WORKDIR).strip().split()[0]
		md += "* gpio_mouse_device, gpio_keys_device  \nhttps://github.com/notro/fbtft_tools/tree/%s\n" % commit

		commit = sh_output("cd %s/PiBits && git rev-parse HEAD" % WORKDIR).strip().split()[0]
		md += "* ServoBlaster  \nhttps://github.com/richardghirst/PiBits/tree/%s\n" % commit

		md += """

### Kernel source changes

* spi-bcm2708.c: bcm2708_setup_state(): removed ```roundup_pow_of_two()``` limitation


### Kernel configuration changes

"""

		old_cfg = readf("%s/.config.standard" % kernel_src)
		new_cfg = readf("%s/.config" % kernel_src)

		old = [line for line in old_cfg.splitlines() if line.strip() and not line[0] == "#"]
		old.sort()
		new = [line for line in new_cfg.splitlines() if line.strip() and not line[0] == "#"]
		new.sort()

		deleted = list(set(old) - set(new))
		deleted.sort()
		md += "Deleted:  \n```text\n"
		md += "\n".join(deleted)
		md += "\n```\n"

		added = list(set(new) - set(old))
		added.sort()
		md += "\nAdded:  \n```text\n"
		md += "\n".join(added)
		md += "\n```\n"

		writef("%s/README.md" % firmware_dst, md)
		print readf("%s/README.md" % firmware_dst)



# Return whether or not the firmware has changed since last run
def get_firmware(repo_short):
	tarball = "https://api.github.com/repos/%s/tarball" % repo_short
	hash_file = WORKDIR + "/last_firmware_hash"

	if os.path.isfile(hash_file):
		with open(hash_file, 'r') as f:
			last_hash = f.read()
	else:
		last_hash = ""

	ret = sh_output("git ls-remote -h https://github.com/%s refs/heads/master" % repo_short)
	current_hash = ret.strip().split()[0]
	if current_hash == last_hash:
		return False

	rm_rf("%s/tarball" % WORKDIR)
	rm_rf("%s/firmware" % WORKDIR)
	sh("wget --progress=dot:mega --directory-prefix=%s/ %s" % (WORKDIR, tarball))
	sh("tar -C %s -zxf tarball" % WORKDIR)
	sh("cd %s && mv raspberrypi-firmware* firmware" % WORKDIR)

	with open(hash_file, 'w') as f:
		f.write(current_hash)

	return True

def get_kernel(repo, path, branch, commit):
	git_clone(repo, path, branch)
	git_checkout(path, '-- .')
	git_checkout(path, branch)
	git_pull(path)
	git_checkout(path, commit)

def get_fbtft(repo, path):
	git_clone(repo, "%s/drivers/video/fbtft" % path)
	git_pull("%s/drivers/video/fbtft" % path)
	git_apply(path, WORKDIR + "/fbtft.patch")

def modules_install(src, dst):
	rm_rf(dst)
	mkdir_p(dst)
	sh("cd %s && ARCH=arm CROSS_COMPILE=%s INSTALL_MOD_PATH=%s make modules_install" % (src, CCPREFIX, dst))

def update_repo(src, dst, ksrc, msrc):
	rm_rf(dst + "/*")

	mkdir_p(dst + "/modules")
	cp_a(src + "/boot/*", dst + "/")

	cp_a(ksrc + "/arch/arm/boot/Image", dst + "/kernel.img")
	cp_a(msrc + "/lib/modules/*+/", dst + "/modules/")

	mkdir_p(dst + "/vc/sdk/opt/vc")
	cp_a(src + "/opt/vc/include/", dst + "/vc/sdk/opt/vc/")
	cp_a(src + "/opt/vc/src/",  dst + "/vc/sdk/opt/vc/")

	mkdir_p(dst + "/vc/softfp/opt/vc")
	cp_a(src + "/opt/vc/LICENCE", dst + "/vc/softfp/opt/vc")
	cp_a(src + "/opt/vc/bin/", dst + "/vc/softfp/opt/vc")
	cp_a(src + "/opt/vc/lib/", dst + "/vc/softfp/opt/vc")
	cp_a(src + "/opt/vc/sbin/", dst + "/vc/softfp/opt/vc")

	mkdir_p(dst + "/vc/hardfp/opt/vc")
	cp_a(src + "/hardfp/opt/vc/LICENCE", dst + "/vc/hardfp/opt/vc")
	cp_a(src + "/hardfp/opt/vc/bin/", dst + "/vc/hardfp/opt/vc")
	cp_a(src + "/hardfp/opt/vc/lib/", dst + "/vc/hardfp/opt/vc")
	cp_a(src + "/hardfp/opt/vc/sbin/", dst + "/vc/hardfp/opt/vc")

	mkdir_p(dst + "/extra")
	cp_a(ksrc + "/Module.symvers", dst + "/extra/")
	cp_a(ksrc + "/System.map", dst + "/extra/")
	cp_a(ksrc + "/.config", dst + "/extra/")

	sh("ls -l %s" % dst)


def begin(task):
	begin.start = time.time()
	begin.task = task
	print("\n#\n# Begin: %s\n# Time: %s\n#\n" % (task, time.ctime(begin.start)))

def end():
	t = time.time()
	print("\n#\n# End: %s\n# Time: %s\n# Elapsed: %.2f min\n#\n" % (begin.task, time.ctime(t), (t - begin.start)/60))

def kernel_config(path, vars, val):
	if val == "n":
		arg = "--disable"
	elif val == "y":
		arg = "--enable"
	elif val == "m":
		arg = "--module"
	else:
		raise ValueError("kernel_config: unknown val: %s" % val)
	for v in vars:
		sh("cd %s && scripts/config %s %s" % (path, arg, v))


def make(path, args=""):
	sh("cd %s && ARCH=arm CROSS_COMPILE=%s make %s" % (path, CCPREFIX, args))

def make_mrproper(path):
	sh("cd %s && ARCH=arm CROSS_COMPILE=%s make mrproper" % (path, CCPREFIX))

def make_oldconfig(path, default_answer=''):
	if default_answer:
		sh("cd %s && yes %s | ARCH=arm CROSS_COMPILE=%s make oldconfig" % (path, default_answer, CCPREFIX))
	else:
		sh("cd %s && ARCH=arm CROSS_COMPILE=%s make oldconfig" % (path, CCPREFIX))

def git_clone(repo, path, branch=''):
	if os.path.isdir(path):
		print("\ngit_clone(%r, %r, %r)\nAlready cloned" % (repo, path, branch))
		return
	if branch:
		branch = "-b %s" % branch
	sh("cd %s && git clone %s %s" % (os.path.split(path)[0], branch, repo))

def git_pull(path):
	sh("cd %s && git pull" % path)

def git_checkout(path, ref):
	sh("cd %s && git checkout %s" % (path, ref))
	
def git_apply(path, patch):
	sh("cd %s && git apply %s" % (path, patch))

# Alternative: http://amoffat.github.io/sh/
def sh(cmd):
	print("\n=> %s" % cmd)
	subprocess.check_call(cmd, shell=True)

def sh_output(cmd):
	print("\n=> %s" % cmd)
	ret = subprocess.check_output(cmd, shell=True)
	print(ret)
	return ret

def mkdir_p(path):
	sh("mkdir -p %s" % path)

def rm_rf(path):
	sh("rm -rf %s" % path)

def cp_a(src, dst):
	sh("cp -a %s %s" % (src, dst))

def readf(f):
	str = ""
	if os.path.isfile(f):
		with open(f, 'r') as f:
			str = f.read()
	return str

def writef(f, str):
	print("=> writef(%s)" % f)
	with open(f, 'w') as f:
		f.write(str)



if __name__ == '__main__':
	main(sys.argv[1:])
