# frozen_string_literal: true

require 'sinatra'
require 'sinatra/reloader' if development?
require 'sinatra/content_for'
require 'tilt/erubis'
require 'redcarpet'
require 'yaml'
require 'bcrypt'

def valid_credentials
  YAML.load_file(File.expand_path(File.join(root, 'users.yml'), __FILE__))
end

def add_new_credentials(new_user, password)
  credentials = valid_credentials
  credentials[new_user] = BCrypt::Password.create(password).to_s
  File.open(File.join(root, 'users.yml'), 'w') { |file| file.write(credentials.to_yaml) }
end

def supported_types
  ['.txt', '.md']
end

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
  File.join(data_root, filename)
end

def root
  if ENV["RACK_ENV"] == "test"
    File.expand_path("../test", __FILE__)
  else
    File.expand_path("..", __FILE__)
  end
end

def data_root
  if ENV["RACK_ENV"] == "test"
    File.expand_path("../test/data", __FILE__)
  else
    File.expand_path("../data", __FILE__)
  end
end

def validate_document_creation(new_doc)
  if new_doc == ""
    status 422
    session[:message] = "A name is required."
  elsif !supported_doc_type?(new_doc)
    status 415
    session[:message] = "The file must be #{supported_types.join(' or ')} file types."
  elsif document_exists?(file_path(new_doc))
    status 409
    session[:message] = "#{new_doc} already exists."
  else
    yield
  end
end

def create_document(name, content = "")
  File.open(file_path(name), "w") do |file|
    file.write(content)
  end
end

def document_exists?(path)
  File.file?(path)
end

def supported_doc_type?(filename)
  supported_types.include?(File.extname(filename).downcase)
end

def valid_credentials?(username, password)
  hashed_password = valid_credentials[username]
  hashed_password ? BCrypt::Password.new(hashed_password) == password : false
end

def validate_user
  if valid_credentials.keys.include?(session[:username])
    yield
  else
    session[:message] = 'You must be signed in to do that.'
    redirect '/'
  end
end

def invalid_user_force_sign_in(message='Invalid credentials.')
  session.delete(:username)
  status 422
  session[:message] = message
  erb :sign_in, layout: :layout
end

helpers do
  def display_message
    session.delete(:message) if session[:message]
  end
end

configure do
  set :erb, :escape_html => true
  enable :sessions
  set :session_secret, 'secret'
end

before do
  @docs = Dir.glob(data_root + '/*').map do |path|
    File.basename(path) if File.ftype(path) == 'file'
  end.compact
end

get '/' do
  if session[:username].nil?
    erb :index, layout: :layout
  else
    erb :doc_list, layout: :layout
  end
end

get '/users/signin' do
  erb :sign_in, layout: :layout
end

post '/users/signin' do
  if valid_credentials?(params[:username], params[:password])
    session[:username] = params[:username]
    session[:message] = 'Welcome!'
    redirect '/'
  else
    status 422
    session[:message] = 'Invalid credentials.'
    erb :sign_in, layout: :layout
  end
end

get '/users/signout' do
  session.delete(:username)
  session[:message] = 'You have been signed out.'
  redirect '/'
end

get '/users/signup' do
  erb :sign_up, layout: :layout
end

post '/users/signup' do
  if !valid_credentials.keys.include?(params[:username]) && params[:password] != ''
    add_new_credentials(params[:username], params[:password])
    session[:message] = "User #{params[:username]} added!  Please sign in with the new credentials."
    redirect '/users/signin'
  elsif params[:password] == ''
    status 409
    session[:message] = 'Password must not be blank.'
    erb :sign_up, layout: :layout
  else
    status 409
    session[:message] = 'Username already exists.'
    erb :sign_up, layout: :layout
  end

end

get "/new_doc/" do
  validate_user do
    erb :new_doc, layout: :layout
  end
end

post "/new_doc/" do
  validate_user do
    new_doc = params[:doc_name]

    validate_document_creation(new_doc) do
      create_document(new_doc)
      session[:message] = "#{new_doc} was created."
      redirect "/"
    end

    erb :new_doc, layout: :layout
  end
end

get "/:filename" do # look at a document
  validate_user do
    path = file_path(params[:filename])

    validate_document_access(path) { load_document(path) }
  end
end

get "/:filename/edit" do # edit a document
  validate_user do
    path = file_path(params[:filename])

    validate_document_access(path) do
      @content = get_content(path)
      erb :doc_edit, layout: :layout
    end
  end
end

post "/:filename/edit" do # submit edits and rename a document
  validate_user do
    filename = params[:filename]
    new_name = params[:new_name] || filename
    old_content = get_content(file_path(filename))
    @content = params[:updated_content] || old_content
    message = []

    if filename != new_name
      validate_document_creation(new_name) do
        File.rename(file_path(filename), file_path(new_name))
        message << "has been renamed to #{new_name}"
      end
    end

    if !session[:message].nil?
      erb :doc_edit, layout: :layout
    else
      if old_content != @content
        write_content(file_path(filename), @content)
        message << 'has been updated'
      end

      session[:message] = if !message.empty?
        "#{filename} #{message.join(' and ')}." 
      else
        "No changes were made to #{filename}."
      end

      redirect "/"
    end
  end
end

post "/:filename/delete" do
  validate_user do
    path = file_path(params[:filename])

    validate_document_access(path) do
      File.delete(path)
      session[:message] = "#{params[:filename]} was deleted."
      redirect "/"
    end
  end
end

post "/:filename/duplicate" do # duplicate a document
  validate_user do
    old_document_path = file_path(params[:filename])
    new_doc = params[:filename]

    until !document_exists?(file_path(new_doc)) do
      new_doc = new_doc.split(".").insert(1, '_copy').insert(-2, '.').join
    end

    validate_document_creation(new_doc) do
      create_document(new_doc, get_content(old_document_path))
      session[:message] = "#{params[:filename]} was duplicated to #{new_doc}."
      redirect "/"
    end
  end
end
