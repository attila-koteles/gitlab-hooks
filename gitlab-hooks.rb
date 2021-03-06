require 'rubygems'
require 'sinatra'
require 'eventmachine' # lol node wat
require 'json'
require 'asana'
require 'hipchat'
require './env' if File.exists?('env.rb')

set :protection, :except => [:http_origin]

# use Rack::Auth::Basic do |username, password|
#   [username, password] == [ENV['username'], ENV['password']]
# end

HIPCHAT_COLORS = %w(yellow green purple gray) # red is reserved for errors
DEFAULT_COLOR = 'yellow'

post '/' do
  EventMachine.run do
    json_string = request.body.read.to_s
    puts json_string
    payload = JSON.parse(json_string)

    user = payload['user_name']
    branch = payload['ref'].split('/').last

    rep = payload['repository']['url'].split('/').last(2).join('/')
    push_msg = user + " pushed to branch " + branch + " of " + rep

    Asana.configure do |client|
      client.api_key = ENV['auth_token']
    end

    @hipchat = HipChat::Client.new(ENV['hipchat_token'])
    @msg_color = params['color'].nil? || !HIPCHAT_COLORS.include?(params['color']) ? DEFAULT_COLOR : params['color']
    room = params['room']

    EventMachine.defer do
      payload['commits'].each do |commit|
        message = " (" + commit['url'] + ")\n- #{commit['message']}"
        check_commit(message, push_msg)
        post_hipchat_message(push_msg + message, room)
      end
    end
  end
  "BOOM! EvenMachine handled it!"
end

def check_commit(message, push_msg)
  task_list = []
  close_list = []

  message.split("\n").each do |line|
    task_list.concat(line.scan(/#(\d+)/)) # look for a task ID
    close_list.concat(line.scan(/(fix\w*)\W*#(\d+)/i)) # look for a word starting with 'fix' followed by a task ID
  end

  # post commit to every taskid found
  task_list.each do |taskid|
    task = Asana::Task.find(taskid[0])
    task.create_story({'text' => "#{push_msg} #{message}"})
  end

  # close all tasks that had 'fix(ed/es/ing) #:id' in them
  close_list.each do |taskid|
    task = Asana::Task.find(taskid.last)
    task.modify(:completed => true)
  end
end

def post_hipchat_message(message, room)
  @hipchat[room].send('GitLab Bot', message, :notify => true, :color => @msg_color)
end

