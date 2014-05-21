task :admin do
end

task :addlib, [:gitrepo] do |t, args|
  raise "missing gitrepo argument to 'addlib'" unless args.gitrepo
  u = URI args.gitrepo
  if URI(args.gitrepo).absolute?
    url = args.gitrepo
  else
    url = "https://github.com/#{args.gitrepo}"
  end

  path = File.join ENV["RPI_BUILD_DIR"], File.basename(url, File.extname(url))
  if File.exists? path
    puts "Library already exists"
  else
    puts "Add library: #{args.gitrepo}"
    verbose(true) { sh "git clone #{url} #{path}" }
  end
end

task :update do
  Dir.glob("#{ENV['RPI_BUILD_DIR']}/*/.git") do |file|
    sh "cd #{File.dirname file} && git pull"
  end
end
