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

  def setup
    FileUtils.mkdir_p(root)
    create_document "about.md", "#Ruby is simple in appearance, but is very complex inside"
    create_document "another_document.txt"
    create_document "changes.txt", "This site is dedicated to history of Ruby language evolution. Basically, it is just the same information that each Ruby versionâ€™s NEWS file contains, just in more readable and informative manner."
  end

  def teardown
    FileUtils.rm_rf(root)
  end

  def test_index # test for listing of documents, edit links, new document
    get "/"

    assert_equal 200, last_response.status
    assert_includes last_response["Content-Type"], "text/html"
    assert_includes last_response.body, "about.md"
    assert_includes last_response.body, "changes.txt"
    assert_includes last_response.body, 'action="about.md/edit'
    assert_includes last_response.body, '<a href="/new_doc/">'
    assert_includes last_response.body, 'action="about.md/delete"'
  end

  def test_content # test to see if content can be accessed
    get "/changes.txt"

    assert_equal 200, last_response.status
    assert_includes last_response["Content-Type"], "text/plain"
    assert_includes last_response.body, "This site is dedicated to history of Ruby language"
  end

  def test_nonexistant_content # test for redirection, error message, clearing of error message
    get "/thisfiledoesnotexist.txt"

    assert_equal 302, last_response.status

    get last_response["Location"]

    assert_equal 200, last_response.status
    assert_includes last_response.body, "thisfiledoesnotexist.txt does not exist."

    get "/"
    refute_includes last_response.body, "thisfiledoesnotexist.txt does not exist."
  end

  def test_markdown_to_html # test for content conversion from markdown to HTML
    get "/about.md"

    assert_equal 200, last_response.status
    assert_includes last_response["Content-Type"], "text/html"
    assert_includes last_response.body, "<h1>Ruby is"
  end

  def test_content_edit_page # test contents of edit page
    get "/changes.txt/edit"

    assert_equal 200, last_response.status
    assert_includes last_response.body, "Edit content of changes.txt:"
    assert_includes last_response.body, "<textarea"
    assert_includes last_response.body, 'type="submit"'
  end

  def test_nonexistant_content_edit_page
    get "/thisfiledoesnotexist.txt/edit"

    assert_equal 302, last_response.status
    
    get last_response["Location"]

    assert_equal 200, last_response.status
    assert_includes last_response.body, "thisfiledoesnotexist.txt does not exist."

    get "/"
    refute_includes last_response.body, "thisfiledoesnotexist.txt does not exist."
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

  def test_new_content_page
    get "/new_doc/"

    assert_equal 200, last_response.status
    assert_includes last_response.body, "Add a new document:"
    assert_includes last_response.body, '<input type="text"'
    assert_includes last_response.body, '<input type="submit"'
  end

  def test_content_creation
    new_doc = "new.txt"

    post "/new_doc/", doc_name: new_doc
    
    assert_equal 302, last_response.status
    
    get last_response["Location"]

    assert_equal 200, last_response.status
    assert_includes last_response.body, "#{new_doc} was created."

    get "/"

    assert_equal 200, last_response.status
    assert_includes last_response.body, new_doc
  end

  def test_content_creation_no_name
    post "/new_doc/", doc_name: ""

    assert_equal 422, last_response.status
    assert_includes last_response.body, "A name is required."
  end

  def test_content_creation_invalid_type
    post "/new_doc/", doc_name: "invalid.invalid"
    
    assert_equal 415, last_response.status
    assert_includes last_response.body, "The file must be #{SUPPORTED_TYPES.join(' or ')} file types."
  end

  def test_content_creation_no_type
    post "/new_doc/", doc_name: "invalid"
    
    assert_equal 415, last_response.status
    assert_includes last_response.body, "The file must be #{SUPPORTED_TYPES.join(' or ')} file types."
  end

  def test_content_creation_already_exists
    post "/new_doc/", doc_name: "about.md"
    
    assert_equal 409, last_response.status
    assert_includes last_response.body, "about.md already exists."
  end

  def test_content_deletion
    post "/about.md/delete"

    assert_equal 302, last_response.status

    get last_response["Location"]
    
    assert_equal 200, last_response.status
    assert_includes last_response.body, "about.md was deleted."
    refute_includes last_response.body, '<a href="about.md">'
  end

end
