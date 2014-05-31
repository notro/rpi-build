# Lazy environment variable expansion
# stores the value in workdir for later runs
class VAR
  @@defaults = {}

  class << self
  def read(var)
    fn = workdir "#{var}.variable"
    if File.exists? fn
      File.read fn
    else
      nil
    end
  end

  def write(var, value)
    fn = workdir "#{var}.variable"
    File.open(fn, 'w') { |file| file.write value }
  end

  def [](var)
    if ENV.key? var
      debug "#{var} == #{ENV[var]}"
      return ENV[var]
    end
    value = self.read var
    unless value == nil
      debug "#{var} <= #{value}"
      ENV[var] = value
      return value
    end
    if @@defaults.key? var
      value = @@defaults[var].call
      debug "#{var} ?= #{value}"
      ENV[var] = value
      self.write var, value
    else
      debug "#{var} (not set)"
      nil
    end
  end

  def []=(var, value)
    debug "#{var} = #{value}"
    ENV[var] = value
    self.write var, value
  end

  def delete(var)
    ENV.delete var
    fn = workdir "#{var}.variable"
    File.unlink fn if File.exists? fn
  end

  def default(var, &block)
    raise "block missing" unless block_given?
    @@defaults[var] = block
  end
  end
end
