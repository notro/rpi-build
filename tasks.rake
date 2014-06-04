require 'tempfile'

# If specified on the command line, these tasks are run before loading the rakefile

task :default => :usage

task :usage do
  puts """Usage:
rpi-build [option tasks] <release> <target>

Targets:
* fetch           - Download files
* unpack          - Unpack archives into workdir
* patch           - Patch Linux kernel source
* config          - Configure Linux kernel
* menuconfig      - make menuconfig
* diffconfig      - Show kernel config diff from default config
* kbuild          - Build Linux kernel
* kmodules        - Copy modules and device firmware to a temporary directory
* external        - Build and install out-of-tree modules
* build           - Build all
* readme          - Create README.md
* commit          - Commit kernel and firmware
* push            - Push commit(s)
* archive         - Archive workdir out
* transfer        - Copy archive to machine (needs SSHIP)
* install         - Install

Option tasks:
* use[library]    - Use library (Rakefile)
* clean           - Clean workdir
* log             - Redirect output to build.log

rpi-build is built on top of Rake, and has much of the same behaviour.
Targets, releases and option tasks are Rake tasks.
They are run in the order they are given on the command line,
except for option tasks which are run before any other tasks.

Some Rake options:
-h      - Help
--trace - Be more verbose
          Print full stack trace on exceptions

Environment variables:
RPI_BUILD_DIR     - rpi-build root directory
                    Default: ~/rpi-build
WORKDIR           - Working directory used when building
                    Default: ./workdir
DOWNLOAD_DIR      - Directory for downloaded files
                    Default: $RPI_BUILD_DIR/downloads


Admin mode:
rpi-build admin <action>

Actions:
* addlib[gitrepo] - Add library with git
                    Short gitrepo assumes Github: addlib[notro/fbtft-build]
* update          - Update git repos in RPI_BUILD_DIR

"""
end

desc "Clean workdir"
task :clean do
  rm_rf Rake.application.workdir
end

desc "Set which library to use (Rakefile)"
task :use, [:library] do |t, args|
  raise "missing library argument to task 'use' (e.g. use[fbtft-build])" if args.library.empty?
  fn = File.join ENV["RPI_BUILD_DIR"], args.library, 'Rakefile'
  raise "can't find library #{args.library} (#{fn})" unless File.exists? fn
  Dir.chdir File.dirname fn
end

desc "Redirect output to build.log"
task :log do
  $stderr = $stdout

  logfile = Tempfile.open(['rpi-build', '.log'])
  puts "Temporary logfile: #{logfile.path}"
  logfile.puts "Start: #{Time.now}\n\n"
  logfile.puts "Commandline arguments: #{ARGV.join ' '}\n\n"
  STDOUT.reopen logfile
  STDERR.reopen logfile
  Rake.application.logfile = logfile
end

