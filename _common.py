import subprocess
import os
import sys
import time
from tempfile import mktemp
import tarfile


class TasksBase:
	def __init__(self, workdir, ccprefix):
		self.workdir = workdir
		self.ccprefix = ccprefix
		self.scriptdir = os.path.dirname(os.path.abspath(__file__))
		self.modules_tmp = self.workdir + "/modules"
		self.setup()

	def __call__(self, task):
		try:
			func = getattr(self, "task_%s" % task)
		except AttributeError:
			print("No such task: %s" % task)
			sys.exit(1)
		begin(task)
		func()
		end()

	def setup(self):
		raise NotImplementedError

	def task_init(self):
		pass

	def task_config(self):
		pass

	def task_build(self):
		nproc = int(sh_output("nproc").strip())
		self.linux.make("-j%d" % (nproc * 2))

	def task_modules_install(self):
		rm_rf(self.modules_tmp)
		mkdir_p(self.modules_tmp)
		self.linux.make.modules_install(self.modules_tmp)

	def task_extra(self):
		pass

	def task_readme(self):
		writef(self.readme.filename, self.readme.to_md())
		print self.readme.to_md()

	def task_update_repo(self):
		src = self.firmware.workdir
		dst = self.rpi_firmware.workdir
		ksrc = self.linux.workdir
		msrc = self.modules_tmp

		self.rpi_firmware.checkout(self.branch)

		rm_rf(dst + "/*")

		cp_a(self.readme.filename, dst + "/")

		mkdir_p(dst + "/modules")
		cp_a(src + "/boot/*", dst + "/")

		cp_a(ksrc + "/arch/arm/boot/Image", dst + "/kernel.img")
		cp_a(msrc + "/lib/modules/*+/", dst + "/modules/")

		mkdir_p(dst + "/vc/sdk/opt/vc")
		cp_a(src + "/opt/vc/include/", dst + "/vc/sdk/opt/vc/")
		cp_a(src + "/opt/vc/src/",  dst + "/vc/sdk/opt/vc/")
		# delete due to size 30MB
		rm_rf(dst + "/vc/sdk/opt/vc/src/hello_pi/hello_video/test.h264")

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

	def task_commit(self):
		rpi_firmware_log = self.rpi_firmware.log("-1 --pretty=%s")
		linux_log = self.linux.repo.log("-1 --pretty=%s")
		if hasattr(self, 'fbtft'):
			fbtft_log = self.fbtft.log("-1 --pretty=%s")
		else:
			fbtft_log = ''
		print("\n\n--------------------------------------------------------------\n\n")
		print("Last commit messages:")
		print("  rpi-firmware: '%s'" % rpi_firmware_log)
		print("  Linux:        '%s'" % linux_log)
		if fbtft_log:
			print("  fbtft:        '%s'" % fbtft_log)
		print("\n\n")
		print("cd %s" % self.rpi_firmware.workdir)
		print("git add .")
		print("git commit -a -m \"%s\" " % linux_log)
		print("\n")


class Git:
	def __init__(self, repo, workdir, desc=''):
		self.repo = repo
		self.workdir = workdir
		self.desc = desc

	def __call__(self, cmd):
		sh("cd %s && git %s" % (self.workdir, cmd))

	def apply(self, patch):
		sh("cd %s && git apply -v %s" % (self.workdir, patch))

	def checkout(self, ref):
		sh("cd %s && git checkout %s" % (self.workdir, ref))

	def clean(self, options=''):
		sh("cd %s && git clean %s" % (self.workdir, options))

	def clone(self, branch=''):
		if os.path.isdir(self.workdir):
			print("\ngit.clone(%r, %r, %r)\nAlready cloned" % (self.repo, self.workdir, branch))
			return
		if branch:
			branch = "-b %s" % branch
		sh("cd %s && git clone %s %s" % (os.path.split(self.workdir)[0], branch, self.repo))

	def log(self, options=''):
		return sh_output("cd %s && git log %s" % (self.workdir, options)).strip()

	def ls_remote(self, branch='master'):
		ret = sh_output("git ls-remote -h %s refs/heads/%s" % (self.repo, branch))
		return ret.strip().split()[0]

	def pull(self):
		sh("cd %s && git pull" % self.workdir)
	
	def rev_parse(self, ref='HEAD'):
		return sh_output("cd %s && git rev-parse %s" % (self.workdir, ref)).strip().split()[0]

	def to_md(self):
		return "* " + self.desc + "  \n" + self.repo + "/tree/" + self.rev_parse() + "\n"


class GithubTarball(Git):
	def clone(self, branch=''):
		if os.path.isdir(self.workdir):
			print("\ngit.clone(%r, %r, %r)\nAlready cloned" % (self.repo, self.workdir, branch))
			return
		self.pull()

	def pull(self, branch=''):
		hash_fn = "%s/.rpi-build_hashfile" % self.workdir

		if os.path.isfile(hash_fn):
			with open(hash_fn, 'r') as f:
				last_hash = f.read()
		else:
			last_hash = ""

		current_hash = self.ls_remote()
		if current_hash == last_hash:
			print("\ngit.pull(%r, %r, %r)\nAlready up-to-date." % (self.repo, self.workdir, branch))
			return False

		rootdir = os.path.split(self.workdir)[0]
		tmp = self.repo.split('/')
		tarball = "https://api.github.com/repos/%s/%s/tarball" % (tmp[-2], tmp[-1])
		tarball_fn = mktemp()

		rm_rf(self.workdir)
		sh("wget --progress=dot:mega -O %s %s" % (tarball_fn, tarball))
		sh("tar -C %s -zxf %s" % (rootdir, tarball_fn))
		with tarfile.open(tarball_fn) as t:
			tardir = t.getnames()[0]
		sh("mv %s/%s %s" % (rootdir, tardir, self.workdir))
		rm_rf(tarball_fn)
	
		with open(hash_fn, 'w') as f:
			f.write(current_hash)


class Make:
	def __init__(self, dir, ccprefix=''):
		self.dir = dir
		self.ccprefix = ccprefix

	def __call__(self, *args):
		self.make(*args)

	def make(self, targets=''):
		sh("cd %s && ARCH=arm CROSS_COMPILE=%s make %s" % (self.dir, self.ccprefix, targets))

	def mrproper(self):
		self.make('mrproper')

	def oldconfig(self, default_answer=None):
		if default_answer==None:
			self.make('oldconfig')
		elif default_answer:
			sh("cd %s && yes %s | ARCH=arm CROSS_COMPILE=%s make oldconfig" % (self.dir, default_answer, self.ccprefix))
		else:
			sh("cd %s && yes \"\" | ARCH=arm CROSS_COMPILE=%s make oldconfig" % (self.dir, self.ccprefix))

	def modules(self, modpath=''):
		str = ""
		if modpath:
			str = "M=%s " % modpath
		self.make(str + "modules")

	def modules_install(self, installpath, modpath=''):
		str = ""
		if modpath:
			str = "M=%s " % modpath
		self.make(str + "INSTALL_MOD_PATH=%s modules_install" % installpath)


class Linux:
	def __init__(self, repo, workdir, branch='master', ccprefix='', desc="Linux Kernel"):
		self.repo = repo
		self.workdir = workdir
		self.branch = branch
		self.repo = Git(repo, workdir, desc)
		self.make = Make(workdir, ccprefix)

	def update(self):
		self.repo.clone(self.branch)
		self.repo.checkout('-- .')
		self.repo.clean('-fd')
		self.repo.checkout(self.branch)
		self.repo.pull()

	def config(self, vars, val):
		if val == "n":
			arg = "--disable"
		elif val == "y":
			arg = "--enable"
		elif val == "m":
			arg = "--module"
		else:
			raise ValueError("Linux#config: unknown val: %s" % val)
		for v in vars:
			sh("cd %s && scripts/config %s %s" % (self.workdir, arg, v))

	def to_md(self):
		return self.repo.to_md()


class WgetFile:
	def __init__(self, url, dest, desc=''):
		self.url = url
		self.dest = dest
		self.desc = desc

	def pull(self):
		sh("wget -O %s %s" % (self.dest, self.url))


	def to_md(self):
		return "* " + self.desc + "  \n" + self.url + "\n"


class Patches:
	def __init__(self, path, branch):
		self.path = path
		self.patches = [ "%s/%s" % (self.path, patch) for patch in os.listdir(self.path)]
		self.branch = branch

	def __iter__(self):
		return iter(self.patches)

	def to_md(self):
		str = ""
		for patch in self.patches:
			patchname = os.path.split(patch)[1]
			str += "* [%s](https://github.com/notro/rpi-build/blob/master/patches/%s/%s)\n" % (patchname, self.branch, patchname)
		return str


class Readme:
	def __init__(self, filename, release_branch='master', desc=''):
		self.filename = filename
		self.branch = release_branch
		self.desc = desc
		self.sources = []
		self.patches = None
		self.linuxdir = ''

	def desc_to_md(self):
		md = """
notro/rpi-firmware
=======================================================

"""
		md += self.desc + "\n"
		md += """

Build scripts used: https://github.com/notro/rpi-build  
Build logs in the [extra/](https://github.com/notro/rpi-firmware/tree/master/extra) directory
"""
		return md

	def install_to_md(self):
		md = """


### Install

If [rpi-update](https://github.com/Hexxeh/rpi-update) is older than 12. august 2013, then it has to be manually updated first (or REPO_URI will be overwritten):
```text
sudo wget https://raw.github.com/Hexxeh/rpi-update/master/rpi-update -O /usr/bin/rpi-update && sudo chmod +x /usr/bin/rpi-update
```

Because of an [issue](https://github.com/Hexxeh/rpi-update/issues/106), the following command is needed when going from the vanilla kernel to this kernel (not needed on subsequent notro/rpi-firmware updates):
```text
sudo mv /lib/modules/$(uname -r) /lib/modules/$(uname -r).bak
```

**Install**
```text
"""
		md += "sudo REPO_URI=https://github.com/notro/rpi-firmware "


		print("\n\nself.branch: %s\n\n" % self.branch)


		if self.branch != 'master':
			md += "BRANCH=%s " % self.branch
		md += "rpi-update\n"
		md += "sudo shutdown -r now\n"
		md += "```\n"
		return md

	def add_source(self, *args):
		self.sources.extend(args)

	def sources_to_md(self):
		md = "\n\n### Sources\n\n"
		for src in self.sources:
			md += src.to_md()
		return md

	def add_patches(self, patches):
		self.patches = patches

	def patches_to_md(self):
		md = ""
		if self.patches:
			patches = self.patches.to_md()
			if patches:
				md += "\n\n### Kernel patches\n"
				md += patches
		return md

	def config_diff(self, linuxdir):
		self.linuxdir = linuxdir

	def config_diff_to_md(self):
		if not self.linuxdir:
			return ""
		heading = "\n\n### Kernel configuration changes\n\n"
		md = ""
		old_cfg = readf("%s/.config.standard" % self.linuxdir)
		new_cfg = readf("%s/.config" % self.linuxdir)

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

		if not deleted and not added:
			md = "None"
		return heading + md

	def __str__(self):
		str = ""
		str += self.desc_to_md()
		str += self.install_to_md()
		str += self.sources_to_md()
		str += self.patches_to_md()
		str += self.config_diff_to_md()
		return str

	def to_md(self):
		return "%s" % self


def begin(task):
	begin.start = time.time()
	begin.task = task
	print("\n#\n# Begin: %s\n# Time: %s\n#\n" % (task, time.ctime(begin.start)))

def end():
	t = time.time()
	print("\n#\n# End: %s\n# Time: %s\n# Elapsed: %.2f min\n#\n" % (begin.task, time.ctime(t), (t - begin.start)/60))

def heading(msg):
	print("\n\n %s\n%s" % (msg, "-"*(len(msg)+2)))

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
