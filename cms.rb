# frozen_string_literal: true

require 'sinatra'
require 'sinatra/reloader' if development?
require 'sinatra/content_for'
require 'tilt/erubis'

configure do
  set :erb, :escape_html => true
end

helpers do; end

before do
  root = File.expand_path('..', __FILE__)
  @docs = Dir.glob(root + '/data/*').map do |path|
    File.basename(path)
  end
end

get '/' do
  erb :doc_list, layout: :layout
end
