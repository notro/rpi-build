
module Readme
  def self.method_missing(method, *args, &block)
    if block_given?
      VAR.default "README_#{method}", block
    elsif method =~ /.*=$/
      VAR["README_#{method}".chop] = args.join
    else
      VAR["README_#{method}"]
    end
  end

  def self.clear(name)
    VAR.delete "README_#{name}"
  end

  def self.source(str=nil)
    VAR["README_source"] ||= ''
    if str.nil?
      VAR["README_source"]
    else
      VAR["README_source"] += str
    end
  end

  def self.patch(str=nil)
    VAR["README_patch"] ||= ''
    if str.nil?
      VAR["README_patch"]
    else
      VAR["README_patch"] += str
    end
  end

  def self.diffconfig
    diff = `cd #{workdir 'linux'} && scripts/diffconfig .config.defconfig .config`
    added = []
    changed = []
    deleted = []
    diff.each_line do |line|
      m = line.match(/ (\w+) (\S+) \-> (\S+)/)
      if m
        if m[2] == 'n'
          added << "* #{m[1]}=#{m[3]}"
        elsif m[3] == 'n'
          deleted << "* #{m[1]}"
        else
          changed << "* #{line.strip}"
        end
      else
        m = line.match(/([\+\-])(\w+) (\w)/)
        raise "can't parse diffconfig line: #{line}" unless m
        if m[1] == '+'
          unless m[3] == 'n'
            added << "* #{m[2]}=#{m[3]}"
          end
        else
          deleted << "* #{m[2]} #{m[3]}" unless m[3] == 'n'
        end
      end
    end
    added.sort!
    changed.sort!
    deleted.sort!
    str = ''
    str << "\n\nAdded:\n" unless added.empty?
    str << added.join("\n")
    str << "\n\nChanged:\n" unless changed.empty?
    str << changed.join("\n")
    str << "\n\nDeleted:\n" unless deleted.empty?
    str << deleted.join("\n")
    "```text\n" + diff + "\n```\n\n" + str
  end

  def self.write
    File.open(workdir('out/README.md'), 'w') { |file| file.write VAR['README_all'] }
  end
end
