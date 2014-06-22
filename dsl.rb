require 'json'

def github_get_head(repo, branch='master')
  url = "https://api.github.com/repos/#{repo}/git/refs/heads/#{branch}"
  j = JSON.parse http_get url
  begin
    ref = j['object']['sha']
  rescue
    puts "\n\n\n\n===>"
    puts j.inspect
    puts "<===\n\n    ERROR: bad response from #{url}\n\n"
    raise
  end
  ref
end

def gitweb_get_head(repo, branch='master')
  # this is very slow on the Pi (~9s), only require when needed
  require 'rss'
  url = "#{repo};a=rss;h=refs/heads/#{branch}"
  feed = open(url) { |rss| RSS::Parser.parse(rss) }
  begin
    m = feed.items.first.link.match(/h=(.+)$/)
    m[1]
  rescue
    puts "\n\n\n\n===>"
    puts feed.inspect
    puts "<===\n\n    ERROR: bad response from #{url}\n\n"
    raise
  end
end

def find_patch_file(fn, ver, dir)
  [workdir(fn), download_dir(fn), "#{dir}/patches/#{fn}"].each { |f| return f if File.file? f }

  fl = FileList["#{workdir fn}/*"] + FileList["#{dir}/patches/#{fn}/*"]
  raise "can't find patch '#{fn}'" if fl.empty?
  patches = []
  fl.each { |f| patches << { :file => f, :ver => LinuxVersion.new(File.basename f) } }
  # favour workdir entries by removing duplicates
  patches.uniq! { |p| p[:ver].to_i }
  patches = patches.sort_by { |p| p[:ver].to_i }
  bestmatch = nil
  v = LinuxVersion.new(ver)
  patches.each do |p|
    break unless v >= p[:ver]
    bestmatch = p# if v >= p[:ver]
  end
  raise "can't find patch '#{fn}' that match '#{ver}'" unless bestmatch
  bestmatch[:file]
end

def findfile(fn)
  # find directories for required files beneath RPI_BUILD_DIR
  searchdirs = $LOADED_FEATURES.map{ |f| File.dirname f }.uniq.select{ |d| d.index(ENV['RPI_BUILD_DIR']) == 0 }
  # add dir of current Rakefile
  searchdirs << download_dir
  searchdirs << File.dirname(File.expand_path Rake.application.rakefile)
  searchdirs << workdir
  searchdirs.reverse!
  unless @findfile_debug_done
    debug "findfile searchdirs: #{searchdirs.inspect}"
    @findfile_debug_done = true
  end
  searchdirs.each do |d|
    f = File.join d, fn
    return f if File.exists? f
  end
  raise "ERROR: Could not find file #{fn.inspect}"
end

module Rake
  module DSL
    def pre_install(str)
      File.open(workdir('pre-install'), 'a') { |file| file.write str }
    end

    def post_install(str)
      File.open(workdir('post-install'), 'a') { |file| file.write str }
    end

    def patch(file, opts='', usegitapply=false)
      dir = File.dirname caller[0][/[^:]*/]
      target :patch do
        print "Trying '#{file}'..."
        f = find_patch_file file, VAR['LINUX_KERNEL_VERSION'], dir
        if File.zero? f
          puts " skipped"
          next
        else
          puts
        end
        if usegitapply
          # doesn't always work without a git repository. Does work when 'git init' is done
          sh "cd #{workdir 'linux'} && git apply -v #{opts} #{File.expand_path f}"
        else
          sh "cd #{workdir 'linux'} && patch -p1 #{opts} < #{File.expand_path f}"
        end

# TODO: remove the RPI_BUILD_DIR part
        Readme.patch "* #{f}\n"


      end
    end

    def config(option, command, answer=nil)
      option = [option] unless option.is_a? Array
      cmd = []
      option.each do |k|
        value = ''
        case command
        when :enable, 'enable', 'y'
          c = '--enable'
        when :disable, 'disable', 'n'
          c = '--disable'
        when :module, 'module', 'm'
          c = '--module'
        when :str
          c = '--set-str'
          val = "\"#{answer}\""
          answer = nil
        when :val
          c = '--set-val'
          val = answer
          answer = nil
        when :undefine
          c = '--undefine'
        end
        cmd << "cd #{workdir 'linux'} && scripts/config #{c} #{k} #{val}"
      end

      if answer
        cmd << make('oldconfig', "yes #{answer} | ")
      else
        cmd << make('oldconfig', "yes \"\" | ")
      end

      target :config do
        cmd.each { |c| sh c }
      end
    end

    def github_tarball(repo, symlink, env_name=nil)
      env_name ||= repo.gsub(/[\/\-]/, '_').upcase
      VAR["#{env_name}_BRANCH"] ||= 'master'
      VAR["#{env_name}_REF"] ||= github_get_head(repo, VAR["#{env_name}_BRANCH"])
      ref = VAR["#{env_name}_REF"]
      saveas = "#{repo.gsub '/', '-'}-#{ref}.tar.gz"

      dl = download "https://github.com/#{repo}/archive/#{ref}.tar.gz", saveas, repo

      un = unpack saveas, symlink
      un.enhance [dl.name]
      return dl, un
    end

    def gitweb_tarball(repo, symlink, env_name)
      VAR["#{env_name}_BRANCH"] ||= 'master'
      VAR["#{env_name}_REF"] ||= gitweb_get_head repo, VAR["#{env_name}_BRANCH"]
      url = "#{repo};a=snapshot;h=#{VAR["#{env_name}_REF"]};sf=tbz2"
      saveas = "#{repo}-#{VAR["#{env_name}_REF"]}.tar.bz2".gsub(/.+:\/\//, '').gsub(/[^A-Za-z\d\._\-]/, '-')

      dl = download url, saveas, repo

      un = unpack saveas, symlink
      un.enhance [dl.name]
      return dl, un
    end

    def download(src, saveas=nil, desc=nil)
      saveas ||= File.basename(src)
      dst = download_dir saveas

      t = file dst do
        begin
          sh "wget --no-use-server-timestamps --progress=dot:mega -O '#{dst}' '#{src}'"
        rescue
          info "\nClean up after failed download:"
          sh "rm -f #{dst}"
          raise
        end
        shafile = "#{dst}.sha"
        if File.exists? shafile
          sh "cd #{File.dirname shafile} && shasum -c #{File.basename shafile}"
        end
      end
      target :fetch => dst do
        if desc
          Readme.source "* [#{desc}](#{src})\n"
        else
          Readme.source "* #{src}\n"
        end
      end
      t
    end

    def unpack(fn, symlink=nil)
      src = download_dir fn
      if %w{.tar .tgz .tar.gz .tar.Z .tar.bz2 .tar.xz}.any? { |ext| src.end_with? ext }
        cmd = "tar -x --checkpoint=100 --checkpoint-action=dot -C #{workdir} -f #{src}"
        list = "tar tf #{src} | sed -e 's@/.*@@' | uniq"
      elsif %w{.zip}.any? { |ext| src.end_with? ext }
        cmd = "unzip -q #{src} -d #{workdir}"
        list = "unzip -Z -1 #{src} | sed -e 's@/.*@@' | uniq"
      else
        raise "Don't know how to unpack #{src}"
      end

      dst_name = File.basename(fn, File.extname(fn))
      dst_name = File.basename(dst_name, File.extname(dst_name)) if File.extname(dst_name) == '.tar'
      symlink ||= dst_name
      t = file workdir(dst_name) do
        sh cmd
        puts
        # if we can list the contents of the archive, make a symlink to the first entry
        if list
          toplevel = `#{list}`.strip
          raise "Failed to rename unpacked archive (status = #{$?.to_i})" if $?.to_i != 0
          if toplevel != symlink
            cd workdir do
              ln_s toplevel, symlink, :verbose => true
            end
          end
        end
        # a marker to show that we have unpacked
        touch workdir(dst_name)
      end
      target :unpack => workdir(dst_name)
      t
    end

    def git(src, saveas)
      d = file download_dir(saveas) do
        cd download_dir do
          sh "git clone #{src} #{saveas}"
        end
      end
      target :fetch => download_dir(saveas)

      l = file workdir(saveas) do
        ln_s download_dir(saveas), workdir(saveas)
      end
      target :unpack => workdir(saveas)

      return d, l
    end

    def package(*args, &block)
      Rake::Package.define_task(*args, &block)
    end

    def target(*args, &block)
      Rake::TargetTask.define_task(*args, &block)
    end

    def release(*args, &block)
      Rake::ReleaseTask.define_task(*args, &block)
    end

  end
end
