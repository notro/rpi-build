# targets (or stages)

# Set up environment variables
task :environment

# deferred task creation
task :deferred => :environment

target :fetch do
  Readme.clear 'source'
end


target :unpack => :fetch


target :patch => :unpack do
  fn = workdir 'linux/Makefile'
  raise "Kernel Makefile is missing: #{fn}" unless File.exists? fn
  # this is used by the patch target
  ENV['LINUX_KERNEL_VERSION'] = "#{LinuxVersion.parse_makefile fn}"
#ENV['LINUX_KERNEL_VERSION'] = "3.10.3"
  puts "Linux kernel version: #{ENV['LINUX_KERNEL_VERSION']}"
  Readme.clear 'patch'
end


#target :config => b.name do
target :config => :patch do
  raise "missing environment variable LINUX_DEFCONFIG" unless ENV['LINUX_DEFCONFIG']
  sh "#{make ENV['LINUX_DEFCONFIG']}"
  cp workdir('linux/.config'), workdir('linux/.config.defconfig')
end


target :menuconfig => :config do
  if `ldconfig -p | grep ncurses`.strip.empty?
    raise 'missing ncurses library. apt-get install libncurses5-dev'
  end
  sh make 'menuconfig'
  if File.mtime(workdir 'linux/.config') > File.mtime(workdir 'config')
    # .config has change, mark config target as changed
    touch workdir 'config'
  end
end


target :diffconfig => :config do
  sh "cd #{workdir 'linux'} && scripts/diffconfig .config.defconfig .config"
end


desc "Build kernel => #{Rake::Task[:config].comment}"
target :build => :config do
  rm FileList["#{workdir}/{pre-install,post-install}"]

  post_install <<EOM
if [ -d ${FW_REPOLOCAL}/firmware ]; then
        echo "     /lib/firmware"
        cp -R "${FW_REPOLOCAL}/firmware/"* /lib/firmware/
fi
EOM

  cpus = `nproc`.strip.to_i
  sh make "-j#{cpus*2}"
end


target :modules_install => :build do
  d = workdir 'modules'
  mkdir d unless File.directory? d
  unless `cd #{workdir 'linux'} && scripts/config --state MODULES`.strip == 'n'
    sh make "INSTALL_MOD_PATH=#{d} modules_install"
  else
    puts 'Loadable kernel module support is disabled'
    # for rpi-update
    mod = workdir 'modules/lib/modules'
    mkdir_p mod unless File.directory? mod
    touch "#{mod}/dummy"
  end
  sh make "INSTALL_MOD_PATH=#{d} firmware_install"
end


target :external => :modules_install


target :install => :external do
  dst = workdir 'out'
  rm_rf dst
  mkdir_p dst

  fl = FileList["#{workdir}/{pre-install,post-install}"]
  cp fl, dst unless fl.empty?
end


target :readme => :install do
  Readme.write
end


target :release => :readme


target :upload => :release


#desc "Archive firmware"
#task :archive => :install


target 'rpi-update' => :install do
  cmd = "sudo UPDATE_SELF=0 SKIP_DOWNLOAD=1 SKIP_REPODELETE=1 SKIP_BACKUP=1 FW_REPOLOCAL=#{workdir 'out'} rpi-update \"#{Time.now}\""
  if uname_m == 'armv6l'
    if File.mtime('/usr/bin/rpi-build') < Time.new(2014, 4, 16)
      puts "Update rpi-update to ensure FW_REPOLOCAL support:"
      sh "sudo wget https://raw.github.com/Hexxeh/rpi-update/master/rpi-update -O /usr/bin/rpi-update && sudo chmod +x /usr/bin/rpi-update"
      puts
    end
    sh cmd
  else
    puts "\nUse this command on the Pi with adjusted FW_REPOLOCAL is you have it connected through NFS or similar."
    puts "Make sure rpi-update is more recent than 2014-04-15 for FW_REPOLOCAL support.\n\n"
    puts "----"
    puts cmd
    puts "----\n\n"
  end
end
