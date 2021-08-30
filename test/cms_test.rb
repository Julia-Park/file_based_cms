ENV["RACK_ENV"] = "test"

require "minitest/autorun"
require "rack/test"

require_relative "../cms.rb"

class AppTest < Minitest::Test
  include Rack::Test::Methods

  def app
    Sinatra::Application
  end

  def test_index
    get "/"

    assert_equal 200, last_response.status
    assert last_response["Content-Type"].match("text/html")
    assert_includes last_response.body, "about.txt"
    assert_includes last_response.body, "changes.txt"
    assert_includes last_response.body, "history.txt"
  end

  def test_content
    get "/about.txt"

    assert_equal 200, last_response.status
    assert last_response["Content-Type"].match("text/plain")
    assert_includes last_response.body, "Ruby is simple in appearance, but is very complex inside"
  end
end
