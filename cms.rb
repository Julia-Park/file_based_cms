# frozen_string_literal: true

require 'sinatra'
require 'sinatra/reloader' if development?
require 'sinatra/content_for'
require 'tilt/erubis'
require 'redcarpet'

SUPPORTED_TYPES = ['.txt', '.md']
VALID_CREDENTIALS = [ 
  ['admin', 'secret'] 
]

def render_markdown(string)
  markdown = Redcarpet::Markdown.new(Redcarpet::Render::HTML)
  markdown.render(string)
end

def get_content(path)
  File.read(path)
end

def write_content(path, new_content)
  File.write(path, new_content)
end

def load_document(path)
  content = get_content(path)

  case File.extname(path).downcase
  when ".txt"
    headers["Content-Type"] = "text/plain"
    content
  when ".md"
    erb render_markdown(content), layout: :layout
  end
end

def validate_document_access(path)
  if File.file?(path)
    yield
  else
    session[:message] = "#{params[:filename]} does not exist."
    redirect "/"
  end
end

def file_path(filename)
  File.join(root, params[:filename])
end

def root
  if ENV["RACK_ENV"] == "test"
    File.expand_path("../test/data", __FILE__)
  else
    File.expand_path("../data", __FILE__)
  end
end

def create_document(name, content = "")
  File.open(File.join(root, name), "w") do |file|
    file.write(content)
  end
end

def validate_document_creation(path)
  new_doc = File.basename(path)

  if File.file?(path)
    status 409
    session[:message] = "#{new_doc} already exists."
    erb :new_doc, layout: :layout
  else
    create_document(new_doc)
    session[:message] = "#{new_doc} was created."
    redirect "/"
  end
end

def supported_doc_type?(filename)
  SUPPORTED_TYPES.include?(File.extname(filename).downcase)
end

def valid_credentials?(username, password)
  VALID_CREDENTIALS.include?([username, password])
end

helpers do
  def display_message
    session.delete(:message) if session[:message]
  end
end

configure do
  set :erb, :escape_html => true
  # set :public_folder, __dir__ + '/data'
  enable:sessions
  set :session_secret, 'secret'
end

before do
  @docs = Dir.glob(root + '/*').map do |path|
    File.basename(path) if File.ftype(path) == 'file'
  end.compact
end

get '/' do
  erb :doc_list, layout: :layout
end

get '/users/signin' do
  if valid_credentials?(params[:username], params[:password])
    session[:username] = params[:username]
    session[:message] = 'Welcome!'
    redirect '/'
  else
    erb :sign_in, layout: :layout
  end
end

get "/new_doc/" do
  erb :new_doc, layout: :layout
end

post "/new_doc/" do
  new_doc = params[:doc_name]

  if new_doc == ""
    status 422
    session[:message] = "A name is required."
    erb :new_doc, layout: :layout
  elsif !supported_doc_type?(new_doc)
    status 415
    session[:message] = "The file must be #{SUPPORTED_TYPES.join(' or ')} file types."
    erb :new_doc, layout: :layout
  else new_doc == ""
    validate_document_creation(File.join(root, new_doc))
  end
end

get "/:filename" do # look at a document
  path = file_path(params[:filename])

  validate_document_access(path) { load_document(path) }
end

get "/:filename/edit" do # edit a document
  path = file_path(params[:filename])

  validate_document_access(path) do
    @content = get_content(path)
    erb :doc_edit, layout: :layout
  end
end

post "/:filename/edit" do # submit edits to a document
  write_content(file_path(params[:filename]), params[:updated_content])

  session[:message] = "#{params[:filename]} has been updated."
  redirect "/"
end

post "/:filename/delete" do
  path = file_path(params[:filename])

  validate_document_access(path) do
    File.delete(path)
    session[:message] = "#{params[:filename]} was deleted."
    redirect "/"
  end
end