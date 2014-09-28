require 'open-uri'

def info(msg)
  $stdout.puts msg unless msg.empty?
end

def debug(msg)
  $stderr.puts msg if Rake.application.options.trace
end

def uname_m
  @uname_m ||= `uname -m`.strip
end

def rpi?
  uname_m == 'armv6l'
end

def cross_compile(name='CROSS_COMPILE')
  if rpi?
    ''
  else
    if uname_m.include? '64'
      ENV['CROSS_COMPILE'] ||= workdir 'tools/arm-bcm2708/gcc-linaro-arm-linux-gnueabihf-raspbian-x64/bin/arm-linux-gnueabihf-'
    else
      ENV['CROSS_COMPILE'] ||= workdir 'tools/arm-bcm2708/gcc-linaro-arm-linux-gnueabihf-raspbian/bin/arm-linux-gnueabihf-'
    end
    (name ? "#{name}=" : '') + ENV['CROSS_COMPILE']
  end
end

def make(target='', pre='')
  "cd #{workdir 'linux'} && #{pre}ARCH=arm #{cross_compile} make #{target}"
end

def workdir(file=nil)
  file ? File.join(Rake.application.workdir, file) : Rake.application.workdir
end

def download_dir(file=nil)
  file ? File.join(Rake.application.download_dir, file) : Rake.application.download_dir
end

def http_get(url)
  begin
    r = open url
  rescue
    puts "could not get #{url}"
    raise
  end
  if r.meta['X-RateLimit-Remaining'] == "0"
    raise "Github API rate limit exceeded for #{url} (#{r.meta['X-RateLimit-Limit']} per hour)"
  end
  r.read
end

def ssh(command, opts='', pre='')
  raise 'missing SSHIP' unless ENV['SSHIP']
  ENV['SSHUSER'] ||= 'pi'
  ENV['SSHPASS'] ||= 'raspberry'
  cmd = "#{pre}sshpass -e ssh -o LogLevel=quiet -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no #{opts} #{ENV['SSHUSER']}@#{ENV['SSHIP']} \"#{command}\""
  info cmd
  `#{cmd}`
end

def insert_before(fn, search, insert)
  info "insert_before: #{fn}"
  s = File.read fn
  i = s.index search
  raise "insert_before: can't find #{search.inspect}" unless i
  s = s.insert i, insert
  File.write fn, s
end

def insert_after(fn, search, insert)
  info "insert_after: #{fn}"
  s = File.read fn
  raise "insert_after: can't find #{search.inspect}" unless s.index search
  s.gsub! search, search + insert
  File.write fn, s
end

def replace(fn, search, replac)
  info "replace: #{fn}"
  s = File.read fn
  raise "replace: can't find #{search.inspect}" unless s.index search
  s.gsub! search, replac
  File.write fn, s
end
