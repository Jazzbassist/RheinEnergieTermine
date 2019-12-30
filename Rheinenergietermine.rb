#!/bin/ruby
require 'google/apis/calendar_v3'
require 'googleauth'
require 'googleauth/stores/file_token_store'
require 'fileutils'
require 'open-uri'
require 'certified'
require 'net/http'

String.class_eval do
  def stripspecialchars()
    self.sub!(/#{"&#8211;"}/,'-')
    self.sub!(/#{"&#8222;"}/, '"')
    self.sub!(/#{"&#8220;"}/, '"')
    self.sub!(/#{"&#038;"}/, '&')
  end
end

RheinCalID='8sk61icsa79psfcc9adn6kbqvk@group.calendar.google.com'
OOB_URI = 'urn:ietf:wg:oauth:2.0:oob'.freeze
APPLICATION_NAME = 'RheinEnergieAlarm'.freeze
CREDENTIALS_PATH = 'credentials.json'.freeze
# The file token.yaml stores the user's access and refresh tokens, and is
# created automatically when the authorization flow completes for the first
# time.
TOKEN_PATH = 'token.yaml'.freeze
CALv3 = Google::Apis::CalendarV3
SCOPE = [CALv3::AUTH_CALENDAR_EVENTS, CALv3::AUTH_CALENDAR_READONLY, CALv3::AUTH_CALENDAR]
EventAttributes = Struct.new(:title,:desc,:date,:loc)
##
# Ensure valid credentials, either by restoring from the saved credentials
# files or intitiating an OAuth2 authorization. If authorization is required,
# the user's default browser will be launched to approve the request.
#
# @return [Google::Auth::UserRefreshCredentials] OAuth2 credentials
def NotATest?
  return true
end

def webdownload
    uri=URI('https://www.koelnersportstaetten.de/die-naechsten-termine/')
  begin
    htmljabber = Net::HTTP.get(uri)
    contents = htmljabber.read
    myfile = File.open('webcontents', 'w')
    myfile.write(contents)
    myfile.close
  rescue
    puts "ERROR: Contents from the Website could not be read. A likely cause is an issue with the SSL certificate. You could try to run gem update or certified-update. Unfortunately, however, all that currently works for me is to manually copy the contents from https://www.koelnersportstaetten.de/die-naechsten-termine/ into the webcontents file"
  end
end

def file2events #takes strings from 'webcontents', shortens them, and returns relevant events
  eventstrings=[]
  date="error"
  title="error"
  desc="error"
  loc="error"
  File.foreach('webcontents') do |line|
    if line.include?("<p><b style")
      date=line.sub(/#{"<p><.*>"}(\d\d\.\d\d\.20\d\d)#{"<.*><\/p>"}/,'\1')
    end
    if line.include?("<p style") #line includes time
      line.stripspecialchars()
      desc = line.sub(/#{"<p style=.*>"}(.*?)#{"<br \/>"}/,'\1')
    end
    if line.include?("<h1><b>")
      line.stripspecialchars()
      title=line.sub(/#{"<h1><.*>"}(.*?)#{"<.*><\/h1>"}/,'\1')
    end
    if line.include?("<p><h2>")
      line.stripspecialchars()
      desc << line.sub(/#{"<p><h2>"}(.*?)#{"<\/h2>"}/,'\1')
    end
    if line.include?("<p>[")
      line.stripspecialchars()
      loc=line.sub(/#{"<p>"}(.*?)#{"<\/p>"}/,'\1')
      loc.sub!(/\[/,'')
      loc.sub!(/\]/,'')
      eventstrings.append(EventAttributes.new(title.chop!,desc.chop!,date.chop!,loc.chop!))
      date="error"
      title="error"
      desc="error"
      loc="error"
    end
  end
  return eventstrings
#<p><h2>Album Release-Konzert 2020</h2>
 # r=/<h1><b>
end

def authorize
  client_id = Google::Auth::ClientId.from_file(CREDENTIALS_PATH)
  token_store = Google::Auth::Stores::FileTokenStore.new(file: TOKEN_PATH)
  authorizer = Google::Auth::UserAuthorizer.new(client_id, SCOPE, token_store)
  user_id = 'default'
  credentials = authorizer.get_credentials(user_id)
  if credentials.nil?
    url = authorizer.get_authorization_url(base_url: OOB_URI)
    puts 'Open the following URL in the browser and enter the ' \
         "resulting code after authorization:\n" + url
    code = gets
    credentials = authorizer.get_and_store_credentials_from_code(
      user_id: user_id, code: code, base_url: OOB_URI
    )
  end
  credentials
end

def createEvent (service,title='TEST',desc='Ein Test der Google Kalender API',mydate='2019-01-15')
#CALv3 = Google::Apis::CalendarV3
  event = CALv3::Event.new(
    summary:title,
    location:'RheinEnergieStadion',
    description:desc,
    start:{
      date:mydate,
      time_zone:'Europe/Berlin',
     },
    end:{
      date:mydate,
      time_zone:'Europe/Berlin',
    },
#  recurrence: [
#'RRULE:FREQ=DAILY;COUNT=2'
#  ],
 # attendees:[
 #   {email:'lpage@example.com'},
 #   {email:'sbrin@example.com'},
 # ],
    reminders:{
      use_default:false,
  #  overrides: [
   #   {method' => 'email', 'minutes: 24 * 60},
    #  {method' => 'popup', 'minutes: 10},
 #   ],
    },
  )
  result = service.insert_event(RheinCalID, event)
  puts "Event created: #{title}:\n#{result.html_link}"
end

def listCalendars (service)
  page_token = nil
  begin
    result = service.list_calendar_lists(page_token: page_token)
    result.items.each do |e|
      print e.summary + "\n"
      print e.id
      print "\n\n"
    end
    if result.next_page_token != page_token
      page_token = result.next_page_token
    else
      page_token = nil
    end
  end while !page_token.nil?
end

def deleteAll(service)
  events=service.list_events(RheinCalID).items
  events.each do |event|
    id = event.id
    service.delete_event(RheinCalID, id)
    sleep(0.1)
  end
  puts "All Events deleted"
end

service = CALv3::CalendarService.new
service.client_options.application_name = APPLICATION_NAME
service.authorization = authorize
if NotATest?
  createEvent(service, title="Test-Fehlermeldung", desc="Wenn diese Veranstaltung existiert, war die Löschung der alten Termine nicht erfolgreich", mydate=Date.today)
  deleteAll(service)
  createEvent(service, title="Letzte Aktualisierung", desc="Die letzte Aktualisierung dieses Kalenders fand heute statt", mydate=Date.today)
end
webdownload()
evs=file2events()
#evs=[]
evs.each do |event|
  if event.loc=="RheinEnergieSTADION"
    print event.title + " "	\
      + event.date + "\n"	\
      + event.desc + "\n"
    if NotATest?
      createEvent(service, title=event.title, desc=event.desc, mydate=Date.parse(event.date))
    end
    print "\n"
  end
end
###########################################
#listCalendars(service)
#########################################


###########################################
# Initialize the API


# Fetch the next 10 events for the user
#calendar_id = 'primary'
#response = service.list_events(calendar_id,
#                               max_results: 10,
#                               single_events: true,
#                               order_by: 'startTime',
#                               time_min: Time.now.iso8601)
#puts 'Upcoming events:'
#puts 'No upcoming events found' if response.items.empty?
#response.items.each do |event|
#  start = event.start.date || event.start.date_time
#  puts "- #{event.summary} (#{start})"
#end
