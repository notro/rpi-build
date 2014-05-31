
class LinuxVersion
  include Comparable

  attr_reader :version
  attr_reader :patchlevel
  attr_reader :sublevel
  attr_reader :extraversion

  def initialize(str)
    m = str.match /^(\d+)\.(\d+)\.(\d+)(.*)$/
    if m
      @sublevel = m[3].to_i
      @extraversion = m[4]
    else
      m = str.match /^(\d+)\.(\d+)$/
      raise "can't parse Linux kernel version number '#{str}'" unless m
      @sublevel = 0
      @extraversion = ""
    end
    @version = m[1].to_i
    @patchlevel = m[2].to_i
    @version_number = @version * 10**6 + @patchlevel * 10**3 + @sublevel
  end

  def <=>(other)
    self.to_i <=> other.to_i
  end

  def to_i
    @version_number
  end

  def to_s
    if @sublevel == 0
      "#{@version}.#{@patchlevel}"
    else
      "#{@version}.#{@patchlevel}.#{@sublevel}#{@extraversion}"
    end
  end

  class << self
    def parse_makefile(fn)
      makefile = File.read fn
      version = makefile.match(/VERSION = (\d+)$/)
      patchlevel = makefile.match(/PATCHLEVEL = (\d+)$/)
      sublevel = makefile.match(/SUBLEVEL = (\d+)$/)
      extraversion = makefile.match(/EXTRAVERSION =\s*(\w+)$/)
      unless version and patchlevel and sublevel
        raise "Can't extract the kernel version"
      end
      new "#{version[1]}.#{patchlevel[1]}.#{sublevel[1]}#{extraversion[1] if extraversion }"
    end
  end

end
