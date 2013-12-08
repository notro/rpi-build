from master import Tasks as MasterTasks

class Tasks(MasterTasks):
	def setup(self):
		self.branch = 'next'
		self.kernel_branch = "rpi-3.12.y"
		MasterTasks.setup(self)
