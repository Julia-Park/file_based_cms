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
    assert_includes last_response["Content-Type"], "text/html"
    assert_includes last_response.body, "about.md"
    assert_includes last_response.body, "about.txt"
    assert_includes last_response.body, "changes.txt"
    assert_includes last_response.body, "history.txt"
  end

  def test_content
    get "/about.txt"

    assert_equal 200, last_response.status
    assert_includes last_response["Content-Type"], "text/plain"
    assert_includes last_response.body, "Ruby is simple in appearance, but is very complex inside"
  end

  def test_content_does_not_exist # test for redirection, error message, clearing of error message
    get "/thisfiledoesnotexist.txt"

    assert_equal 302, last_response.status

    get last_response["Location"]

    assert_equal 200, last_response.status
    assert_includes last_response.body, "thisfiledoesnotexist.txt does not exist."

    get "/"
    refute_includes last_response.body, "thisfiledoesnotexist.txt does not exist."
  end

  def text_markdown_to_html # test for content type (HTML)
    get "/about.md"

    assert_equal 200, last_response.status
    assert_includes last_response["Content-Type"], "text/html"
    assert_includes last_response.body, "<h1>Ruby is...</h1>"
  end
end
