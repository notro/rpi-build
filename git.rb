class Git
  attr_reader :path
  attr_reader :branch
  attr_accessor :verbose

  def initialize(path, branch)
    @path = File.expand_path path
    @branch = branch
    @verbose = Git.verbose
    
    @last_remote_commit = nil
    raise "not a git repo: #{path}" unless Git.is_repo? path
    raise "not equipped to handle repo's without a single commit" if empty?
    create_branch(branch) unless branches.include? branch
    checkout branch
  end

  def git(cmd)
    puts "cd #{@path} && git #{cmd}" if @verbose
    res = `cd #{@path} && git #{cmd}`
    puts res if (@verbose || $?.to_i != 0)
    res
  end

  def empty?
    git('log 2>&1 > /dev/null')
    $?.to_i != 0
  end

  def branches
    git('branch').gsub('* ', '').strip.split
  end

  def current_branch(name)
    git 'git rev-parse --abbrev-ref HEAD'
  end

  def create_branch(name)
    git "branch #{name}"
  end

  def checkout(ref)
    git "checkout -q #{ref}"
  end

  def commit_all(msg)
    git 'add .'
    git "commit -a -m \"#{msg}\""
  end

  def push
    git "push origin #{branch}"
  end

  # no tracked file(s) has changed
  def clean?
    git('ls-files -m').strip.empty?
  end

  # no untracked file(s) nor changed tracked file(s)
  def pristine?
    git('status -s').strip.empty?
  end

  def last_commit
    git("log -1 --format=%H").strip
  end

  def last_remote_commit
    @last_remote_commit ||= git("ls-remote origin -h refs/heads/#{branch}").strip.split.first
  end

  def commits_ahead
    remote = last_remote_commit
    return 0 if remote.nil?
    commits = git "log --format=%H #{branch}"
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
    raise "#{path} has uncommitted changes" unless clean?
    puts "WARNING: #{path} has untracked files" unless pristine?
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
