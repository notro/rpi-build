task :admin do
  puts "yes admin"
end

task :addlib, [:gitrepo] do |t, args|
  raise "missing gitrepo argument to 'addlib'" unless args.gitrepo
  puts "Add library: #{args.gitrepo}"
end