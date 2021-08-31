ENV["RACK_ENV"] = "test"

require "minitest/autorun"
require "rack/test"
require "fileutils"

require_relative "../cms.rb"

class AppTest < Minitest::Test
  include Rack::Test::Methods

  def app
    Sinatra::Application
  end

  def create_document(name, content = "")
    File.open(File.join(root, name), "w") do |file|
      file.write(content)
    end
  end

  def setup
    FileUtils.mkdir_p(root)
    create_document "about.md", "#Ruby is simple in appearance, but is very complex inside"
    create_document "changes.txt", "This site is dedicated to history of Ruby language evolution. Basically, it is just the same information that each Ruby versionâ€™s NEWS file contains, just in more readable and informative manner."
  end

  def teardown
    FileUtils.rm_rf(root)
  end

  def test_index # test for listing of documents, edit links
    get "/"

    assert_equal 200, last_response.status
    assert_includes last_response["Content-Type"], "text/html"
    assert_includes last_response.body, "about.md"
    assert_includes last_response.body, "changes.txt"
    assert_includes last_response.body, '<a href="about.md/edit">'
  end

  def test_content
    get "/changes.txt"

    assert_equal 200, last_response.status
    assert_includes last_response["Content-Type"], "text/plain"
    assert_includes last_response.body, "This site is dedicated to history of Ruby language"
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

  def test_markdown_to_html # test for content type (HTML)
    get "/about.md"

    assert_equal 200, last_response.status
    assert_includes last_response["Content-Type"], "text/html"
    assert_includes last_response.body, "<h1>Ruby is"
  end

  def test_content_edit_page
    get "/changes.txt/edit"

    assert_equal 200, last_response.status
    assert_includes last_response.body, "Edit content of changes.txt:"
    assert_includes last_response.body, "<textarea"
    assert_includes last_response.body, 'type="submit"'
  end

  def test_content_update
    new_content = "THIS IS A NEW EDIT VIA TESTING - #{Time.now.getutc}"

    post "/changes.txt/edit", updated_content: new_content

    assert_equal 302, last_response.status

    get last_response["Location"]
    
    assert_equal 200, last_response.status
    assert_includes last_response.body, "changes.txt has been updated."

    get "/changes.txt"
    assert_equal 200, last_response.status
    assert_includes last_response.body, new_content
  end
end
