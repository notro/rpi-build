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
  raise "missing environment variable LINUX_DEFCONFIG" unless VAR['LINUX_DEFCONFIG']
  sh "#{make VAR['LINUX_DEFCONFIG']}"
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

  version = `strings #{workdir 'linux/arch/arm/boot/Image'} | grep "Linux version"`.strip
  sh "mkdir -p #{dst}/extra"
  File.open("#{dst}/extra/version", 'w') { |file| file.write version }

  fl = FileList["#{workdir}/{pre-install,post-install}"]
  cp fl, dst unless fl.empty?
end


target :readme => :install do
  VAR['FW_REPO'] ||= File.expand_path('rpi-firmware') if File.exists? 'rpi-firmware/.git'
  VAR['FW_BRANCH'] ||= 'master'
  raise 'missing FW_REPO' unless VAR['FW_REPO']
  raise "not a git repo: #{VAR['FW_REPO']}" unless File.exists? "#{VAR['FW_REPO']}/.git"

  Git.verbose = Rake.application.options.trace
  git = Git.new VAR['FW_REPO'], VAR['FW_BRANCH']
  git.check
  VAR['FW_URL'] ||= `cd #{VAR['FW_REPO']} && git ls-remote --get-url`.gsub(/.git$/, '').strip
  VAR['FW_SHORT_REPO'] ||= URI.parse(VAR['FW_URL']).path.gsub(/^\//, '')
  ENV['KERNEL_RELEASE'] ||= `#{make('kernelrelease')}`.strip

  Readme.install ||= """
```text
sudo REPO_URI=#{VAR['FW_URL']}#{VAR['FW_BRANCH'] != 'master' ? (' BRANCH=' + VAR['FW_BRANCH']) : ''} rpi-update
```
"""
  Readme.all ||= """#{VAR['FW_SHORT_REPO']}
==========

#{Readme.desc}

Install
-------
#{Readme.install}
#{Readme.body}

Sources
-------
#{Readme.source.empty? ? 'None' : Readme.source}

Patches
--------
#{Readme.patch.empty? ? 'None' : Readme.patch}

Kernel config
-------------
Default config: #{VAR['LINUX_DEFCONFIG']}

#{Readme.diffconfig}

#{Readme.footer}
"""

  Readme.write
end


target :commit => :readme do
  raise "missing COMMIT_MESSAGE" unless VAR['COMMIT_MESSAGE']
  sh "rm -rf #{VAR['FW_REPO']}/*"
  sh "cp -a #{workdir 'out'}/* #{VAR['FW_REPO']}"
  sh "rm -rf #{VAR['FW_REPO']}/modules/*/{source,build}"
  cp workdir('build.log'), VAR['FW_REPO'] if File.exists? workdir('build.log')
  Git.verbose = Rake.application.options.trace
  git = Git.new VAR['FW_REPO'], VAR['FW_BRANCH']
  git.commit_all VAR['COMMIT_MESSAGE']
end


target :push => :commit do
  if $logfile
    puts "\n\nWon't push when logging to file, in case username and password is asked for\n\n"
  else
    Git.verbose = Rake.application.options.trace
    git = Git.new VAR['FW_REPO'], VAR['FW_BRANCH']
    git.push
  end
end


target 'rpi-update' => :install do
  cmd = "sudo UPDATE_SELF=0 SKIP_DOWNLOAD=1 SKIP_REPODELETE=1 FW_REPOLOCAL=#{workdir 'out'} rpi-update \"#{Time.now}\""
  if uname_m == 'armv6l'
    if File.mtime('/usr/bin/rpi-build') < Time.new(2014, 4, 16)
      puts "Update rpi-update to ensure FW_REPOLOCAL support:"
      sh "sudo wget https://raw.github.com/Hexxeh/rpi-update/master/rpi-update -O /usr/bin/rpi-update && sudo chmod +x /usr/bin/rpi-update"
      puts
    end
    sh cmd
  else
    puts "\nUse this command on the Pi with adjusted FW_REPOLOCAL if you have it connected through NFS or similar."
    puts "Make sure rpi-update is more recent than 2014-04-15 for FW_REPOLOCAL support.\n\n"
    puts "----"
    puts cmd
    puts "----\n\n"
  end
end
