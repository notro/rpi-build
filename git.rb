class Git
  attr_reader :path
  attr_reader :branch
  attr_accessor :verbose
  attr_accessor :debug

  def initialize(path, branch=nil)
    @path = File.expand_path path
    @verbose = Git.verbose
    @debug = false
    
    @last_remote_commit = nil
    raise "not a git repo: #{path}" unless Git.is_repo? path
    if branch
      create_branch(branch) unless branches.include? branch
      checkout branch
    end
  end

  def git(cmd, talkative=nil, print_output=nil)
    full_cmd = "cd #{@path} && git #{cmd}"
    puts full_cmd if talkative.nil? ? @verbose : talkative
    res = `#{full_cmd}`
    if $?.exitstatus != 0
      puts res
      raise "Command failed with status (#{$?.exitstatus}): [#{full_cmd}]"
    end
    puts res if print_output
    res
  end

  def empty?
    git('log 2>&1 > /dev/null')
  rescue
    true
  else
    false
  end

  def branch
    @branch ||= current_branch
  end

  def branch=(name)
    checkout name
  end

  def branch?(name)
    branches.include? name
  end

  def branches
    git('branch', @debug, @debug).gsub('* ', '').strip.split
  end

  def current_branch
    git 'rev-parse --abbrev-ref HEAD'
  end

  def create_branch(name)
    git "branch #{name}", true
  end

  def checkout(ref)
    git "checkout -q #{ref}"
  end

  def commit_all(msg)
    git 'add .', nil, @debug
    git "commit -a -m \"#{msg}\"", nil, @debug
  end

  def push
    git "push origin #{branch}", true
  end

  # no tracked file(s) has changed
  def clean?
    git('ls-files -m', @debug, @debug).strip.empty?
  end

  # no untracked file(s) nor changed tracked file(s)
  def pristine?
    git('status -s', @debug, @debug).strip.empty?
  end

  def last_commit
    git("log -1 --format=%H", nil, @debug).strip
  end

  def last_remote_commit
    @last_remote_commit ||= {}
    @last_remote_commit[branch] ||= git("ls-remote origin -h refs/heads/#{branch}", nil, @debug).strip.split.first
  end

  def commits_ahead
    remote = last_remote_commit
    return 0 if remote.nil?
    commits = git "log --format=%H #{branch}", nil, @debug
    count = 0
    i = 0
    commits.split("\n").each do |commit|
      if remote == commit
        count = i
        break
      end
      i += 1
    end
    count
  end

  def check
    raise "not equipped to handle repo's without a single commit" if empty?
    puts "WARNING: #{path} has changed/untracked files" unless pristine?
    # FIXME: I don't think this works
    puts "'#{branch}' has not been pushed upstream yet" if last_remote_commit.nil?
    ahead = commits_ahead
    if ahead > 0
      puts "#{branch} is #{ahead} commits ahead of 'origin/#{branch}'"
    else
      if !last_remote_commit.nil? && last_remote_commit != last_commit
        raise "repo is not up-to-date (git pull)"
      end
    end
  end

  class << self
    attr_accessor :verbose

    def is_repo?(path)
      File.exists? "#{path}/.git"
    end
  end
end
