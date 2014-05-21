# targets (or stages)

# Set up environment variables
task :environment

# deferred task creation
task :deferred => :environment

desc "Fetch"
target :fetch


desc "Unpack => #{Rake::Task[:fetch].comment}"
target :unpack => :fetch


desc "Patch kernel => #{Rake::Task[:unpack].comment}"
target :patch => :unpack do
  fn = workdir 'linux/Makefile'
  raise "Kernel Makefile is missing: #{fn}" unless File.exists? fn
  # this is used by the patch target
  ENV['LINUX_KERNEL_VERSION'] = "#{LinuxVersion.parse_makefile fn}"
#ENV['LINUX_KERNEL_VERSION'] = "3.10.3"
  puts "Linux kernel version: #{ENV['LINUX_KERNEL_VERSION']}"
end


desc "Configure kernel"
#target :config => b.name do
target :config => :patch do
  sh "#{make ENV['LINUX_DEFCONFIG']}"
  cp workdir('linux/.config'), workdir('linux/.config.defconfig')
end


desc "Build kernel => #{Rake::Task[:config].comment}"
target :build => :config do
  cpus = `nproc`.strip.to_i
  sh make "-j#{cpus*2}"
end


target :modules_install => :build do
  d = workdir 'modules'
  mkdir d unless File.directory? d
  sh make "INSTALL_MOD_PATH=#{d} modules_install"
end


desc "Build and install out-of-tree modules"
target :external => :modules_install


target :install => :external do
  # the first action is to make a clean directory
  dst = workdir 'out'
  rm_rf dst
  mkdir_p dst
end


desc "rpi-update: Commit files"
target :release => :install


desc "rpi-update: Push changes"
target :upload => :release


#desc "Archive firmware"
#task :archive => :install


desc "Install using rpi-update locally (only on the Pi)"
target 'rpi-update' => :install do
  puts "sudo UPDATE_SELF=0 SKIP_DOWNLOAD=1 SKIP_REPODELETE=1 SKIP_BACKUP=1 FW_REPOLOCAL=#{workdir 'out'} rpi-update \"#{Time.now}\""
end

# => sudo UPDATE_SELF=0 SKIP_DOWNLOAD=1 SKIP_REPODELETE=1 SKIP_BACKUP=1 FW_REPOLOCAL=/home/pi/repos/rpi-build/workdir/out rpi-update "2014-05-18 00:02:23 +0200"

# Testing
# sudo UPDATE_SELF=0 SKIP_DOWNLOAD=1 SKIP_REPODELETE=1 SKIP_BACKUP=1 FW_REPOLOCAL=/home/pi/work/repos/rpi-build/workdir/out rpi-update $(date --rfc-3339 seconds)
