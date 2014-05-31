
module Rake
  class TargetTask < Task
    # the first dependency is also a special target dependency
    def enhance(deps=nil, &block)
      if deps
          @target_dep = deps[0] if @prerequisites.empty?
          @prerequisites |= deps
      end
      @actions << block if block_given?
      self
    end

    # always run when using direct invocation 
    def invoke(*args)
      out = `rm -vf #{workdir name.to_s}`
      debug out
      super
    end

    # stop the invocation chain if timestamp is later than every
    # target in the target dependency chain
    def invoke_with_call_chain(task_args, invocation_chain)
      super if ! File.exist?(workdir name) or target_dep_timestamp > timestamp
    end

    def target_dep_timestamp
      if @target_dep
        td = application[@target_dep, @scope]
        if td.respond_to? 'target_dep_timestamp'
          stamp = td.target_dep_timestamp
          return stamp > timestamp ? stamp : timestamp
        end
      end
      timestamp
    end

    def timestamp
      if File.exist?(workdir name)
        File.mtime(workdir name.to_s)
      else
        Rake::EARLY
      end
    end

    def execute(args=nil)
      super
      cmd = "touch #{workdir name.to_s}"
      debug cmd
      `#{cmd}`
      puts "Target '#{self.name}' done\n\n"
    end
  end

  class Package < Task
    def invoke_with_call_chain(task_args, invocation_chain)
      puts "Package: #{self.name}"
      super
    end
  end

  class ReleaseTask < Task
    attr_reader :invoke_action

    # the first block runs before the dependencies
    # other actions as usual
    def enhance(deps=nil, &block)
      @prerequisites |= deps if deps
      if block_given?
        unless @invoke_action
          @invoke_action = block
        else
          @actions << block
        end
      end
      self
    end

    def invoke(*args)
      if @invoke_action
        # use application.trace in > 0.9.2
        $stderr.puts "** Execute #{name} (invoke_action)" if application.options.trace
        @invoke_action.call(self)
      end
      super
    end

    def invoke_with_call_chain(task_args, invocation_chain)
      puts "Release: #{self.name}"
      super
    end
  end
end
