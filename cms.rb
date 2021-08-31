# frozen_string_literal: true

require 'sinatra'
require 'sinatra/reloader' if development?
require 'sinatra/content_for'
require 'tilt/erubis'
require 'redcarpet'

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

  case File.extname(path)
  when ".txt"
    headers["Content-Type"] = "text/plain"
    content
  when ".md"
    render_markdown(content)
  end
end

def validate_document(path)
  if File.file?(path)
    yield
  else
    session[:error] = "#{params[:filename]} does not exist."
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

helpers do
  def display_error
    session[:error] ? session.delete(:error) : ""
  end

  def display_message
    session[:message] ? session.delete(:message) : ""
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

get "/:filename" do # look at a document
  path = file_path(params[:filename])

  validate_document(path) { load_document(path) }
end

get "/:filename/edit" do # edit a document
  path = file_path(params[:filename])

  validate_document(path) do
    @content = get_content(path)
    erb :doc_edit, layout: :layout
  end
end

post "/:filename/edit" do # submit edits to a document
  write_content(file_path(params[:filename]), params[:updated_content])

  session[:message] = "#{params[:filename]} has been updated."
  redirect "/"
end