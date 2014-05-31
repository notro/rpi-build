
module Rake
  class Rpibuild < Application
    attr_reader :basedir
    attr_accessor :workdir
    attr_accessor :download_dir
    attr_accessor :logfile

    def initialize(basedir, workdir=nil, download_dir=nil)
      super()
      @basedir = basedir
      @workdir = workdir ? File.expand_path(workdir) : File.join(original_dir, 'workdir')
      @download_dir = download_dir ? File.expand_path(download_dir) : File.join(@basedir, 'downloads')
    end

    def run
      logfile_exception_handling do
        init 'rpi-build'
        if @top_level_tasks.include? 'admin'
          load File.join File.dirname(__FILE__), 'admin.rake'
        else
          load File.join File.dirname(__FILE__), 'tasks.rake'
          @top_level_tasks << :usage if @top_level_tasks.empty?
          # run 'tasks.rake' tasks first if mentioned
          @top_level_tasks.reject! { |task_string|
            name, args = parse_task_string(task_string)
            t = lookup name
            if t
              t.invoke args
              true
            else
              false
            end
          }
          exit if @top_level_tasks.empty?
          info "Workdir: #{@workdir}"
          `mkdir -p #{@workdir}`
          `mkdir -p #{@download_dir}`
          load File.join File.dirname(__FILE__), 'targets.rake'
          load_rakefile
        end
        top_level
      end
    end

    def logfile_exception_handling
      begin
        STDOUT.sync = true
        STDERR.sync = true
        stdout_org = STDOUT.dup
        stderr_org = STDERR.dup
        yield
      rescue SystemExit => ex
        # Exit silently with current status
        raise
      rescue OptionParser::InvalidOption => ex
        $stderr.puts ex.message
        exit(false)
      rescue Exception => ex
        # Exit with error message
        display_error_message(ex)
        exit(false)
      ensure
        STDOUT.reopen stdout_org
        STDERR.reopen stderr_org
        if @logfile
          @logfile.puts "\nEnd: #{Time.now}\n\n"
          @logfile.close
          `cat #{@logfile.path} >> #{@workdir}/build.log`
          @logfile.unlink
          # re-display, since it was caught by the logfile
          display_error_message(@exception_raised) if @exception_raised
        end
      end
    end

    def display_error_message(ex)
      @exception_raised = ex
      super
    end
  end
end
