# Lazy environment variable expansion
# stores the value in workdir for later runs
class VAR
  @@defaults = {}

  class << self
  def [](name)
    if ENV.key? name
      debug "#{name} == #{ENV[name]}"
      return ENV[name]
    end
    value = self.read name
    unless value.nil?
      debug "#{name} <= #{value}"
      ENV[name] = value
      return value
    end
    if @@defaults.key? name
      value = @@defaults[name].call
      debug "#{name} ?= #{value}"
      ENV[name] = value
    else
      debug "#{name} (not set)"
      nil
    end
  end

  def []=(name, value)
    debug "#{name} = #{value}"
    ENV[name] = value
    self.write name, value
  end

  def store(name)
    self[name] &&= self[name]
  end

  def key?(name)
    ENV.key?(name) || @@defaults.key?(name) || File.exists?(self.fn(name))
  end

  def delete(name)
    ENV.delete name
    File.unlink self.fn(name) if File.exists? self.fn(name)
  end

  def default(name, &block)
    raise "block missing" unless block_given?
    @@defaults[name] = block
  end

  def delete_default(name)
    @@defaults.delete name
  end

  def fn(name)
    workdir "#{name}.variable"
  end

  def read(name)
    if File.exists? self.fn(name)
      File.read self.fn(name)
    else
      nil
    end
  end

  def write(name, value)
    File.open(self.fn(name), 'w') { |file| file.write value.to_s }
  end
  end
end
