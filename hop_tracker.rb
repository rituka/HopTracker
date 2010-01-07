require 'rubygems'
require 'net/http'
require 'uri'
require "rexml/document"
require 'yaml'
class Hop
  HOPTOAD_URL = 'http://usmov.hoptoadapp.com/'

  PIVOTAL_URL = 'http://www.pivotaltracker.com/services/v2'
  attr_accessor :errors
  
  def initialize(&args)
    config = YAML.load_file("config.yml")
  	hoptoad_auth_token = config["config"]["HOPTOAD_AUTH_TOKEN"]
  	pivotal_project_id = config["config"]["PIVOTAL_PROJECT_ID"]
  	pivotal_api_token = config["config"]["PIVOTAL_API_TOKEN"]
  	@css_file = config["config"]["css_file"]
  	
    @hop_url = HOPTOAD_URL+'errors.xml?auth_token='+ hoptoad_auth_token
    @pivotal_url = "#{PIVOTAL_URL}/projects/#{pivotal_project_id}/stories"
    @pivotal_headers = {
            "X-TrackerToken" => pivotal_api_token,
            "Accept"         => "application/xml",
            "Content-type"   => "application/xml"
          }
  end
  
  
  def errors
    @errors = []
    res = Net::HTTP.get_response(URI.parse(@hop_url)).body
    result = REXML::Document.new(res)
    result.root.elements.each do |x|
      error_id = x.elements['id'].text
      unless check_existing?(error_id)
        error_title = %&[#{x.elements['rails-env'].text}]Hoptoad Error id-#{error_id}: #{x.elements['error-message'].text[0..50]}&
        error_description = %&In #{x.elements['controller'].text}/ #{x.elements['action'].text}. /n check the details at #{HOPTOAD_URL}/errors/#{error_id}&
    
        story = %&<story><story_type>bug</story_type><name>#{error_title}</name><requested_by>Ritu Kamthan</requested_by><description>#{error_description}</description></story>&
        @errors << {:id => error_id, :story => story}
      end
    end
    return @errors
  end
  
  def post_errors(errors)
    uri = URI.parse(@pivotal_url)
    errors.each do |e|
      res = Net::HTTP.new(uri.host, uri.port).start do |http|
        http.post(uri.path, e[:story], @pivotal_headers )
      end
      p "======="*5
      p "Entering error id #{e[:id]}..."
      p "======="*5
      p "STORY: #{e[:story]}"
      result =  REXML::Document.new(res.body)
      case res
      when Net::HTTPSuccess,Net::HTTPRedirection
        e[:story_id] = result.root.elements['id'].text
        update_existing(e)
        p "OK. Entered Story id:#{e[:story_id]}"
      else
        res.root.elements.text
      end
    end
  end
  
  def self.recent_errors
    h = Hop.new
    e = h.errors
    h.post_errors(e)
  end
  
  private
  
  def check_existing?(e_id)
    errors = YAML.load_file("errors.yml")
    return unless errors
    errors[e_id]
  end
  
  def update_existing(error)
    errors = YAML.load_file("errors.yml") || {}
    errors["#{error[:id]}"] = "#{error[:story_id]}"
    File.open("errors.yml", 'w') { |f| YAML.dump(errors, f) }
  end

end

# run

Hop.recent_errors