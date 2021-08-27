# frozen_string_literal: true

require 'sinatra'
require 'sinatra/reloader' if development?
require 'sinatra/content_for'
require 'tilt/erubis'

helpers do; end

configure do
  set :erb, :escape_html => true
  set :public_folder, __dir__ + '/data'
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
