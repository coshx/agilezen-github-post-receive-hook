require 'sinatra'
require 'net/http'
require 'net/https'
require 'openssl'
require 'uri'
require 'json'



# Post a with a query string to identify the project_id and api_key
# e.g. http:/wherever.com/?project_id=123&api_key=i234b23j4b23r89f7szd98uih23ew
post "/" do

  http = Net::HTTP.new 'agilezen.com', 443
  http.use_ssl = true
  http.verify_mode = OpenSSL::SSL::VERIFY_NONE

  headers ={'X-Zen-ApiKey' => params[:api_key], 'Content-Type' => 'application/json'  }
  task_id_regex_body = '(?:story|card|task|az)(?: |-|)#?(\d+)'
  task_id_regex = /#{task_id_regex_body}/i
  push = JSON.parse(params[:payload])

  return if push['base_ref']

  commits_with_task = push['commits'].select{|commit| task_id_regex.match(commit['message'])}
  commits_with_task.each do |commit|
    data = "{\"text\":\"#{comment_message_from commit }\"}"

    commit['message'].scan(task_id_regex).flatten.each do |story_id|
      path = "https://agilezen.com/api/v1/projects/#{params[:project_id]}/stories/#{story_id}/comments"
      http.post path,data, headers 
    end
  end

  # for now, just assume "finishes" means advance the story one stage
  finishes_id_regex = /(?:finishes|completes|fixes) #{task_id_regex_body}/i
  finished_tasks = {}
  push['commits'].each do |commit| 
    commit['message'].scan(finishes_id_regex).flatten.each do |story_id|
      finished_tasks[story_id] = true
    end
  end
  phase_id_to_phase = {}
  phase_index_to_phase = {}
  if !finished_tasks.empty?
    # need phase indexes so we can increment the story's phase
    path = "https://agilezen.com/api/v1/projects/#{params[:project_id]}/phases"
    JSON.parse(http.get(path, headers).body)["items"].each do |item|
      phase_id_to_phase[item["id"]] = item
      phase_index_to_phase[item["index"]] = item
    end
  end
  finished_tasks.each_key do |story_id|
    path = "https://agilezen.com/api/v1/projects/#{params[:project_id]}/stories/#{story_id}"
    story_details = JSON.parse(http.get(path, headers).body)
    puts "story_details: #{story_details.inspect}"
    phase_id = story_details["phase"]["id"]
    new_phase = phase_index_to_phase[phase_id_to_phase[phase_id]["index"].to_i + 1]

    if new_phase
      data = {"phase" => new_phase}.to_json
      http.put path, data, headers
    end
  end

  ""
end

get "/" do
  "You just don't get this, do you?"
end


def comment_message_from(commit)
  commit_message = commit['message'].slice(0,commit['message'].index("\n") || 50 )
  "#{commit['author']['name']} commited [<a href='#{commit['url']}'>#{commit['id'].slice(0,7)}</a>] #{commit_message}"
end
