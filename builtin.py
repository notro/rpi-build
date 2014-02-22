from _common import *
from master import Tasks as MasterTasks

class Tasks(MasterTasks):
	def setup(self):
		self.branch = 'builtin'
		self.kernel_branch = "rpi-3.10.y"
		MasterTasks.setup(self)
		self.readme.desc = "Raspberry Pi kernel and firmware with builtin support for FBTFT (not loadable modules)."

	def task_config(self):
		self.task_config_do('y')
		self.linux.config(['SPI_BCM2708'], 'y')
		self.linux.config(['BCM2708_SPIDEV'], 'n')
		self.linux.make.oldconfig()
