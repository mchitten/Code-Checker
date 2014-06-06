require 'sinatra'
require 'json'
require 'yaml'
require 'github_api'
require 'sshkey'

# Writes some data to a file in the current directory.  The file will have the current timestamp,
# to differentiate it from others.
#
# = Parameters
# * <tt>text</tt> -     The text that should be written to a file.
# * <tt>filename</tt> - The appended "tag" of the file name.  Defaults to "POST".
#
def write_stuff(text, filename="POST")
  File.open(Dir.getwd + '/' + Time.now.to_i.to_s + '-' + filename + '.txt', 'w+') { |f| f.write(text) }
end

before do
  @config = YAML.load_file('./config.yml')
  @gh = Github.new client_id: @config['client_id'], client_secret: @config['client_secret']
end

# Basic landing page for the basic app.
get '/' do
  "Hey there."
end

get '/get_token' do
  redirect to @gh.authorize_url redirect_uri: 'http://mcs.ngrok.com/token', scope: 'repo'
end

get '/token' do
  @token = @gh.get_token(params['code']).token
  p @token
end

get '/pr' do
  @user, @repo = @config['user'], @config['repo']
  gh = Github.new oauth_token: @config['token'], user: @user, repo: @repo

  unless File.exist?("./test/#{@user}/#{@repo}/id_rsa_#{@user}_#{@repo}")
    p 'creating key...'
    `mkdir -p ./test/#{@user}/#{@repo}`
    k = SSHKey.generate
    File.open("./test/#{@user}/#{@repo}/id_rsa_#{@user}_#{@repo}", 'w') { |f| f.write(k.private_key) }
    File.open("./test/#{@user}/#{@repo}/id_rsa_#{@user}_#{@repo}.pub", 'w') { |f| f.write(k.ssh_public_key) }
    `sh ./test/store_rsa.sh #{@user} #{@repo}`

    gh.repos.keys.create title: 'Codey.io', key: k.ssh_public_key
  end
end

# This is the route that receives the GitHub payload.
post '/pr' do
  # The payload sent from GitHub in the POST request.
  @load = JSON.parse(request.env['rack.input'].read)

  # # Basic user and repo information.  You can figure out these values from this standard: git@github.com:@user/@repo.git.
  @user, @repo = @config['user'], @config['repo']

  # Auth through our OAuth token.
  gh = Github.new oauth_token: @config['token'], user: @user, repo: @repo

  # Set up RSA keys if applicable.
  rsa_path = "./test/#{@user}/#{@repo}/id_rsa_#{@user}_#{@repo}"
  unless File.exist?(rsa_path)
    `mkdir -p ./test/#{@user}/#{@repo}`
    k = SSHKey.generate
    File.open(rsa_path, 'w') { |f| f.write(k.private_key) }
    File.open("#{rsa_path}.pub", 'w') { |f| f.write(k.ssh_public_key) }
    `sh ./test/store_rsa.sh #{@user} #{@repo}`

    gh.repos.keys.create title: 'Codey.io', key: k.ssh_public_key
  end

  # Commit listener.
  if @load['before'] && @load['after']
    # The repository to fetch the diff from.
    repo_path = @load['repository']['url'].gsub(/https?\:\/\/github\.com\//i, '') + '.git'
    # The branch to fetch the diff from.
    branch_name = @load['ref'].gsub('refs/heads/', '')

    # The SHA of the new commit.
    sha = @load['after']

    # The wannabe PR number.
    @pr = 0

    # Runs through the pull requests to find one where the HEAD matches this commit's SHA.
    gh.pull_requests.list(@user, @repo).body.each do |pr|
      @pr = pr.number if pr.head.sha == sha
    end
  # A pull request was opened.
  elsif @load['pull_request'] && @load['action'] == "opened"
    request = @load['pull_request']
    # The repository that this PR is coming from.
    repo_path = request['head']['repo']['full_name'] + '.git'
    # The branch that this PR is coming from.
    branch_name = request['head']['ref']
    # The HEAD SHA to use.
    sha = request['head']['sha']

    @pr = @load['number']
  end

  # Don't even bother unless there's  PR number.  We don't want to comment on every commit!
  if @pr.to_i > 0
    results = `sh ./test/pull.sh #{repo_path} #{branch_name} #{@user} #{@repo}`
    report = JSON.parse(results)

    # Hooks into the GitHub API.  Used below.
    reporter = gh.pull_requests
    status = gh.repos.statuses

    changed_files = reporter.files(@user, @repo, @pr).map(&:filename)
    existing_comments = reporter.comments.list(@user, @repo, request_id: @pr).body.map { |i| "#{i.path}:#{i.position}:#{i.body}" }

    # Run through the files and comment on them, then leave a state.
    report['files'].each do |file|
      # Remove the relative URL to this directory.
      file_path = file['path'].gsub(Dir.getwd + "/test/#{@user}/#{@repo}/", '')
      if changed_files.include?(file_path)
        file_path = file['path']
        if file['offenses'].is_a?(Array)
          file['offenses'].each do |offense|
            unless existing_comments.include?("#{file_path}:#{offense['location']['line']}:#{offense['message']}")
              reporter.comments.create @user, @repo, @pr, body: "#{offense['message']}", commit_id: sha, path: file_path, position: offense['location']['line']
            end
          end
          # Leave a status update.
          status.create @user, @repo, sha, state: "error", description: "CodeSniffer found errors in this code."
        else
          # Leave a successful status update.
          status.crate @user, @repo, sha, state: "success", description: "CodeSniffer tests passed."
        end
      end
    end
  end
end
