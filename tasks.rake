# If specified on the command line, these tasks are run before loading the rakefile

task :default => :usage

task :usage do
  puts """Usage:
rpi-build [option tasks] <release> <target>

Targes:
* fetch           - Download files
* unpack          - Unpack archives into workdir
* patch           - Patch Linux kernel source
* config          - Configure Linux kernel
* menuconfig      - make menuconfig
* diffconfig      - Show kernel config diff from default config
* build           - Build Linux kernel
* modules_install - 
* external        - Build and install out-of-tree modules
* install         - Install other files

Option tasks:
* cwd             - Use current directory as workdir
* use[library]    - Use library (Rakefile)
* clean           - Clean workdir
* log             - Redirect output to build.log

Environment variables:
RPI_BUILD_DIR     - rpi-build root directory
WORKDIR           - Working directory used when building
DOWNLOAD_DIR      - Directory for downloaded files


Admin mode:
rpi-build admin <action>

Actions:
* addlib[gitrepo] - Add library with git
                    Short gitrepo assumes Github: addlib[notro/fbtft-build]
"""
end

desc "Clean workdir"
task :clean do
  rm_r workdir
end

desc "Set which library to use (Rakefile)"
task :use, [:library] do |t, args|
  raise "missing library argument to task 'use' (e.g. use[fbtft-build])" if args.library.empty?
  fn = File.join ENV["RPI_BUILD_DIR"], args.library, 'Rakefile'
  raise "can't find library #{args.library} (#{fn})" unless File.exists? fn
  ENV['WORKDIR'] ||= File.join Dir.pwd, 'workdir'
  Dir.chdir File.dirname fn
end

desc "Set WORKDIR to the current working directory (pwd)"
task :cwd do
  if ENV['WORKDIR']
    puts "cwd: WORKDIR already set, ignoring (cwd must be the first task)"
  else
    ENV['WORKDIR'] = Dir.pwd
  end
end

desc "Redirect output to build.log"
task :log do
  $stderr = $stdout

  $logfile = Tempfile.open(['rpi-build', '.log'])
  puts "Temporary logfile: #{$logfile.path}"
  $logfile.puts "Start: #{Time.now}\n\n"
  $logfile.puts "Commandline arguments: #{ARGV.join ' '}\n\n"
  STDOUT.reopen $logfile
  STDERR.reopen $logfile
end

