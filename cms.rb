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

def load_content(path)
  File.read(path)
end

def write_content(path, new_content)
  File.write(path, new_content)
end

def load_document(path)
  content = load_content(path)

  case File.extname(path)
  when ".txt"
    headers["Content-Type"] = "text/plain"
    content
  when ".md"
    render_markdown(content)
  end
end

def file_path(filename)
  @root + "/data/" + params[:filename]
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
  @root = File.expand_path('..', __FILE__)
  @docs = Dir.glob(@root + '/data/*').map do |path|
    File.basename(path) if File.ftype(path) == 'file'
  end.compact
end

get '/' do
  erb :doc_list, layout: :layout
end

get "/:filename" do # look at a document
  path = file_path(params[:filename])

  if File.file?(path)
    load_document(path)
  else
    session[:error] = "#{params[:filename]} does not exist."
    redirect "/"
  end
end

get "/:filename/edit" do # edit a document
  path = file_path(params[:filename])
  @content = load_content(path)
  erb :doc_edit, layout: :layout
end

post "/:filename/edit" do # submit edits to a document
  write_content(file_path(params[:filename]), params[:updated_content])

  session[:message] = "#{params[:filename]} has been updated."
  redirect "/"
end