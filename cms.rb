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

def load_document(path)
  content = File.read(path)

  case File.extname(path)
  when ".txt"
    headers["Content-Type"] = "text/plain"
    content
  when ".md"
    render_markdown(content)
  end
end

helpers do
  def display_error
    session[:error] ? session.delete(:error) : ""
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

get "/:filename" do
  file_path = @root + "/data/" + params[:filename]

  if File.file?(file_path)
    load_document(file_path)
  else
    session[:error] = "#{params[:filename]} does not exist."
    redirect "/"
  end
end
