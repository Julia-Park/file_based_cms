# frozen_string_literal: true

require 'sinatra'
require 'sinatra/reloader' if development?
require 'sinatra/content_for'
require 'tilt/erubis'
require 'redcarpet'
require 'yaml'
require 'bcrypt'

def create_blank_users_yaml
  save_credentials({})
end

def valid_credentials
  YAML.load_file(File.expand_path(File.join(root, 'users.yml'), __FILE__))
end

def save_credentials(credentials)
  File.open(File.join(root, 'users.yml'), 'w') { |file| file.write(credentials.to_yaml) }
end

def add_new_credentials(new_user, password)
  credentials = valid_credentials
  credentials[new_user] = BCrypt::Password.create(password).to_s
  save_credentials(credentials)
end

def delete_credentials(user)
  credentials = valid_credentials
  credentials.delete(user)
  save_credentials(credentials)
end

def supported_document_types
  ['.txt', '.md']
end

def supported_image_types
  [".jpeg", ".jpg", ".gif", ".png", ".tif"]
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

def load_content(path)
  content = get_content(path)

  case File.extname(path).downcase
  when ".txt"
    headers["Content-Type"] = "text/plain"
    content
  when ".md"
    erb render_markdown(content), layout: :layout
  when *supported_image_types
    send_file path
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
  elsif !supported_document_type?(new_doc)
    status 415
    session[:message] = "The file must be #{supported_document_types.join(' or ')} file types."
  elsif content_exists?(file_path(new_doc))
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

def content_exists?(path)
  File.file?(path)
end

def supported_document_type?(filename)
  supported_document_types.include?(File.extname(filename).downcase)
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
  create_blank_users_yaml if !File.file?(File.join(root, 'users.yml'))
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
    new_doc = params[:doc_name].strip.gsub(' ', '_')

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

    validate_document_access(path) { load_content(path) }
  end
end

get "/:filename/edit" do # edit a document
  validate_user do
    path = file_path(params[:filename])
    
    validate_document_access(path) do
      if supported_image_types.include?(File.extname(path).downcase)
        session[:message] = "Image files cannot be edited."
        redirect '/'
      end
      
      @content = get_content(path)
      erb :doc_edit, layout: :layout
    end
  end
end

post "/:filename/edit" do # submit edits and rename a document
  validate_user do
    filename = params[:filename].strip.gsub(' ', '_')
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

    if supported_image_types.include?(File.extname(old_document_path).downcase)
      session[:message] = "Image files cannot be duplicated."
      redirect '/'
    end

    until !content_exists?(file_path(new_doc)) do
      new_doc = new_doc.split(".").insert(1, '_copy').insert(-2, '.').join
    end

    validate_document_creation(new_doc) do
      create_document(new_doc, get_content(old_document_path))
      session[:message] = "#{params[:filename]} was duplicated to #{new_doc}."
      redirect "/"
    end
  end
end

get "/image/upload" do
  validate_user do
    erb :upload_image, layout: :layout
  end
end

post "/image/upload" do
  validate_user do
    if params[:image_file].nil?
      status 400
      session[:message] = "Select an image to upload."
    else
      image_name = params[:image_name].strip.gsub(' ', '_')
      image_name = params[:image_file][:filename] if image_name == ''
      image_path = file_path(image_name) 

      if content_exists?(image_path)
        status 409
        session[:message] = "#{image_name} already exists."
      else
        File.open(image_path, "wb") do |file|
          session[:message] = image_name
            file.write(params[:image_file][:tempfile].read)
        end
        session[:message] = "#{image_name} has been uploaded."
        redirect "/"
      end
    end
    erb :upload_image, layout: :layout
  end
end