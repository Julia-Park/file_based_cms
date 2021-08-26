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
  @docs = Dir.children("data").select { |fname| File.ftype("data/#{fname}") == "file" }
end

get '/' do
  erb :doc_list, layout: :layout
end
