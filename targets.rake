# targets (or stages)

target :fetch do
  Readme.clear 'source'
end


target :unpack => :fetch
task :unpack_post do
  next unless VAR['DIFFPREP']
  VAR.store 'DIFFPREP'
  info "Prepare '#{VAR['DIFFPREP']}' for diff"
  VAR['DIFFPREP'].split(',').each do |d|
    path = workdir d
    raise "DIFFPREP: No such directory '#{path}'" unless Dir.exists? path
    unless Git.is_repo? path
      info "WARNING: No .gitignore in #{path}" unless File.exists? "#{path}/.gitignore"
      sh "cd #{path} && git init"
    end
    repo = Git.new path
    repo.verbose = true
    raise "DIFFPREP: Branch 'rpi-build-unpack' already exists for '#{repo.path}'" if repo.branch? 'rpi-build-unpack'
    repo.git 'checkout -b rpi-build-unpack'
    unless repo.pristine?
      repo.commit_all 'diff for unpack stage'
    else
      info "DIFFPREP: Nothing to commit for repo #{repo.path}"
    end
  end
end


target :diff, [:against] => [:unpack] do |t, args|
  raise "diffprep is not set" unless VAR['DIFFPREP']
  against = args.against ? args.against : 'unpack'
  raise "diff: unknown target '#{against}'" unless %w[unpack patch].include? against

  VAR['DIFFPREP'].split(',').each do |d|
    repo = Git.new workdir d
    repo.verbose = true
    fn = workdir "#{d}-#{against}.patch"
    puts repo.git "diff rpi-build-#{against} > #{fn}"
    info "No diff against '#{against}'\n\n" if File.size(fn) == 0
  end
end


target :patch => :unpack do
  fn = workdir 'linux/Makefile'
  raise "Kernel Makefile is missing: #{fn}" unless File.exists? fn
  # this can be used by the patch target to determine which patchfile version to use
  VAR['LINUX_KERNEL_VERSION'] = "#{LinuxVersion.parse_makefile fn}"
  puts "Linux kernel version: #{ENV['LINUX_KERNEL_VERSION']}"
  Readme.clear 'patch'
end
task :patch_post do
  next unless VAR['DIFFPREP']
  info "Prepare #{VAR['DIFFPREP']} for diff"
  VAR['DIFFPREP'].split(',').each do |d|
    path = workdir d
    raise "DIFFPREP: #{path} is not a git repo" unless Git.is_repo? path
    repo = Git.new path, 'rpi-build-unpack'
    repo.verbose = true
    raise "DIFFPREP: branch '#{rpi-build-patch}' already exists for '#{repo.path}'" if repo.branch? 'rpi-build-patch'
    repo.git 'checkout -b rpi-build-patch'
    unless repo.pristine?
      repo.commit_all 'diff for patch stage'
    else
      info "DIFFPREP: Nothing to commit for repo #{repo.path}"
    end
  end
end


target :config => :patch do
  raise "missing environment variable LINUX_DEFCONFIG" unless VAR['LINUX_DEFCONFIG']
  sh "#{make VAR['LINUX_DEFCONFIG']}"
  cp workdir('linux/.config'), workdir('linux/.config.defconfig')
end


target :menuconfig => :config do
  sh make 'menuconfig'
  config_fn = Rake.application[:config].marker
  if File.mtime(workdir 'linux/.config') > File.mtime(config_fn)
    # .config has changed, mark config target as changed
    touch config_fn
  end
end


target :diffconfig => :config do
  sh "cd #{workdir 'linux'} && scripts/diffconfig .config.defconfig .config"
end


target :kbuild => :config do
  rm FileList["#{workdir}/{pre-install,post-install}"]

  cpus = `nproc`.strip.to_i
  sh make "-j#{cpus*2}"
  VAR['KERNEL_RELEASE'] = `#{make('kernelrelease')}`.strip
end


target :kmodules => :kbuild do
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
end


target :external => :kmodules


target :build => :external do
  dst = workdir 'out'
  rm_rf dst
  mkdir_p dst

  version = `strings #{workdir 'linux/arch/arm/boot/Image'} | grep "Linux version"`.strip
  sh "mkdir -p #{dst}/extra"
  File.open("#{dst}/extra/version", 'w') { |file| file.write version }

  fl = FileList["#{workdir}/{pre-install,post-install}"]
  cp fl, dst unless fl.empty?
end


target :readme => :build do
  fn = File.join Rake.application.original_dir, 'rpi-firmware'
  VAR['FW_REPO'] ||= fn if File.exists? "#{fn}/.git"
  VAR['FW_BRANCH'] ||= 'master'
  raise 'missing FW_REPO' unless VAR['FW_REPO']
  raise "not a git repo: #{File.expand_path VAR['FW_REPO']}" unless File.exists? "#{VAR['FW_REPO']}/.git"

  Git.verbose = Rake.application.options.trace
  git = Git.new VAR['FW_REPO'], VAR['FW_BRANCH']
  git.check
  # use ENV to prevent the variables from being stored
  ENV['FW_URL'] = `cd #{VAR['FW_REPO']} && git ls-remote --get-url`.gsub(/.git$/, '').strip unless VAR.key? 'FW_URL'
  ENV['FW_SHORT_REPO'] = URI.parse(ENV['FW_URL']).path.gsub(/^\//, '') unless VAR.key? 'FW_SHORT_REPO'

  ENV['README_desc'] = "Linux kernel release #{VAR['KERNEL_RELEASE']} for the Raspberry Pi." unless VAR.key? 'README_desc'
  ENV['README_install'] = """
```text
sudo REPO_URI=#{VAR['FW_URL']}#{VAR['FW_BRANCH'] != 'master' ? (' BRANCH=' + VAR['FW_BRANCH']) : ''} rpi-update
```
""" unless VAR.key? 'README_install'

  unless VAR.key? 'README_footer'
    ENV['README_footer'] = '<p align="center">Built with <a href="https://github.com/notro/rpi-build/wiki">rpi-build</a></p>'
  end

  unless VAR.key? 'README_defconfig'
    ENV['README_defconfig'] = "#{VAR['LINUX_DEFCONFIG']}"
  end

  ENV['README_all'] = """#{VAR['FW_SHORT_REPO']}
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
Default config: #{ENV['README_defconfig']}

#{Readme.diffconfig}

#{Readme.footer}
""" unless VAR.key? 'README_all'

  Readme.write
end


target :commit => :readme do
  raise "missing COMMIT_MESSAGE" unless VAR['COMMIT_MESSAGE']
  dst = VAR['FW_REPO']
  sh "rm -rf #{dst}/*"
  sh "cp -a #{workdir 'out'}/* #{dst}"
  sh "rm -rf #{dst}/modules/*/{source,build}"
  cp workdir('build.log'), "#{dst}/extra" if File.exists? workdir('build.log')
  Git.verbose = true
  repo = Git.new dst, VAR['FW_BRANCH']
  unless repo.pristine?
    repo.commit_all VAR['COMMIT_MESSAGE']
  else
    info "nothing to commit for repo #{repo.path}"
  end
end


target :push => :commit do
  if $logfile
    puts "\n\nWon't push when logging to file, in case username and password is asked for\n\n"
  else
    Git.verbose = true
    git = Git.new VAR['FW_REPO'], VAR['FW_BRANCH']
    git.push
  end
end


target :archive => :build do
  sh "cd #{workdir 'out'}; tar -zcf #{workdir 'archive.tar.gz'} *"
end


target :transfer => :archive do
  ssh "rm -rf rpi-build-archive; mkdir rpi-build-archive"
  ssh "cd rpi-build-archive; tar zxvf -", '', "cat #{workdir 'archive.tar.gz'} | "
end


VAR.default('UPDATE_SELF') { '0' }
VAR.default('SKIP_BACKUP') { '1' }
VAR.default('RPI_UPDATE_OPTS') { "UPDATE_SELF=#{VAR['UPDATE_SELF']} SKIP_BACKUP=#{VAR['SKIP_BACKUP']} SKIP_REPODELETE=#{VAR['SKIP_REPODELETE']} SKIP_DOWNLOAD=1" }
if rpi?
  VAR.default('SKIP_REPODELETE') { '1' }
  target :install => :build do
    if File.mtime('/usr/bin/rpi-update') < Time.new(2014, 4, 16)
      info "Update rpi-update to ensure FW_REPOLOCAL support:"
      sh "sudo wget https://raw.github.com/Hexxeh/rpi-update/master/rpi-update -O /usr/bin/rpi-update && sudo chmod +x /usr/bin/rpi-update"
      info ''
    end
    sh "sudo #{VAR['RPI_UPDATE_OPTS']} FW_REPOLOCAL=#{workdir 'out'} rpi-update '#{Time.now}'"
  end
else
  VAR.default('SKIP_REPODELETE') { '0' }
  target :install => :transfer do
    res = ssh "stat --printf=%Y /usr/bin/rpi-update"
    if res.to_i < (Time.now - 7*24*60*60).to_i
      info "Update rpi-update:"
      ssh "sudo curl -L --output /usr/bin/rpi-update https://raw.githubusercontent.com/Hexxeh/rpi-update/master/rpi-update && sudo chmod +x /usr/bin/rpi-update"
    end
    res = ssh "sudo #{VAR['RPI_UPDATE_OPTS']} FW_REPOLOCAL=rpi-build-archive rpi-update '#{Time.now}' 1>&2"
    info res
    rm workdir('transfer.target')
  end
end

def cp_build_log(src_workdir, dst_workdir)
  src = File.join(src_workdir, 'build.log')
  dst = File.join(dst_workdir, 'out/extra', "#{File.basename(src_workdir)}-build.log")
  if File.exists? src
    sh "cp #{src} #{dst}"
  end
end

target :merge, [:workdir1, :workdir2] do |t, args|
  basedir = workdir '..'
  wds = [args.workdir1, args.workdir2].compact
  if wds.empty?
    wds = Dir.entries(basedir).select { |entry| (entry[/^workdir.+/]) and File.directory? File.join(basedir, entry) }
  end
  info "Merge directories: #{wds.join(',')}"
  raise "merge target can only merge 2 directories: #{wds.inspect}" unless wds.length == 2
  wds.map! { |d| File.expand_path(d, basedir) }
  wds.each { |d| raise "merge target: '#{d}' not a directory" unless File.directory? d }
  wd1 = wds[0]
  wd2 = wds[1]

  rm_rf "#{workdir()}"
  mkdir_p "#{workdir('out')}"
  sh "cd #{workdir()} && ln -s #{wd1}/firmware firmware"
  sh "cd #{workdir()} && ln -s #{wd1}/linux linux"
  sh "cp #{wd1}/*.variable #{workdir()}"
  sh "cp #{wd1}/*.target #{workdir()}"

  sh "cp -r #{wd1}/out/* #{workdir('/out/')}"
  cp_build_log wd1, workdir()

  sh "cp -r #{wd2}/out/* #{workdir('/out/')}"
  cp_build_log wd2, workdir()
end
